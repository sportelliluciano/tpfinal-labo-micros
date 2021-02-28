;.equ UBRR_BPS = (CLK_FREC_MHZ * 1000000)/16/38400 - 1
.equ UBRR_BPS = ((CLK_FREC_MHZ * 1000000) / 4 / 38400 - 1) / 2

.if UBRR_BPS > 4095
 .error "UBRR_BPS debe ser menor que 4095"
.endif

usart_configurar:
    ldi r16, LOW(UBRR_BPS)
    sts UBRR0L, r16
    ldi r16, HIGH(UBRR_BPS)   ; Configurar baud rate
    sts UBRR0H, r16
    
	ldi r16, (1 << U2X0)
	sts UCSR0A, r16

    ; Activar transmisión y recepción USART.
    ldi r16, (1 << RXEN0) | (1 << TXEN0) | (1 << RXCIE0) | (1 << UDRIE0)
    sts UCSR0B, r16
    
    ; 8 bits de datos, sin paridad, 1 bit de parada (8N1)
    ldi r16, (0 << USBS0) | (1 << UCSZ01) | (1 << UCSZ00)
    sts UCSR0C, r16
    ret

usart_transmitir:
	; Entrada: r16 - Byte a transmitir
    lds r17, UCSR0A      ; while !tx_buffer_empty() {
    andi r17, 1 << UDRE0 ;     ;
    breq usart_transmitir  ; }
    sts UDR0, r16        ; tx_buffer = r16
    ret