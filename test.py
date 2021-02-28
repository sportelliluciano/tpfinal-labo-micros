# ADC genera 1 muestra cada 104uS
# Se deberían enviar 10 bits cada 104uS
# A 115.200bps enviamos 1 bit cada 8.7uS
# Podríamos enviar 10 bits cada 87uS (por ej: LLLH)
# 16 bits requieren 139.2uS para enviarse
# 8 bits requieren 70uS para enviarse
# 1 ciclo de clock = 0.0625uS

# A 250.000bps enviamos 1 bit cada 4uS
# 16 bits cada 64uS
# 32 bits cada 128uS

# 24 bits cada 96uS

# 32 bits = PWM [TsL:TsH TbL:TbH]
# 

# Si fuera a 115.200bps
# 24 bits = 208uS

# Si fuera a 250.000bps
#          |   ID   | ADCL | ADCL
#          00II HHHH  ; I = ID; H = bit alto
# 24 bits: ID ADCL ADCL (cada muestra)   // se envian cada 96uS / 104uS
# 24 bits: ID PWML PWMH (tiempo en alto) // 1 cada 8ms
# 24 bits: ID PWML PWMH (tiempo en bajo) //

# while (true) {
#    if pwm: enviar pwm (como mucho cambia 1 vez cada 8ms)
#    if buffer del adc no esta vacio: enviar adc (cambia 1 vez cada 104uS)
# }
# BUFFER DEL ADC: [ ADCL, ADCL, ... ]

# - Bufferear las muestras del ADC en un buffer de (aprox) 10 muestras
# - Guardamos mediciones del PWM en una variable (no hace falta buffer porque es 1 cada 8ms)
# - En ISR - TX: transmitir desde el buffer del ADC a menos que haya nueva muestra de PWM.


import numpy as np
from matplotlib import pyplot
from matplotlib.animation import FuncAnimation
from random import randrange
import time
import struct
import threading
import serial

x_data, y_data, pwm_data = [0], [0], [0]

figure = pyplot.figure()
pyplot.grid(which='both', axis='both')
pyplot.xlabel('Tiempo [ms]')
pyplot.ylabel('Vc [V]')
line, = pyplot.plot(x_data, y_data, '-')
pwm_line, = pyplot.plot(x_data, pwm_data, '-')
scatter = pyplot.scatter(x_data, y_data)

muestras_por_segundo = 100

TIMEOUT=10 # Si no hay datos por 1 segundo terminar
BUFFER_SIZE = 20480 # No más de 20480 muestras en buffer

FCPU = 16000000
TIME_BETWEEN_SAMPLES = (128 / FCPU) * 13.5
SAMPLES_PER_SECOND = int(1/TIME_BETWEEN_SAMPLES)
SAMPLES_OFFSET = int(0.005 * SAMPLES_PER_SECOND)

def hear_port():
    pwm_is_low = False
    last_tlow = 0
    last_thigh = 0    
    global y_data
    global x_data
    global muestras_por_segundo
    with serial.Serial('COM5', 115200, timeout=TIMEOUT) as port:
        time.sleep(3)
        port.write(b'L') # Enviar un byte para iniciar el programa
        t1 = time.time()
        n_muestras = 0
        while True:
            data = port.read(3)
            if len(data) != 3:
                print(f'No data in {TIMEOUT} seconds... quitting...')
                return
            if data[0] & 0b11000000 or data[0] & 0b00110000 == 0:
                print(f'Discarding byte to sync ({bin(data[0])}, {bin(data[1])})')
                next_byte = port.read(1)
                if not next_byte:
                    print(f'No data in {TIMEOUT} seconds... quitting...')
                    return
                continue
            
            tag = data[0] & 0b00110000
            if tag == 0b00010000:
                # Dos muestras del ADC
                # 0b00II AABB AAAA AAAA BBBB BBBB
                muestra_1 = ((data[0] & 0b00001100) << 6) | data[1]
                muestra_2 = ((data[0] & 0b00000011) << 8) | data[2]
                
                for adc_val in (muestra_1, muestra_2):
                    y_data.append(adc_val * 5.0 / 1024)
                    x_data.append(x_data[-1] + TIME_BETWEEN_SAMPLES)
                    pwm_data.append(5 * pwm_is_low)
                    n_muestras += 1
            elif tag == 0b00100000:
                # TL del PWM
                tlow, = struct.unpack(">H", data[1:])
                if abs(tlow - last_tlow) > 10:
                    last_tlow = tlow
                    print('PWM Tlow:', tlow * 0.5e-3, 'ms')
                pwm_is_low = not pwm_is_low
            elif tag == 0b00110000:
                # TH del PWM
                thigh, = struct.unpack(">H", data[1:])
                if abs(thigh - last_thigh) > 10:
                    last_thigh = thigh
                    print('PWM Thigh:', thigh * 0.5e-3, 'ms')
                pwm_is_low = not pwm_is_low
            
            if time.time() - t1 > 1:
                muestras_por_segundo = n_muestras
                n_muestras = 0
                t1 = time.time()

def find_trigger(samples, level=1.5, number=1, default=0):
    trigger_edge = 'rising'
    trigger_id = 0
    for i, sample in enumerate(samples[:-1]):
        if trigger_edge == 'rising' and samples[i+1] > sample and samples[i+1] >= level:
            if trigger_id == number:
                return i
            else:
                trigger_id += 1           #  Si se detectó el un trigger en el rising edge...
                trigger_edge = 'falling'  #  ...esperar un trigger en el falling edge...
        elif trigger_edge == 'falling' and samples[i+1] < sample and sample >= level: 
            trigger_edge = 'rising'       # ...para finalmente detectar el siguiente trigger en el rising edge.
    return default

def update(frame):
    global x_data
    global y_data
    global pwm_data

    #final_trigger = len(y_data) - find_trigger(list(reversed(y_data)), number=1)
    #initial_trigger = len(y_data) - find_trigger(list(reversed(y_data)), number=3, default=len(y_data))

    final_trigger = len(pwm_data) - find_trigger(list(reversed(pwm_data)), number=1)
    initial_trigger = len(pwm_data) - find_trigger(list(reversed(pwm_data)), number=3, default=len(pwm_data))

    t_primer_muestra = x_data[initial_trigger]
    t_data = [ 1000 * (t_muestra - t_primer_muestra) for t_muestra in x_data[initial_trigger:final_trigger] ]

    line.set_data(t_data, y_data[initial_trigger:final_trigger])
    pwm_line.set_data(t_data, pwm_data[initial_trigger:final_trigger])
    scatter.set_offsets(list(zip(t_data, y_data[initial_trigger:final_trigger])))
    figure.gca().set_ylim(0, 5)
    figure.gca().set_xlim(0, 35)
    figure.gca().relim()
    figure.gca().autoscale_view()

    x_data = x_data[-BUFFER_SIZE:]
    y_data = y_data[-BUFFER_SIZE:]
    pwm_data = pwm_data[-BUFFER_SIZE:]
    return line, scatter

thread = threading.Thread(target=hear_port)
thread.start()
animation = FuncAnimation(figure, update, interval=200)
pyplot.show()
thread.join()