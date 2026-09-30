# v0.6.0 Milestone: FPGA Bring-Up on Arty A7-100T

## Summary

v0.6.0 runs the frozen v0.5.0 pipeline on a Digilent Arty A7-100T
(`xc7a100tcsg324-1`). The core is functionally unchanged. The only core edit is
the removal of `` `default_nettype none `` from the ten `rtl/pipeline/**` files,
because Vivado rejects that directive together with `input logic` ports
(`[Synth 8-6735]`, which cannot be downgraded).

A technology-independent system wrapper (`fpga_sys`) adds an instruction ROM,
the existing `dmem_bram`, and passive observers for the trap and for a `tohost`
store. A board wrapper (`arty_a7_top`) adds the MMCM clock, reset conditioning
and an LED view multiplexer. The program on the board is the directed
`hazard_test` with a self-checking tail: it compares its own 15 signature words
against constants and writes a verdict word to `tohost`.

```text
fpga_sys_tb (VCS)          cycles=206 halted=1 cause=EXC_BREAKPOINT trap_pc=00000240
                           tohost_seen=1 tohost=00000001 pass=1 fail=0 error_trap=0 mark_seen=1
                           FPGA_SYS PASS
Vivado, 25 MHz             WNS +21.925 ns, WHS +0.162 ns, all user constraints met, 0 critical warnings
                           1750 LUT, 1641 FF, 1 RAMB18E1, 1 MMCM, 2 BUFG
Arty A7-100T (2026-09-30)  PASS LED on; all four LED views show the expected pattern
```

**Status: board smoke test passed** — one directed, self-checking program,
positive case only. The fail path has not been exercised in simulation or on
the board yet (§7), and no random program has run on hardware.

---

## 1. Structure

```text
arty_a7.xdc                  pin map, 100 MHz input clock
arty_a7_top.sv   (board)     MMCME2_BASE 100 -> 25 MHz, 2 x BUFG
                             reset bridge: async assert, sync release (button, !locked)
                             LED views selected by sw[1:0], heartbeat, RGB status
  fpga_sys.sv    (portable)  core_5stage + imem_rom + dmem_bram
                             trap latch, store / tohost snoop, pass / fail
    imem_rom.sv              256 x 32 ROM, combinational read, $readmemh
```

`fpga_sys` contains no vendor primitives and no pin names, so VCS simulates it
with the same program the board runs. `arty_a7_top` touches no core internals.

| File | Role |
|---|---|
| `rtl/fpga/rtl/imem_rom.sv` | Instruction ROM: `DEPTH` words, `INIT_FILE`, index `addr[AW+1:2]`, combinational read |
| `rtl/fpga/rtl/fpga_sys.sv` | Core + memories + observers; outputs `halted`, `trap_cause_q`, `trap_pc_q`, `tohost_seen`, `tohost`, `pass`, `fail`, `mark_seen`, `error_trap` |
| `rtl/fpga/arty_a7/arty_a7_top.sv` | Board wrapper: clocking, reset bridge, LED and RGB mapping |
| `rtl/fpga/arty_a7/arty_a7.xdc` | Pins (from the Digilent Arty A7 master XDC) and `create_clock` |
| `rtl/fpga/tb/fpga_sys_tb.sv` | VCS testbench for `fpga_sys`: backdoor program load, run to halt, verdict checks |
| `rtl/fpga/build/` (ignored) | Generated, `EBREAK`-padded `.mem` images |

---

## 2. Design decisions

| Topic | Decision | Reason |
|---|---|---|
| Instruction memory | Asynchronous-read ROM initialized by `$readmemh` | The frozen IF stage uses `imem_rdata` in the same cycle as `imem_addr`; a registered (block-RAM) read would arrive one cycle late. Vivado folds the 256×32 ROM into logic LUTs (`LUT as Memory` = 0) |
| ROM image | Program padded to 256 words with `EBREAK` (`00100073`) | The same content in VCS and in the bitstream (a short file leaves X in simulation and 0 on the FPGA); a jump outside the program traps with `EXC_BREAKPOINT` at a visible `trap_pc` |
| Data memory | The v0.5.0 `dmem_bram`, 256 words | Inferred as one RAMB18E1 |
| Clock | `MMCME2_BASE`: D = 1, M = 10 (VCO 1000 MHz; the valid range for speed grade -1 is 600–1200 MHz), O = 40 → 25 MHz; feedback through a BUFG; `RST` tied low | The critical path does not fit 100 MHz. At 25 MHz WNS is +21.9 ns; 50 MHz would leave about 2 ns by extrapolation (not built) |
| Reset | `!reset_n \|\| !locked` → two-flop bridge with an asynchronous preset (`ASYNC_REG`) → synchronous, active-high `rst` | The core uses a synchronous reset, so the release has to be aligned to the clock. Assertion is asynchronous because the clock is not running before the MMCM locks. The program runs once after configuration; the RESET button runs it again. Button bounce is not filtered: a bounce only restarts the program, and the observers are reset with it |
| Trap observation | `trap_cause_q` / `trap_pc_q` latched on `trap_valid` | `trap_valid` is a one-cycle pulse, and `trap_cause` / `trap_pc` are combinational from `memwb_q`, which is flushed to zero one cycle later. The latched values are valid only while `halted` is set |
| Self-check protocol | `tohost` at `0x3FC`: `1` = PASS, `(n << 1) \| 1` = FAIL at check `n` | riscv-tests convention. Bit 0 marks "written"; `tohost[4:1]` shows `n` on four LEDs |
| `tohost` observer | Passive snoop of the request channel: `valid && ready && write && addr == 0x3FC && wstrb == 4'b1111`, first write only | The store still reaches `dmem_bram`, so the handshake is untouched (the core waits for a response on stores too). `0x3FC` lies inside the 1 KB data window and is unused by the program |
| Verdict | `pass = halted && cause == EBREAK && tohost_seen && tohost == 1`; `fail = halted && !pass` | Three states: running, pass, fail. Any halt that is not a clean pass — a self-check failure, another trap, or a crash before the verdict — is a fail |
| `mark_seen` | Set by any store handshake | Tells "never started" apart from "hung later" when `halted` never rises |

---

## 3. The program

`programs/asm/hazard_test.S` keeps its hazard body (load-use, forwarding and
redirect cases A–E) and gains a self-checking tail:

- One check per `SIG` line of `programs/expected/hazard_test.expected`, in file
  order: `n` = 1…15 for addresses `0x00, 0x04, 0x08, 0x10, …, 0x3C`. `0x0C` is
  never written, and `0x40` belongs to the store that case D2 must squash.
- Each check is `li x3, n` / `lw x5, addr(x0)` / `li x6, expected` /
  `bne x5, x6, fail`.
- All checks pass → write `1` to `0x3FC`, then `j end`. `fail:` writes
  `(x3 << 1) | 1`. `end:` is the last line of the file, so both paths fall into
  the `EBREAK` padding. There is no explicit `ebreak`: `tools/rv32i_ref.py`
  stops when the PC leaves the program and does not implement SYSTEM
  instructions.
- The program is 144 words (of 256). The reference-model output contains
  `TXN W 000003fc 00000001 1111` and `SIG 000003fc 00000001`. With one expected
  constant deliberately corrupted (check 3, in a scratch copy), the reference
  model produced `SIG 000003fc 00000007`.

The checking code runs on the device under test. A core that is wrong in a way
that also breaks the checking code (for example, a `bne` that never branches)
could report PASS; the negative tests listed in §7 and §9 address that.

---

## 4. LED map

`sw[1:0]` selects what LD7…LD4 show:

| `sw[1:0]` | LD7 | LD6 | LD5 | LD4 | Expected after PASS |
|---|---|---|---|---|---|
| `00` | `halted` | `error_trap` | `pass` | `mark_seen` | on, off, on, on |
| `01` | `tohost[4]` | `tohost[3]` | `tohost[2]` | `tohost[1]` | all off (`n` = 0) |
| `10` | `cause[3]` | `cause[2]` | `cause[1]` | `cause[0]` | `0011` (EBREAK) |
| `11` | MMCM `locked` | `rst` | `tohost_seen` | heartbeat | on, off, on, blinking |

RGB LD0 (green) flashes with the heartbeat, about every 1.3 s. RGB LD1 (red) is
`fail`, and blinks when the core has not halted 2.5 M cycles (0.1 s) after
reset.

Reading view `00` after a failure:

| View `00` | Meaning | Next view |
|---|---|---|
| `halted` off, `mark_seen` off | Never started | `11`: lock, reset, heartbeat |
| `halted` off, `mark_seen` on | Started, then hung | needs simulation or an ILA |
| `halted` on, `pass` off, `error_trap` off | Self-check failed | `01`: `n`, the `n`-th `SIG` line |
| `error_trap` on | A trap other than `EBREAK` | `10`: cause |

`LD7` and `LD6` on together with cause `0010` (illegal instruction) is the
signature of an empty instruction ROM.

---

## 5. Evidence

| Level | Evidence | Status |
|---|---|---|
| Reference model | Verdict `1`; corrupted-constant check gives `7` | Checked |
| `fpga_sys` in VCS | Positive run in the summary | Integration-tested, positive case only |
| v0.5.0 pipeline regression on this tree | 2026-09-30, `simv +SEED_OFFSET=1 +NUM_SEEDS=500`: identical to the v0.5.0 release (`total_txns=5688`, `total_retired=29676`, same coverage, 0 assertion and 0 SVA failures). A second 500-seed run with a time-based offset also passed | Unchanged after the `default_nettype` removal |
| Vivado implementation | Numbers in the summary. `report_clocks` lists `sys_clk_pin` (10 ns) and the auto-derived `clk25_mmcm` (40 ns); `check_timing` reports no unclocked and no unconstrained internal endpoints | Timing met |
| Board | Expected pattern in all four views | Board smoke test passed |

---

## 6. Issues found during bring-up

| # | Issue | How it surfaced | Fix |
|---|---|---|---|
| 1 | `` `default_nettype none `` with `input logic` ports | Vivado `ERROR [Synth 8-6735]`, not downgradable (VCS and Verilator accept it) | Directive removed from the ten pipeline files |
| 2 | `create_clock` named a port that did not exist | `WARNING [Vivado 12-584] No ports matched` and `CRITICAL WARNING [Vivado 12-4739]`; `report_clocks` empty, every path unconstrained, so timing "passes" without being checked. The synthesis summary line still read "0 critical warnings" | Port name corrected; checked with `report_clocks` and `check_timing` |
| 3 | Repository-relative `$readmemh` path in a Vivado project | `CRITICAL WARNING [Synth 8-4445]` even with the `.mem` added to the project; the ROM would be all zero | Bare file name `hazard_test.mem` plus the `.mem` in the project → `[Synth 8-3876] ... read successfully` |
| 4 | Verdict without `tohost == 1` | Review: a failing program (`tohost = 7`) would have lit PASS; the code was lint-clean | Term added |
| 5 | Trap latch recorded only `EBREAK`, with a hard-coded value | Review: any other trap would have read as cause 0 | Latch every trap; judge it in the verdict |
| 6 | Top level: 1-bit `trap_cause_q`, undeclared `locked` | Vivado `ERROR [Synth 8-9250]` and `ERROR [Synth 8-36]` | Fixed |
| 7 | Branch labels `d1`–`d4`, `e1`, `e2` deleted while editing the program | Review. GNU `as` exits 0 on undefined labels because `asm_to_hex.sh` never links: `beq` is relaxed to `bnez` + `j` with an unresolved relocation, so the branch goes to a wrong address | Labels restored; the script still has no link step |
| 8 | Self-check list started at `0x04` and ended at `0x40` | Review: `0x00` unchecked, `0x40` never written | List rebuilt from the `SIG` lines |

Issues 2, 3 and 7 are one pattern: a setup mistake that breaks the result is
reported as a warning, or not at all, while the summary line stays clean.

A tool behavior checked on a scratch design: an MMCM configured with an
out-of-range VCO (M = 15, 1500 MHz) synthesizes without a message, raises
`CRITICAL WARNING [DRC AVAL-46]` at placement, and fails only at
`write_bitstream` (`ERROR [DRC PDRC-34]`).

---

## 7. Known limitations

- **Fail path not exercised.** There is no negative run yet, neither in
  simulation (`+EXPECT_TOHOST=7`) nor on the board; the PASS LED has never been
  seen to fail.
- One directed program on hardware. The random regression runs in simulation
  only.
- `fpga_sys_tb` checks `halted`, the cause, `mark_seen`, `tohost` and `pass`,
  but not `fail`, `error_trap` or `tohost_seen`, and it has no Makefile target.
- The Vivado build is a local GUI project outside the repository. There is no
  scripted build, and the XDC was re-saved by the GUI (comments dropped).
- `fpga_sys` defaults `IMEM_INIT` to the bare `hazard_test.mem` for Vivado
  project mode. Under VCS the ROM's own load therefore warns
  (`STASKW_RMCOF`, cannot open file), and the testbench loads the program
  through a hierarchical `$readmemh` (`+MEM=`).
- `mark_seen` and `error_trap` are implicit nets in `arty_a7_top`
  (`[Synth 8-11241]`, INFO). Harmless because both are one bit wide.
- No timing exceptions on the asynchronous inputs and LED outputs, and no
  `CFGBVS` / `CONFIG_VOLTAGE`. Not needed for correctness here: unconstrained
  I/O paths are not timed.
- JTAG programming only (volatile); nothing is written to the configuration
  flash.
- No ILA or UART: `trap_pc` and the signature words are not visible on the
  board.
- `asm_to_hex.sh` does not link, so undefined labels are silent (§6, issue 7).
- `make pl-run` passes a time-based `+SEED_OFFSET` before `$(ARGS)`, and
  `$value$plusargs` returns the first match, so `ARGS="+SEED_OFFSET=1"` has no
  effect through `make`. For a fixed offset, run the simulator directly (§8).

---

## 8. Reproducing

Program image:

```sh
./scripts/asm_to_hex.sh hazard_test
./tools/rv32i_ref.py hazard_test
grep 3fc programs/expected/hazard_test.expected      # expect SIG 000003fc 00000001
mkdir -p rtl/fpga/build
awk -v N=256 'NF {print; n++} END {if (n > N) {print "too big: " n > "/dev/stderr"; exit 1} for (; n < N; n++) print "00100073"}' \
    programs/hex/hazard_test.hex > rtl/fpga/build/hazard_test.mem
```

`fpga_sys` simulation, from the repository root:

```sh
mkdir -p sim/build/fpga_sys_vcs/csrc
vcs -full64 -sverilog -debug_access+all -top fpga_sys_tb \
    -f tb/filelists/pipeline_rtl.f \
    rtl/fpga/rtl/imem_rom.sv rtl/fpga/rtl/fpga_sys.sv rtl/fpga/tb/fpga_sys_tb.sv \
    -Mdir=sim/build/fpga_sys_vcs/csrc -o sim/build/fpga_sys_vcs/simv \
    -l sim/build/fpga_sys_vcs/compile.log
./sim/build/fpga_sys_vcs/simv +MEM=rtl/fpga/build/hazard_test.mem -l sim/build/fpga_sys_vcs/run.log
```

Pipeline regression with a fixed seed offset:

```sh
make pl-build
./sim/build/pipeline_vcs/simv +SEED_OFFSET=1 +NUM_SEEDS=500 -l sim/build/pipeline_vcs/run.log
```

Vivado, project mode, part `xc7a100tcsg324-1`:

1. Add the files listed in `tb/filelists/pipeline_rtl.f`, `rtl/fpga/rtl/*.sv`,
   `rtl/fpga/arty_a7/arty_a7_top.sv`, the constraints
   `rtl/fpga/arty_a7/arty_a7.xdc`, and `rtl/fpga/build/hazard_test.mem`
   (recognized as a Memory File). Set `arty_a7_top` as the top module.
2. After synthesis, search the whole log for `CRITICAL WARNING`; the summary
   line does not count messages from constraint parsing. Confirm the ROM
   loaded (`Synth 8-3876`) and that the design uses about 1.7 k LUTs; far
   fewer means an empty ROM.
3. After implementation, check `report_clocks` and WNS / WHS.
4. Program over JTAG with the Hardware Manager. On Linux the cable drivers
   have to be installed first, as root:
   `<Vivado>/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers`.

---

## 9. Next

1. Negative tests: in simulation (`+EXPECT_TOHOST=7` with a corrupted `.mem`
   built outside `programs/`) and on the board (view `01` must show `0011`,
   RGB red on).
2. Testbench: check `fail`, `error_trap` and `tohost_seen`; add `fpga-mem` /
   `fpga-sim` Makefile targets.
3. A scripted, non-project Vivado build in the repository, with
   `Synth 8-4445` promoted to an error.
4. Visibility on the board: an HDL-instantiated ILA (the Vivado license on the
   build host does not allow netlist-inserted debug cores) or a UART TX for
   `trap_pc` and the signature words.
5. v0.7.0: request/response instruction fetch, so the instruction memory can
   move to block RAM; a memory model with back-pressure.
