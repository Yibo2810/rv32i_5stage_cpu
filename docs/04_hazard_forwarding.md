# Hazard Control and Forwarding

Status: **implemented in RTL, directed bring-up only — not verified.**
Last updated: 2026-09-14.

This document describes how the five-stage pipeline keeps instruction ordering:
the two forwarding paths, the load-use stall, the redirect flush, the memory
stall freeze, and the priority order that arbitrates them.

Design and interface context: [03_pipeline_design.md](03_pipeline_design.md).
Current verification state: [11_v0_5_0_pipeline_bringup.md](11_v0_5_0_pipeline_bringup.md).

---

## 1. Hazard Classes

| Class | Producer | Consumer | Mechanism |
|---|---|---|---|
| RAW, 1 instruction apart | EX/MEM (`alu_result`, `pc_plus_4`) | EX operands | Forwarding, `FWD_EXMEM` |
| RAW, 2 instructions apart | MEM/WB (`wb_rd_data`) | EX operands | Forwarding, `FWD_MEMWB` |
| RAW, WB and ID in the same cycle | WB write port | ID register read | WB→ID bypass in `id_stage` |
| Load-use (data is not ready in EX/MEM) | MEM/WB (after the load's transaction) | EX operands | 1-cycle stall: `pc_stall`, `ifid_en = 0`, `idex_flush = 1` |
| Control (branch/jump) | EX redirect decision | IF/ID | Flush IF/ID and ID/EX, redirect the PC |
| Structural (data memory busy) | MEM transaction | whole pipeline | Global freeze: all four `*_en = 0`, `pc_stall = 1` |
| Trap / halt | WB commit point | all younger instructions | `wb_trap \| halted` flushes all four stages |

---

## 2. Forwarding

### 2.1 Sources

| Source | Value | File |
|---|---|---|
| `FWD_EXMEM` | `exmem_fwd_data` from the EX/MEM register | mux in `core_5stage`, selected from `exmem_q.ctrl_m.wb_sel` |
| `FWD_MEMWB` | `memwb_fwd_data = wb_rd_data` from the WB mux | `wb_stage` already resolved `WB_ALU` / `WB_MEM` / `WB_PC4` |
| none | `idex_q.rs1_data` / `idex_q.rs2_data` | `id_stage` (register file or WB→ID bypass) |

`core_5stage` resolves the EX/MEM forwarding value:

```systemverilog
always_comb begin
  case (exmem_q.ctrl_m.wb_sel)
    WB_ALU: exmem_fwd_data = exmem_q.alu_result;
    WB_PC4: exmem_fwd_data = exmem_q.pc_plus_4;   // jal / jalr link value
    default: exmem_fwd_data = 32'b0;              // WB_MEM: not forwardable from EX/MEM
  endcase
end
```

`WB_MEM` (a load) deliberately contributes nothing here: in EX/MEM the load's
data does not exist yet — `alu_result` holds its *address*. A dependent
instruction in EX with the load in EX/MEM is therefore stalled instead (§3), and
picks the value up from MEM/WB one cycle later. `WB_PC4` has to be selectable
here because `jal`/`jalr` link values are produced in EX and consumed by the
next instruction before they ever reach WB.

### 2.2 Selection rules (`forwarding_unit.sv`)

```systemverilog
if (idex_valid) begin
  if (exmem_reg_write && exmem_rd_addr != 5'd0 && exmem_rd_addr == idex_rs1_addr
      && !exmem_reg_read)
      fwd_a_sel = FWD_EXMEM;
  else if (memwb_reg_write && memwb_rd_addr != 5'd0 && memwb_rd_addr == idex_rs1_addr)
      fwd_a_sel = FWD_MEMWB;
  // identical logic for rs2 / fwd_b_sel
end
```

Three guards, each for a specific reason:

| Guard | Reason |
|---|---|
| `exmem_rd_addr != 5'd0` | `x0` is never a real producer |
| `!exmem_reg_read` | **Load guard.** If EX/MEM holds a load, its `exmem_fwd_data` is the *address*, not the data — forwarding it would silently corrupt the dependent instruction. This is why the load-use stall exists at all |
| EX/MEM checked before MEM/WB | The younger value must win when both match the same register |

### 2.3 WB→ID bypass

The register file has a single synchronous write port and cannot be read in the
same cycle it is written, while the WB instruction is *older* than the ID
instruction:

```systemverilog
assign id_rs1_data = (wb_w_en && wb_rd_addr != 5'd0 && wb_rd_addr == rs1_addr)
                     ? wb_rd_data : rf_rs1_data;
```

`wb_w_en` is the same signal that strobes the register file, so the bypass sees
"a write that will really happen" — including the `rd != x0`, `reg_write`, and
`!exc.valid` qualifications.

### 2.4 Forwarding and exceptions

The forwarding unit qualifies on the `reg_write` *bits* carried in the control
sub-structs. Those bits are already gated for exceptions:

- in `id_stage`: `ctrl_final.reg_write = ctrl.reg_write && (rd_addr != 0) && !decode_exc.valid`;
- in `mem_stage`: `memwb_d.ctrl_wb.reg_write = exmem_q.ctrl_m.reg_write && !mem_exc.valid`.

So the forwarding unit can never select a source that will not actually write.

---

## 3. Load-Use Stall

### 3.1 Detection

```systemverilog
load_use_hazard = ifid_valid && idex_valid && idex_mem_read && idex_reg_write &&
                  (( id_uses_rs1 && (id_rs1_addr == idex_rd_addr)) ||
                   ( id_uses_rs2 && (id_rs2_addr == idex_rd_addr)));
```

`id_uses_rs1` / `id_uses_rs2` come from the decoder (`ctrl_uses_rs1/rs2`) and
are opcode-class properties: R-type and branch/store use both, I-type /
load / `jalr` use `rs1` only, `lui` / `auipc` / `jal` use neither. Without them
the pipeline would stall on `rs1`/`rs2` *fields* of instructions that never read
those registers (e.g. `lui`).

### 3.2 Action

| Signal | Value | Effect |
|---|---|---|
| `pc_stall` | 1 | PC holds; IF re-fetches nothing new |
| `ifid_en` | 0 | IF/ID keeps the dependent instruction |
| `idex_flush` | 1 | ID/EX is cleared, so the bubble enters EX behind the load |
| `exmem_en`/`memwb_en` | 1 | Older stages keep moving |

One stall cycle is always enough: after it, the load is in MEM/WB where
`wb_rd_data` (the loaded value) is the forward source, and `FWD_MEMWB` is
available to the dependent instruction in EX.

The stall is **not** applied when MEM is busy — see the priority rules in §5.

---

## 4. Control Hazard (Redirect)

### 4.1 Resolution in EX

```systemverilog
assign ex_normal_valid   = idex_q.valid && !idex_q.exc.valid;
assign branch_taken      = idex_q.ctrl.branch && (alu_zero == idex_q.ctrl.branch_on_zero);
assign ex_redirect_taken = ex_normal_valid && (branch_taken || idex_q.ctrl.jump_and_link);
assign ex_redirect_pc    = (idex_q.ctrl.pc_target_sel == PC_TARGET_ALU)
                           ? {alu_result[31:1], 1'b0}          // jalr: bit 0 cleared
                           : (idex_q.pc + idex_q.imm);         // branch / jal
assign ex_pc_next        = ex_redirect_taken ? ex_redirect_pc : idex_q.pc_plus_4;
```

Points worth noting:

- `ex_normal_valid` gates the redirect on `!exc.valid`, so an instruction that
  is already poisoned cannot redirect the PC.
- `jalr` takes its target from the ALU result with bit 0 forced to zero (RV32I
  clears `target[0]`); branches and `jal` use the PC+immediate adder result.
- All six branch conditions reuse the ALU: `BEQ`/`BNE` compare via the `zero`
  flag (`branch_on_zero`), the ordered comparisons come from `SLT`/`SLTU`.
- The computed `ex_pc_next` is carried in EX/MEM as `next_pc` so a
  commit/retire monitor can reconstruct the dynamic instruction stream.

### 4.2 Flush

```systemverilog
end else if (ex_redirect_taken) begin
  ifid_flush = 1'b1;
  idex_flush = 1'b1;
end
```

Exactly two instructions are wrong at that point (IF and ID), so exactly two
registers are flushed: IF/ID and ID/EX. EX/MEM and MEM/WB hold older, correct
instructions. The redirect costs 2 cycles.

The PC priority is fixed in `if_stage`:

```systemverilog
assign pc_next = pc_stall ? pc_current : ex_redirect_taken ? ex_redirect_pc : pc_plus_4;
```

`pc_stall` (freeze/trap) outranks the redirect, so a pending memory transaction
or a trap can never be overtaken by a redirect.

---

## 5. Memory Stall = Global Freeze

While a data-memory request is outstanding, MEM cannot accept a new instruction,
so the **whole** pipeline stops:

```systemverilog
end else if (mem_stall) begin
  pc_stall = 1'b1;
  ifid_en  = 1'b0;
  idex_en  = 1'b0;
  exmem_en = 1'b0;
  memwb_en = 1'b0;
end
```

No flush is issued: every in-flight instruction is still valid and will
eventually retire. Commit eligibility is filtered in WB instead — the single
retire rule

```systemverilog
wb_retire = memwb_q.valid && !mem_stall;
```

### Why not "bubble the downstream stages"?

An earlier design let MEM/WB keep advancing during a memory stall (bubble the
pipeline below the stall point). It is wrong, and it was rejected on simulation
evidence:

```text
I0 in WB, load I1 in MEM waiting for its response, I2 in EX and dependent on I0
-> if MEM/WB keeps advancing, I0's data leaves the pipeline after one cycle
-> I2 is still frozen in EX (its idex_q.rs1_data is a stale value from ID)
-> forwarding finds no source -> ALU uses the stale operand -> wrong result
```

The bubble version failed 6 comparisons on a 5-program smoke test (the first
failure is the `lw` right after the first `sw`: the address was computed as
`x3 = 0` instead of `5`); the global-freeze version passed all of them.

The general rule: **if a frozen instruction may still depend on a bypass
source, that source must not disappear before the frozen instruction resumes.**
Freezing all four stages upholds it by construction.

### Request stability falls out of the freeze

`dmem_req_valid && !dmem_req_ready` is a stalled MEM, and therefore a frozen
pipeline: `exmem_q` cannot change, so `addr` / `write` / `wdata` / `wstrb` hold
their values without any dedicated handshake logic. See
[03_pipeline_design.md §5](03_pipeline_design.md#5-memory-interface-request--response).

---

## 6. Priority (`hazard_unit.sv`)

```systemverilog
always_comb begin
  pc_stall = 1'b0;
  ifid_en  = 1'b1;  ifid_flush  = 1'b0;
  idex_en  = 1'b1;  idex_flush  = 1'b0;
  exmem_en = 1'b1;  exmem_flush = 1'b0;
  memwb_en = 1'b1;  memwb_flush = 1'b0;

  if (wb_trap || halted) begin          // 1. trap: kill everything younger, freeze the PC
    pc_stall = 1'b1;
    ifid_flush = idex_flush = exmem_flush = memwb_flush = 1'b1;
  end else if (mem_stall) begin         // 2. memory freeze: nothing moves, nothing is killed
    pc_stall = 1'b1;
    ifid_en = idex_en = exmem_en = memwb_en = 1'b0;
  end else if (ex_redirect_taken) begin // 3. branch/jump: kill IF and ID
    ifid_flush = 1'b1;  idex_flush = 1'b1;
  end else if (load_use_hazard) begin   // 4. load-use: one bubble
    pc_stall = 1'b1;  ifid_en = 1'b0;  idex_flush = 1'b1;
  end
end
```

| Priority | Event | Scope |
|---|---|---|
| 1 (`wb_trap \| halted`) | Precise trap / halt | Flush all four stages, freeze PC |
| 2 (`mem_stall`) | Single-outstanding memory transaction in flight | Freeze all four stages, no flush |
| 3 (`ex_redirect_taken`) | Branch taken / jump | Flush IF/ID and ID/EX |
| 4 (`load_use_hazard`) | Load immediately followed by a user | 1-cycle stall + ID/EX flush |

Every output is assigned a default before the priority chain, because a signal
left unassigned in a clocked consumer's `if` reads as X and silently stops the
pipeline from updating.

`mem_stall` **must** outrank both the redirect and the load-use branches: those
two branches assert `idex_flush`, and flushing ID/EX during a memory freeze
would discard the instruction frozen in EX — an instruction would simply
disappear. (The load-use detector stays active during a freeze only in the
sense that it is evaluated; branch 2 wins.)

---

## 7. Invariants

1. During `mem_stall`, no flush is asserted and all four enables are 0.
2. A redirect never flushes EX/MEM or MEM/WB.
3. A trap (`wb_trap`) or `halted` flushes all four stages in the same cycle it
   is observed; the trap instruction itself was already committed in WB.
4. `load_use_hazard` implies `idex_mem_read && idex_reg_write` and a real
   register match on a register the ID instruction actually reads.
5. Forwarding never selects `x0` and never selects an EX/MEM load.
6. `pc_stall` wins over `ex_redirect_taken` in `if_stage`.

---

## 8. Not Handled (current state)

| Item | Consequence |
|---|---|
| No branch prediction / no ID-stage resolution | Every taken branch and every jump costs 2 cycles |
| No branch history / BTB / return-address stack | Out of scope for this stage |
| No multi-outstanding or non-blocking memory | A memory transaction freezes the entire pipeline (2 cycles per load/store against a 1-cycle BRAM) |
| Trap = permanent halt | No `mtvec` redirect, no `mepc`/`mcause`; halting is forever by design |
| No store-buffer | Store ordering is trivially program order because of the freeze |
| `EXC_INSTR_ADDR_MISALIGNED` not produced | A misaligned jump target is not caught in EX yet |

---

## 9. Status Evidence

Tool state (2026-09-14): Verilator 5.048 `--lint-only -Wall` reports 0 errors on
`tb/filelists/pipeline_rtl.f`; VCS W-2024.09-SP1 compiles and elaborates
`pipeline_tb`.

Functional evidence is limited to the six directed programs in the bring-up
testbench; see [11_v0_5_0_pipeline_bringup.md](11_v0_5_0_pipeline_bringup.md)
for the run tables, the transaction/signature cross-check, and the cycle
accounting. Measured from the committed instruction streams, those programs do
exercise every mechanism in this document at least once:

| Mechanism | Where it fires today |
|---|---|
| EX/MEM forwarding | every program (distance-1 ALU-result dependency; 10/12/24/7/6/5 times) |
| MEM/WB forwarding | `branch_matrix_test` (12), `load_store_width_test` (1), `x0_test` (1) |
| WB→ID bypass | `alu_rtype_test` (1), `load_store_width_test` (1) |
| `WB_PC4` forwarding | `jump_u_type_test`: one `jal` link value consumed by the next instruction |
| Load-use stall | `load_store_width_test` (5), `x0_test` (2) — and the cycle accounting closes with exactly those counts |
| Redirect flush | `branch_matrix_test` (12 taken redirects), `jump_u_type_test` (3) |
| Memory freeze | all 58 load/store transactions (2 cycles each in MEM) |

What is still **not** checked:

- deliberate deep RAW chains and every-corner hazard tests — `hazard_test.S` is
  still a stub (TODO comment, empty `.hex`, so the run halts on the preloaded
  `ebreak` image without executing anything);
- multiple outstanding/back-to-back memory transactions with `req_ready` de-asserted
  (the request-stability rule has no stimulus in the repository);
- trap during a memory freeze and other trap/flush/redirect interleavings;
- misaligned load/store, illegal instruction, and `ecall` trap paths;
- any random/stress stimulus, coverage, or assertion (see
  [05_verification_plan.md](05_verification_plan.md)).
