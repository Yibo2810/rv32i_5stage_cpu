# v0.7.1 (in progress): Address Map and Unified Memory

## Versioning from here

`v0.7.x` are the steps from the v0.7.0 core to a CPU that runs C programs.
`v0.8.0` is reserved for that point: a C program built with a linker script
and start-up code runs self-checking on the SoC, in simulation and on the
board. Until then each step gets the next patch number.

## Summary

v0.7.1 moves the reset PC to `0x8000_0000` (the address Spike and the usual
RISC-V linker scripts expect), and starts replacing the separate instruction
ROM and data RAM of v0.7.0 with one RAM behind a small address decoder.

| Item | Files | Status |
|---|---|---|
| `RESET_PC` parameter: `pc` → `if_stage` → `core_5stage` → `pipeline_tb` | `rtl/single_cycle/pc.v`, `rtl/pipeline/{if_stage,core_5stage}.sv`, `tb/sv/pipeline/pipeline_tb.sv` | integration-tested (below) |
| Text relocation in the random program and the ISS (`text_base`) | `tb/sv/pipeline/random/{pl_program,pl_ref_model}.sv` | integration-tested (below) |
| Tool support: `asm_to_hex.sh LINK_BASE=`, `rv32i_ref.py --base`, `gen_random_program.py --data-base` | `scripts/`, `tools/` | implemented, not run in this check |
| `sys_ram`: one block RAM, fetch port + data port | `rtl/fpga/rtl/sys_ram.sv` | under development, does not compile |
| `dmem_xbar`: RAM / MMIO / unmapped decode | `rtl/fpga/rtl/dmem_xbar.sv` | under development, does not compile |
| `mmio_regs`: `tohost` register | `rtl/fpga/rtl/mmio_regs.sv` | implemented, not simulated |
| `fpga_sys` wired to the three blocks above | `rtl/fpga/rtl/fpga_sys.sv`, `rtl/fpga/tb/fpga_sys_tb.sv` | under development; test program `mmap_test` not in the repo yet |
| Random data accesses relative to a RAM base register (`x22`) | `tb/sv/pipeline/random/{pl_instr,pl_program}.sv` | under development (uncommitted) |

The FPGA system does not build on this branch until `sys_ram` and
`dmem_xbar` compile. The last working FPGA build is v0.7.0 (`49b33ba`).

## Address map

| Region | Base | Size | Slave |
|---|---|---|---|
| RAM (text + data) | `0x8000_0000` | 64 KB (`RAM_AW = 16`) | `sys_ram` |
| MMIO | `0x1000_0000` | 4 KB (`MMIO_AW = 12`) | `mmio_regs`, `tohost` at offset `0x000` |
| anything else | | | `dmem_xbar` answers with `rdata = 0` and flags a bus error |

Bases must be aligned to their region size, so the decode is one compare of
`addr[31:AW]`; a misaligned base is an elaboration error. Only the data port
goes through `dmem_xbar`. The fetch port is wired straight to `sys_ram`, so a
fetch outside the RAM aliases into it instead of faulting.

## Regression (committed tree `f2de8a0`, 2026-10-06)

```text
make pl-build
./sim/build/pipeline_vcs/simv +SEED_OFFSET=1 +NUM_SEEDS=500
  SUMMARY: 500 passed, 0 failed | total_txns=5688, total_retired=29676   (same as v0.5.0 / v0.7.0)
  ASSERTION FAILURES: 0 | PIPELINE SVA FAILURES: 0
  PIPE_FWD 100.00% | PIPE_LU 87.00% | PIPE_REDIR 95.24%

make pl-build PL_VCS_ARGS="-pvalue+pipeline_tb.RESET_PC=2147483648"     # 0x8000_0000
./sim/build/pipeline_vcs/simv +SEED_OFFSET=1 +NUM_SEEDS=500
  RANDOM TEST: RESET_PC=80000000 (text relocated, data x0-relative)
  SUMMARY: 500 passed, 0 failed | total_txns=5653, total_retired=29197
  ASSERTION FAILURES: 0 | PIPELINE SVA FAILURES: 0
  PIPE_FWD 100.00% | PIPE_LU 87.00% | PIPE_REDIR 95.24%
```

With relocated text the JALR template needs an extra `lui` for the upper
target bits, so the programs differ and the totals are not comparable to the
first run. Data is still `x0`-relative (low addresses) in both runs; moving it
into the RAM region is the uncommitted `x22` work.

Pass the parameter in decimal: a `32'h...` literal inside `PL_VCS_ARGS` breaks
the shell quoting in the Makefile recipe.

## Toward v0.8.0 (tentative)

| Step | Content |
|---|---|
| v0.7.2 | SoC compiles; `fpga_sys_tb` runs `mmap_test` (text and data in RAM, verdict through MMIO `tohost`); a negative test for an unmapped access |
| v0.7.3 | Random regression with data in the RAM region; one directed program cross-checked against Spike at `0x8000_0000` |
| v0.7.4 | SoC bitstream on the Arty A7-100T |
| v0.8.0 | Linker script + `crt0` + `gcc -march=rv32i`; a self-checking C program passes in simulation and on the board |
