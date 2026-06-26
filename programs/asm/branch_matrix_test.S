branch_matrix_test:
  # BEQ taken: 5==5
  addi x1, x0, 5
  addi x2, x0, 5
  beq  x1, x2, beq_t
  addi x3, x0, 99
  sw   x3, 0(x0)
  jal  x0, beq_done
beq_t:
  addi x3, x0, 1
  sw   x3, 0(x0)
beq_done:

  # BEQ not-taken: 5!=6
  addi x1, x0, 5
  addi x2, x0, 6
  beq  x1, x2, beq_nt_fail
  addi x3, x0, 2
  sw   x3, 4(x0)
  jal  x0, beq_nt_done
beq_nt_fail:
  addi x3, x0, 99
  sw   x3, 4(x0)
beq_nt_done:

  # BNE taken: 5!=6
  addi x1, x0, 5
  addi x2, x0, 6
  bne  x1, x2, bne_t
  addi x3, x0, 99
  sw   x3, 8(x0)
  jal  x0, bne_done
bne_t:
  addi x3, x0, 3
  sw   x3, 8(x0)
bne_done:

  # BNE not-taken: 7==7
  addi x1, x0, 7
  addi x2, x0, 7
  bne  x1, x2, bne_nt_fail
  addi x3, x0, 4
  sw   x3, 12(x0)
  jal  x0, bne_nt_done
bne_nt_fail:
  addi x3, x0, 99
  sw   x3, 12(x0)
bne_nt_done:

  # BLT taken: -1 < 1
  addi x1, x0, -1
  addi x2, x0, 1
  blt  x1, x2, blt_t
  addi x3, x0, 99
  sw   x3, 16(x0)
  jal  x0, blt_done
blt_t:
  addi x3, x0, 5
  sw   x3, 16(x0)
blt_done:

  # BLT not-taken: 5 not < 3
  addi x1, x0, 5
  addi x2, x0, 3
  blt  x1, x2, blt_nt_fail
  addi x3, x0, 6
  sw   x3, 20(x0)
  jal  x0, blt_nt_done
blt_nt_fail:
  addi x3, x0, 99
  sw   x3, 20(x0)
blt_nt_done:

  # BGE taken: 5 >= 3
  addi x1, x0, 5
  addi x2, x0, 3
  bge  x1, x2, bge_t
  addi x3, x0, 99
  sw   x3, 24(x0)
  jal  x0, bge_done
bge_t:
  addi x3, x0, 7
  sw   x3, 24(x0)
bge_done:

  # BGE not-taken: 3 not >= 5
  addi x1, x0, 3
  addi x2, x0, 5
  bge  x1, x2, bge_nt_fail
  addi x3, x0, 8
  sw   x3, 28(x0)
  jal  x0, bge_nt_done
bge_nt_fail:
  addi x3, x0, 99
  sw   x3, 28(x0)
bge_nt_done:

  # BLTU taken: 3 < 5 (unsigned)
  addi x1, x0, 3
  addi x2, x0, 5
  bltu x1, x2, bltu_t
  addi x3, x0, 99
  sw   x3, 32(x0)
  jal  x0, bltu_done
bltu_t:
  addi x3, x0, 9
  sw   x3, 32(x0)
bltu_done:

  # BLTU not-taken: 5 not < 3
  addi x1, x0, 5
  addi x2, x0, 3
  bltu x1, x2, bltu_nt_fail
  addi x3, x0, 10
  sw   x3, 36(x0)
  jal  x0, bltu_nt_done
bltu_nt_fail:
  addi x3, x0, 99
  sw   x3, 36(x0)
bltu_nt_done:

  # BGEU taken: 5 >= 3
  addi x1, x0, 5
  addi x2, x0, 3
  bgeu x1, x2, bgeu_t
  addi x3, x0, 99
  sw   x3, 40(x0)
  jal  x0, bgeu_done
bgeu_t:
  addi x3, x0, 11
  sw   x3, 40(x0)
bgeu_done:

  # BGEU not-taken: 3 not >= 5
  addi x1, x0, 3
  addi x2, x0, 5
  bgeu x1, x2, bgeu_nt_fail
  addi x3, x0, 12
  sw   x3, 44(x0)
  jal  x0, bgeu_nt_done
bgeu_nt_fail:
  addi x3, x0, 99
  sw   x3, 44(x0)
bgeu_nt_done:
