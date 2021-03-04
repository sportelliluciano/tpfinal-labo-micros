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

TIMEOUT = 10 # Si no hay datos por 10 segundos terminar
BUFFER_SIZE = 20480 # No más de 20480 muestras en buffer

FCPU = 16000000
TIME_BETWEEN_SAMPLES = (128 / FCPU) * 13.5
SAMPLES_PER_SECOND = int(1/TIME_BETWEEN_SAMPLES)
SAMPLES_OFFSET = int(0.005 * SAMPLES_PER_SECOND)
PORT = 'COM4'
BAUD_RATE = 230400
WAIT_BEFORE_START = 3  # El Arduino se reinicia a abrir el puerto:
                       #  - Esperar WAIT_BEFORE_START segundos antes de empezar.

# Resolución del tick del PWM
PWM_RESOLUTION_MS = 0.5e-3

def hear_port():
    pwm_is_low = False
    last_tlow = 0
    last_thigh = 0    
    global y_data
    global x_data
    
    with serial.Serial(PORT, BAUD_RATE, timeout=TIMEOUT) as port:
        time.sleep(WAIT_BEFORE_START)
        port.write(b'L') # Enviar un byte para iniciar el programa
        t1 = time.time()
        last_adc_packets = adc_packets = 0
        last_pwm_packets = pwm_packets = 0
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

                adc_packets += 1
            elif tag == 0b00100000: # Flanco ascendente
                # TL del PWM
                tlow, = struct.unpack(">H", data[1:])
                if abs(tlow - last_tlow) > 10:
                    last_tlow = tlow
                    print('PWM Tlow:', tlow * PWM_RESOLUTION_MS, 'ms')
                pwm_is_low = False
                pwm_packets += 1
            elif tag == 0b00110000: # Flanco descendente
                # TH del PWM
                thigh, = struct.unpack(">H", data[1:])
                if abs(thigh - last_thigh) > 10:
                    last_thigh = thigh
                    print('PWM Thigh:', thigh * PWM_RESOLUTION_MS, 'ms')
                pwm_is_low = True
                pwm_packets += 1
            
            if time.time() - t1 > 1:
                t1 = time.time()
                adc_packets_seg = adc_packets - last_adc_packets
                pwm_packets_seg = pwm_packets - last_pwm_packets
                # 24 bits por paquete + 3 bits de inicio + 3 de parada
                bits_per_seg = (adc_packets_seg + pwm_packets_seg) * (24 + 3 + 3)
                print(f'{adc_packets=}, {pwm_packets=},', 
                      f'ADC: {2 * adc_packets_seg} muestras/seg,',
                      f'PWM: {pwm_packets_seg} muestras/seg,',
                      f'{bits_per_seg} bps')
                last_adc_packets = adc_packets
                last_pwm_packets = pwm_packets

def find_trigger(samples, level=1.5, number=1, default=0):
    '''
    Simulación simple del disparo de un osciloscopio en base al
    nivel y flanco ascendente de la señal.

    Devuelve el índice de la primer muestra que esté detrás de
    de `number` flancos ascendentes con valor superior a `level`.

    Si no se cumple para ninguna muestra se devolverá el valor
    `default`.
    '''
    trigger_edge = 'rising'
    trigger_id = 0
    for i, sample in enumerate(samples[:-1]):
        if trigger_edge == 'rising' and samples[i+1] > sample and samples[i+1] >= level:
            if trigger_id == number:
                return i
            else:
                trigger_id += 1          #  Si se detectó el un trigger en el rising edge...
                trigger_edge = 'falling' #  ...esperar un trigger en el falling edge...
        elif trigger_edge == 'falling' and samples[i+1] < sample and sample >= level: 
            trigger_edge = 'rising'      # ...para finalmente detectar el siguiente 
                                         # trigger en el rising edge.
    return default

def update(frame):
    global x_data
    global y_data
    global pwm_data

    final_trigger = len(pwm_data) - find_trigger(list(reversed(pwm_data)), 
                                                 number=1)
    initial_trigger = len(pwm_data) - find_trigger(list(reversed(pwm_data)), 
                                                   number=3, 
                                                   default=len(pwm_data))

    t_primer_muestra = x_data[initial_trigger]
    t_data = [ 1000 * (t_muestra - t_primer_muestra) \
               for t_muestra in x_data[initial_trigger:final_trigger] ]

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