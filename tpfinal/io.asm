io_configurar:
	; Configurar 
	;  - PORTD.2 (INT0) como entrada por interrupci�n 
	;  - PORTB.0 (ICP1) como salida para generar captura por software
	;  - PORTD.6 como salida PWM
	ldi r16, (1 << DDB0)
	out DDRB, r16
	ldi r16, (0 << DDD2) | (1 << DDD6)
    out DDRD, r16

	; PORTB.0 inicialmente en 1 porque el timer detecta el falling edge
	sbi PORTB, DDB0

	; INT0 responde al cualquier cambio l�gico
	ldi r16, (0 << ISC01) | (1 << ISC00)
	sts EICRA, r16
	
	; Activar interrupciones para INT0
	ldi r16, (1 << INT0)
	out EIMSK, r16
    ret