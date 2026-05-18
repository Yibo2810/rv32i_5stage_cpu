branch_test:
  addi x1, x0, 3
  addi x2, x0, 3
  beq  x1, x2, taken
  addi x3, x0, 99
taken:
  addi x3, x0, 1
  sw   x3, 0(x0)
