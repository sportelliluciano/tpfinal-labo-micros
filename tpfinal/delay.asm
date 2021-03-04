; ---------------------------- RUTINAS DE RETARDO ----------------------------
; Cantidad de ciclos necesarios para retardar la ejecución durante 1ms.
; Esta constante dividido 400 debe entrar en un registro para que la rutina 
; funcione correctamente. Esto limita las frecuencias de clock de 2MHz a 
; aproximadamente 100MHz. Dado que el microcontrolador funciona a 8MHz en Proteus
; y a 16MHz en la placa Arduino no debería haber ningún problema.
; Adicionalmente, cuando CLK_FREC_MHZ*1000 es divisible por 400, no se producen
; errores de redondeo. Esto sucede, en particular, para 8MHz y 16MHz.
.equ CICLOS_PER_MS = CLK_FREC_MHZ * 1000
.if CICLOS_PER_MS / 400 > 256
 .error "CICLOS_PER_MS / 400 debe entrar en un registro"
.endif
; ***************************************************************************
; **** Cálculo de la cantidad de ciclos tomados por la rutina de retardo ****
; ***************************************************************************
; _delay1ms = call + ldi + mov + delay1ms_preloop + ldi + delay1ms_final + ret
; _delay1ms = 11 + delay1ms_preloop + delay1ms_final
;  delay1ms_preloop = (CPM/400-1)*(ldi + nop + delay1ms_loop + dec + branch) - 1
;   delay1ms_loop = 99*(nop + dec + branch) - 1 = 395
;  delay1ms_preloop = (CPM/400-1)*(ldi + nop + 395 + dec + branch) - 1
;  delay1ms_preloop = (CPM/400-1)*400 - 1 = CPM-399
;  delay1ms_final = 97*(nop+dec+branch)-1 = 387
; _delay1ms = 11 + CPM - 399 + 387 = CPM - 1
_delay1ms:
    ldi r21, (CICLOS_PER_MS / 400) - 1
    mov r8, r21              ; r8 = (CICLOS_PER_MS / 400) - 1
  delay1ms_preloop:          ; while r8 > 0 {
    ldi r21, 99              ;   r21 = 99
    nop                      ;   
  delay1ms_loop:             ;   while r21 > 0 {
    nop                      ;
    dec r21                  ;     r21--
    brne delay1ms_loop       ;   }
    dec r8                   ;   r8--
    brne delay1ms_preloop    ; }
  
    ldi r21, 97              ; r16 = 97
  delay1ms_final:            ; while r16 > 0 {
    nop                      ;
    dec r21                  ;   r21--
    brne delay1ms_final      ; }
    ret

; Rutina de retardo variable de 1ms a 256ms
; r16 = Tiempo de retardo en milisegundos, 0 equivale a 256ms.
delayms:
	push r21 ; Guardar registros extra >= 16 (r21 usado por _delay1ms)
	push r8
 delayms_loop:
	call _delay1ms
    dec r16
    brne delayms_loop

	pop r8
	pop r21 ; Restaurar registros
    ret