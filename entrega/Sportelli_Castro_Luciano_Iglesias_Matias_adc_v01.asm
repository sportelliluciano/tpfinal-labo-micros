adc_configurar:
	; ADMUX: REFS1:0 | ADLAR |  -  | MUX3:0
	;           01       0      0     0000
	; REFS1:0 = 01   -- Referencia desde AVCC
	; ADLAR   = 0    -- Justificar el resultado a derecha
	; MUX3:0  = 0000 -- Utilizar ADC0
	ldi r16, (0 << REFS1) | (1 << REFS0) | \
	         (0 << ADLAR) | \
			 (0 << MUX3) | (0 << MUX2) | (0 << MUX1) | (0 << MUX0)
	sts ADMUX, r16

	; ADCSRA: ADEN | ADSC | ADATE | ADIF | ADIE | ADPS2:0
	;           1      0      1       -      1      111
	; ADEN    = 1   -- Habilitar ADC
	; ADSC    = 1   -- Iniciar conversión
	; ADATE   = 1   -- Activar trigger automático
	; ADIE    = 1   -- Habilitar interrupción de conversión completa
	; ADPS2:0 = 111 -- Preescaler = 128 (125kHz @ 16MHz; 62.5kHz @ 8Mhz)
	ldi r16, (1 << ADEN) | (1 << ADSC) | (1 << ADATE) | \
	         (1 << ADIE) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0)
	sts ADCSRA, r16

	; ACSRB = 0 -- Free running mode
	ret