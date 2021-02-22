import numpy as np
from matplotlib import pyplot
from matplotlib.animation import FuncAnimation
from random import randrange
import time
import struct
import threading
import serial

x_data, y_data = [0], [0]

figure = pyplot.figure()
pyplot.grid(which='both', axis='both')
pyplot.xlabel('Muestra')
pyplot.ylabel('Vc')
line, = pyplot.plot(x_data, y_data, '-')
scatter = pyplot.scatter(x_data, y_data)

muestras_por_segundo = 100

TIMEOUT=10 # Si no hay datos por 1 segundo terminar
BUFFER_SIZE = 2048 # No más de 2048 muestras en buffer

def hear_port():
    global y_data
    global x_data
    global muestras_por_segundo
    with serial.Serial('COM4', 38400, timeout=TIMEOUT) as port:
        t1 = time.time()
        n_muestras = 0
        while True:
            data = port.read(2)
            if len(data) != 2:
                print(f'No data in {TIMEOUT} seconds... quitting...')
                return
            if data[0] & 0xF0:
                print(f'Discarding byte to sync ({bin(data[0])}, {bin(data[1])})')
                next_byte = port.read(1)
                if not next_byte:
                    print(f'No data in {TIMEOUT} seconds... quitting...')
                    return
                data = data[1:] + next_byte
            
            adc_val = struct.unpack(">H", data)[0]
            y_data.append(adc_val * 5.0 / 1024)
            x_data.append(x_data[-1] + 1)
            n_muestras += 1

            if time.time() - t1 > 1:
                muestras_por_segundo = n_muestras
                n_muestras = 0
                t1 = time.time()

def find_trigger(samples, level=1.5, number=1, default=0):
    trigger_edge = 'rising'
    trigger_id = 0
    for i, sample in enumerate(samples[:-1]):
        if sample >= level:
            if trigger_edge == 'rising' and samples[i+1] > sample:
                if trigger_id == number:
                    return i
                else:
                    trigger_id += 1           #  Si se detectó el un trigger en el rising edge...
                    trigger_edge = 'falling'  #  ...esperar un trigger en el falling edge...
            elif trigger_edge == 'falling' and samples[i+1] < sample: 
                trigger_edge = 'rising'       # ...para finalmente detectar el siguiente trigger en el rising edge.

    return default

def update(frame):
    global x_data
    global y_data

    final_trigger = len(y_data) - find_trigger(list(reversed(y_data)), number=1)
    initial_trigger = len(y_data) - find_trigger(list(reversed(y_data)), number=3, default=len(y_data))

    t_data = [ muestra / muestras_por_segundo for muestra in range(len(x_data[initial_trigger:final_trigger])) ]

    line.set_data(t_data, y_data[initial_trigger:final_trigger])
    scatter.set_offsets(list(zip(t_data, y_data[initial_trigger:final_trigger])))
    figure.gca().set_ylim(0, 5)
    figure.gca().relim()
    figure.gca().autoscale_view()

    x_data = x_data[-BUFFER_SIZE:]
    y_data = y_data[-BUFFER_SIZE:]
    return line, scatter

thread = threading.Thread(target=hear_port)
thread.start()
animation = FuncAnimation(figure, update, interval=200)
pyplot.show()
thread.join()