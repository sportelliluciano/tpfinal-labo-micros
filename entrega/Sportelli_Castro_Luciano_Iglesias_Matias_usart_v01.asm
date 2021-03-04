.equ UBRR_BPS = ((CLK_FREC_MHZ * 1000000) / 4 / BAUD_RATE - 1) / 2

.if UBRR_BPS > 4095
 .error "UBRR_BPS debe ser menor que 4095"
.endif

.def buffer_head = r10
.def buffer_tail = r11

.dseg 
.equ PACKET_SZ = 4          ; 3 bytes + padding, debe ser potencia de 2
.equ BUFFER_SZ = (1 << 8)   ; 256 bytes = 64 paquetes
BUFFER: .byte BUFFER_SZ     ; Búfer de 256 bytes = se aprovecha el 
                            ; overflow de enteros de 8 bits.

.cseg
usart_configurar:
    ldi r16, LOW(UBRR_BPS)
    sts UBRR0L, r16
    ldi r16, HIGH(UBRR_BPS)   ; Configurar baud rate
    sts UBRR0H, r16
    
	ldi r16, (1 << U2X0)
	sts UCSR0A, r16

    ; Activar transmisión y recepción USART.
    ldi r16, (1 << RXEN0) | (1 << TXEN0)
    sts UCSR0B, r16
    
    ; 8 bits de datos, sin paridad, 1 bit de parada (8N1)
    ldi r16, (0 << USBS0) | (1 << UCSZ01) | (1 << UCSZ00)
    sts UCSR0C, r16

	clr buffer_head
	clr buffer_tail
    ret

usart_desactivar_rx:
	lds r16, UCSR0B
	andi r16, ~(1 << RXEN0)
    sts UCSR0B, r16
	ret

; Encola un paquete en el búfer de transmisión.
; Si no hay espacio para el paquete se ignorará y se encenderá
; el led de DEBUG (PORTB.5)
usart_push_packet:
	ldi r26, PACKET_SZ           ; r26 y r27 son XL y XH, no hay necesidad de salvarlos
	add r26, buffer_head         ; r26 = buffer_head + 4
	mov r27, buffer_tail
	andi r27, ~(PACKET_SZ - 1)   ; r27 = buffer_tail & 0b11111100
	cp r26, r27                  ; if buffer_head + 4 == buffer_tail & 0b11111100:
	breq upp_sin_espacio         ;     no hay espacio
	
	ldi XL, LOW(BUFFER)
	ldi XH, HIGH(BUFFER)
	add XL, buffer_head
	adc XH, zero                 ; X = &BUFFER + buffer_head
	
	st X+, paq1 
	clr reth
	st X+, paq2 
	clr retl
	st X+, paq3 

	ldi r26, PACKET_SZ
	add buffer_head, r26         ; buffer_head += 4
	
	; Activar UDRIE0
	lds r26, UCSR0B
	ori r26, (1 << UDRIE0)
	sts UCSR0B, r26

	rjmp upp_fin
upp_sin_espacio:
	sbi PORTB, 5 ; DEBUG: Encender led de packet dropped
upp_fin:
	ret

; Obtiene un byte del búfer de transmisión, devuelve 0x00BB, donde BB es el valor del byte.
; Si no hay datos devuelve 0xFFXX, donde XX significa cualquier valor.
usart_get_byte_tx:
	cp buffer_tail, buffer_head
	breq ugb_sin_datos          ; if buffer_tail == buffer_head: no hay datos

	ldi XL, LOW(BUFFER)
	ldi XH, HIGH(BUFFER)
	add XL, buffer_tail
	adc XH, zero                ; X = BUFFER + buffer_tail

	clr reth                     ; reth = 0x00
	ld retl, X					 ; retl = BUFFER[buffer_tail][buffer_byte_index]
	inc buffer_tail              ; buffer_tail++

	ldi r26, (PACKET_SZ - 1)
	and r26, buffer_tail
	cpi r26, 3                   ; if buffer_tail & 0b11 != 3:
	brne ugb_fin                 ;    fin
	inc buffer_tail              ; else: saltear padding
	rjmp ugb_fin
ugb_sin_datos:
	; Desactivar UDRIE0
	lds r26, UCSR0B
	andi r26, ~(1 << UDRIE0)
	sts UCSR0B, r26
	
	; Devolver 0xFFxx
	ldi r26, 0xFF
	mov reth, r26
ugb_fin:
	ret