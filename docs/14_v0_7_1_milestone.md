# v0.7.1 Milestone: Address Map and Unified Memory

## Versioning from here

`v0.7.x` are the steps from the v0.7.0 core to a CPU that runs C programs.
`v0.8.0` is reserved for that point: a C program built with a linker script
and start-up code runs self-checking on the SoC, in simulation and on the
board. Until then each step gets the next patch number.

## Summary

v0.7.1 moves the reset PC to `0x8000_0000` (where Spike and the usual RISC-V
linker scripts put text) and replaces the separate instruction ROM and data
RAM of v0.7.0 with one RAM behind an address decoder.

**Status: integration-tested in simulation** (random pipeline regression with
text and data in the RAM region, plus a directed SoC test in `fpga_sys_tb`),
**board smoke test passed** on the Arty A7-100T (2026-10-07, `mmap_test`,
passing case only).

| Item | Files | Status |
|---|---|---|
| `RESET_PC` parameter: `pc` → `if_stage` → `core_5stage` → `pipeline_tb` (default `0x8000_0000`) | `rtl/single_cycle/pc.v`, `rtl/pipeline/{if_stage,core_5stage}.sv`, `tb/sv/pipeline/pipeline_tb.sv` | integration-tested |
| Random programs: text at `RESET_PC`, data through base register `x22` = `DATA_BASE` (`0x8000_8000`); every transaction checked to fall in that window | `tb/sv/pipeline/random/{pl_instr,pl_program,pl_ref_model}.sv`, `pipeline_scoreboard.sv` | integration-tested |
| `sys_ram`: one block RAM, fetch port + data port | `rtl/fpga/rtl/sys_ram.sv` | integration-tested (`mmap_test`) |
| `dmem_xbar`: RAM / MMIO / unmapped decode, sticky `bus_err` | `rtl/fpga/rtl/dmem_xbar.sv` | integration-tested (`mmap_test`) |
| `mmio_regs`: `tohost` register | `rtl/fpga/rtl/mmio_regs.sv` | integration-tested (`mmap_test`) |
| `bus_err` on LED1 blue | `rtl/fpga/arty_a7/arty_a7_top.sv` | board smoke test |
| Tool support: `asm_to_hex.sh LINK_BASE=`, `rv32i_ref.py --base`, `gen_random_program.py --data-base` | `scripts/`, `tools/` | `LINK_BASE` used for `mmap_test`; the other two not run |

## Address map

| Region | Base | Size | Slave |
|---|---|---|---|
| RAM (text + data) | `0x8000_0000` | 64 KB (`RAM_AW = 16`) | `sys_ram` |
| MMIO | `0x1000_0000` | 4 KB (`MMIO_AW = 12`) | `mmio_regs`: `tohost` at `+0x100`, other offsets read 0, writes dropped |
| anything else | | | `dmem_xbar` answers (load returns 0, store dropped) and sets `bus_err` |

Bases must be aligned to their region size, so the decode is one compare of
`addr[31:AW]`; a misaligned base is an elaboration error. `tohost` sits at
`+0x100` so the low offsets stay free (Spike puts a UART at `0x1000_0000`).

Only the data port goes through `dmem_xbar`. The fetch port is wired straight
to `sys_ram`, so a fetch outside the RAM aliases into it instead of faulting.

## Directed SoC test: `programs/fpga/asm/mmap_test.S`

| Case | Checks |
|---|---|
| 1 | RAM word write / read back |
| 2 | Byte and half-word lanes through `dmem_xbar` → `sys_ram` strobes, sign extension |
| 3 | An MMIO store does not reach RAM; an unimplemented MMIO offset reads 0 |
| 4 | MMIO and RAM loads back to back, both orders (response mux) |
| 5 | Unmapped load returns 0, unmapped store is dropped, no hang |
| 6 | Unified memory: code written through the data port, then executed |

Verdict: `tohost = 1` then `ebreak`; a failing case writes
`tohost = (case << 1) | 1`. `bus_err` must end at 1 (case 5).

## Results (2026-10-07)

```text
pipeline, make pl-build && simv +SEED_OFFSET=1 +NUM_SEEDS=500
  SUMMARY: 500 passed, 0 failed | total_txns=5558, total_retired=28796
  ASSERTION FAILURES: 0 | PIPELINE SVA FAILURES: 0
  RV_* coverage 100% | PIPE_FWD 100.00% | PIPE_LU 87.00% | PIPE_REDIR 95.24%
  load_use_hazard 444

fpga_sys_tb, mmap_test, +EXPECT_BUS_ERR=1
  cycles=115 halted=1 cause=EXC_BREAKPOINT trap_pc=80000118
  tohost=00000001 pass=1 fail=0 bus_err=1
  FPGA_SYS PASS
  (same run without +EXPECT_BUS_ERR=1: FAIL on the bus_err check, as expected)

single-cycle, simv +SEED_OFFSET=1 +NUM_SEEDS=200: 200 passed, 0 failed, 0 assertion failures
directed suite, asm_to_hex.sh && rv32i_ref.py --all: regenerated files identical
```

The totals differ from v0.7.0 (5688 / 29676) because the programs changed
(one `lui x22` per program, base-register addressing, an extra `lui` in JALR
blocks), not because the commit stream diverged.

## FPGA build and board test (2026-10-07)

```text
Vivado, xc7a100tcsg324-1, 25 MHz   WNS +19.539 ns, WHS +0.085 ns, 0 critical warnings
                                   1772 LUT, 1777 FF, 16 RAMB36 (64 KB sys_ram)
Arty A7-100T                       mmap_test: PASS LED on, LED1 blue (bus_err) on
```

The 64 KB RAM uses 16 RAMB36 (v0.7.0: 2 RAMB18 for a 1 KB ROM and a 1 KB data
RAM). Vivado reports `Synth 8-6841`: with a 14-bit address it does not use the
block RAM byte-write enables and builds the byte lanes from separate RAMs with
a single write enable each.

## Limitations

- Fetch from outside the RAM aliases instead of trapping (see above).
- `bus_err` is a sticky flag, not an exception: the core does not trap on an
  access fault.
- The fail path of `mmap_test` has not been exercised.
- On the board only the passing case of `mmap_test` has run.
  `hazard_test` is linked at address 0 and no longer runs on this `fpga_sys`.
- No Spike cross-check yet.

## Toward v0.8.0 (tentative)

| Step | Content |
|---|---|
| v0.7.2 | Fail-path test in simulation and on the board; directed programs cross-checked against Spike at `0x8000_0000` |
| v0.8.0 | Linker script + `crt0` + `gcc -march=rv32i`; a self-checking C program passes in simulation and on the board |
