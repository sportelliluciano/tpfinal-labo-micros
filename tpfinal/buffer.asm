
.def buffer_head = r10
.def buffer_tail = r11

.dseg 
.equ PACKET_SZ = 4          ; 3 bytes + padding
.equ BUFFER_SZ = (1 << 8)   ; 256 bytes = 64 paquetes
BUFFER: .byte BUFFER_SZ     ; Búfer de 256 bytes = se aprovecha el overflow de enteros de 8 bits.

.cseg
buffer_init:
	clr buffer_head
	clr buffer_tail
	ret

; Copia paq1:paq2:paq3 al buffer
; Devuelve 0 si había espacio, FFFF en caso contrario.
buffer_push_packet:
	push XL
	push XH

	ldi XL, PACKET_SZ
	add XL, buffer_head
	cp XL, buffer_tail
	breq bpp_sin_espacio      ; if buffer_head + sizeof(packet) == buffer_tail: goto sin_espacio
	
	ldi XL, LOW(BUFFER)
	ldi XH, HIGH(BUFFER)
	add XL, buffer_head
	adc XH, zero              ; X = &BUFFER + buffer_head
	
	st X+, paq1 
	clr reth
	st X+, paq2 
	clr retl
	st X+, paq3 
	st X+, zero

	ldi XL, PACKET_SZ
	add buffer_head, XL
	rjmp bpp_fin
bpp_sin_espacio:
	ldi XH, 0xFF
	mov reth, XH
	mov retl, XH
bpp_fin:
	pop XH
	pop XL
	ret


; Copia un paquete del búfer en r6:r7:r8, devuelve 0x0000.
; Si no hay datos devuelve 0xFFFF
buffer_get_packet:
	push XL
	push XH

	cp buffer_tail, buffer_head
	breq bgp_sin_datos

	ldi XL, LOW(BUFFER)
	ldi XH, HIGH(BUFFER)
	add XL, buffer_tail
	adc XH, zero
	
	ld paq1, X+
	clr reth
	ld paq2, X+
	clr retl
	ld paq3, X+
	
	ldi XL, PACKET_SZ
	add buffer_tail, XL
	rjmp bgp_fin
bgp_sin_datos:
	ldi XH, 0xFF
	mov reth, XH
	mov retl, XH
bgp_fin:
	pop XH
	pop XL
	ret

; Copia un byte del búfer en r6, devuelve 0x0000.
; Si no hay datos devuelve 0xFFFF
buffer_get_byte:
	push XL
	push XH
	push r16

	cp buffer_tail, buffer_head
	breq bgb_sin_datos

	ldi XL, LOW(BUFFER)
	ldi XH, HIGH(BUFFER)
	add XL, buffer_tail
	adc XH, zero

	adiw XH:XL, 3
	ld reth, X      ; paquete[3] tiene el offset al byte que se debe entregar
	
	sbiw XH:XL, 3
	add XL, reth 
	adc XH, zero    ; X = BUFFER[buffer_tail] + paquete[3]

	ld retl, X      ; retl = BUFFER[buffer_tail][paquete[3]]

	ldi r16, 2
	cp reth, r16
	brne bgb_inc_ptr
	
	ldi XL, PACKET_SZ
	add buffer_tail, XL
	rjmp bgb_fin
bgb_inc_ptr:
	ldi XL, LOW(BUFFER)
	ldi XH, HIGH(BUFFER)
	add XL, buffer_tail
	adc XH, zero
	adiw XH:XL, 3
	inc reth
	st X, reth
	clr reth
	rjmp bgb_fin
bgb_sin_datos:
	ldi XH, 0xFF
	mov reth, XH
	mov retl, XH
bgb_fin:
	pop r16
	pop XH
	pop XL
	ret