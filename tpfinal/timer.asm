timer_configurar:
	; Configurar el timer 1 en modo normal, con ticks cada 0.5uS, overflow cada 32.768ms

    ; WGM11 = WGM10 = 0 (modo normal)
    ; COM1A1 = COM1A0 = COM1B1 = COM1B0 = 0 (salidas desconectadas)
    ; 0b0000xx00
    sts TCCR1A, zero

    ; WGM12 = WGM13 = 0 (modo normal)
    ; CS12 = 0, CS11 = 1, CS10 = 0 (preescaler 8)
	; ICNC1 = 0 (noise canceler desactivado)
	; ICES1 = 0 (falling edge trigger)
	ldi r16, (0 << CS12) | (1 << CS11) | (0 << CS10) \
			 | (0 << WGM13) | (0 << WGM12) \
			 | (0 << ICNC1) | (0 << ICES1)
    sts TCCR1B, r16
	ret

; Devuelve el valor actual del timer 1 y lo reinicia a 0
timer_capturar:
	; Generar un evento de captura por software
	cbi PORTB, DDB0    ; El timer captura en el falling edge
	sbi PORTB, DDB0    ; Volver a subir el pin para la próxima captura

	; Copiar ICR1 en r0:r1
	lds retl, ICR1L
	lds reth, ICR1H

	; Reiniciar timer
	sts TCNT1H, zero
	sts TCNT1L, zero
	ret