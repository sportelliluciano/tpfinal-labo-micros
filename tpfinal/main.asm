.equ CLK_FREC_MHZ = 16
.equ BAUD_RATE = 230400

.def retl = r0 ; Byte bajo de retornos
.def reth = r1 ; Byte alto de retornos
.def zero = r2 ; Registro que siempre vale 0
.def sreg_save = r3  ; Registro que almacena SREG durante ISRs.
.def last_adch = r4  ; Bits altos de las últimas mediciones del ADC
.def last_adcl1 = r5 ; Anteúltima medición del ADC (low)
.def last_adcl2 = r6 ; Última medición del ADC (low)
.def paq1 = r7       ; Parámetro 1 para usart_push_packet
.def paq2 = r8       ; Parámetro 2 para usart_push_packet
.def paq3 = r9       ; Parámetro 3 para usart_push_packet
; r10, r11, X        ; Usados por USART
.def isr_tmp1 = r16  ; Registro temporal para usar en ISRs


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
	; ------------------------------------------
esperar_inicio:
	; Esperar a que la PC nos envíe algo para iniciar el programa.
	sbi PORTB, DDB5         ; Parpadear LED en PORTB.5 para indicar
	ldi r16, 250            ; que está esperando el inicio del programa
	call delayms
	cbi PORTB, DDB5
	ldi r16, 250
	call delayms
	lds r16, UCSR0A
	sbrs r16, RXC0           ; if (! byte recibido)
    rjmp esperar_inicio      ;     goto esperar_inicio
    lds r16, UDR0
	call usart_desactivar_rx ; Ya no es necesaria
	; ---------------- setup -------------------
    call pwm_configurar
	call adc_configurar
	call timer_configurar
	sei
	; ------------------------------------------
main_loop:
	rjmp main_loop

isr_int0:
	in sreg_save, SREG
	call timer_capturar  ; Capturar el valor del timer y reiniciarlo

	ldi isr_tmp1, 0b00100000     ; isr_tmp1 = 0b0010 0000
	sbic PIND, DDD2              ; si es flanco descendente:
	ori isr_tmp1, 0b00010000     ;    isr_tmp1 |= 0b0001 0000
	mov paq1, isr_tmp1
	mov paq2, reth
	mov paq3, retl
	call usart_push_packet       ; usart_push_packet(isr_tmp1, reth, retl)
	out SREG, sreg_save
	reti

isr_usart_tx:
	in sreg_save, SREG
	call usart_get_byte_tx          ; vacio, byte = usart_get_byte()
	sbrs reth, 7                    ; if (! vacio):
	sts UDR0, retl                  ;     enviar dato
	out SREG, sreg_save
	reti

isr_adc:
	in sreg_save, SREG
	; Los paquetes que llevan información de ADC contienen
	; dos muestras en cada uno para aprovechar mejor los 
	; 24 bytes.
	; Cada una de estas muestras es de 10 bits, dejando
	; 4 bits para el identificador de paquete.
	; Si nombramos a la primer muestra 'A' y a la segunda 'B',
	; el paquete quedaría codificado como
	; 0001 aabb aaaa aaaa bbbb bbbb
	; Donde 0001 es el ID de paquete, a y b representan bits
	; de la muestra a y b respectivamente. 
	; El bit más significativo es el que está más a la izquierda.
	;
	; Esta rutina, por lo tanto, debe ser llamada dos veces
	; (una para la primer muestra, una para la segunda) para
	; generar un paquete.
	;
	; Al llamarse la primera vez almacenará en last_adcl1 y
	; last_adch la muestra obtenida; agregando en last_adch
	; el bit de ID de paquete, que será usado también como
	; bandera para indicar que ya se leyó la primer medición.
	lds last_adcl2, ADCL       ; Leer primero ADCL
	lds isr_tmp1, ADCH         ; isr_tmp1 = ADCH
	andi isr_tmp1, 0b00000011  ; Asegurarse que los bits más significativos son 0.
	sbrc last_adch, 7          ; if last_adch.2:
	rjmp isr_adc_medicion_dos  ;     es medicion 2
	; es medicion 1:
	mov last_adcl1, last_adcl2 ; Mover medicion a last_adcl1
	ori isr_tmp1, 0b10000100   ; Agregar el bit de ID a last_adch y un bit que
	mov last_adch, isr_tmp1    ; indicará también que ya tenemos una medición (bit 7)
	rjmp isr_adc_fin           ; last_adch = 0b10000100 | ADCH
	                           ; Notar que el bit de ID está dos posiciones
	                           ; desplazado. Se corregirá al agregar la 
							   ; segunda medición.
isr_adc_medicion_dos:          ; Mover last_adch 2 posiciones a la izquierda.
	lsl last_adch              ; Esto borra el flag (bit 7) y acomoda el ID en la
	lsl last_adch              ; posición correcta.
	or isr_tmp1, last_adch     ; last_adch = (last_adch << 2) | ADCH
	mov paq1, isr_tmp1
	mov paq2, last_adcl1
	mov paq3, last_adcl2       ; usart_push_packet(ID | (ADCH1 << 2) | ADCH2, ADCL1, ADCL2)
	call usart_push_packet     ; usart_push_packet(0001 AABB, AAAA AAAA, BBBB BBBB)
isr_adc_fin:
	out SREG, sreg_save
	reti