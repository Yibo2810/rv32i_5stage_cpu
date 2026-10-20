# After v0.7.1: C Runtime, UART, Hardware Panic, OLEDrgb (in progress)

## Versioning

`v0.7.1` is the last small public tag. The next public release is `v1.0`, a
usable version. Work in between is tracked as short-term stages:

| Stage | Content | Status |
|---|---|---|
| A | GCC + `crt0` + linker script, first C program | integration-tested in simulation, board smoke test passed (`ec50988`) |
| B | 16550-subset UART TX, C drivers, hardware panic line | UART TX on the board; panic integration-tested in simulation, not on the board yet |
| — | Pmod OLEDrgb (SSD1331) | under development: full-screen red fill passes against an SSD1331 model, not on the board yet |
| C1 | UART RX + loader | planned |

## Stage A: bare-metal C (`sw/`)

| Path | Content |
|---|---|
| `sw/common/rt/` | `crt0.S` (stack, clear `.bss`, call `main`, write `tohost`, `ebreak`; `.data` is already in the RAM image), `link.ld`, `lib.c`, `tohost_spike.S` |
| `sw/common/drv/` | `platform.h` (the only file with addresses), `uart.c/.h` |
| `sw/common/lib/` | `print.c/.h` (`puts`, `print_hex`, on top of the driver) |
| `sw/programs/<prog>/` | `main.c`, optional `expect_uart.txt` |

`-march=rv32i -mabi=ilp32`; `*`, `/`, `%` go to libgcc. `crt0` writes
`tohost = (main() << 1) | 1`, so returning 0 gives `tohost = 1` = PASS. `hello` checks `.bss`,
`.data`, `.rodata`, recursion and libgcc mul/div/mod.

```sh
make c-run PROG=hello          # build sw, run on fpga_sys_tb
make c-spike PROG=hello        # same sources on Spike (PLATFORM_SPIKE)
```

## Stage B: UART TX and hardware panic

**MMIO map** (base `0x1000_0000`): UART 16550 subset at `+0x000..+0x01C`
(reg-shift 2; THR, IER, IIR, LCR with DLAB, MCR, LSR, SCR, DLL/DLM), `tohost`
at `+0x100`. LSR reports THRE/TEMT from `uart_tx` busy. On Spike the layout is
reg-shift 0 with byte access, selected by `PLATFORM_SPIKE` in `platform.h`.

**Hardware panic** (`rtl/fpga/rtl/halt_reporter.sv`): once the core halts it
prints one line on the UART, then repeats it every `PANIC_PERIOD` cycles
(25 M = 1 s on the board), so the cause is visible even if the terminal is
opened late:

```text
HALT PASS cause=3 pc=80000040 tohost=00000001 buserr=0 addr=00000000
```

`addr` is the first unmapped address (`bus_err_addr`, latched in `dmem_xbar`).
The program's UART output and the panic share one `uart_tx` (OR mux, panic data
wins); `halt_reporter` only sends after `halted`.

`fpga_sys_tb` separates program text from panic lines: program bytes are compared
with `+EXPECT_UART_FILE`, and two panic lines are compared with the DUT state.

## OLEDrgb (`rtl/fpga/rtl/oled/`, under development)

| Module | Role | Unit test |
|---|---|---|
| `oled_spi` | SPI mode 3 byte sender, D/C, `HALF` = sclk half period in clk cycles | `make oled-spi-test` |
| `oled_seq` | Power-up and init sequence (after Digilent's `OLEDrgb_DevInit`) as a small command ROM with ms waits | `make oled-seq-test` |
| `oled_fill` | Window `0..95 × 0..63`, then 6144 pixels of RGB565 `0xF800` (red), repeated | — |
| `oled_ctrl` | `oled_seq` until `done`, then `oled_fill`, one shared `oled_spi` | `make oled-ctrl-test` |
| `oled_render` | (empty) | — |

`tb/oled/ssd1331_model.sv` is a behavioral SSD1331 (SPI mode 3 receiver, command
parser, 96×64 GDDRAM). The first test is a full-screen red fill. `arty_a7_top`
and the XDC (Pmod JA) are wired but not committed.

## Results (scratch copy of the working tree, 2026-10-20)

```text
make oled-spi-test    SUMMARY sent=21 received=21 errors=0              OLED_SPI PASS
make oled-seq-test    SUMMARY bytes=45 ... done@3059                    OLED_SEQ PASS
make oled-ctrl-test   SUMMARY bytes=24633 pixels_written=12288 display_on=1 not_red=0
                                                                        OLED_CTRL PASS
make uart-tx-test                                                       UART_TX PASS
make c-run PROG=hello       HALT PASS cause=3 pc=80000040 ...           FPGA_SYS PASS
make c-run PROG=uart_hello  UART MATCH: 39 chars                        FPGA_SYS PASS
mmap_test +EXPECT_BUS_ERR=1 +EXPECT_BUS_ERR_ADDR=20000000
                            HALT PASS ... buserr=1 addr=20000000        FPGA_SYS PASS
```

`make uart-tx-test`, `make c-run` (hello, uart_hello) and `mmap_test` were
re-run in the repository on 2026-10-22 with the same results.

## Known issues

- Panic and OLED have not run on the board; the last bitstream is the stage B
  UART TX build (2026-10-16).
- `ssd1331_model` does not model remap (`A0h`) orientation.

## Next

1. Run panic and the red fill on the board.
2. OLED as a CPU-writable MMIO peripheral (character or frame buffer), so C can draw.
3. C1: UART RX and loader.
