# v0.5.0 Milestone (in progress): Five-Stage Pipeline Bring-Up

Status: **in progress — directed bring-up only, not verified.**
Date: 2026-09-14. Branch: `feature/pipeline-5stage` (working tree on top of
`bf50ee1`, uncommitted).

## Summary

The five-stage pipeline now exists in RTL with forwarding, load-use stalls,
redirect flushes, a global freeze on memory stalls, and a request/response data
memory interface intended for the FPGA build. The verification state is
deliberately modest and this document records it exactly:

- **Directed tests first.** Six directed assembly programs are run through the
  pipeline one at a time and their behaviour is dumped; the testbench checks
  only that execution ends in a single `ebreak` trap (no timeout).
- **No random regression yet.** The constrained-random sources exist under
  `tb/sv/pipeline/random/` (ported from the frozen single-cycle flow) but are
  commented out of `tb/filelists/pipeline.f` and are not used by the testbench.
- **No oracle inside the testbench yet.** The pipeline scoreboard and assertion
  files are unadapted copies of the single-cycle ones; neither is compiled into
  the pipeline filelist.

Everything below is the state of the repository as of the date above.

---

## 1. What is implemented

| Area | State |
|---|---|
| IF/ID/EX/MEM/WB partition | Implemented (`rtl/pipeline/{if,id,ex,mem,wb}_stage.sv`) |
| Pipeline registers with per-stage `en` + `flush` | Implemented (`pipeline_regs.sv`) |
| Forwarding | Implemented: EX/MEM and MEM/WB to EX, plus a WB→ID bypass in `id_stage` |
| Load-use stall | Implemented (1 bubble), gated by decoder-provided `ctrl_uses_rs1/rs2` |
| Redirect flush | Implemented: branch/jump resolved in EX, flushes IF/ID + ID/EX (2-cycle penalty) |
| Memory stall handling | Implemented as a **global freeze** with a single retire rule `wb_retire = memwb_q.valid && !mem_stall` |
| Exception token | Implemented: `exception_t {valid, cause[3:0]}` produced in ID (`illegal > ebreak > ecall`), merged with MEM misalignment (upstream wins), committed at WB |
| Trap | Implemented as flush-younger + sticky `halted`; no CSR, no `mtvec` |
| Data memory interface | Implemented as a single-outstanding `req_valid/req_ready` + `rsp_valid/rsp_ready` protocol |
| BRAM adapter | Implemented (`rtl/pipeline/memory/dmem_bram.sv`, 1-cycle latency, byte writes, `initial` zero-fill) |
| Instruction memory | Still combinational fetch (`imem_addr`/`imem_rdata` same cycle) → FPGA target is LUTRAM; imem on BRAM is a separate milestone |
| Single-cycle core | Untouched as a verified baseline (v0.4.0) and still in the tree under `rtl/single_cycle/` |

Design details: [03_pipeline_design.md](03_pipeline_design.md) and
[04_hazard_forwarding.md](04_hazard_forwarding.md).

---

## 2. Bring-Up Testbench

```text
tb/sv/pipeline/pipeline_tb.sv          top level: reset, load hex, run until halt, dump, verdict
tb/sv/pipeline/pipeline_probe_if.sv    pipeline_probe_if: wires + modports (pl_core / bram / pipeline_monitor)
tb/sv/pipeline/pipeline_memory.sv      imem (256 words, preloaded with EBREAK, $readmemh overlay) + dmem_bram #(.DEPTH(256))
tb/sv/pipeline/pipeline_monitor.sv     passive capture: commits, memory transactions, trap count/cause/pc
tb/filelists/pipeline.f                compile order
tb/filelists/pipeline_rtl.f            RTL compile order (shared by lint and VCS)
```

Behaviour:

1. The instruction memory is **pre-filled with `ebreak`** before `$readmemh`,
   so any fetch beyond the program image halts deterministically instead of
   executing garbage.
2. `run_until_halt()` polls `pif.halted` up to `MAX_CYCLES = 4000`, then two
   extra cycles are simulated so the post-trap state is visible in the dump.
3. `dump_result()` prints the commit trace (`COMMIT pc=... instr=... next=...
   x<rd>=...`), the memory transaction trace (`TXN W/R addr data wstrb`),
   all non-zero registers, and a `SUMMARY` line with cycles / timeout / trap
   count / trap cause / trap PC / commits / transactions.
4. **Verdict today**: `BRINGUP DONE` iff there was no timeout and exactly one
   trap with `EXC_BREAKPOINT`. The dump itself is for eyeballing — there is no
   expected-value comparison inside the testbench yet.

The commit trace is produced from the WB stage, so it is a genuine architectural
retire view (`u_core.u_wb_stage.wb_retire`), not a fetch-side guess.

### Running it

```sh
make pl-lint                                        # Verilator -Wall lint of the pipeline RTL
make pl-run ARGS="+HEX=programs/hex/branch_matrix_test.hex"
make pl-run ARGS="+HEX=programs/hex/load_store_width_test.hex"
```

Output goes to `sim/build/pipeline_vcs/{compile.log,run.log}`; the per-test logs
from the runs below are under `sim/build/pipeline_vcs/bringup/<test>.log`
(gitignored build area).

---

## 3. Directed Bring-Up Results (2026-09-14)

Six of the seven `programs/asm/*.S` programs have non-empty `.hex` images; all
six were run through the pipeline. The seventh (`hazard_test`) is a stub and is
listed last for completeness:

| Program | Static insns | Commits | Memory txns | Cycles | Trap | Verdict |
|---|---|---|---|---|---|---|
| `alu_rtype_test` | 24 | 24 | 10 | 39 | `EXC_BREAKPOINT` @ `0x60` | halted, no timeout |
| `alu_itype_test` | 25 | 25 | 12 | 42 | `EXC_BREAKPOINT` @ `0x64` | halted, no timeout |
| `load_store_width_test` | 15 | 15 | 13 | 38 | `EXC_BREAKPOINT` @ `0x3c` | halted, no timeout |
| `branch_matrix_test` | 96 | 66 | 12 | 107 | `EXC_BREAKPOINT` @ `0x180` | halted, no timeout |
| `jump_u_type_test` | 15 | 10 | 3 | 24 | `EXC_BREAKPOINT` @ `0x3c` | halted, no timeout |
| `x0_test` | 15 | 15 | 8 | 30 | `EXC_BREAKPOINT` @ `0x3c` | halted, no timeout |
| `hazard_test` | TODO stub | 0 | 0 | 5 | `EXC_BREAKPOINT` @ `0x00` | **empty test** — `hazard_test.S` is a TODO comment and its `.hex` is empty, so the preloaded `ebreak` halts immediately |

Reading the columns:

- `alu_*` and `x0_test` execute every static instruction (`commits = static`).
- `branch_matrix_test` commits 66 of 96 static instructions and
  `jump_u_type_test` 10 of 15 — i.e. instructions really were skipped by taken
  branches and jumps, and execution still ended in the expected `ebreak`. This
  is the observable effect of the redirect flush working.

### Cycle accounting (off-line analysis of the commit traces)

The commit trace carries the resolved `next_pc` for every retired instruction,
so the dynamic behaviour can be reconstructed and compared against a simple
pipeline timing model:

```text
cycles = commits
       + 4                      pipeline fill
       + txns                   one extra cycle per memory transaction (2-cycle MEM)
       + 2 x redirects          next_pc != pc+4 (taken branch / jump) -> flush IF+ID
       + load_use_stalls        load consumed at instruction distance 1
       + 1
```

| Program | Cycles | Commits | Txns | Redirects | Load-use stalls | Model | Residual |
|---|---|---|---|---|---|---|---|
| `alu_rtype_test` | 39 | 24 | 10 | 0 | 0 | 39 | 0 |
| `alu_itype_test` | 42 | 25 | 12 | 0 | 0 | 42 | 0 |
| `load_store_width_test` | 38 | 15 | 13 | 0 | 5 | 38 | 0 |
| `branch_matrix_test` | 107 | 66 | 12 | 12 | 0 | 107 | 0 |
| `jump_u_type_test` | 24 | 10 | 3 | 3 | 0 | 24 | 0 |
| `x0_test` | 30 | 15 | 8 | 0 | 2 | 30 | 0 |

The model fits all six programs with **zero residual**, which is the useful
part: there are no unexplained stall cycles. Redirect counts are read out of
the traces (12 taken redirects in `branch_matrix_test`, 3 in
`jump_u_type_test`), and load-use stalls are counted from the committed
instruction stream (`load_store_width_test` ends the program with five
`l*`→`sw` pairs that each consume the loaded register in the next instruction;
`x0_test` has two). The trailing `+ 1` is an empirical constant of the
measurement (the testbench's halt-detection convention), not a modelled stall.

**Caveat**: this accounting is an off-line script run over the dumped traces, not
part of the testbench. It is evidence that the observed cycle counts are
consistent with the intended microarchitecture; it is not a checker.

### Off-line cross-check against the single-cycle reference

The single-cycle flow produced `programs/expected/*.expected` (generated by
`tools/rv32i_ref.py` from the same `.hex` images). The pipeline dump prints
memory transactions in exactly the same `TXN W/R <addr> <data> <wstrb>` format,
so the pipeline's observed stream was compared line by line against those files
**outside** the testbench:

| Program | Expected TXN records | Observed TXN records | Stream match | `SIG` words checked | Mismatches |
|---|---|---|---|---|---|
| `alu_rtype_test` | 10 | 10 | yes | 10 | 0 |
| `alu_itype_test` | 12 | 12 | yes | 12 | 0 |
| `load_store_width_test` | 13 | 13 | yes | 8 | 0 |
| `branch_matrix_test` | 12 | 12 | yes | 12 | 0 |
| `jump_u_type_test` | 3 | 3 | yes | 3 | 0 |
| `x0_test` | 8 | 8 | yes | 6 | 0 |

`SIG` records were checked by replaying the observed write transactions into a
byte-level model of data memory and comparing the final words — 51 of 51
signature words match, 0 mismatches.

What this does and does not prove:

- **Proves**: the load/store stream (address, direction, byte strobes, data),
  the loaded data, and the final data-memory image match the single-cycle
  reference for these six programs. Because the stream is compared in program
  order over the *executed* path, the branch and jump programs also confirm
  that redirects changed the instruction stream the same way the single-cycle
  core did.
- **Does not prove**: register-file contents (the expected files carry no
  register records), retire count/final PC against an ISS, exception behaviour
  beyond "halted on ebreak", any random or stress behaviour, or anything about
  FPGA timing/resources.
- The comparison is an ad-hoc off-line check, not a committed part of the
  testbench. Promoting it into the testbench is part of the next step below.

### Which hazard paths the six programs actually exercise

Derived from the committed instruction streams (register use per opcode class,
producer→consumer distance in retired instructions):

| Path | Exercise evidence |
|---|---|
| EX/MEM forwarding | every program; distance-1 dependency on an ALU result — `alu_rtype_test` 10, `alu_itype_test` 12, `branch_matrix_test` 24, `load_store_width_test` 7, `x0_test` 6, `jump_u_type_test` 5 |
| MEM/WB forwarding | distance-2 dependencies — `branch_matrix_test` 12, `load_store_width_test` 1, `x0_test` 1 |
| WB→ID bypass (register file read/write in the same cycle) | distance-3 dependencies — `alu_rtype_test` 1, `load_store_width_test` 1 |
| WB_PC4 forwarding (`jal`/`jalr` link value) | `jump_u_type_test`: one `jal` whose link register is consumed by the immediately following instruction |
| Load-use stall | `load_store_width_test` 5, `x0_test` 2 |
| Redirect flush | `branch_matrix_test` 12 taken redirects, `jump_u_type_test` 3 |
| Memory freeze | every program with transactions: all 58 loads/stores occupy MEM for 2 cycles |

The distances are static instruction distances, which approximates the
pipeline-stage distance; a stall in between shifts a producer further back, so
the counts are a lower bound on the number of forwarding decisions taken.

### Tool state

```text
Verilator 5.048 : make pl-lint
  -> 0 errors
  -> warnings: EOFNEWLINE x4, IMPORTSTAR x3, PINMISSING x3 (legacy control_unit
     ports), UNUSEDPARAM x1, UNUSEDSIGNAL x4

VCS W-2024.09-SP1 : make pl-build (vcs -full64 -sverilog -top pipeline_tb -f tb/filelists/pipeline.f)
  -> compiles, elaborates and runs
```

---

## 4. What is not written yet

| Gap | Detail |
|---|---|
| No oracle in the pipeline testbench | The expected `TXN`/`SIG` comparison above was done by hand; the testbench only checks halt-on-`ebreak` |
| Pipeline scoreboard not adapted | `tb/sv/pipeline/pipeline_scoreboard.sv` is still the single-cycle `core_scoreboard` (module name, `core_verif_pkg` import); it is not in `tb/filelists/pipeline.f` |
| Pipeline assertions not adapted | `tb/sv/pipeline/pipeline_assertions.sv` is still the single-cycle `core_assertions` (`core_mem_if`, `sys_ecall`/`sys_ebreak` properties); the pipeline's own invariants (trap precision, single-outstanding request, freeze consistency, commit count) have no properties yet |
| Random regression not started | `tb/sv/pipeline/random/` holds `pl_instr.sv`, `pl_program.sv`, `pl_ref_model.sv`, `pl_coverage.sv` in package `rv_random_pkg`, but the package is commented out of `tb/filelists/pipeline.f` and the testbench has no random mode |
| No coverage | No `-cm` build/run targets and no covergroups for the pipeline; the single-cycle `make cov` flow still points at the frozen core |
| Directed hazard tests missing | No load-use, chain-forwarding, or trap-during-freeze test exists. `hazard_test.S` is an empty stub |
| Design-phase scratch programs not in the repo | The request-back-pressure smoke programs and the misaligned/illegal/`ecall` programs from the design phase live in a scratch copy under `/tmp`, not in `programs/asm/` |
| Exception directs missing for the pipeline | `programs/asm/` has no misaligned load/store, illegal-instruction, or `ecall` program; the trap paths except `ebreak` are unexercised |
| Single-cycle regression not re-run | `control_unit`, `load_store_unit` and `core_single_cycle` were modified while landing the pipeline, so the v0.4.0 "verified" claim needs a fresh `make run` before it is repeated |
| Vivado | Never run: BRAM inference for `dmem_bram`, LUTRAM inference for imem, resources and timing are all unchecked |
| Working tree | All of the above is uncommitted on `feature/pipeline-5stage` |

---

## 5. Next Steps

1. Commit the current state (suggest splitting into: exception token, memory
   protocol, BRAM adapter, pipeline testbench bring-up).
2. Re-run the single-cycle `make run` regression to confirm the shared-module
   edits did not break the v0.4.0 baseline.
3. Move the expected-file comparison into the testbench: adapt the scoreboard to
   the commit/transaction view and register the six programs as directed tests
   with per-test expected `TXN`/`SIG` data.
4. Add pipeline assertions: single retire per instruction, no flush during a
   freeze, `req_sent` implies `req_valid = 0`, `!(wb_exc_pending && req_sent)`,
   `halted` implies no request/no writeback.
5. Write the missing directed tests: hazard chains (load-use, double
   forwarding), `hazard_test.S`, misaligned load/store, illegal instruction,
   `ecall`, and request-channel back-pressure (`req_ready` randomised).
6. Port the random flow (`pl_random_pkg`) into the pipeline filelist and enable
   the ISS-lockstep regression on top of the commit view.
7. Then: Vivado synthesis/first board bring-up (BRAM/LUTRAM inference, `halted`
   to an LED), `EXC_INSTR_ADDR_MISALIGNED` in EX, and an `rsp_err` channel.
