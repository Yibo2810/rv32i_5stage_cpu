#!/usr/bin/env python3
"""Send a program to uart_loader (fpga_sys, sw[2] load mode) over the board's USB-UART.

Frame (the only definition of the format; fpga_sys_tb sends what --out writes):

    "RVLD"  |  len (4 B, little endian)  |  len image bytes  |  sum (4 B, little endian)

    len  = image size in bytes, padded with zeros to a multiple of 4, at most 64 KB
    sum  = sum of the image bytes, modulo 2**32

The loader writes the image to RAM from 0x8000_0000 and releases the core when the sum
matches. It sends nothing back: watch the board (blue LED off = loaded, red = bad sum).

    tools/uart_load.py oled_term                      rtl/fpga/build/oled_term.bin -> default port
    tools/uart_load.py path/to/prog.bin --monitor     then print what the program sends
    tools/uart_load.py oled_term --port COM7          another port
    tools/uart_load.py --list                         show the serial ports on this machine
    tools/uart_load.py oled_term --out f.frame        write the frame to a file, no serial port

Default port: COM13 on Windows, /dev/ttyUSB1 on Linux (the Arty's FT2232 makes two
devices there: ttyUSB0 = JTAG, ttyUSB1 = UART). Needs Python 3 and pyserial
(pip install pyserial). On Windows only one program can open a COM port: close PuTTY /
Tera Term before running this, and use --monitor to see the output.

Board: sw[2] up first (blue LED on), then run this. After a load the loader stays in DONE and
ignores further frames (the running program owns the UART), so to load again press reset with
sw[2] still up (blue LED on again), or toggle sw[2]. With sw[2] down, reset reruns the program
already in RAM. On Linux a terminal can stay open on the port while this sends (two
openers are allowed), but not with --monitor: two readers split the bytes between them.
"""
import argparse
import struct
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PORT = "COM13" if sys.platform.startswith("win") else "/dev/ttyUSB1"
MAGIC = b"RVLD"
RAM_BYTES = 64 * 1024          # peripherals.sv: SOC_RAM_AW = 16


def image_path(arg: str) -> Path:
    """A path to a .bin, or a program name under sw/programs (built by sw/Makefile)."""
    p = Path(arg)
    if p.suffix == ".bin" or p.exists():
        return p
    return ROOT / "rtl" / "fpga" / "build" / f"{arg}.bin"


def build_frame(image: bytes) -> bytes:
    image += b"\0" * (-len(image) % 4)
    if not 0 < len(image) <= RAM_BYTES:
        sys.exit(f"image is {len(image)} bytes, the loader takes 4 .. {RAM_BYTES}")
    total = sum(image) & 0xFFFFFFFF
    return MAGIC + struct.pack("<I", len(image)) + image + struct.pack("<I", total)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("program", nargs="?", help="program name (e.g. oled_term) or path to a .bin")
    ap.add_argument("--port", default=DEFAULT_PORT, help=f"serial port (default here: {DEFAULT_PORT})")
    ap.add_argument("--list", action="store_true", help="list the serial ports on this machine and exit")
    ap.add_argument("--baud", type=int, default=115200, help="must match SOC_UART_BAUD (default 115200)")
    ap.add_argument("--monitor", action="store_true", help="after sending, print what the board sends (Ctrl-C ends)")
    ap.add_argument("--out", metavar="FILE", help="write the frame to FILE instead of sending it")
    args = ap.parse_args()

    if args.list:
        from serial.tools import list_ports
        ports = [p for p in list_ports.comports() if p.description != "n/a"]   # skip Linux's empty ttyS*
        for p in ports:
            ftdi = "  <- FTDI (Arty USB-UART)" if p.vid == 0x0403 else ""
            print(f"{p.device:16s} {p.description}{ftdi}")
        if not ports:
            print("no serial ports found (board unplugged, or driver missing)")
        return
    if not args.program:
        ap.error("give a program name or a .bin path (or --list)")

    path = image_path(args.program)
    if not path.exists():
        sys.exit(f"{path} not found (build it: make -C sw PROG={args.program})")
    frame = build_frame(path.read_bytes())
    length = struct.unpack_from("<I", frame, 4)[0]
    total = struct.unpack_from("<I", frame, len(frame) - 4)[0]
    print(f"{path.name}: {length} bytes ({length // 4} words), sum {total:08x}, frame {len(frame)} bytes")

    if args.out:
        Path(args.out).write_bytes(frame)
        print(f"frame written to {args.out}")
        return

    import serial                                    # pyserial; only needed when sending
    seconds = len(frame) * 10 / args.baud            # 8N1: 10 bits per byte
    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.1)
    except serial.SerialException as e:
        sys.exit(f"cannot open {args.port}: {e}\n"
                 f"  wrong port? see --list.  Windows: is PuTTY / Tera Term still holding it?")
    with ser:
        ser.reset_input_buffer()                     # --monitor shows only what comes after the load
        ser.write(frame)
        ser.flush()                                  # returns once the OS has taken every byte
        time.sleep(seconds + 0.05)                   # let the USB-UART chip shift them out
        print(f"sent to {args.port} in about {seconds:.2f} s; blue LED off = loaded, red LED = bad sum")
        if args.monitor:
            print("--- monitor (Ctrl-C to quit) ---")
            try:
                while True:
                    data = ser.read(256)
                    if data:
                        sys.stdout.write(data.decode("ascii", errors="replace"))
                        sys.stdout.flush()
            except KeyboardInterrupt:
                print()


if __name__ == "__main__":
    main()
