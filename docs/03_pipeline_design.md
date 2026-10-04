# Pipeline Design (Five-Stage)

Status: **frozen in v0.5.0 — verified in simulation; synthesized and run on an
Arty A7-100T in v0.6.0 ([12_v0_6_0_milestone.md](12_v0_6_0_milestone.md)).**
Last updated: 2026-09-30.

> **v0.7.0 (in progress, branch `feature/fpga-arty-a7`): instruction fetch is
> now request/response** — see [13_v0_7_0_milestone.md](13_v0_7_0_milestone.md).
> On that branch the following parts of this document describe the v0.5.0 /
> v0.6.0 core and no longer match the RTL: the IF and `hazard_unit` rows of §1
> (`pc_stall` was removed), the instruction-memory row of §5.4, the Fetch ports
> in §6, the `pc_stall` clause of invariant 2 in §7, and the "Instruction memory
> on BRAM" row of §8. The data-memory interface (§5.1–§5.3) is unchanged.

This document describes the five-stage pipeline that replaces the verified
single-cycle datapath: the stage partition, the pipeline register payloads, the
unified exception token, the commit rule, and the request/response memory
interface that the FPGA build will hang off.

Related documents:

| Document | Content |
|---|---|
| [04_hazard_forwarding.md](04_hazard_forwarding.md) | Forwarding, load-use stall, redirect flush, global freeze, hazard priority |
| [05_verification_plan.md](05_verification_plan.md) | What is checked today, what is not, and the next verification steps |
| [11_v0_5_0_milestone.md](11_v0_5_0_milestone.md) | v0.5.0 freeze: regression, assertions, coverage, waivers, known limitations |
| [09_v0_4_0_milestone.md](09_v0_4_0_milestone.md) | Frozen single-cycle baseline the pipeline reuses |

The block is **not** a rewrite of the single-cycle core: the leaf modules stay
shared, and the single-cycle core remains in the tree as the v0.4.0 baseline.

---

## 1. Stage Partition

| Stage | File | Consumes | Produces | Responsibility |
|---|---|---|---|---|
| IF | `rtl/pipeline/if_stage.sv` | `pc_stall`, `ex_redirect_taken`, `ex_redirect_pc`, `imem_rdata` | `imem_addr`, `ifid_d` | PC update and instruction fetch |
| ID | `rtl/pipeline/id_stage.sv` | `ifid_q`, WB port (`wb_w_en`/`wb_rd_addr`/`wb_rd_data`) | `idex_d`, `id_rs1_addr`, `id_rs2_addr`, `id_uses_rs1/2` | Decode, register read, immediate generation, exception decode |
| EX | `rtl/pipeline/ex_stage.sv` | `idex_q`, forwarding operands | `exmem_d`, `ex_redirect_taken`, `ex_redirect_pc` | Forwarding mux, ALU, branch/jump resolution |
| MEM | `rtl/pipeline/mem_stage.sv` | `exmem_q`, dmem req/rsp, `wb_exc_pending` | `memwb_d`, `mem_stall`, dmem request/response ports | Data access transaction, misaligned detection, exception merge |
| WB | `rtl/pipeline/wb_stage.sv` | `memwb_q`, `mem_stall` | register-file write port, `trap_valid/trap_cause/trap_pc` | Single commit point, writeback select, trap |

Surrounding control:

| Module | File | Role |
|---|---|---|
| `pipeline_regs` | `rtl/pipeline/pipeline_regs.sv` | IF/ID, ID/EX, EX/MEM, MEM/WB registers, each with `en` + `flush` |
| `hazard_unit` | `rtl/pipeline/hazard_unit.sv` | Four-level priority arbiter producing `pc_stall`, the four `*_en`, the four `*_flush` |
| `forwarding_unit` | `rtl/pipeline/forwarding_unit.sv` | EX operand forwarding selects (`fwd_a_sel`, `fwd_b_sel`) |
| `core_5stage` | `rtl/pipeline/core_5stage.sv` | Top level: wiring, `wb_exc_pending`, sticky `halted`, EX/MEM forward data mux |
| `dmem_bram` | `rtl/pipeline/memory/dmem_bram.sv` | 1-cycle-latency BRAM data-memory slave (also used as the simulation memory model) |

Shared with the single-cycle core (unchanged ports where possible):

| Module | Note |
|---|---|
| `rtl/single_cycle/control_unit.sv` | Decoder. Added `ctrl_uses_rs1/2` and `decode_exc`; the legacy `illegal_instr`/`sys_ecall`/`sys_ebreak` ports stay for the frozen single-cycle core |
| `rtl/single_cycle/alu.sv` | ALU, unchanged |
| `rtl/single_cycle/imm_gen.sv` | Immediate generation, unchanged |
| `rtl/single_cycle/regfile.sv` | 32x32 register file, sync write, `x0` hardwired |
| `rtl/single_cycle/load_store_unit.sv` | Lane replication + sign/zero extension + misalignment; the `default` arm now returns `1'b0` instead of `1'bx` |
| `rtl/single_cycle/pc.v` | PC register, now instantiated inside `if_stage` |

`rtl/pipeline/reuse/control_unit.sv` (a pipeline-local decoder copy) was
deleted — the pipeline uses the shared decoder directly.

### Data flow

```text
        +------+    +------+    +------+    +------+    +------+
imem -->|  IF  |--->|  ID  |--->|  EX  |--->| MEM  |--->|  WB  |--> regfile
        +------+    +------+    +------+    +------+    +------+
           ^                       |           |            |
           |             ex_redirect_taken     | req/rsp    | trap_valid
           +-----------------------<-----------+            v
                                                     flush all younger +
                                                     sticky halted
```

---

## 2. Pipeline Registers

Payload types live in `rtl/include/pipeline_pkg.sv`. Every payload starts with
`valid`, so a flushed register is a zeroed token (`pipeline_regs` writes `'0`).

```systemverilog
typedef struct packed {                        // IF/ID
    logic        valid;
    logic [31:0] pc;
    logic [31:0] pc_plus_4;
    logic [31:0] instr;
} ifid_t;

typedef struct packed {                        // ID/EX
    logic          mem_write;   logic        mem_read;
    logic          reg_write;   logic        alu_sel_b;
    wb_sel_e       wb_sel;      logic        branch;
    alu_ctrl_e     alu_ctrl;    logic        branch_on_zero;
    mem_size_e     mem_size;    logic        load_unsigned;
    logic          jump_and_link;
    alu_src_a_sel_e alu_src_a_sel;
    pc_target_sel_e pc_target_sel;
} idex_ctrl_t;

typedef struct packed {
    logic        valid;
    logic [31:0] pc, pc_plus_4, instr;
    logic [31:0] rs1_data, rs2_data, imm;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    idex_ctrl_t  ctrl;
    exception_t  exc;                          // 5-bit token
} idex_t;
```

`exmem_t` carries `valid, pc, instr, next_pc, alu_result, store_data,
pc_plus_4, rd_addr, ctrl_m (exmem_ctrl_t) , exc`; `memwb_t` carries `valid, pc,
instr, next_pc, alu_result, load_data, pc_plus_4, rd_addr, ctrl_wb
(memwb_ctrl_t), exc`.

Two structural rules are baked into these structs:

1. **The control sub-structs (`idex_ctrl_t`/`exmem_ctrl_t`/`memwb_ctrl_t`)
   contain no exception flags.** Exception state travels only in the `exc`
   field of the payload. Splitting control per stage keeps
   `memwb_ctrl_t = {reg_write, wb_sel}` down to the two bits WB actually uses.
2. **`imm_sel` is not forwarded.** It is only consumed by `imm_gen` inside ID,
   so `idex_t` stores the generated `imm` instead of the selector.

`pipeline_regs` implements flush-over-enable:

```systemverilog
if (ifid_flush)      ifid_q  <= '0;
else if (ifid_en)    ifid_q  <= ifid_d;
// ... same shape for idex_q / exmem_q / memwb_q
```

A flush always wins, which is what makes "trap kills every younger
instruction" a one-cycle, per-stage action.

### ID is combinational, EX has no state

`id_stage` decodes, reads the register file, and assembles `idex_d` purely
combinationally: **all** state in the pipeline lives in the four pipeline
registers plus the register file, the PC, and `req_sent` in MEM. `ex_stage` is
likewise combinational (forwarding mux + ALU + redirect decision).

### Register-file write path

`wb_w_en` is the only register-file write strobe. It is produced by
`wb_stage` from `wb_retire` and the forwarded `reg_write` bit, so the WB→ID
bypass in `id_stage` sees exactly the same qualification:

```systemverilog
assign id_rs1_data = (wb_w_en && wb_rd_addr != 5'd0 && wb_rd_addr == rs1_addr)
                     ? wb_rd_data : rf_rs1_data;
```

---

## 3. Exceptions

### 3.1 Representation

```systemverilog
// rtl/include/single_pkg.sv
typedef enum logic [3:0] {
  EXC_INSTR_ADDR_MISALIGNED = 4'd0,  EXC_ILLEGAL_INSTR        = 4'd2,
  EXC_BREAKPOINT            = 4'd3,  EXC_LOAD_ADDR_MISALIGNED = 4'd4,
  EXC_LOAD_ACCESS_FAULT     = 4'd5,  EXC_STORE_ADDR_MISALIGNED = 4'd6,
  EXC_STORE_ACCESS_FAULT    = 4'd7,  EXC_ECALL_MMODE          = 4'd11
} exc_cause_e;                              // value == mcause code

typedef struct packed { logic valid; exc_cause_e cause; } exception_t;  // 5 bit
```

The width is deliberately 4 bits — the encoding is the `mcause` value, not a
32-bit extended field. Zero-extension to 32 bits is a CSR-milestone concern.

### 3.2 Producers

| Cause | Produced where | Trigger |
|---|---|---|
| `EXC_ILLEGAL_INSTR` | ID (`control_unit.decode_exc`) | `illegal_main \| illegal_alu` |
| `EXC_BREAKPOINT` | ID | `ebreak` (`0x00100073`) |
| `EXC_ECALL_MMODE` | ID | `ecall` (`0x00000073`) |
| `EXC_LOAD_ADDR_MISALIGNED` / `EXC_STORE_ADDR_MISALIGNED` | MEM | `mem_fault` from the LSU's `misaligned` output |

Priority inside `control_unit`: `illegal > ebreak > ecall`.

### 3.3 Flow

```text
control_unit.decode_exc
        |  priority: illegal > ebreak > ecall
        v
ID      idex_d.exc      = decode_exc
        reg_write       &= (rd != x0) && !decode_exc.valid
        |
        v
EX      exc passes through unchanged
        ex_normal_valid = valid && !exc.valid     -> gates redirect only
        |
        v
MEM     mem_exc <= exact exception:
          mem_exc = exmem_q.exc                    (upstream wins)
          if (mem_fault) { valid = 1; cause = load/store misaligned }
        reg_write &= !mem_exc.valid
        mem_go requires !exc.valid
        |
        v
WB      wb_trap = wb_retire && memwb_q.exc.valid
        -> flush every younger instruction, pc_stall, sticky halted
```

### 3.4 Rules

1. **An excepting instruction keeps `valid = 1`.** It travels to WB as a
   poisoned token carrying its PC and cause; it is never turned into a bubble.
   This is what makes the trap precise.
2. **Upstream wins.** A stage only writes an exception when the payload has
   none (`if (mem_fault)` after `mem_exc = exmem_q.exc`).
3. **Every normal side effect is ANDed with `!exc.valid`**: redirect in EX
   (`ex_normal_valid`), the data-memory request in MEM (`mem_go`), the
   register-file write in WB, and the forwarding qualification (the
   `reg_write` bits are gated at the ID source and again in MEM so the
   forwarding unit only ever sees a writer that will really write).
4. **Trap is committed in WB.** Program order is guaranteed by the pipeline
   itself; no cross-stage arbitration is needed, and misaligned data accesses
   are only known in MEM anyway.
5. **`mtval` is not carried in the pipeline.** When CSRs arrive, it is derived
   at WB from `memwb_q.instr` / `memwb_q.alu_result` / `memwb_q.pc`.
6. **No CSR exists yet**: trap = flush everything younger + permanent halt
   (`halted`). Replacing the halt with a redirect to `mtvec` later does not
   change the structure.

---

## 4. Commit Semantics

```systemverilog
// rtl/pipeline/wb_stage.sv
assign wb_retire  = memwb_q.valid && !mem_stall;              // the only retire qualification
assign wb_trap    = wb_retire && memwb_q.exc.valid;
assign wb_w_en    = wb_retire && !memwb_q.exc.valid
                    && memwb_q.ctrl_wb.reg_write && (memwb_q.rd_addr != 5'b0);
assign trap_valid = wb_trap;
assign trap_pc    = memwb_q.pc;
assign trap_cause = memwb_q.exc.cause;

// rtl/pipeline/core_5stage.sv
assign wb_exc_pending = memwb_q.valid && memwb_q.exc.valid;
always_ff @(posedge clk)
  if (rst)            halted <= 1'b0;
  else if (trap_valid) halted <= 1'b1;
```

- During a memory freeze `memwb_q.valid` stays 1 for several cycles, so `valid`
  alone is **not** a commit condition — `!mem_stall` is mandatory.
- `wb_w_en` drives both the register file and the WB→ID bypass, so both see the
  final decision.
- `trap_valid` is a one-cycle pulse; `halted` is sticky and is the signal to
  route to an FPGA LED.
- `trap_cause`/`trap_pc` are only meaningful on the `trap_valid` cycle.

---

## 5. Memory Interface (Request / Response)

The data memory is no longer a combinational `addr -> data` path. The core
exposes a two-channel transaction interface, and the same protocol is intended
for the on-board BRAM, a later SRAM/cache, and eventually a bus.

### 5.1 Protocol rules

| # | Rule |
|---|---|
| 1 | Request handshake is `valid && ready`. While `req_valid && !req_ready`, the request contents stay unchanged. `req_valid` never depends on `req_ready` |
| 2 | Each accepted request produces **exactly one** response. Stores also get a response (an ack; `rdata` is ignored) |
| 3 | A response arrives **at least one cycle after** acceptance, never in the same cycle. A 1-cycle BRAM satisfies this |
| 4 | At most **one request outstanding** (single outstanding) |
| 5 | The core drives `dmem_rsp_ready = 1'b1` permanently |
| 6 | `addr` is a byte address; the slave indexes with `addr[AW+1:2]`. `wstrb` selects byte lanes; `wdata` is already lane-replicated by the LSU |

Rule 1's "request contents stay stable" is not extra logic — it follows from
the global freeze: while a request is outstanding the whole pipeline is frozen,
so `exmem_q` (the source of `addr`/`write`/`wdata`/`wstrb`) cannot change.

### 5.2 MEM stage equations

```systemverilog
assign mem_op     = exmem_q.ctrl_m.mem_read || exmem_q.ctrl_m.mem_write;
assign mem_active = exmem_q.valid && !exmem_q.exc.valid && mem_op;
assign mem_fault  = mem_active && mem_misaligned;
assign mem_go     = mem_active && !mem_misaligned && !wb_exc_pending;

assign dmem_req_valid = mem_go && !req_sent;
assign dmem_req_addr  = exmem_q.alu_result;
assign dmem_req_write = mem_go && exmem_q.ctrl_m.mem_write;
assign dmem_req_wdata = dmem_req_write ? lsu_wdata : 32'b0;
assign dmem_req_wstrb = dmem_req_write ? lsu_wstrb : 4'b0000;
assign dmem_rsp_ready = 1'b1;

assign req_fire  = dmem_req_valid && dmem_req_ready;
assign rsp_fire  = dmem_rsp_valid && dmem_rsp_ready;
assign mem_done  = req_sent && rsp_fire;
assign mem_stall = mem_go && !mem_done;

always_ff @(posedge clk)
  if (rst)           req_sent <= 1'b0;
  else if (req_fire) req_sent <= 1'b1;
  else if (mem_done) req_sent <= 1'b0;
```

Two signals deserve their own line:

| Signal | Why it exists |
|---|---|
| `req_sent` | Retracts `req_valid` after the handshake. Without it the stalled pipeline would re-send the same request every cycle and get duplicate responses |
| `!wb_exc_pending` | Precise-exception hole: if an older instruction sitting in WB is going to trap, MEM must not start a new transaction. Without this, a `sw` immediately after an `ebreak` really writes memory before the `ebreak` commits |

`wb_exc_pending` is computed in `core_5stage` (it is a function of `memwb_q`,
which lives in `pipeline_regs`) and folded into `mem_go`; the mem_stage
boundary stays `exmem_q -> transaction -> memwb_d`.

### 5.3 Lifecycle of one load/store against a 1-cycle memory

| Cycle | MEM state | `mem_stall` | Whole pipeline |
|---|---|---|---|
| E1 | `req_valid=1`, handshake accepted, `req_sent <- 1` | 1 | Frozen: all four `*_en = 0`, WB does not retire |
| E2 | `rsp_valid=1`, `mem_done=1`, `req_sent <- 0` | 0 | All stages advance; the instruction moves into MEM/WB |

Cost: every load/store occupies MEM for 2 cycles. This is deliberate —
correctness first, throughput later.

### 5.4 FPGA-oriented memory plan

| Item | Decision |
|---|---|
| Data memory | `rtl/pipeline/memory/dmem_bram.sv`, parameterised `DEPTH` (words), `req_ready = 1'b1`, byte-write via `req_wstrb`, registered read data, `rsp_valid <= fire` (exactly one response per request). Simulation and the board use the **same file**, so behaviour cannot drift |
| BRAM initialisation | Storage array is `always @(posedge clk)` with an `initial` zero-fill loop. `always_ff` plus `initial` on the same array triggers a VCS `Error-[ICPD]` multi-driver error |
| Instruction memory | IF reads the instruction combinationally (`imem_rdata` in the same cycle as `imem_addr`), so on FPGA it must be an **asynchronous-read memory in LUTs** (distributed ROM/RAM), not BRAM. Putting imem on BRAM requires changing the IF fetch timing and is a separate milestone |
| `halted` | Sticky, intended for an LED (the trap pulse is one cycle wide and invisible to the eye) |

Checked in Vivado in v0.6.0 (`xc7a100tcsg324-1`): `dmem_bram` with 256 words
infers one RAMB18E1, and the 256-word instruction ROM (`rtl/fpga/rtl/imem_rom.sv`)
is folded into logic LUTs (`LUT as Memory` = 0). See
[12_v0_6_0_milestone.md](12_v0_6_0_milestone.md).

---

## 6. Top-Level Interface (`core_5stage`)

| Group | Port | Dir | Contract |
|---|---|---|---|
| Clock/reset | `clk`, `rst` | in | Synchronous, active-high reset |
| Fetch | `imem_addr[31:0]` | out | `= pc`, byte address |
| | `imem_rdata[31:0]` | in | Same-cycle combinational read (ROM in LUTs on FPGA) |
| Request | `dmem_req_valid` | out | Does not depend on `req_ready` |
| | `dmem_req_ready` | in | `valid && ready` = handshake |
| | `dmem_req_write` | out | 0 = load, 1 = store (gated with `mem_go`) |
| | `dmem_req_addr[31:0]` | out | Byte address |
| | `dmem_req_wdata[31:0]`, `dmem_req_wstrb[3:0]` | out | Zero for loads |
| Response | `dmem_rsp_valid` | in | Exactly one per accepted request |
| | `dmem_rsp_ready` | out | Constant 1 |
| | `dmem_rsp_rdata[31:0]` | in | Meaningful for loads only |
| Trap | `trap_valid` | out | One-cycle pulse |
| | `trap_cause` (`exc_cause_e`, 4 bit) | out | Valid only while `trap_valid = 1` |
| | `trap_pc[31:0]` | out | Same |
| | `halted` | out | Sticky, stays 1 after a trap |

`trap_cause` reads 0 (`EXC_INSTR_ADDR_MISALIGNED`) while idle — it must always be
sampled together with `trap_valid`.

---

## 7. Invariants worth an assertion

1. **Single commit point**: each instruction has `wb_retire = 1` for exactly one
   cycle.
2. **Freeze consistency**: `mem_stall = 1` implies all four `*_en = 0` and no
   flush, plus `pc_stall = 1`.
3. **Request stability**: while `req_valid && !req_ready`, `addr`/`write`/
   `wdata`/`wstrb` are unchanged (derived from the freeze).
4. **Single outstanding**: `req_sent = 1` implies `req_valid = 0`.
5. **Exception vs in-flight transaction**: `!(wb_exc_pending && req_sent)` — if
   broken, `req_sent` sticks at 1 and every memory access deadlocks.
6. **Trap commits in the trap cycle**: `wb_exc_pending` forces `mem_go = 0`, so
   `mem_stall = 0` and `wb_trap = wb_exc_pending` cannot be delayed by MEM.
7. **Acyclic combinational paths**: every request-inhibiting condition depends
   only on registers (`wb_exc_pending`), never on `wb_trap`.
8. **No side effects after halt**: `halted = 1` flushes all four stages, so
   `req_valid = 0` and `wb_w_en = 0`.

---

## 8. Deliberate Non-Goals (current state)

| Item | Status |
|---|---|
| `EXC_INSTR_ADDR_MISALIGNED` | Declared but no producer; a jump target with `[1:0] != 0` is not checked (planned in EX) |
| `EXC_LOAD/STORE_ACCESS_FAULT` | Declared but no producer; needs an `rsp_err` channel |
| CSRs (`mtvec`/`mepc`/`mcause`/`mtval`), interrupts | Out of scope; a trap means permanent halt |
| Instruction memory on BRAM | Needs a new IF fetch timing; separate milestone |
| Legacy `control_unit` ports (`illegal_instr`, `sys_ecall`, `sys_ebreak`) | Kept for the frozen single-cycle core; to be cleaned up after the pipeline is verified |
| Performance | Same-cycle responses, multiple outstanding requests, non-blocking accesses are all intentionally not implemented |

---

## 9. Status Evidence

v0.5.0 release evidence (2026-09-28):

```text
make pl-lint
  -> 0 errors; warnings UNUSEDSIGNAL x4, EOFNEWLINE x4, PINMISSING x3
     (legacy control_unit ports), IMPORTSTAR x3, UNUSEDPARAM x1

make pl-run ARGS="+NUM_SEEDS=500 +SEED_OFFSET=1"
  -> SUMMARY: 500 passed, 0 failed
     ASSERTION FAILURES: 0
     PIPELINE SVA FAILURES: 0
     ALL RANDOM TESTS PASSED
```

The regression compares every retired instruction against the ISS; see
[11_v0_5_0_milestone.md](11_v0_5_0_milestone.md) for the assertions, the
coverage results and waivers, the mutation check, and the known limitations
(combinational instruction fetch; no memory back-pressure; only the terminating
`ebreak` trap exercised). Synthesis and board results are in
[12_v0_6_0_milestone.md](12_v0_6_0_milestone.md).
