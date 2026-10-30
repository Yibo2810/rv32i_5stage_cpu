# Core Architecture

`core_5stage` is an in-order RV32I pipeline with five stages, full forwarding
and request/response ports for instruction and data memory. RTL lives in
`rtl/pipeline/`, shared types in `rtl/include/{core_pkg,pipeline_pkg}.sv`.

## ISA

The 37 RV32I instructions below are implemented and verified. `ecall` and
`ebreak` are decoded and trap; `fence`, CSRs and interrupts are not
implemented.

```text
add sub and or xor slt sltu sll srl sra
addi slti sltiu xori ori andi slli srli srai
lb lh lw lbu lhu sb sh sw
beq bne blt bge bltu bgeu
jal jalr lui auipc
```

## Stages

```text
        +------+    +------+    +------+    +------+    +------+
imem <->|  IF  |--->|  ID  |--->|  EX  |--->| MEM  |--->|  WB  |--> regfile
        +------+    +------+    +------+    +------+    +------+
           ^                       |           ^            |
           +----- redirect --------+      dmem req/rsp      +--> trap / halted
```

| Stage | File | Work |
|---|---|---|
| IF | `if_stage.sv` | PC, fetch request/response, one-entry fetch buffer |
| ID | `id_stage.sv` | Decode (`control_unit`), register read, immediate, decode exceptions, WB→ID bypass |
| EX | `ex_stage.sv` | Forwarding mux, ALU, branch/jump resolution |
| MEM | `mem_stage.sv` | Data request/response, load/store lanes, misalignment |
| WB | `wb_stage.sv` | Single commit point: register write or trap |

Control: `hazard_unit.sv` (stall/flush priority), `forwarding_unit.sv`,
`pipeline_regs.sv` (four registers, each with `en` and `flush`; flush wins).
Leaf units in `rtl/pipeline/units/`: `pc`, `alu`, `regfile`, `imm_gen`,
`control_unit`, `load_store_unit`.

All state sits in the four pipeline registers, the PC, the fetch state and
the register file. ID and EX are combinational.

## Hazards

| Hazard | Handling | Cost |
|---|---|---|
| RAW, 1 instruction apart | Forward from EX/MEM | 0 |
| RAW, 2 instructions apart | Forward from MEM/WB | 0 |
| RAW, 3 apart (WB writes while ID reads) | WB→ID bypass in `id_stage` | 0 |
| Load followed by a user | Hold IF/ID, insert one bubble into ID/EX | 1 cycle |
| Taken branch, `jal`, `jalr` | Resolved in EX; flush IF/ID and ID/EX | 2 cycles |
| Data memory busy | Freeze all four stages until the response | 1 cycle per load/store with a 1-cycle RAM |
| Trap | Flush every stage; `halted` stays set | — |

Priority in `hazard_unit`: trap/halt > memory freeze > redirect > load-use.
The memory freeze must outrank redirect and load-use: both flush ID/EX, and a
flush during a freeze would drop the instruction frozen in EX.

Forwarding rules: never from `x0`; never a load's EX/MEM value (that is its
address, the load-use bubble covers it); EX/MEM wins over MEM/WB. The
`reg_write` bits the forwarding unit sees are already cleared for
instructions that carry an exception.

Why freeze the whole pipeline on a memory stall instead of letting the stages
below MEM drain: an instruction frozen in EX may still need a value that is
about to leave WB. Freezing everything keeps every bypass source in place.

## Memory interfaces

Both ports use the same handshake: a request is accepted on
`req_valid && req_ready`, each accepted request gets exactly one response, at
least one cycle later, and only one request is outstanding.

**Data port.** `dmem_rsp_ready` is always 1. The request stays stable while it
waits, because the pipeline is frozen. A `req_sent` flag keeps a stalled MEM
stage from sending the same request twice. MEM does not start a request while
an older instruction in WB is about to trap, so a store right behind an
`ebreak` never reaches memory.

**Instruction port.** IF keeps one request in flight and a one-entry fetch
buffer.

- A redirect marks an accepted-but-unanswered fetch as `killed`; its response
  is taken and dropped.
- A request that has not been accepted yet switches its address to the
  redirect target, which saves the cycle the buffer costs.
- IF holds `imem_rsp_ready = 0` when the buffer is full and not draining; the
  memory must then hold its response.
- The PC advances only when a request is accepted.

The address of a waiting fetch request may change, which an AXI slave does not
allow. A bus adapter has to register the request first.

## Exceptions

An exception is a token (`exception_t`: valid bit + 4-bit `mcause` code) that
travels with the instruction. The instruction stays valid, so the trap is
precise.

| Cause | Raised in |
|---|---|
| Illegal instruction | ID |
| `ebreak` (breakpoint), `ecall` | ID |
| Load / store address misaligned | MEM |

The older exception wins. Every side effect (redirect, memory request,
register write, forwarding) is gated by "no exception". The trap commits in
WB: `trap_valid` pulses with `trap_cause` and `trap_pc`, all younger
instructions are flushed, and `halted` stays set until reset. There are no
CSRs: a trap ends the program.

## Top-level ports (`core_5stage`)

| Group | Ports |
|---|---|
| Clock, reset | `clk`, `rst` (synchronous, active high); parameter `RESET_PC` |
| Fetch | `imem_req_{valid,ready,addr}`, `imem_rsp_{valid,ready,rdata}` |
| Data | `dmem_req_{valid,ready,write,addr,wdata,wstrb}`, `dmem_rsp_{valid,ready,rdata}` |
| Trap | `trap_valid` (1-cycle pulse), `trap_cause`, `trap_pc`, `halted` (sticky) |

## Limitations

- No branch prediction: every taken branch or jump costs 2 cycles.
- Single outstanding memory access on both ports; no cache.
- Misaligned jump targets and access faults have cause codes but no producer.
- No CSRs or interrupts; a trap halts the core.
- The address of a waiting fetch request can change (not AXI-compatible).
