# Changelog

The detailed write-up of each step is in the `docs/` folder of its release
tag (for example `git show v0.5.0:docs/11_v0_5_0_milestone.md`).

## v1.0 — 2026-10 (final RV32I release)

- UART program loader: `sw[2]` holds the core in reset, a framed image with a
  checksum is written to RAM over the UART, then the core starts.
  `tools/uart_load.py` sends it; `make c-load` checks it in simulation,
  including a corrupted frame.
- Fail-path test (`fail_test`): non-PASS `tohost` and the `HALT FAIL` line.
- Single-cycle core removed (it stays in tag `v0.4.0`). The six leaf modules
  the pipeline uses moved to `rtl/pipeline/units/`, `single_pkg` became
  `core_pkg`. The 500-seed regression log is identical before and after.
- `make mmap-test`; `make pl-run` takes `SEED_OFFSET` and `NUM_SEEDS`.
- Documentation reduced to the README and four documents.

## v0.9 — 2026-10-27

- Bare-metal C: `crt0`, linker script, UART and OLED drivers, `print`, `tty`.
- 16550-subset UART (TX and RX) in MMIO; hardware panic line on halt.
- Pmod OLEDrgb text display: init sequence, continuous renderer, 8 × 8 font,
  MMIO text buffer and row colors, status row, panic page.
- Unit testbenches for every UART and OLED block; C programs checked end to
  end in `fpga_sys_tb` against expected UART text and screen contents.

## v0.7.1 — 2026-10-07

- Reset PC `0x8000_0000`; one 64 KB RAM for text and data; data-port decoder
  for RAM / MMIO / unmapped with a sticky `bus_err`; `tohost` in MMIO.
- `mmap_test` passes in simulation and on the board.

## v0.7.0 — 2026-10-03

- Request/response instruction fetch: single outstanding, kill on redirect,
  one-entry buffer, response back-pressure. The instruction memory moves to
  block RAM. Same commit stream as v0.5.0 against a randomly stalling memory.

## v0.6.0 — 2026-09-30

- First board run on the Arty A7-100T at 25 MHz: a self-checking hazard
  program reports PASS on the LEDs.

## v0.5.0 — 2026-09-28

- Five-stage pipeline with forwarding, load-use stall, redirect flush, global
  freeze on memory stalls and precise traps committed in WB.
- Random regression against an ISS on the commit stream, interface and
  white-box assertions, pipeline coverage, four injected bugs caught.

## v0.4.0 — 2026-07-08

- Single-cycle core: constrained-random programs, ISS lockstep, assertions,
  functional coverage closed to 100 % of its bins.

## v0.3.0 — 2026-06-26

- Single-cycle core with all 37 instructions, directed assembly suite and a
  SystemVerilog core testbench.

## v0.2.0 — 2026-06-12

- RTL and testbench moved to SystemVerilog; directed tests for R/I-type ALU
  instructions.

## v0.1 — 2026-05-19

- First single-cycle subset (`add`, `sub`, `addi`, `lw`, `sw`, `beq`) with
  directed tests.
