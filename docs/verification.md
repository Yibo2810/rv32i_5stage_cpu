# Verification

Three layers, each with its own make target:

| Layer | Testbench | Checks against |
|---|---|---|
| Core | `pipeline_tb` (constrained-random, 500 seeds) | An instruction-set simulator inside the testbench, instruction by instruction |
| SoC | `fpga_sys_tb` (C and assembly programs) | Expected `tohost`, UART text, OLED screen, panic line, RAM contents |
| Blocks | 9 unit testbenches (UART, loader, OLED) | Models and reference values written in each testbench |

The random regression and the assertions need a simulator with SystemVerilog
constrained randomization, SVA and covergroups (the Makefile calls Synopsys
VCS). The C programs also run on Spike.

## Core: `pipeline_tb` (`tb/sv/pipeline/`)

```sh
make pl-run SEED_OFFSET=1 NUM_SEEDS=500     # release regression
make pl-run ARGS=+SINGLE_SEED=<n>           # reproduce one seed
```

**Per seed:**

1. Build a random program from templates that are correct by construction:
   straight-line code with a 50 % bias to read the result of one of the last
   three instructions, bounded loops, forward branches, `jalr` blocks, and
   memory accesses whose base register is forwarded or loaded.
2. Run it on the ISS, then on the core, until the final `ebreak`.
3. Compare every retired instruction (PC, instruction, next PC, destination
   register and value), every memory transaction, the retire count, the final
   PC and the final register file.

**Memory models.** The instruction memory is ready about 80 % of the time and
answers after 1 to 6 cycles, at random but reproducible per seed. The data
memory always accepts and answers in one cycle.

**Hang detection.** 200 cycles without a retire is reported as `DEADLOCK`,
4000 cycles in total as `TIMEOUT`. Both print the state of each handshake.

**Assertions.** Both sets gate the verdict: any failure fails the seed.

| Set | File | Properties |
|---|---|---|
| Interface | `pipeline_assertions.sv` | 14: no memory side effects in reset, known and aligned requests, reads only from loads and writes only from stores, store strobes match width and address, fetch response held while not taken, every fetch answered in time |
| White-box (bound into the core) | `pipeline_sva_bind.sv` | 11: redirect flushes IF/ID and ID/EX in the same cycle, load-use bubble, forwarding priority, no EX read of a load's destination, each instruction retires once, commit-PC continuity, and two assumptions that a jump in EX/MEM or MEM/WB has a bubble behind it |

**Coverage** (printed at the end of the run):

| Group | Content | 500 seeds |
|---|---|---|
| Instruction, opcode, kind | Every instruction retired | 100 % |
| Memory | Width × strobe × alignment | 100 % |
| Branch | Kind × direction × taken | 100 % |
| Forwarding | Source of each operand × consumer kind | 100 % |
| Load-use | Consumer × operand, load width × consumer | 87.00 % |
| Redirect | Source × deferred by memory stall × squashed kind × operand source | 95.24 % |

The bins left open are reachable but not generated, and are waived:

- Load-use into the second operand of a branch, or into both operands of a
  branch or store. The first operand uses the same forwarding mux and is
  covered.
- Byte and half-word loads feeding a branch, `jalr` or a load address.
  Sub-word extension is covered through ALU and store consumers.
- `jal` / `jalr` redirects delayed by a memory stall. The delay logic is shared
  with branches and covered there.

Forwarding a jump's link value is unreachable in this design (jumps flush the
two younger slots); the two assumption properties document it.

**Checking the checkers.** Four bugs were injected into copies of the RTL
(at v0.5.0):
no load-use bubble, retire not gated by the memory stall, redirect not
flushing ID/EX, reversed forwarding priority. Each one failed the regression.

**Current result** (`SEED_OFFSET=1`, 500 seeds):

```text
SUMMARY: 500 passed, 0 failed | total_txns=5558, total_retired=28796
ASSERTION FAILURES: 0
PIPELINE SVA FAILURES: 0
```

## SoC: `fpga_sys_tb` (`rtl/fpga/tb/`)

```sh
make c-run  PROG=<prog>                      # program preloaded into RAM
make c-load PROG=<prog>                      # program sent over UART to the loader
make c-load PROG=hello ARGS=+LOAD_CORRUPT=1  # one byte flipped: loader must refuse it
make mmap-test                               # assembly test of the address map
make c-spike PROG=<prog>                     # same C sources on Spike
```

Each run checks:

- the halt cause (`ebreak`) and `tohost`: 1, or the value in
  `expect_tohost.txt`;
- UART output against `expect_uart.txt`, with input from `uart_rx.txt`;
- the screen against `expect_oled.txt`, through an SSD1331 model;
- two panic lines against the DUT state;
- `bus_err` and the first unmapped address (`mmap-test`);
- after `c-load`, that RAM holds the image word for word.

| Program | Result |
|---|---|
| `hello`, `uart_hello`, `uart_echo`, `oled_hello`, `oled_term` | PASS (`c-run` and `c-load`) |
| `fail_test` | PASS: `tohost = 7`, `HALT FAIL` line |
| `mmap_test` | PASS: RAM lanes, MMIO isolation, unmapped access, code written then executed |
| Corrupted load frame | PASS: loader error, core stays in reset |
| `hello`, `uart_hello` on Spike | PASS |

## Blocks

| Target | Checks |
|---|---|
| `make uart-tx-test` | Against an independent receiver model: idle, bit order, stop bit, back-to-back bytes, request while busy |
| `make uart-rx-test` | Random phase and ±3 % baud error, at 12 and 217 clocks per bit |
| `make uart-16550-test` | Reset values, LSR bits set/clear on exact cycles, overrun, DLAB access |
| `make loader-test` | Magic resync, bad checksum, illegal lengths, switch off mid-frame |
| `make oled-spi-test` | SPI mode 3 bytes and D/C |
| `make oled-seq-test` | Init command bytes |
| `make oled-ctrl-test` | Init then full frames into the SSD1331 model |
| `make oled-text-test` | Text buffer, status row, panic rows |
| `make oled-render-test` | Whole frames pixel by pixel for RUN, PASS and FAIL |

## On the board

The C programs run on the Arty A7-100T, both as the preloaded image and
through the UART loader. These are manual smoke runs, judged by the UART
output, the OLED and the LEDs; the fail path is checked in simulation only.

## Not verified

- Data-memory back-pressure: the testbench data memory never stalls a request.
- Trap paths in the random regression other than the final `ebreak`: no
  illegal instructions, `ecall` or misaligned accesses are generated.
- The ISS is part of this testbench; the core has not been run against an
  external ISA test suite.
- No gate-level or post-synthesis simulation.
