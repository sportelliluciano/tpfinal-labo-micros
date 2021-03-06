.equ UBRR_BPS = ((CLK_FREC_MHZ * 1000000) / 4 / BAUD_RATE - 1) / 2

.if UBRR_BPS > 4095
 .error "UBRR_BPS debe ser menor que 4095"
.endif

; Este archivo contiene la configuración del puerto serie y 
; la implementación de un búfer circular para los paquetes
; que se enviarán.
; Enviar un paquete significa encolarlo en el búfer. El 
; puerto serie lo enviará lo antes posible.
;
; El búfer se manjea con dos punteros: buffer_head y buffer_tail.
; Agregar un paquete al búfer desplaza buffer_head mientras que
; obtener un byte del paquete  desplaza buffer_tail.
;
; El valor que está almacenado tanto en buffer_head como en buffer_tail
; es un desplazamiento respecto del inicio del búfer. Dado que el búfer
; es de 256 bytes, se aprovecha el overflow de enteros de 8 bits en estos
; registros para no tener que ir revisando y reiniciando los valores.
;
; buffer_head siempre apunta a la posición donde se escribirá el próximo
; byte, mientras que buffer_tail siempre apunta a la posición del próximo
; byte que debe ser leido.
;
; El búfer se considera "lleno" cuando buffer_head + 4 == buffer_tail, y
; se considera vacío cuando buffer_head == buffer_tail.
;
; Si bien los paquetes son de 3 bytes, el búfer los considera de 4 bytes, es
; decir, 3 de datos y uno de padding. Esto permite simplificar la aritmética y 
; aprovechar el overflow de enteros.
;
; Cabe destacar que buffer_head siempre se incrementa de a 4, ya que siempre
; se agregan los datos de a "paquetes"; mientras que buffer_tail se incrementa
; de a uno o de a dos, ya que se lee de a bytes. Este último caso es cuando se
; llega al padding, que debe ser ignorado.

.def buffer_head = r10      ; Desplazamiento a la cabeza del búfer de transmisión
.def buffer_tail = r11      ; Desplazamiento a la cola del búfer de transmisión

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
	mov r27, buffer_tail         ; r27 = buffer_tail
	andi r27, ~(PACKET_SZ - 1)   ; r27 = buffer_tail & 0b11111100
	cp r26, r27                  ; if buffer_head + 4 == buffer_tail & 0b11111100:
	breq upp_sin_espacio         ;     no hay espacio
	
	ldi XL, LOW(BUFFER)
	ldi XH, HIGH(BUFFER)
	add XL, buffer_head
	adc XH, zero                 ; X = &BUFFER + buffer_head
	
	st X+, paq1                  ; Copiar los 3 bytes del paquete en el búfer...
	clr reth                     ; *X++ = paq1
	st X+, paq2                  ; *X++ = paq2
	clr retl                     ; ...y limpiar reth:retl.
	st X+, paq3                  ; *X++ = paq3

	ldi r26, PACKET_SZ           ; Avanzar el puntero a la cabeza del búfer
	add buffer_head, r26         ; buffer_head += 4
	
	; Activar UDRIE0. No tiene ningún efecto si ya estaba activa.
	lds r26, UCSR0B
	ori r26, (1 << UDRIE0)
	sts UCSR0B, r26

	rjmp upp_fin                 ; fin
upp_sin_espacio:
	sbi PORTB, 5 ; DEBUG: Encender led de packet dropped
upp_fin:
	ret

; Obtiene un byte del búfer de transmisión, devuelve 0x00BB, donde BB es el valor del byte.
; Si no hay datos devuelve 0xFFXX, donde XX significa cualquier valor.
usart_get_byte_tx:
	cp buffer_tail, buffer_head ; Revisar si el búfer está vacío
	breq ugb_sin_datos          ; if buffer_tail == buffer_head: no hay datos

	ldi XL, LOW(BUFFER)
	ldi XH, HIGH(BUFFER)
	add XL, buffer_tail
	adc XH, zero                 ; X = BUFFER + buffer_tail

	clr reth                     ; reth = 0x00
	ld retl, X					 ; retl = BUFFER[buffer_tail][buffer_byte_index]
	inc buffer_tail              ; buffer_tail++

	ldi r26, (PACKET_SZ - 1)
	and r26, buffer_tail         ; r26 = buffer_tail & 0b00000011 (buffer_tail % 4)
	cpi r26, 3                   ; if buffer_tail & 0b11 != 3:
	brne ugb_fin                 ;    fin
	inc buffer_tail              ; else: saltear padding
	rjmp ugb_fin
ugb_sin_datos:
	; Desactivar UDRIE0. Si el búfer está vacío, desactivar UDRIE0.
	lds r26, UCSR0B
	andi r26, ~(1 << UDRIE0)
	sts UCSR0B, r26
	
	; Devolver 0xFFxx
	ldi r26, 0xFF
	mov reth, r26
ugb_fin:
	ret