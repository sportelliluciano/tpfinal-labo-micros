.equ CLK_FREC_MHZ = 16

.def retl = r0 ; Byte bajo de retornos
.def reth = r1 ; Byte alto de retornos
.def zero = r2 ; Registro que siempre vale 0
.def sreg_save = r3 ; Registro que almacena SREG durante ISRs.
.def last_adch = r4 ; Última medición del ADC (high)
.def last_adcl1 = r5 ; Última medición del ADC (low)
.def last_adcl2 = r9
.def paq1 = r6
.def paq2 = r7
.def paq3 = r8

.cseg
.org 0x0000
	rjmp main
.org INT0Addr
	rjmp isr_int0
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

.include "buffer.asm"
.include "delay.asm"

main:
    ; ------------ Configurar stack -----------
    ldi r16, HIGH(RAMEND)
    out SPH, r16
	ldi r16, LOW(RAMEND)
    out SPL, r16
    ; ------------ setup inicial --------------
	clr zero

	call io_configurar
	call usart_configurar
	call buffer_init
	; ------------------------------------------
esperar_inicio:
	; Esperar a que la PC nos envíe algo para iniciar el programa.
	sbi PORTB, DDB5
	ldi r16, 250
	call delayms
	cbi PORTB, DDB5
	ldi r16, 250
	call delayms
	lds r16, UCSR0A     ; while !rx_buffer_full() {
    andi r16, 1 << RXC0 ;     ;
    breq esperar_inicio     ; }
    lds r16, UDR0       ; Descartar byte recibido
	; ---------------- setup -------------------
    call pwm_configurar
	call adc_configurar
	call timer_configurar
	sei
	; ------------------------------------------
main_loop:
    rjmp main_loop

; ISR - INT0
isr_int0:
	in sreg_save, SREG
	
	call timer_capturar  ; Copiar el valor del timer
	call timer_reiniciar ; Reiniciar timer

	push r16
	sbis PIND, DDD2              ; if ! is_rising_edge()
	rjmp isr_int0_capturar_td    ;     goto capturar_tiempo_high
	ldi r16, 0b00100000          ; id = 10 
	rjmp isr_int0_flush          ; goto flush
isr_int0_capturar_td:
	ldi r16, 0b00110000          ; id = 11
isr_int0_flush:                  ; flush
	mov paq1, r16
	mov paq2, reth
	mov paq3, retl
	call push_packet             ; push_packet(id, reth, retl)
	out SREG, sreg_save          
	pop r16
	reti

isr_usart_tx:
	in sreg_save, SREG
	call buffer_get_byte
	sbrc reth, 7                    ; if reth.7:
	rjmp isr_usart_tx_sin_datos     ;     goto sin datos
	sts UDR0, retl
	rjmp isr_usart_tx_fin
isr_usart_tx_sin_datos:
	; Desactivar UDRIE0
	lds r16, UCSR0B
	andi r16, ~(1 << UDRIE0)
	sts UCSR0B, r16
isr_usart_tx_fin:
	out SREG, sreg_save
	reti

; Agrega un paquete de 3 bytes al bufer de transmisión
; Los 3 bytes se obtienen de los registros paq1, paq2, paq3.
;
; El paquete de transmisión siempre tiene el siguiente formato:
; 00II DDDD DDDD DDDD DDDD DDDD
; Donde I representa un bit correspondiente al ID de paquete,
; y D representa un bit de datos.
;
; Hay 3 posibles paquetes:
; - Paquete de datos de ADC: contiene dos muestras del ADC
; 0001 AABB AAAA AAAA BBBB BBBB
; Donde:
;  - El ID es 01
;  - A representa un bit de la primer muestra, siendo el bit 
;    más a la izquierda el más significativo.
;  - B representa un bit de la segunda muestra, siendo el bit
;    más a la izquierda el más significativo.
; La primera muestra se debe haber obtenido temporalmente antes
; que la segunda.
;
; - Paquete de datos del PWM (1): contiene el tiempo que la señal
;   del PWM está en nivel lógico bajo.
;   0010 0000 HHHH HHHH LLLL LLLL
; Donde:
;   - El ID es 10
;   - H representa bits del byte alto, L del byte bajo, siendo el
;     bit de más a la izquierda el más significativo.
;
; - Paquete de datos del PWM (2): contiene el tiempo que la señal
;   del PWM está en nivel lógico alto.
;   0011 0000 HHHH HHHH LLLL LLLL
; Donde:
;   - El ID es 11
;   - H representa bits del byte alto, L del byte bajo, siendo el
;     bit de más a la izquierda el más significativo.
;
; Un paquete que no empiece en 00 será rechazado por el host.
push_packet:
	push r24
	call buffer_push_packet
	sbrc reth, 7 ; if reth.7 == 1:
	rjmp pp_drop ;     goto paquete_droppeado

	; Activar UDRIE0 cv.notify
	lds r24, UCSR0B
	ori r24, (1 << UDRIE0)
	sts UCSR0B, r24
	rjmp pp_fin
pp_drop:
	sbi PORTB, 5 ; DEBUG: Encender led de packet dropped
pp_fin:
	pop r24
	ret

isr_adc:
	in sreg_save, SREG
	push r16
	
	; last_adch = 0000 0000
	sbrc last_adch, 7        ; if last_adch.7: goto save_second
	rjmp isr_adc_save_second
	; else: save_first
	lds last_adcl1, ADCL ; Leer el low primero
	lds r16, ADCH 
	andi r16, 0b00000011 ; Asegurarse que los bits más significativos son 0.
	ori r16, (1 << 7)
	mov last_adch, r16   ; last_adch = 0b10000000 | ADCH
	rjmp isr_adc_fin

isr_adc_save_second:
	lds last_adcl2, ADCL ; Leer el low primero
	lsl last_adch
	lsl last_adch
	lds r16, ADCH        ; r16 = (last_adch << 2) | ADCH
	andi r16, 0b00000011 ; Asegurarse que los bits más significativos son 0.
	or r16, last_adch

	; Push packet to tx queue: 0001 AABB AAAA AAAA BBBB BBBB
	ori r16, 0b00010000 ; Agregar ID
	mov paq1, r16
	mov paq2, last_adcl1
	mov paq3, last_adcl2
	call push_packet

isr_adc_fin:
	pop r16
	out SREG, sreg_save
	reti