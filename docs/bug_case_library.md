# Bug Case Library

| # | Date | Case | Defect layer | Found by |
|---|------|------|--------------|----------|
| 1 | 2026-07-01 | JAL J-immediate bit swap | RTL (`imm_gen`) | Bit-exact cross-check vs. spec |
| 2 | 2026-07-08 | `sys_ecall`/`sys_ebreak` driven X forever | RTL (`control_unit`) | First run of new SVA |
| 3 | 2026-06-30 | Reference model wrote the address instead of the data | Checker (ISS) | Delayed false FAIL |
| 4 | 2026-06-30 | Generator emitted instructions the ISS didn't implement | Checker contract | First random run, size mismatch |
| 5 | 2026-07-03 | Retire counting off-by-one at reset release | Checker (TB timing) | FINAL-PC mismatch, all else green |
| 6 | 2026-07-03 | Vacuity guard false-fatal on arithmetic loops | Checker (meta) | Spurious `$fatal` |
| 7 | 2026-07-06 | `pick_operands` never returned its operands | Stimulus | Static review |
| 8 | 2026-07-06 | Bounded-loop back-edge measured from the wrong origin | Stimulus | Run-budget watchdog |
| 9 | 2026-06-18 | Illegal driver combination through a task call chain | TB construction | Compile error, misleading location |
| 10 | 2026-07-07 | 1290 loads, zero non-zero data | Coverage hole | Anti-vacuity coverage bin |
| 11 | 2026-07-08 | Every backward jump was a JAL | Coverage hole | Review; no bin existed |
| 12 | 2026-09-19 | Pipeline random test task defined but never called; coverage 0% | TB construction | 0% coverage on every group |
| 13 | 2026-09-20 | Memory-request assertions read the IF-stage instruction | Checker (stage alignment) | 25 false failures on the bring-up program |
| 14 | 2026-09-20 | Commit comparison included `rd_data` when `rd_we = 0` | Checker (don't-care field) | 29 of 30 seeds failed; 294 mismatches, all `rd_data` of branches/stores |
| 15 | 2026-09-18 | Hazard-bias producer taken from a store's never-encoded `rd` | Stimulus (dead field) | Code review of the bias design |
| 16 | 2026-09-18 | Hard constraint `rs1 == c` silently removed loads/stores | Stimulus (solver) | Reasoning about the constraint; no error was raised |
| 17 | 2026-09-20 | Textbook flush and load-use assertions misfired on correct RTL | Checker (timing/priority) | Failure counts equal to antecedent counts (1516, 43) |
| 18 | 2026-09-20 | Redirect-during-memory-stall and load-into-branch never occurred | Coverage hole (template shape) | Cover counts of zero at 200 and 500 seeds |
| 19 | 2026-09-27 | White-box assertions did not gate the verdict; counter keys crossed | Checker (verdict) | Injected bug reported under the wrong name |
| 20 | 2026-09-27 | Backward `JAL` counted as forwarding in coverage | Coverage (dead field) | Unexpected bin in a per-bin tally |
| 21 | 2026-09-29 | `create_clock` on a port name that did not exist: no clocks, timing "met" unchecked | Constraints (XDC) | `report_clocks` empty; `[Vivado 12-4739]` critical warning under a "0 critical warnings" synthesis summary |
| 22 | 2026-09-29 | Repository-relative `$readmemh` path unreadable in a Vivado project; the ROM would be all zero | Build flow | `[Synth 8-4445]` in a scratch project-mode test, with the `.mem` already added to the project |
| 23 | 2026-09-29 | On-chip verdict without `tohost == 1`: a failing self-check would light PASS | Checker (verdict, in RTL) | Review; the code was lint-clean |
| 24 | 2026-09-29 | Deleted branch labels assembled without an error | Tooling (`asm_to_hex.sh` never links) | Review; GNU `as` exits 0 and leaves unresolved relocations |
| 25 | 2026-10-02 | Instruction-memory model accepted one fetch every three cycles; load-use, EX/MEM forwarding and redirect-behind-memory never occurred while the regression passed | Testbench model (throughput) | Hazard cover counts of zero; same core against a pipelined model |
| 26 | 2026-10-02 | Same-cycle accept erased by a later nonblocking assignment; the core deadlocked and the log showed only a commit-count mismatch | Testbench model (ordering) + observability | 30 of 30 seeds failing with one commit each |
| 27 | 2026-10-02 | Memory model would accept a second request during its latency countdown, hidden by an IF that never requests while a fetch is pending | Testbench model (latent protocol) | Review |

---

## Recurring patterns

1. **Silent passes are the enemy, in four flavors:** an output nobody checks
   (Case 2), stimulus that doesn't mean what it says (Case 7), checks that
   only ever see trivial data (Case 10), and behavior with no coverage bin
   (Cases 1, 11). None of these can turn a regression red.
2. **Every DUT output needs a consumer** — a scoreboard field, an assertion,
   or a written exclusion. "Connected to the interface" is not consumption.
3. **The verdict logic is part of the testbench.** Any failure source that
   does not feed the final pass/fail gate — assertion counts included — is
   decoration (Case 2).
4. **Generator and oracle share one contract.** The supported-instruction
   set lives in one place, and the oracle fatals on anything outside it
   (Case 4).
5. **Checkers and meta-checkers are code too:** single write-back points in
   the ISS (Case 3), aligned counting semantics (Case 5), and consistent
   metric domains in vacuity guards (Case 6) all required the same rigor as
   RTL.
6. **Push self-checks upstream.** A generation-time `$fatal` on a mis-aimed
   back edge (Case 8) is worth thousands of simulation cycles of watchdog
   debugging.
7. **Bit-slicing logic is guilty until every bit is excited** — by random
   fields wide enough to reach the boundaries, or by an independent
   bit-exact model (Cases 1, 11).
8. **A field is meaningful only when the encoding or a valid bit says so.**
   The same mistake appeared four times in one phase — a store's `rd` used as
   a producer (Case 15), `rd_data` compared with `rd_we = 0` (Case 14), and
   immediate bits read as `rs1`/`rs2` in an assertion decode and in coverage
   (Case 20).
9. **In a pipeline, "the same cycle" is not "the same instruction."** Every
   property and covergroup has to name the stage each operand comes from
   (Case 13), and whether a control signal is combinational or registered
   (Case 17).
10. **When a failure count equals an antecedent count, suspect the property,
    not the design** (Case 17).
11. **A zero that survives more seeds is structural.** It is fixed by changing
    the generator's templates, not by running longer (Case 18); a bin the RTL
    cannot reach is written as an assumption property plus `ignore_bins`.
12. **Test the checkers.** Injecting four hazard-logic bugs showed which
    properties could see which bug — a property that restates the mechanism
    missed one that a property stating the goal caught.
13. **A clean summary line is not evidence.** In the FPGA flow, setup mistakes
    that destroy the result came back as warnings (Cases 21, 22) or not at all
    (Case 24) while the headline stayed green. Check the artifact the mistake
    would destroy — `report_clocks`, the ROM-load message and LUT count, the
    object file's relocations — and grep the full log for `CRITICAL`.
14. **An on-chip verdict is a checker too** (Case 23). It needs the same
    independent expectation as a testbench verdict, and a negative run that
    shows it can say FAIL.
15. **The partner on an interface bounds what the regression can see.** A slow
    memory model makes whole hazard classes structurally impossible (Case 25),
    and a well-behaved master hides a slave that breaks the protocol (Case 27).
    Give each side its own assertions and negative tests, and gate on hazard
    counts, not only on the pass line.
16. **A hang must name itself** (Case 26): stop on lack of progress, tell
    deadlock from non-termination, and print which side of each handshake is
    waiting.
