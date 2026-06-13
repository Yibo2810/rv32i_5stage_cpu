`timescale 1ns/1ps

package ri_pkg;

  typedef enum logic[7:0] {
    BAD_0 = 0, RI_ADD = 1, RI_SUB, RI_AND, RI_OR, RI_XOR,
    RI_SLT, RI_SLTU, RI_SLL, RI_SRL, RI_SRA,
    RI_ADDI, RI_ANDI, RI_ORI, RI_XORI,
    RI_SLTI, RI_SLTIU, RI_SLLI, RI_SRLI, RI_SRAI
  } ri_op_e;

endpackage
