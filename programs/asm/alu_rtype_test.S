alu_rtype_test:
  # operands
  addi x10, x0, 7
  addi x11, x0, 3
  addi x12, x0, -1
  addi x13, x0, 1

  # ADD: 7+3=10
  add  x3, x10, x11
  sw   x3, 0(x0)

  # SUB: 7-3=4
  sub  x3, x10, x11
  sw   x3, 4(x0)

  # AND: 7&3=3
  and  x3, x10, x11
  sw   x3, 8(x0)

  # OR: 7|3=7
  or   x3, x10, x11
  sw   x3, 12(x0)

  # XOR: 7^3=4
  xor  x3, x10, x11
  sw   x3, 16(x0)

  # SLL: 7<<3=56
  sll  x3, x10, x11
  sw   x3, 20(x0)

  # SRL: 7>>3=0
  srl  x3, x10, x11
  sw   x3, 24(x0)

  # SRA: 7>>>3=0
  sra  x3, x10, x11
  sw   x3, 28(x0)

  # SLT: -1 < 1 → 1 (signed)
  slt  x3, x12, x13
  sw   x3, 32(x0)

  # SLTU: 0xFFFFFFFF < 1 → 0 (unsigned)
  sltu x3, x12, x13
  sw   x3, 36(x0)
