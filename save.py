import time
import serial
import struct

TIMEOUT = 1
def hear_port(port_name, baud_rate):
    print(f'Hearing {port_name} at {baud_rate} bps')
    try:
        with serial.Serial(port_name, baud_rate, timeout=TIMEOUT) as port, \
            open('salida.csv', 'w') as salida:
            t1 = time.time()
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
                salida.write(f'{time.time() - t1},{adc_val}\n')
    except KeyboardInterrupt:
        return

hear_port('COM5', 38400)
            