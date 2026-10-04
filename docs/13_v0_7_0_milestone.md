# v0.7.0 Milestone (in progress): Request/Response Instruction Fetch

## Summary

v0.7.0 replaces the combinational instruction fetch (`imem_addr` →
`imem_rdata` in the same cycle) with the same two-channel request/response
style the data memory has used since v0.5.0. This is the change that lets the
instruction memory move from LUTs to block RAM, and later behind an address
decoder, a cache or a bus.

The IF stage now owns a single-outstanding fetch transaction, can kill a fetch
that is already in flight when a branch redirects, buffers one response, and
applies back-pressure to the memory when IF/ID cannot take an instruction. The
testbench instruction memory is a new back-pressure model with random request
readiness and random latency, reproducible per seed.

```text
make pl-build
./sim/build/pipeline_vcs/simv +SEED_OFFSET=1 +NUM_SEEDS=500     (2026-10-03, branch feature/fpga-arty-a7)

SUMMARY: 500 passed, 0 failed | total_txns=5688, total_retired=29676
ASSERTION FAILURES: 0
PIPELINE SVA FAILURES: 0
ALL RANDOM TESTS PASSED
load_use_hazard 436 | redirect && mem_stall 68 | mem_stall 5688
PIPE_FWD_COVERAGE = 100.00%   PIPE_LU_COVERAGE = 87.00%   PIPE_REDIR_COVERAGE = 95.24%
```

`total_txns` and `total_retired` are identical to the v0.5.0 release run: the
same 500 programs produce the same commit stream with the new fetch path and a
memory that stalls at random.

**Status: in progress — integration-tested in simulation; board smoke test
passed on 2026-10-03 with the instruction ROM in block RAM (§10).** One
directed program, passing case only; not tagged.

---

## 1. Why the fetch path had to change

| Constraint | Consequence for a combinational fetch |
|---|---|
| FPGA block RAM has a registered read | `addr → instr` in the same cycle is impossible; v0.6.0 had to put the 256-word program in LUTs |
| Next steps are an address map (text at `0x8000_0000` for Spike), then caches and a bus | Fetch latency stops being a constant |
| The data memory already speaks request/response ([03_pipeline_design.md §5](03_pipeline_design.md#5-memory-interface-request--response)) | Instruction memory was the last combinational interface of the core |

The core of the problem is that, with a transaction interface, an instruction
can exist **outside every pipeline register**: the request has been accepted,
the response has not arrived. A redirect that only flushes IF/ID and ID/EX
misses that instruction — it arrives one or more cycles later, on the wrong
path. And when it arrives, `pc_current` has already moved on, so the response
has to carry back the PC of the request that produced it.

---

## 2. Interface and contract

```text
CORE                              IMEM
imem_req_valid  ------------------>
imem_req_addr   ------------------>
                <------------------ imem_req_ready
imem_rsp_ready  ------------------>
                <------------------ imem_rsp_valid
                <------------------ imem_rsp_rdata
```

Request and response are independent channels: `req_ready` and `rsp_valid`
may both be 1 in the same cycle (one transaction retires while the next is
accepted).

The data-memory rules of v0.5.0 ([03_pipeline_design.md §5.1](03_pipeline_design.md#51-protocol-rules))
carry over, with two deliberate differences:

| # | dmem (v0.5.0) | imem (v0.7.0) |
|---|---|---|
| 1 | While `valid && !ready`, the request contents are unchanged | `req_valid` never drops before the handshake, but **`req_addr` may change to a redirect target** before it is accepted. The slave must sample the address only in the handshake cycle |
| 2 | Exactly one response per accepted request | Same |
| 3 | Response at least one cycle after acceptance | Same |
| 4 | Single outstanding | Same |
| 5 | Core drives `rsp_ready = 1` | **Core may hold `rsp_ready = 0`**; the slave must keep `rsp_valid` and `rsp_rdata` stable until the handshake |
| 6 | Byte address, slave indexes `addr[AW+1:2]` | Same |

Both differences are design choices with a cost later; see §7.1.

---

## 3. IF stage (`rtl/pipeline/if_stage.sv`)

### 3.1 State (`pipeline_pkg::fetch_state_t`)

| Field | Meaning |
|---|---|
| `pending` | A request has been accepted and its response has not been taken yet |
| `pending_pc` | Address of that request; becomes `ifid.pc` when the response is used |
| `killed` | That request was overtaken by a redirect; its response is accepted and dropped |
| `buf_valid`, `buf_pc`, `buf_instr` | One-entry fetch buffer; it drives `ifid_d` directly |

### 3.2 Equations

```systemverilog
// response channel: free buffer, or a response to drop, or the buffer drains this cycle
assign imem_rsp_ready = !fetch_q.buf_valid || fetch_q.killed || ex_redirect_taken || ifid_take;
// request channel: single outstanding, but a new request may go out in the
// same cycle the previous response is taken (back-to-back fetch)
assign imem_req_valid = !fetch_q.pending || imem_rsp_fire;
// a request that has not been accepted yet can be retargeted to the redirect
assign imem_req_addr  = arbitration_redirect ? ex_redirect_pc : pc_current;

// the PC advances only when a request is accepted
pc_next = pc_current;
if (imem_req_fire)          pc_next = imem_req_addr + 32'd4;
else if (ex_redirect_taken) pc_next = ex_redirect_pc;
```

`core_5stage` provides the two arbitrated inputs:

```systemverilog
assign arbitration_redirect = ex_redirect_taken && !mem_stall && !wb_trap && !halted;
.ifid_take(ifid_en && !ifid_flush)
```

The next-state block starts from `fetch_d = fetch_q` and then applies, in this
order (the last write wins):

```text
1. IF/ID takes the buffer                      buf_valid = 0
2. response taken, not killed, no redirect     buffer <= {pending_pc, rsp_rdata}
3. redirect                                    buffer cleared; killed = 1 if a request is pending
4. response taken                              pending = 0, killed = 0
5. request accepted                            pending = 1, pending_pc = req_addr, killed = 0
```

The `fetch_d = fetch_q` default is required: without it every field not
written on some path becomes a latch (a scratch Vivado out-of-context run of
the first version reported 99 extra latches, `Synth 8-327`).

`hazard_unit` no longer produces `pc_stall`. Whether the PC moves is decided by
the request handshake alone; the stall and freeze cases reach IF through
`ifid_take` (the buffer is not drained, so `rsp_ready` drops, so no new
response and no new request).

### 3.3 Four cycle cases

**Back-to-back fetch, memory latency 1:**

| Cycle | Request | Response | Fetch buffer | IF/ID |
|---|---|---|---|---|
| c0 | A accepted | — | — | — |
| c1 | B accepted (`req_valid = rsp_fire`) | A taken | — | — |
| c2 | C accepted | B taken | A | — |
| c3 | D accepted | C taken | B | A |

One instruction per cycle once the stream is running.

**Redirect while a fetch is in flight:** the redirect marks the in-flight
request `killed` and clears the buffer. `req_valid` is 0 (a request is
pending), so `pc_next = ex_redirect_pc`. When the wrong-path response
arrives, `rsp_ready = 1` because of `killed`; it is dropped, and in the same
cycle (`req_valid = rsp_fire`) the request for the target goes out.

**Redirect while a request is waiting for `req_ready`:** nothing has been
accepted, so nothing has to be killed. `req_addr` switches to the target in
the redirect cycle. If the memory accepts it, the target is fetched with no
lost cycle; if not, `pc_next = ex_redirect_pc` keeps the target for the next
cycle.

**Response arrives while IF/ID is stalled:** the response goes into the
buffer. If the buffer is already full and not being drained, `rsp_ready = 0`
and the memory holds the response.

### 3.4 Cost

Measured on a scratch harness (500 seeds, `+SEED_OFFSET=1`, an ideal memory
with latency 1 that holds its response; the repository has no cycle-count
target yet):

| Fetch path | Total cycles | CPI |
|---|---|---|
| v0.6.0 combinational fetch | 45961 | 1.549 |
| v0.7.0 IF (with retargeting) | 50648 | 1.707 |
| Same IF, address taken only from `pc_current` | 54335 | 1.831 |

The difference between the last two rows is 3687 cycles, the number of
effective redirects in the run: retargeting saves one cycle per redirect, which
cancels the cycle added by the fetch buffer stage.

---

## 4. Testbench instruction memory (`tb/sv/pipeline/imem_bram.sv`)

Testbench-only, not synthesizable; listed in `tb/filelists/pipeline.f`, not in
`pipeline_rtl.f`.

| Behavior | Implementation |
|---|---|
| Single outstanding, back-to-back | `busy_q` (accepted, not yet handed over); `req_ready = (!busy_q \|\| rsp_fire) && ready_rand_q` |
| Latency `1 + d` | In the accept cycle `rsp_valid <= (d == 0)`; otherwise a countdown raises it |
| Latency distribution | `d = 0` with about 60 %, otherwise uniform in `[1, MAX_DELAY]` (`MAX_DELAY = 5`) |
| Request back-pressure | `ready_rand_q` redrawn every cycle, about 80 % ready |
| Response hold | While `rsp_valid && !rsp_ready`, `busy_q = 1` blocks new requests, so `rsp_rdata` cannot be overwritten |
| Same-cycle ordering | Three nonblocking sections — response leaves, countdown, accept — with **accept written last** so a new request survives a same-cycle response handshake |
| Per-seed reproducibility | Random draws use `$dist_uniform(s, lo, hi)` on a state `rng_q` that is reloaded from `seed_q` on reset; `pipeline_tb` calls `u_memory.reseed(seed)` before `apply_reset()` |

Why each rule exists:

| Variant | Effect | Evidence |
|---|---|---|
| `req_ready = !pending_q` (first model) | At most one fetch every 3 cycles; instructions are never adjacent, so load-use stalls, EX/MEM forwarding and redirects behind a memory access cannot occur | seed 1: `load_use_hazard 0`, FWD coverage 44.84 %, while the regression passed |
| Accept written before "response leaves" | A request accepted in the response cycle is erased; the core waits forever | 30 of 30 seeds fail (`COMMITS size mismatch: dut=1 iss=54`) |
| Uniform latency 0..5 | Hazards become rare | 500 seeds: `load_use_hazard` 117 instead of 436, LU coverage 76 % instead of 87 % |
| `$urandom_range` | The random stream of seed N depends on the seeds run before it; `+SINGLE_SEED=N` does not reproduce a batch failure | seeds 37/137/400 now give the same cycle counts in a batch run and alone (215/190/336) |

The array keeps the name `mem` because `pipeline_tb` loads programs through
`u_memory.u_imem.mem`.

---

## 5. Verification changes

| Area | Change |
|---|---|
| Probe interface | `imem_addr`/`imem_rdata` replaced by the six request/response signals |
| Interface assertions | `p_rsp_hold` (response stable while not taken), `p_req_aligned`, `p_imem_rsp_live` (an accepted request gets `rsp_valid` within `1 + MAX_DELAY` cycles); `u_assertions.fail_count` gates the verdict |
| White-box assertions | `redirect_valid_assert` removed: it encoded "IF/ID is always valid", which is no longer true with fetch bubbles |
| Hang detection | `run_until_halt` stops after `NO_RETIRE_LIMIT = 200` cycles without a retire and reports `DEADLOCK`; after `MAX_CYCLES = 4000` while still retiring it reports `TIMEOUT`. Both print `dump_hang_state` (§5.2) |
| Bring-up | The `+HEX=` bring-up program and its dump were removed; the run before the seed loop executes the `ebreak`-filled memory |

### 5.1 Negative tests

| Injected defect | Result |
|---|---|
| IF does not kill an in-flight fetch on redirect | 184 of 200 seeds fail; 1400 white-box assertion failures |
| Memory model: accept section moved before the response section | `p_imem_rsp_live` fails at the cycle the request is lost; `DEADLOCK` after 200 cycles with the dump below |

### 5.2 Reading a hang report

```text
==== DEADLOCK at cycle 208 (no retire for 200 cycles, 1 commits) ====
  last commit : pc=00000000 instr=dcac8393
  IF          : pc_current=00000008 pending=1 pending_pc=00000004 killed=0 buf_valid=0 buf_pc=00000000
  imem req    : valid=0 ready=1 addr=00000008 | rsp: valid=0 ready=1
  imem slave  : busy_q=0 delay_q=5
  pipe valid  : ifid=0 idex=0 exmem=0 memwb=0 | mem_stall=0 halted=0
```

With one transaction outstanding, both sides must agree on whether it exists:

| core `pending` | slave `busy_q` | `rsp_valid` | Meaning |
|---|---|---|---|
| 1 | 0 | 0 | The slave lost the request |
| 1 | 1 | 1 | The core never takes the response: check `buf_valid` / `ifid_take` |
| 1 | 1 | 0 | The slave is still counting down; stuck here means a slave latency bug |
| 0 | — | — | Not a fetch problem: check `mem_stall` and the data-memory line |

The longest legitimate gap between two retires over 1000 seeds was 15 cycles,
so the 200-cycle limit has about 13x margin. It must be re-measured when a
slower memory model is used.

---

## 6. Issues found during this phase

| Issue | Layer | Found by |
|---|---|---|
| Memory model accepted at most one fetch every three cycles; every hazard counter dropped to zero while the regression passed | Testbench model (throughput) | Cover counts of zero; controlled experiment with the same core and a pipelined model |
| Same-cycle accept erased by a later nonblocking assignment; the core deadlocked | Testbench model (ordering) | 30/30 seed failures, reported only as commit-count mismatches |
| Memory model would accept a second request while counting down (latent: the IF never requests while a fetch is pending) | Testbench model (protocol) | Review |
| A hang was reported only as a commit-count mismatch after 4000 cycles | Testbench (observability) | The deadlock above |
| First IF version: `imem_rsp_ready` declared 32 bits wide; a nonblocking assignment to a non-existent field inside `always_comb`; no `fetch_d = fetch_q` default; `ifid.pc_plus_4` taken from `pc_current` instead of the buffered PC; the buffer was never cleared when IF/ID took it | RTL (IF) | Fixed between the first IF commit and the tested version |

The general lesson: **the core and the memory model can hide each other's
bugs.** A model that never accepts back-to-back requests hides IF bugs that
need adjacent instructions; an IF that never requests while a fetch is
pending hides a model that would accept two. Each side needs its own checks
(the protocol and liveness assertions) and its own negative tests.

---

## 7. Known limitations and open risks

### 7.1 Address retargeting is not AXI-compatible

AXI requires the read address to stay stable while `ARVALID && !ARREADY`
(protocol checker rule `AXI_ERRM_ARADDR_STABLE`). The v0.7.0 IF keeps
`req_valid` high but may change `req_addr` in that window. This is harmless
for the testbench model and for a block RAM, which sample the address only in
the handshake cycle, but a slave that starts work when `valid` rises would
return the wrong instruction.

Before an AXI port: either register the request at an adapter or cache boundary
and keep retargeting on the core side only, or drop retargeting and kill the
held request on acceptance (one extra cycle per affected redirect, see §3.4).

Response back-pressure (`RREADY`) and drop-on-kill (the R beat is still
accepted) are compatible with AXI. With multiple outstanding fetches, the
single `killed` bit would become a counter or an epoch tag.

### 7.2 A second redirect source (CSRs) needs one redirect signal

The IF uses the raw `ex_redirect_taken` for the kill, the buffer clear,
`rsp_ready` and `pc_next`, and `arbitration_redirect` for the request address.
This is correct today only because a redirect that arbitration blocks (memory
stall) is asserted again on the next cycle: the frozen branch stays in EX.

Example: `ex_redirect_taken = 1`, `mem_stall = 1`, and a request is accepted in
the same cycle. It carries the wrong-path `pc_current`, `pc_next` becomes
`pc_current + 4`, and the redirect target is not stored anywhere. The next
cycle repairs this because the branch is still in EX.

A trap or `mret` redirect from WB is a one-cycle event and does not repeat.
Before CSRs: arbitration produces one `fetch_redirect` / `fetch_redirect_pc`
(trap over EX redirect), the IF uses it everywhere, and a blocked redirect is
either impossible or held in a register until IF takes it.

### 7.3 Other

| Item | State |
|---|---|
| Synthesizable instruction memory | Done: `imem_rom` is a request/response slave in block RAM that holds its response while `rsp_ready = 0` (§10). Not covered by the protocol assertions, which are bound only in `pipeline_tb`; no negative test for the hold yet |
| FPGA build | Ported; builds, meets timing at 25 MHz and passes the board smoke test (§10) |
| Hazard-density gate | Not added. The regression still passes if every hazard counter is zero (the first memory model did exactly that) |
| Fetch after halt | IF keeps issuing requests after `halted`; harmless in simulation, not yet decided for the board |
| Bring-up run | Its `timeout` result is printed but does not fail the regression |
| Coupling | `p_imem_rsp_live` uses a hand-copied `IMEM_MAX_LAT = 6` (= 1 + `MAX_DELAY`); `dump_hang_state` reads the model's `busy_q`/`delay_q` and has to change when the model does |
| Coverage | `src_x_def` at 66.7 %: one redirect source × deferred-redirect combination is not reached; not analyzed yet |
| Lint | `make pl-lint`: 0 errors; two new unused declarations (`ifid_take` in `core_5stage`, `pc_plus_4` in `if_stage`) |

---

## 8. Running

```sh
make pl-build
./sim/build/pipeline_vcs/simv +SEED_OFFSET=1 +NUM_SEEDS=500    # fixed-offset regression
./sim/build/pipeline_vcs/simv +SINGLE_SEED=<n>                 # reproduce one seed, same timing as in the batch
make pl-lint
```

`make pl-run` prepends a time-based `+SEED_OFFSET`, so its numbers change from
run to run (see [11_v0_5_0_milestone.md §8](11_v0_5_0_milestone.md#8-running-the-regression)).

---

## 9. Next

1. ~~Synthesizable instruction memory, port `fpga_sys`, repeat the v0.6.0
   board test~~ — done (§10). Remaining on the board side: a negative test for
   the `imem_rom` response hold, the fail-path test, post-synthesis netlist
   simulation, and an Fmax sweep.
2. Hazard-density gate in `pipeline_tb`.
3. Directed tests for the four cycle cases in §3.3.
4. Address map and Spike as an external reference.
5. CSRs, after the redirect unification in §7.2.

---

## 10. FPGA build and board test (2026-10-03)

`fpga_sys` connects the six fetch signals, and `rtl/fpga/rtl/imem_rom.sv` is
now a request/response slave:

| Rule | Implementation |
|---|---|
| Accept | `req_ready = !rsp_valid \|\| rsp_ready` (single outstanding, back-to-back) |
| Read | `rsp_rdata <= rom[idx]` only on `req_fire`: synchronous read with enable, latency 1 |
| Hold (rule 5) | While `rsp_valid && !rsp_ready`, `req_ready = 0`, so the read enable stays low and `rsp_rdata` does not change |
| Mapping | `(* rom_style = "block" *)` on the array |

```text
fpga_sys_tb (VCS)           cycles=215 halted=1 cause=EXC_BREAKPOINT trap_pc=00000240
                            tohost_seen=1 tohost=00000001 pass=1 fail=0 error_trap=0 mark_seen=1
                            FPGA_SYS PASS                         (v0.6.0: 206 cycles)
Vivado 2026.1, 25 MHz       WNS +20.401 ns, WHS +0.154 ns, 0 critical warnings
                            1725 LUT, 1700 FF, 2 RAMB18E1, 1 MMCM, 2 BUFG
Arty A7-100T (2026-10-03)   PASS LED on; all four LED views show the expected pattern
```

### 10.1 Two builds

The first build had no `rom_style` attribute. Both bitstreams passed on the
board.

| | No attribute (02:04) | `rom_style = "block"` (02:28) |
|---|---|---|
| Instruction ROM | LUTs | RAMB18E1, true dual-port 2 × 18 bit, `DOA_REG = DOB_REG = 1` |
| LUT / FF (placed) | 1846 / 1770 | 1725 / 1700 |
| WNS | +20.027 ns | +20.401 ns |
| Worst path | `memwb_q.rd_addr` → `idex_q` reset pin (flush), 19.231 ns, 13 levels | `memwb_q.ctrl_wb.wb_sel` → `pc` D pin, 19.501 ns, 20 levels (7 × CARRY4) |

v0.6.0 for reference: 1750 LUT, 1641 FF, WNS +21.925 ns, worst path
`idex_q.rs2_addr` → `idex_q` reset pin.

### 10.2 Findings

| Finding | Evidence |
|---|---|
| A synchronous read is not enough: without the attribute Vivado kept the 256 × 32 ROM in LUTs | `RAMB18E1 = 1` (data memory only); FF +129 against a prediction of +132 with the read register in fabric |
| The `Block RAM: Final Mapping Report` does not list a ROM, in either build | Only `u_dmem/mem_reg` appears; the evidence is the `RAMB18E1` count and `get_cells -hier -filter {REF_NAME =~ RAMB*}` |
| Vivado moved `fetch_q.buf_instr` from the IF stage into the block RAM output register | No `buf_instr` flip-flops in the routed netlist; `DOA_REG = DOB_REG = 1`; `REGCE` is driven by the buffer load condition. This accounts for 64 of the 70 fewer flip-flops; the other 6 are not attributed |
| The retargeting path exists but is not critical | redirect → `req_addr` → BRAM address: 17.922 ns, slack +21.511 ns |
| The fetch response path is short | BRAM → `ifid_q.instr`: 0 logic levels, 2.473 ns |

`rom_style` is a synthesis attribute that VCS ignores, so `fpga_sys_tb` cannot
tell the two builds apart. The block-RAM build is verified by the board run
only. The 9 extra cycles against v0.6.0 have not been broken down.

Vivado procedures, report reading and the full numbers of both runs:
[rtl/fpga/vivado_notes/](../rtl/fpga/vivado_notes/README.md).
