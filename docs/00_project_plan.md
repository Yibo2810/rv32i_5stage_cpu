# Project Plan

## Goals

- Build a credible RV32I CPU project that grows from a verified single-cycle
  core into a classic five-stage pipeline.
- Keep verification self-checking, reproducible, and documented.
- Use directed tests first, then add assertions, functional coverage, and
  constrained-random stimulus.
- Preserve the project as an engineering portfolio artifact with clear release
  milestones.

## Current Milestone

The project has reached **v0.3.0: verified single-cycle core**.

This milestone completes the single-cycle phase for the supported RV32I base
integer datapath. The primary verification flow is now a VCS-based
SystemVerilog harness under `tb/sv/core/`, using generated assembly programs,
generated expected files, a memory model, a monitor, a scoreboard, and an
assertion scaffold.

The release verifies:

```text
R-type ALU:    add/sub/and/or/xor/slt/sltu/sll/srl/sra
I-type ALU:    addi/slti/sltiu/xori/ori/andi/slli/srli/srai
Load/store:    lb/lh/lw/lbu/lhu/sb/sh/sw
Branch:        beq/bne/blt/bge/bltu/bgeu
Jump/U-type:   jal/jalr/lui/auipc
Special rule:  x0 write protection and read-zero behavior
```

System/trap instructions are deferred because the project does not yet define a
trap, CSR, or privileged execution model.

## Milestones

| Phase | Milestone | Status |
|---|---|---|
| 0 | Repository structure and documentation scaffold | Done |
| 1 | Minimal single-cycle RTL modules | Done |
| 2 | Basic assembly-to-hex and signature tests | Done |
| 3 | v0.1 minimal single-cycle smoke regression | Done |
| 4 | v0.2.0 SystemVerilog R/I direct module-path verification | Done |
| 5 | Expanded single-cycle datapath for branches, jumps, U-type, and load/store widths | Done |
| 6 | v0.3.0 VCS core-level directed verification architecture | Done |
| 7 | Assertions and lightweight functional coverage | Next |
| 8 | Constrained-random program generation with reference expected files | Next |
| 9 | Five-stage pipeline partitioning | Planned |
| 10 | Forwarding, hazard detection, load-use stalls, and branch flushes | Planned |
| 11 | Pipeline verification and coverage closure | Planned |

## Current Release Command

```sh
./scripts/asm_to_hex.sh
./tools/rv32i_ref.py --all
make run
```

Release evidence for v0.3.0:

```text
ALL CORE SV TESTS PASSED
```

## Immediate Next Work

1. Add lightweight functional coverage for the directed regression.
2. Strengthen assertions around PC alignment, memory byte enables, and active
   bus no-X rules.
3. Add a commit/retire monitor so branch and jump tests can report executed
   instruction paths directly.
4. Build a constrained-random program generator that emits assembly, hex, and
   expected files through the existing reference flow.
5. Start the five-stage pipeline from the verified single-cycle datapath.
