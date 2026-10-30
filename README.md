# RV32I 5-Stage CPU

A five-stage pipelined RV32I CPU in SystemVerilog, in a small SoC that runs
bare-metal C on a Digilent Arty A7-100T. Programs print over a UART, write
text to a small OLED screen, and can be loaded over the UART without
rebuilding the bitstream.

**v1.0 is the final RV32I release.** Development continues as RV64.

```text
 C program ── crt0 ──> RAM 64 KB @ 0x8000_0000 <── UART loader (sw[2])
                            ^          ^
                       fetch|          |data
                     +-------------------------+
                     |  IF  ID  EX  MEM  WB    |  core_5stage
                     +-------------------------+
                                       | data, MMIO @ 0x1000_0000
                  UART (16550 subset) ─┼─ tohost ─ OLED text ─ panic line
```

## Features

| Part | What it has |
|---|---|
| ISA | RV32I, 37 instructions (no `fence`, CSRs or interrupts); `ecall`, `ebreak`, illegal instructions and misaligned accesses trap |
| Pipeline | IF/ID/EX/MEM/WB, full forwarding, 1-cycle load-use stall, branches resolved in EX (2-cycle penalty), precise traps, request/response ports for instruction and data memory |
| SoC | 64 KB RAM, address decoder with bus-error flag, 16550-subset UART at 115200 baud, `tohost` result register, OLED text display (12 × 7 characters plus a status row), hardware panic line on halt, UART program loader |
| Software | `crt0`, linker script, UART/OLED drivers, small print and terminal library; six example programs |
| Board | Arty A7-100T, 25 MHz system clock: 3067 LUTs, 3211 flip-flops, 16 block RAMs, worst setup slack +20.3 ns |

## Status

| Item | Status | Evidence |
|---|---|---|
| Pipeline core | Verified in simulation | 500 random seeds, every retired instruction compared with an ISS, 0 assertion failures |
| SoC (RAM, decoder, UART, OLED, panic, loader) | Integration-tested in simulation | All C programs and the address-map test pass in `fpga_sys_tb`, preloaded and through the loader; a corrupted load and a failing program are detected |
| Peripheral blocks | Unit-tested | 9 self-checking unit testbenches |
| Board | Smoke-tested | The C programs run on the Arty A7-100T, preloaded and loaded over the UART |

How each layer is checked: [docs/verification.md](docs/verification.md).

## Quick start

Tools: a RISC-V GCC (`riscv64-unknown-elf-`), Python 3, Synopsys VCS for
simulation, Spike (optional), Vivado for the board, `pyserial` for loading.

```sh
# Core: random regression (500 seeds, fixed offset)
make pl-run SEED_OFFSET=1 NUM_SEEDS=500
#   expect: SUMMARY: 500 passed, 0 failed ... ASSERTION FAILURES: 0

# SoC: build a C program and run it on the system testbench
make c-run PROG=uart_hello          # expect: UART MATCH ... FPGA_SYS PASS
make c-load PROG=oled_term          # same, but sent through the UART loader
make c-run PROG=fail_test           # failing program, detected as expected
make mmap-test                      # address map

# The same C program on Spike
make c-spike PROG=hello

# Unit tests
make uart-tx-test uart-rx-test uart-16550-test loader-test
make oled-spi-test oled-seq-test oled-ctrl-test oled-text-test oled-render-test
```

On the board: build the bitstream from the file list in
[docs/soc.md](docs/soc.md#board-arty-a7-100t), then load any program without
rebuilding it:

```sh
make -C sw PROG=uart_hello
# set sw[2] up (LD0 turns blue), then:
python3 tools/uart_load.py uart_hello --port /dev/ttyUSB1 --monitor
```

## Repository layout

```text
rtl/include/        core_pkg (ISA constants, exception codes), pipeline_pkg (stage payloads)
rtl/pipeline/       core_5stage and the five stages; units/ = ALU, decoder, register file, ...
rtl/fpga/rtl/       fpga_sys: RAM, decoder, MMIO, UART, OLED, panic printer, loader
rtl/fpga/arty_a7/   board top level and pin constraints
rtl/fpga/tb/        fpga_sys_tb and unit testbenches with UART and SSD1331 models
tb/sv/pipeline/     random pipeline testbench: generator, ISS, monitor, scoreboard, assertions, coverage
tb/filelists/       pipeline_rtl.f (core RTL), pipeline.f (core + testbench)
sw/                 C runtime, drivers, library, programs/<prog>/
programs/asm/       mmap_test.S
tools/uart_load.py  sends a program to the loader
```

## Limitations

- No CSRs, interrupts or timer: a trap halts the core, and programs poll the UART.
- No branch prediction and no cache; one memory access in flight per port.
- A fetch outside RAM wraps around, and an unmapped data access only sets a
  flag; neither traps.
- The random regression never stalls a data request and generates no traps
  besides the final `ebreak`.
- The core has not been run against an external ISA test suite.
- The board runs are manual smoke tests.

## Documentation

| Document | Content |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Pipeline: stages, hazards, memory interfaces, exceptions |
| [docs/soc.md](docs/soc.md) | Address map, MMIO registers, UART, OLED, loader, software, board |
| [docs/verification.md](docs/verification.md) | Testbenches, assertions, coverage, results, what is not verified |
| [docs/bug_case_library.md](docs/bug_case_library.md) | Bugs found along the way and what they taught |
| [docs/demo/oled_render.html](docs/demo/oled_render.html) | Interactive model of the OLED text renderer ([中文](docs/demo/oled_render_zh.html)) |
| [CHANGELOG.md](CHANGELOG.md) | Every version from v0.1 |

## License

MIT, see [LICENSE](LICENSE). The 8 × 8 font glyphs in `oled_font.sv` come from
font8x8 by Daniel Hepper (public domain).
