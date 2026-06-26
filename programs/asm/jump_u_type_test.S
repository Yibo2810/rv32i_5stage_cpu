jump_u_type_test:
  # LUI: x3 = 0x12345000
  lui  x3, 0x12345
  sw   x3, 0(x0)

  # AUIPC: x3 = PC + 0x1000
  auipc x3, 0x1
  sw   x3, 4(x0)

  # JAL: jump to jal_dest, link return addr into x3
  jal  x3, jal_dest
  addi x3, x0, 99
  sw   x3, 8(x0)
jal_dest:
  sw   x3, 8(x0)

  # JALR: jalr rd, offset(rs1) — PC = rs1+offset, rd = PC+4
  # compute address of jr_dest into x4 via AUIPC
  auipc x4, 0
  addi  x4, x4, 16
  jalr  x3, 0(x4)
  addi  x3, x0, 99
  sw   x3, 12(x0)
jr_dest:
  sw   x3, 12(x0)
