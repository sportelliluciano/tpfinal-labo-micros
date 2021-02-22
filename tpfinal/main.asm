.equ CLK_FREC_MHZ = 16

.def retl = r0 ; Byte bajo de retornos
.def reth = r1 ; Byte alto de retornos
.def zero = r2 ; Registro que siempre vale 0
.def sreg_save = r3 ; Registro que almacena SREG durante ISRs.
.def last_adch = r4 ; Última medición del ADC (high)
.def last_adcl = r5 ; Última medición del ADC (low)

.dseg
.org SRAM_START
ULTIMO_TH: .byte 2 ; Tiempo en alto de la señal PWM (en ticks)
ULTIMO_TL: .byte 2 ; Tiempo en bajo de la señal PWM (en ticks)

.cseg
.org 0x0000
	rjmp main
.org INT0Addr
	rjmp isr_int0
.org URXCaddr
    rjmp isr_usart_rx
.org UDREaddr
    rjmp isr_usart_tx
.org ADCCaddr
	rjmp isr_adc

.org INT_VECTORS_SIZE ; Inicio del código

.include "adc.asm"
.include "io.asm"
.include "pwm.asm"
.include "timer.asm"
.include "usart.asm"

.include "delay.asm"

main:
    ; ------------ Configurar stack -----------
    ldi r16, HIGH(RAMEND)
    out SPH, r16
	ldi r16, LOW(RAMEND)
    out SPL, r16
    ; ----------------- setup ------------------
	clr zero

	call io_configurar
    call pwm_configurar
	call usart_configurar
	call adc_configurar
	call timer_configurar
	sei                    ; Habilitar interrupciones
	; ------------------------------------------
    
main_loop:
    rjmp main_loop

; ISR - INT0
isr_int0:
	in sreg_save, SREG
	
	call timer_capturar  ; Copiar el valor del timer
	call timer_reiniciar ; Reiniciar timer

	push XH
	push XL
	
	sbis PIND, DDD2              ; if ! is_rising_edge() {
	rjmp isr_int0_capturar_td    ;     capturar_tiempo_high
	ldi XH, HIGH(ULTIMO_TL)      ; } else {
	ldi XL, LOW(ULTIMO_TL)       ;     capturar_tiempo_low
	st X+, retl
	st X+, reth
	rjmp isr_int0_fin            ; }
isr_int0_capturar_td:
	ldi XH, HIGH(ULTIMO_TH)
	ldi XL, LOW(ULTIMO_TH)
	st X+, retl
	st X+, reth
	; fallthrough
isr_int0_fin:
	pop XL
	pop XH
	out SREG, sreg_save
	reti

; ISR - USART
isr_usart_rx:
	in sreg_save, SREG
	; RX: 0x01 = Leer TL
	;     0x02 = Leer TH
	;     0x04 = ADC Status (0 = off, 1 = on)
	
	; lds r16, UDR0
	; call usart_transmitir

	out SREG, sreg_save
	reti

isr_usart_tx:
	in sreg_save, SREG

	sbrc last_adch, 7   ; Si last_adch.7 == 1 -> transmitir byte bajo
	rjmp isr_usart_tx_low
	sbrc last_adch, 6   ; Si last_adch.6 == 1 -> esta muestra ya fue transmitida
	rjmp isr_usart_tx_fin
	sts UDR0, last_adch ; sino -> transmitir byte alto
	
	ldi r16, 0b10000000 ; setear last_adch.7 = 1
	or last_adch, r16
	rjmp isr_usart_tx_fin
isr_usart_tx_low:
	sts UDR0, last_adcl
	ldi r16, 0b11000000 ; setear last_adch.7:6 = 1
	or last_adch, r16
	; Iniciar siguiente conversión
	call adc_iniciar_conversion
isr_usart_tx_fin:
	out SREG, sreg_save
	reti

isr_adc:
	in sreg_save, SREG
	lds last_adcl, ADCL
	lds last_adch, ADCH
	out SREG, sreg_save
	reti