# SoC, Software and Board

`fpga_sys` (`rtl/fpga/rtl/`) wraps the core with memory and peripherals and has
no FPGA primitives. `arty_a7_top` (`rtl/fpga/arty_a7/`) adds the clock, reset
and board I/O for a Digilent Arty A7-100T.

```text
                 fetch port
  core_5stage ------------------------------+
       |                                    v
       | data port                    +-----------+
       +--> dmem_xbar --- RAM ------> |  sys_ram  | <-- uart_loader (sw[2] mode)
                  |                   |   64 KB   |
                  +------ MMIO -----> +-----------+
                  |        |
          unmapped:        +--> mmio_regs: UART 16550 subset, tohost, OLED text + color
          bus_err                      |
                                       +--> uart_tx / uart_rx ---- USB-UART
  halt_reporter (panic line) ----------+
  oled_ctrl (init + renderer) ------------------------------------ Pmod OLEDrgb
```

## Address map

| Region | Base | Size | Notes |
|---|---|---|---|
| RAM | `0x8000_0000` | 64 KB | Text and data; reset PC = `0x8000_0000` |
| MMIO | `0x1000_0000` | 4 KB | Registers below |
| Anything else | | | Load returns 0, store is dropped, sticky `bus_err` is set and the first such address is latched |

Only the data port is decoded. The fetch port goes straight to `sys_ram`, so a
fetch outside RAM wraps around inside it instead of faulting. `bus_err` is a
flag, not an exception.

## MMIO registers (base `0x1000_0000`)

| Offset | Register | Access |
|---|---|---|
| `0x000`–`0x01C` | UART, 16550 subset, one register per word (reg-shift 2) | see below |
| `0x100` | `tohost`: the program's result, `1` = PASS | W |
| `0x200`–`0x3FC` | OLED text: row `r`, column `c` at `0x200 + (16·r + c)·4`, one character per word; 12 visible columns, rows 1–7 shown (row 0 is the status row) | W |
| `0x400`–`0x41C` | OLED text color per row, RGB565 (0 = white) | W |

Other offsets read 0 and ignore writes.

**UART.** 115200 baud, 8N1, fixed at build time (25 MHz / 217).

| Register | Implemented |
|---|---|
| RBR / THR | One-byte receive and transmit, no FIFO |
| LSR | DR, OE, FE, THRE, TEMT |
| LCR | Read/write; DLAB switches offsets 0/1 to DLL/DLM |
| IER, MCR, SCR, DLL, DLM | Read/write storage only (no interrupts, no divisor) |
| IIR | Reads `0x01` (no interrupt pending) |

**OLED.** Pmod OLEDrgb (SSD1331, 96 × 64) on Pmod JA, SPI mode 3. The
controller runs on its own:

1. After reset, a small command ROM powers the panel up and initializes it.
2. A renderer then scans the screen continuously and looks every pixel up in
   the text buffer and an 8 × 8 font. The CPU only writes characters and
   colors.

Row 0 is a hardware status row: `RUN` on green, `PASS` on yellow, `FAIL` on
red. After a failing halt, rows 1–7 show the trap cause, PC, `tohost` and bus
error instead of the CPU text. An interactive model of the renderer:
[demo/oled_render.html](demo/oled_render.html).

**Panic line.** Once the core halts, `halt_reporter` prints this line on the
UART and repeats it every second:

```text
HALT PASS cause=3 pc=80000040 tohost=00000001 buserr=0 addr=00000000
```

The program's UART output and the panic line share one transmitter. The
panic line starts only after the halt.

## UART loader

With `sw[2]` up, `uart_loader` holds the core and all peripherals in reset and
waits for a frame on the UART:

```text
"RVLD" | length (4 bytes, little endian) | image | sum (4 bytes, little endian)
```

- `length` is the image size in bytes: a multiple of 4, from 4 to 65536.
- The image is written to RAM from `0x8000_0000`.
- `sum` is the sum of the image bytes, modulo 2^32.
- On a match the core leaves reset and runs the new program.
- On a mismatch, or on a bad length, the loader stops in an error state and
  the core stays in reset.

`tools/uart_load.py` builds and sends the frame. `make c-load` sends the same
frame in simulation. The loader sends nothing back; the LEDs show its state.

## Software (`sw/`)

| Path | Content |
|---|---|
| `sw/common/rt/` | `crt0.S` (stack, clear `.bss`, call `main`, write `tohost`, `ebreak`), `link.ld`, `lib.c` |
| `sw/common/drv/` | `platform.h` (the only file with addresses), UART and OLED drivers |
| `sw/common/lib/` | `print` (strings, hex), `tty` (line input with echo) |
| `sw/programs/<prog>/` | `main.c` plus optional expected files for the testbench |

Programs are built with `-march=rv32i -mabi=ilp32`; `*`, `/` and `%` come from
libgcc. `crt0` writes `tohost = (main() << 1) | 1`, so returning 0 means PASS.

| Program | Does |
|---|---|
| `hello` | `.bss`, `.data`, `.rodata`, recursion, mul/div/mod |
| `uart_hello` | Prints a few lines over the UART |
| `uart_echo` | Echoes UART input |
| `oled_hello` | Writes text and colors to the OLED |
| `oled_term` | Small terminal: UART input appears on the OLED until `~` |
| `fail_test` | Returns 3 (`tohost = 7`) to exercise the fail path |

`make c-spike PROG=<prog>` runs the same sources on Spike, with the UART at
Spike's layout (`PLATFORM_SPIKE`). Spike has no OLED and no UART input, so
only `hello` and `uart_hello` run there.

## Board (Arty A7-100T)

The board clock is 100 MHz; an MMCM makes the 25 MHz system clock. The
bitstream starts with the program in `RAM_INIT` (default `oled_term.mem`);
other programs come in over the loader.

| Control | Function |
|---|---|
| `sw[1:0]` | Selects what LD7–LD4 show (table below) |
| `sw[2]` | Load mode (UART loader) |
| Reset button | Resets the system; with `sw[2]` up the loader waits again |

| `sw[1:0]` | LD7 | LD6 | LD5 | LD4 |
|---|---|---|---|---|
| `00` | halted | error trap | PASS | first store seen |
| `01` | `tohost[4:1]` | | | |
| `10` | trap cause | | | |
| `11` | MMCM locked | reset | `tohost` written | heartbeat |

| RGB LED | Meaning |
|---|---|
| LD0 green | Heartbeat |
| LD0 blue | Loader active, core held in reset |
| LD0 red | Loader error (bad length or checksum) |
| LD1 red | FAIL; blinks if the core has not halted 0.1 s after reset |
| LD1 blue | `bus_err` |

**Loading a program**

```sh
make -C sw PROG=uart_hello          # builds rtl/fpga/build/uart_hello.bin
# sw[2] up (LD0 blue on), then:
python3 tools/uart_load.py uart_hello --port /dev/ttyUSB1 --monitor
# LD0 blue off = loaded and running, LD0 red = bad checksum. Put sw[2] down afterwards.
```

**Building the bitstream (Vivado project)**

1. Add the RTL in `tb/filelists/pipeline_rtl.f`, every file under
   `rtl/fpga/rtl/` and `rtl/fpga/arty_a7/arty_a7_top.sv`; add
   `rtl/include` as an include directory.
2. Add `rtl/fpga/arty_a7/arty_a7.xdc` and the `.mem` named by `RAM_INIT`
   (build it with `make -C sw PROG=oled_term`). The file is opened by its bare
   name, so it must be part of the project.
3. Part `xc7a100tcsg324-1`, top `arty_a7_top`.

Things that fail quietly in this flow:

- `` `default_nettype none `` together with `input logic` ports is an error
  in Vivado (`Synth 8-6735`) but not in simulators. The RTL does not use it.
- A `.mem` the tool cannot find is only a critical warning; RAM comes up all
  zero. Check that the synthesis log reports the file as read.
- A clock constraint on a misspelled port leaves the design unconstrained while
  timing reports "met". Check `report_clocks`.

## Limitations

- No interrupts, timer or CSRs. Programs poll the UART.
- The UART has no FIFO and a fixed baud rate.
- A fetch outside RAM wraps around instead of trapping; `bus_err` does not trap.
- The OLED is text only (no pixel access from the CPU).
- The loader has no reply channel and no timeout; a lost byte leaves it waiting.
