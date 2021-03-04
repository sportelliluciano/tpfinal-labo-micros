pwm_configurar:
	; Configurar PWM para tener un ciclo de 16.67ms (60Hz) a 16MHz.

	; Considerando Fclk = 16MHz, preescaler = 1024 y que la resolución
	; es de 8 bits:
	; Tpwm = (1024 * 256) / 16.000.000Hz = 16.384ms => 60Hz ± 3%
	; Referencia: Datasheet 14.7.3 (página 80)

    ; Duty inicial = 50%
    ldi r16, 0x7F   ; Ver si esto no debería ser 0x80
    out OCR0A, r16

	; Modo Fast PWM, TOP = 0xFF
    ; COM0A1 = 1; COM0A0 = 0. (no inversor)
    ; COM0B1 = COM0B0 = 0. (desactivado)
    ; WGM01 = 1; WGM10 = 1. (Fast PWM / 0xFF)
    ; 0b0100xx01
    ldi r16, (1 << COM0A1) | (0 << COM0A0) | \
             (0 << COM0B1) | (0 << COM0B0) | \
             (1 << WGM01) | (1 << WGM00)
    out TCCR0A, r16

    ; WGM02 = 0 (FastPWM / 0xFF)
    ; Preescaler = 0
    ; CS02 = 0; CS01 = CS00 = 1
    ldi r16, (0 << WGM02) | \
             (1 << CS02) | (0 << CS01) | (1 << CS00)
    out TCCR0B, r16
    ret