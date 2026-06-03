package ri_pkg;

  typedef enum {
    RI_ADD, RI_SUB, RI_AND, RI_OR, RI_XOR,
    RI_SLT, RI_SLTU, RI_SLL, RI_SRL, RI_SRA,
    RI_ADDI, RI_ANDI, RI_ORI, RI_XORI,
    RI_SLTI, RI_SLTIU, RI_SLLI, RI_SRLI, RI_SRAI
  } ri_op_e;

  typedef struct {
    ri_op_e      op;
    logic [31:0] src_a;
    logic [31:0] src_b_or_imm;
    logic [31:0] expected;
    string       name;
  } ri_case_t;

endpackage
