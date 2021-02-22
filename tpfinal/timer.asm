timer_configurar:
	; Configurar el timer 1 en modo normal, con ticks cada 64uS, overflow cada 4.19 seg.

    ; WGM11 = WGM10 = 0 (modo normal)
    ; COM1A1 = COM1A0 = COM1B1 = COM1B0 = 0 (salidas desconectadas)
    ; 0b0000xx00
    sts TCCR1A, zero

    ; WGM12 = WGM13 = 0 (modo normal)
    ; CS12 = 0, CS11 = 1, CS10 = 0 (preescaler 1024)
	; ICNC1 = 0 (noise canceler desactivado)
	; ICES1 = 0 (falling edge trigger)
	ldi r16, (0 << CS12) | (1 << CS11) | (0 << CS10) \
			 | (0 << WGM13) | (0 << WGM12) \
			 | (0 << ICNC1) | (0 << ICES1)
    sts TCCR1B, r16

	ret

; Reinicia el timer a 0
timer_reiniciar:
	sts TCNT1H, zero
	sts TCNT1L, zero
	ret

; Copia el valor actual del timer en r0:r1
timer_capturar:
	; Generar un evento de captura por software
	cbi PORTB, DDB0
	sbi PORTB, DDB0

	; Copiar ICR1 en r0:r1
	lds retl, ICR1L
	lds reth, ICR1H
	ret