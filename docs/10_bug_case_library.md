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
