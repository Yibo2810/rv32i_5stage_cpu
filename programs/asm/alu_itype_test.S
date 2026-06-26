alu_itype_test:
  addi x12, x0, -1

  # ADDI: 0+7=7
  addi x3, x0, 7
  sw   x3, 0(x0)

  # ADDI neg: 0+(-5)=-5
  addi x3, x0, -5
  sw   x3, 4(x0)

  # SLTI: -1 < 0 → 1
  slti x3, x12, 0
  sw   x3, 8(x0)

  # SLTI: -1 < -2 → 0
  slti x3, x12, -2
  sw   x3, 12(x0)

  # SLTIU: 0xFFFFFFFF < 1 → 0 (unsigned max isn't < 1)
  sltiu x3, x12, 1
  sw   x3, 16(x0)

  # SLTIU: 0xFFFFFFFF < -1(0xFFFFFFFF as imm) → 0
  sltiu x3, x12, -1
  sw   x3, 20(x0)

  # XORI: 0xFFFFFFFF ^ 0xFF = 0xFFFFFF00
  xori x3, x12, 0xFF
  sw   x3, 24(x0)

  # ORI: 0 | 0x123 = 0x123
  ori  x3, x0, 0x123
  sw   x3, 28(x0)

  # ANDI: 0xFFFFFFFF & 0xFF = 0xFF
  andi x3, x12, 0xFF
  sw   x3, 32(x0)

  # SLLI: -1 << 4 = 0xFFFFFFF0
  slli x3, x12, 4
  sw   x3, 36(x0)

  # SRLI: -1 >> 4 = 0x0FFFFFFF (logical)
  srli x3, x12, 4
  sw   x3, 40(x0)

  # SRAI: -1 >>> 4 = 0xFFFFFFFF (arithmetic)
  srai x3, x12, 4
  sw   x3, 44(x0)
