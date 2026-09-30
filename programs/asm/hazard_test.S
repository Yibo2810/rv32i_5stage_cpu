hazard_test:
  # ==========================================================================
  # Directed pipeline hazard / forwarding test.
  # Every "case" below is a producer immediately followed by a consumer, chosen
  # so that the pair lights up a specific point of pipeline_sva_bind.sv:
  #   load-use   -> count_lu / cg_lu (cp_cons x cp_opnd x cp_ld)
  #   ALU chain  -> cg_fwd  (cp_fa/cp_fb x cp_cons x cp_src_a)
  #   branch/jump-> cg_redir (cp_src x cp_kill x cp_opnd)
  # Signature words let rv32i_ref.py / the scoreboard cross-check the result,
  # so "the hazard was exercised" AND "the value is still right" are both
  # checkable. Do NOT insert nops between a producer and its consumer: the
  # adjacency IS the hazard.
  # ==========================================================================

  # ---- setup: distinct values so every width/sign case is observable ----
  lui  x1, 0x12345
  ori  x1, x1, 0x678        # x1 = 0x12345678
  sw   x1, 0(x0)            # dmem[0x00] = 0x12345678
  sw   x1, 16(x0)           # dmem[0x10] = 0x12345678
  lui  x2, 0x89ABD
  addi x2, x2, -0x211      # x2 = 0x89ABCDEF (imm12 >= 0x800 -> addi, not ori)
  sw   x2, 20(x0)           # dmem[0x14] = 0x89ABCDEF (negative byte/half)

  # x9 mirrors x1 so the A4 branch is not taken (control flow stays linear)
  addi x9, x1, 0

  # ---- A1: load-use, rs1, consumer = R-type ----
  lw   x3, 0(x0)
  add  x4, x3, x0
  sw   x4, 4(x0)
  expected: 0x00000004 = 0x12345678

  # ---- A2: load-use, rs1, consumer = I-type ALU ----
  lw   x5, 0(x0)
  addi x6, x5, 1
  sw   x6, 8(x0)
  expected: 0x00000008 = 0x12345679

  # ---- A3: load-use, rs2, consumer = store (store-data hazard) ----
  lw   x7, 0(x0)
  sw   x7, 24(x0)
  expected: 0x00000018 = 0x12345678

  # ---- A4: load-use, rs2, consumer = branch (not taken) ----
  lw   x8, 0(x0)
  bne  x9, x8, a4_skip      # x9 == x8 -> not taken, but x8 is the blocked rs2
  addi x10, x0, 1
a4_skip:

  # ---- A5: load-use, both operands ----
  lw   x11, 0(x0)
  add  x12, x11, x11
  sw   x12, 28(x0)
  expected: 0x0000001c = 0x2468acf0

  # ---- B1: EX/MEM -> EX forwarding on rs1 ----
  add  x13, x1, x1
  add  x14, x13, x0
  sw   x14, 32(x0)
  expected: 0x00000020 = 0x2468acf0

  # ---- B2: EX/MEM -> EX forwarding on rs2 ----
  add  x15, x1, x1
  add  x16, x0, x15
  sw   x16, 36(x0)
  expected: 0x00000024 = 0x2468acf0

  # ---- B3: MEM/WB -> EX forwarding (one bubble between) ----
  add  x17, x1, x1
  addi x31, x0, 0
  add  x18, x17, x0
  sw   x18, 40(x0)
  expected: 0x00000028 = 0x2468acf0

  # ---- B4: load result forwarded from MEM/WB (the tail of a load-use) ----
  lw   x19, 0(x0)
  addi x31, x0, 0
  add  x20, x19, x0
  sw   x20, 44(x0)
  expected: 0x0000002c = 0x12345678

  # ---- C: every load width as the hazard producer (cg_lu.cp_ld) ----
  lb   x21, 20(x0)
  add  x22, x21, x0
  sw   x22, 48(x0)
  expected: 0x00000030 = 0xffffffef

  lbu  x23, 20(x0)
  add  x24, x23, x0
  sw   x24, 52(x0)
  expected: 0x00000034 = 0x000000ef

  lh   x25, 20(x0)
  add  x26, x25, x0
  sw   x26, 56(x0)
  expected: 0x00000038 = 0xffffcdef

  lhu  x27, 20(x0)
  add  x28, x27, x0
  sw   x28, 60(x0)
  expected: 0x0000003c = 0x0000cdef

  # ---- D: redirects, one per source kind, killing instruction classes ----
  # D1: taken branch, kills a load and an I-type ALU op
  beq  x0, x0, d1
  lw   x31, 0(x0)
  addi x31, x31, 1
d1:

  # D2: taken branch, kills a store
  beq  x0, x0, d2
  sw   x31, 64(x0)
d2:

  # D3: jal, kills a branch
  jal  x31, d3
  beq  x0, x0, d3
d3:

  # D4: jalr, kills a load
  auipc x31, 0
  addi x31, x31, 16
  jalr x31, 0(x31)
  lw   x31, 0(x0)
d4:

  # ---- E: redirect while the memory interface is busy (cg_redir.cp_def.defer)
  # A load starts the dmem handshake; the branch resolves while that
  # transaction is still in flight, so the redirect has to be deferred.
  lw   x29, 0(x0)
  beq  x0, x0, e1
  lw   x31, 0(x0)
e1:

  lw   x30, 20(x0)
  beq  x30, x30, e2
  sw   x31, 68(x0)
e2:

  # --- TOHOST ---
  li x3, 1
  lw x5, 0x00(x0)
  li x6, 0x12345678
  bne x5, x6, fail

  li x3, 2
  lw x5, 0x04(x0)
  li x6, 0x12345678
  bne x5, x6, fail

  li x3, 3
  lw x5, 0x08(x0)
  li x6, 0x12345679
  bne x5, x6, fail

  li x3, 4
  lw x5, 0x10(x0)
  li x6, 0x12345678
  bne x5, x6, fail

  li x3, 5
  lw x5, 0x14(x0)
  li x6, 0x89abcdef
  bne x5, x6, fail

  li x3, 6
  lw x5, 0x18(x0)
  li x6, 0x12345678
  bne x5, x6, fail

  li x3, 7
  lw x5, 0x1C(x0)
  li x6, 0x2468acf0
  bne x5, x6, fail

  li x3, 8
  lw x5, 0x20(x0)
  li x6, 0x2468acf0
  bne x5, x6, fail

  li x3, 9
  lw x5, 0x24(x0)
  li x6, 0x2468acf0
  bne x5, x6, fail

  li x3, 10
  lw x5, 0x28(x0)
  li x6, 0x2468acf0
  bne x5, x6, fail

  li x3, 11
  lw x5, 0x2C(x0)
  li x6, 0x12345678
  bne x5, x6, fail

  li x3, 12
  lw x5, 0x30(x0)
  li x6, 0xffffffef
  bne x5, x6, fail

  li x3, 13
  lw x5, 0x34(x0)
  li x6, 0x000000ef
  bne x5, x6, fail

  li x3, 14
  lw x5, 0x38(x0)
  li x6, 0xffffcdef
  bne x5, x6, fail

  li x3, 15
  lw x5, 0x3C(x0)
  li x6, 0x0000cdef
  bne x5, x6, fail

  li x30, 1
  sw x30, 0x3FC(x0)
  j  end

  fail:
    slli x30, x3, 1
    ori  x30, x30, 1
    sw   x30, 0x3FC(x0)
  end:
