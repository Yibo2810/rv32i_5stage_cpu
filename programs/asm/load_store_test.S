load_store_test:
  addi x1, x0, 42
  sw   x1, 0(x0)
  lw   x2, 0(x0)
  sw   x2, 4(x0)
