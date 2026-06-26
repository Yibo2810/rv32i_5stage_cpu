load_store_width_test:
  # x1 = 0x89ABC0EF
  lui  x1, 0x89ABC
  ori  x1, x1, 0x0EF

  # SW: store full word at dmem[0]
  sw   x1, 0(x0)

  # SB: store byte 0xEF at dmem[4]
  sb   x1, 4(x0)

  # SH: store half 0xCDEF at dmem[8]
  sh   x1, 8(x0)

  # LB signed: read 0xEF → sign-extend to 0xFFFFFFEF
  lb   x2, 4(x0)
  sw   x2, 12(x0)

  # LBU: read 0xEF → zero-extend to 0x000000EF
  lbu  x2, 4(x0)
  sw   x2, 16(x0)

  # LH signed: read 0xCDEF → sign-extend to 0xFFFFCDEF
  lh   x2, 8(x0)
  sw   x2, 20(x0)

  # LHU: read 0xCDEF → zero-extend to 0x0000CDEF
  lhu  x2, 8(x0)
  sw   x2, 24(x0)

  # LW: read full word 0x89ABC0EF
  lw   x2, 0(x0)
  sw   x2, 28(x0)
