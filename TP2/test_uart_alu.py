#!/usr/bin/env python3
"""
Prueba de la ALU por UART en la Basys 3 (TP2).

Protocolo: se envian 3 bytes (A, B, OPCODE) y la placa responde 1 byte
con el resultado. Trama: 19200 baudios, 8 bits, paridad par, 1 stop (8E1).

Uso:
    python3 test_uart_alu.py                 # corre los casos de prueba
    python3 test_uart_alu.py -i              # modo interactivo
    python3 test_uart_alu.py -p /dev/ttyUSB0 # cambiar puerto

Requiere pyserial:  pip install pyserial
"""

import argparse
import random
import sys

import serial

BAUDRATE = 19200
NBIT = 8
MASK = (1 << NBIT) - 1

OPS = {
    "ADD": 0b100000,
    "SUB": 0b100010,
    "AND": 0b100100,
    "OR": 0b100101,
    "XOR": 0b100110,
    "SRA": 0b000011,
    "SRL": 0b000010,
    "NOR": 0b100111,
}


def to_signed(x):
    """Interpreta un byte como entero con signo (complemento a 2)."""
    x &= MASK
    return x - (1 << NBIT) if x & (1 << (NBIT - 1)) else x


def modelo_alu(a, b, op):
    """Modelo de referencia de alu.v: devuelve el resultado esperado (0..255)."""
    a &= MASK
    b &= MASK
    if op == "ADD":
        r = a + b
    elif op == "SUB":
        r = a - b
    elif op == "AND":
        r = a & b
    elif op == "OR":
        r = a | b
    elif op == "XOR":
        r = a ^ b
    elif op == "SRA":
        # El desplazamiento usa B sin signo; i_a es signed -> arrastra el bit de signo
        r = to_signed(a) >> min(b, NBIT)
    elif op == "SRL":
        r = a >> b if b < NBIT else 0
    elif op == "NOR":
        r = ~(a | b)
    else:
        r = 0
    return r & MASK


def abrir_puerto(port):
    return serial.Serial(
        port,
        BAUDRATE,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_EVEN,
        stopbits=serial.STOPBITS_ONE,
        timeout=1,
    )


def operar(ser, a, b, op):
    """Envia A, B y OPCODE; devuelve el byte recibido o None si hubo timeout."""
    ser.reset_input_buffer()
    ser.write(bytes([a & MASK, b & MASK, OPS[op]]))
    r = ser.read(1)
    return r[0] if r else None


def casos_de_prueba():
    """Casos de prueba para test automatico"""

    "16 casos escrito a mano"
    casos = [
        (5, 3, "ADD"),
        (127, 1, "ADD"),
        (0x80, 0x80, "ADD"),
        (0, 0, "ADD"),
        (5, 7, "SUB"),
        (0x80, 1, "SUB"),
        (10, 10, "SUB"),
        (0xF0, 0x3C, "AND"),
        (0xF0, 0x0F, "OR"),
        (0xAA, 0xFF, "XOR"),
        (0x80, 2, "SRA"),
        (0x40, 2, "SRA"),
        (0x80, 2, "SRL"),
        (0xFF, 7, "SRL"),
        (0x0F, 0xF0, "NOR"),
        (0, 0, "NOR"),
    ]

    "50 casos creados de manera aleatoria"
    rnd = random.Random(0)
    for _ in range(50):
        op = rnd.choice(list(OPS))
        b = rnd.randint(0, NBIT - 1) if op in ("SRA", "SRL") else rnd.randint(0, MASK)
        casos.append((rnd.randint(0, MASK), b, op))

    return casos


def correr_tests(ser):
    """Corre los tests automaticos y verifica los resultados"""
    fallas = 0
    casos = casos_de_prueba()
    for a, b, op in casos:
        esperado = modelo_alu(a, b, op)
        obtenido = operar(ser, a, b, op)
        ok = obtenido == esperado
        fallas += not ok
        obt_str = "timeout" if obtenido is None else f"0x{obtenido:02X}"
        print(
            f"{'OK ' if ok else 'ERR'}  {op:<3} A=0x{a:02X} B=0x{b:02X}"
            f"  esperado=0x{esperado:02X}  obtenido={obt_str}"
        )
    print(f"\n{len(casos) - fallas}/{len(casos)} casos correctos")
    return fallas == 0


def parse_num(s):
    """Acepta decimal (con signo), hex (0x..) o binario (0b..)."""
    return int(s, 0) & MASK


def modo_interactivo(ser):
    print(f"Operaciones: {', '.join(OPS)}")
    print("Formato: A B OP   (ej: 5 3 ADD, 0xF0 0x0F OR, -3 2 SRA). 'q' para salir.")
    while True:
        try:
            linea = input("> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if linea.lower() in ("q", "quit", "exit"):
            break
        partes = linea.split()
        if len(partes) != 3 or partes[2].upper() not in OPS:
            print("Formato invalido")
            continue
        try:
            a, b = parse_num(partes[0]), parse_num(partes[1])
        except ValueError:
            print("Numero invalido")
            continue
        op = partes[2].upper()
        r = operar(ser, a, b, op)
        if r is None:
            print("Timeout: no llego respuesta (probar reset con btnC)")
            continue
        esperado = modelo_alu(a, b, op)
        marca = "" if r == esperado else f"   <-- esperado 0x{esperado:02X}"
        print(f"= 0x{r:02X}  {r:3d}  (con signo: {to_signed(r):4d})  0b{r:08b}{marca}")


def main():
    parser = argparse.ArgumentParser(description="Prueba de la ALU por UART (TP2)")
    parser.add_argument(
        "-p",
        "--port",
        default="/dev/ttyUSB1",
        help="puerto serie de la Basys 3 (default: /dev/ttyUSB1)",
    )
    parser.add_argument(
        "-i",
        "--interactivo",
        action="store_true",
        help="modo interactivo en lugar de los casos de prueba",
    )
    args = parser.parse_args()

    try:
        ser = abrir_puerto(args.port)
    except serial.SerialException as e:
        sys.exit(f"No se pudo abrir {args.port}: {e}")

    with ser:
        if args.interactivo:
            modo_interactivo(ser)
        else:
            sys.exit(0 if correr_tests(ser) else 1)


if __name__ == "__main__":
    main()
