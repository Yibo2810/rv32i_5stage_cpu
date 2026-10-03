load_store_width_test:
  # x1 = 0x89ABC0EF
  lui  x1, 0x89ABC
  ori  x1, x1, 0x0EF

  # SW: store full word at dmem[0]
  sw   x1, 0x80000000(x0)

  # SB: store byte 0xEF at dmem[4]
  sb   x1, 0x80000004(x0)

  # SH: store half 0xCDEF at dmem[8]
  sh   x1, 0x80000008(x0)

  # LB signed: read 0xEF → sign-extend to 0xFFFFFFEF
  lb   x2, 0x80000004(x0)
  sw   x2, 0x8000000C(x0)

  # LBU: read 0xEF → zero-extend to 0x000000EF
  lbu  x2, 0x80000004(x0)
  sw   x2, 0x80000010(x0)

  # LH signed: read 0xCDEF → sign-extend to 0xFFFFCDEF
  lh   x2, 0x80000008(x0)
  sw   x2, 0x80000014(x0)

  # LHU: read 0xCDEF → zero-extend to 0x0000CDEF
  lhu  x2, 0x80000008(x0)
  sw   x2, 0x80000018(x0)

  # LW: read full word 0x89ABC0EF
  lw   x2, 0x80000000(x0)
  sw   x2, 0x8000001C(x0)
