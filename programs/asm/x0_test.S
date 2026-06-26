x0_test:
  # x0 read always returns 0
  addi x1, x0, 5
  addi x2, x0, 3
  add  x3, x1, x0    # x3 = x1 + 0 = 5
  sw   x3, 0(x0)

  # writing to x0 has no effect: x0 stays 0
  addi x0, x0, 7
  add  x3, x0, x0    # x3 = 0 + 0 = 0
  sw   x3, 4(x0)

  # x0 as rs1: add x4, x0, x2 → x4 = 0 + 3 = 3
  add  x4, x0, x2
  sw   x4, 8(x0)

  # x0 as rs2: sub x5, x1, x0 → x5 = 5 - 0 = 5
  sub  x5, x1, x0
  sw   x5, 12(x0)

  # x0 as base: lw x6, 4(x0) reads dmem[1] = 0
  lw   x6, 4(x0)
  sw   x6, 16(x0)

  # sw to x0 base: store x5 to dmem[20], just to prove x0 base works
  # but we can't easily read this back since feature_test reads from 0/4/8/12...
  # Actually just check that x0 as address base in lw works:
  # We already wrote x3=5 to dmem[0] above. Read it back via lw x7, 0(x0)
  lw   x7, 0(x0)
  sw   x7, 20(x0)
