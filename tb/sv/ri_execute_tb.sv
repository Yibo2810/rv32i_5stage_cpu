`timescale 1ns/1ps
import single_pkg::*;
import ri_pkg::*;

module ri_execute_tb;

  logic [31:0]  instr;
  logic [31:0]  rs1_value;
  logic [31:0]  rs2_value;
  
  logic [31:0]  result;
  logic [31:0]  imm;
  logic         zero;
  logic         mem_write;
  logic         mem_read;
  logic         reg_write;
  logic         alu_src;
  wb_sel_e      wb_sel;
  alu_ctrl_e    alu_ctrl;
  imm_sel_e     imm_sel;
  logic         illegal_instr;
  logic         branch;
  logic [31:0]  alu_src_b;
  assign alu_src_b = alu_src ? imm : rs2_value;
  alu alu0 (
    .src_a(rs1_value),
    .src_b(alu_src_b),
    .alu_ctrl(alu_ctrl),
    .result(result),
    .zero(zero)
  );
  control_unit cu (
    .instr(instr),
    .mem_write(mem_write),
    .mem_read(mem_read),
    .reg_write(reg_write),
    .alu_src(alu_src),
    .wb_sel(wb_sel),
    .branch(branch),
    .alu_ctrl(alu_ctrl),
    .imm_sel(imm_sel),
    .illegal_instr(illegal_instr)
  );
  imm_gen ig (
    .instr(instr),
    .imm_sel(imm_sel),
    .imm(imm)
  );

  function automatic logic [31:0] encode_r_instr(
    input ri_op_e op
  );
    logic [6:0] funct7;
    logic [2:0] funct3;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;

    rs1 = 5'd2;
    rs2 = 5'd3;
    rd  = 5'd1;

    funct7 = 'x;
    funct3 = 'x;

    unique case (op)
      RI_ADD : begin
        funct7 = FUNCT7_ADD;
        funct3 = FUNCT3_ADD_SUB;
      end
      RI_SUB : begin
        funct7 = FUNCT7_SUB;
        funct3 = FUNCT3_ADD_SUB;
      end
      RI_AND : begin
        funct7 = FUNCT7_AND;
        funct3 = FUNCT3_AND;
      end
      RI_OR : begin
        funct7 = FUNCT7_OR;
        funct3 = FUNCT3_OR;
      end
      RI_XOR : begin
        funct7 = FUNCT7_XOR;
        funct3 = FUNCT3_XOR;
      end
      RI_SLT : begin    
        funct7 = FUNCT7_SLT;
        funct3 = FUNCT3_SLT;
      end
      RI_SLTU : begin
        funct7 = FUNCT7_SLTU;
        funct3 = FUNCT3_SLTU;
      end
      RI_SLL : begin
        funct7 = FUNCT7_SLL;
        funct3 = FUNCT3_SLL;
      end
      RI_SRL : begin
        funct7 = FUNCT7_SRL;
        funct3 = FUNCT3_SRL;
      end
      RI_SRA : begin
        funct7 = FUNCT7_SRA;
        funct3 = FUNCT3_SRA;
      end
      default: begin
        funct7 = 'x;
        funct3 = 'x;
      end
    endcase
    encode_r_instr = {funct7, rs2, rs1, funct3, rd, OPCODE_R_TYPE};
  endfunction

  function automatic logic [31:0] encode_i_instr(
    input ri_op_e op,
    input logic [31:0] imm_value
  );
    logic [2:0] funct3;
    logic [4:0] rs1;
    logic [4:0] rd;
    logic [11:0] imm_field;

    rs1 = 5'd0;
    rd  = 5'd1;
    imm_field = imm_value[11:0];

    funct3 = 'x;

    unique case (op)
      RI_ADDI : begin
        funct3 = FUNCT3_ADDI;
      end
      RI_ANDI : begin
        funct3 = FUNCT3_ANDI;
      end
      RI_ORI : begin
        funct3 = FUNCT3_ORI;
      end
      RI_XORI : begin
        funct3 = FUNCT3_XORI;
      end
      RI_SLTI : begin    
        funct3 = FUNCT3_SLTI;
      end
      RI_SLTIU : begin
        funct3 = FUNCT3_SLTIU;
      end
      RI_SLLI : begin
        imm_field = {FUNCT7_SLLI, imm_value[4:0]};
        funct3 = FUNCT3_SLLI;
      end
      RI_SRLI : begin
        imm_field = {FUNCT7_SRLI, imm_value[4:0]};
        funct3 = FUNCT3_SRLI;
      end
      RI_SRAI : begin
        imm_field = {FUNCT7_SRAI, imm_value[4:0]};
        funct3 = FUNCT3_SRAI;
      end
      default: begin
        funct3 = 'x;
      end
    endcase
    encode_i_instr = {imm_field, rs1, funct3, rd, OPCODE_I_TYPE};
  endfunction

  function automatic logic [31:0] reference_result(
    input ri_op_e op,
    input logic [31:0] a,
    input logic [31:0] b
  );
    
    unique case (op)
      RI_ADD, RI_ADDI: begin
        reference_result = a + b;
      end
      RI_SUB : begin
        reference_result = a - b;
      end
      RI_AND, RI_ANDI: begin
        reference_result = a & b;
      end
      RI_OR, RI_ORI: begin
        reference_result = a | b;
      end
      RI_XOR, RI_XORI: begin
        reference_result = a ^ b;
      end
      RI_SLT, RI_SLTI: begin
        reference_result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      end
      RI_SLTU, RI_SLTIU: begin
        reference_result = (a < b) ? 32'd1 : 32'd0;
      end
      RI_SLL, RI_SLLI: begin
        reference_result = a << b[4:0];
      end
      RI_SRL, RI_SRLI: begin
        reference_result = a >> b[4:0];
      end
      RI_SRA, RI_SRAI: begin
        reference_result = $signed(a) >>> b[4:0];
      end
      default: begin
        reference_result = 'x;
        $fatal(0,"Testbench code fail");
      end
    endcase
  endfunction

  function automatic alu_ctrl_e expected_ctrl(
    input ri_op_e op
  );

    unique case (op)
      RI_ADD, RI_ADDI: begin
        expected_ctrl = ALU_ADD;
      end
      RI_SUB: begin
        expected_ctrl = ALU_SUB;
      end
      RI_AND, RI_ANDI: begin
        expected_ctrl = ALU_AND;
      end
      RI_OR, RI_ORI: begin
        expected_ctrl = ALU_OR;
      end
      RI_XOR, RI_XORI: begin
        expected_ctrl = ALU_XOR;
      end
      RI_SLT, RI_SLTI: begin
        expected_ctrl = ALU_SLT;
      end
      RI_SLTU, RI_SLTIU: begin
        expected_ctrl = ALU_SLTU;
      end
      RI_SLL, RI_SLLI: begin
        expected_ctrl = ALU_SLL;
      end
      RI_SRL, RI_SRLI: begin
        expected_ctrl = ALU_SRL;
      end
      RI_SRA, RI_SRAI: begin
        expected_ctrl = ALU_SRA;
      end
      default: begin
        expected_ctrl = ALU_ADD;
      end
    endcase;
  endfunction

  task automatic run_case(
    input string name,
    input ri_op_e op,
    input logic [31:0] a,
    input logic [31:0] b_or_imm
  );
    logic is_i_type;
    logic [31:0] expected_b;
    logic [31:0] expected_result;
    logic [31:0] expected_imm;
    alu_ctrl_e expected_alu_ctrl;
    logic        expected_src;
    imm_sel_e    expected_imm_sel;

    unique case (op)
      RI_ADD, RI_SUB, RI_AND, RI_OR, RI_XOR, RI_SLT, RI_SLTU, RI_SLL, RI_SRL, RI_SRA: begin
        is_i_type = 1'b0;
        rs2_value = b_or_imm;
        expected_src = 1'b0;
        expected_b = b_or_imm;
        expected_imm_sel = IMM_NONE;
        expected_imm = 32'b0;
      end
      RI_ADDI, RI_ANDI, RI_ORI, RI_XORI, RI_SLTI, RI_SLTIU: begin
        is_i_type = 1'b1;
        rs2_value = 32'hdead_beef;
        expected_src = 1'b1;
        expected_imm_sel = IMM_I;
        expected_imm = {{20{b_or_imm[11]}}, b_or_imm[11:0]};
        expected_b = expected_imm;
      end
      RI_SLLI, RI_SRLI, RI_SRAI: begin
        is_i_type = 1'b1;
        rs2_value = 32'hdead_beef;
        expected_src = 1'b1;
        expected_b = {27'b0, b_or_imm[4:0]};
        expected_imm_sel = IMM_I;

        case (op)
          RI_SLLI: expected_imm = {20'b0, FUNCT7_SLLI, b_or_imm[4:0]};
          RI_SRLI: expected_imm = {20'b0, FUNCT7_SRLI, b_or_imm[4:0]};
          RI_SRAI: expected_imm = {20'b0, FUNCT7_SRAI, b_or_imm[4:0]};
          default: expected_imm = 32'b0;
        endcase
      end
      default: $fatal(1, "Unknown operation");
    endcase

    rs1_value = a;
    expected_result = reference_result(op, a, expected_b);
    expected_alu_ctrl = expected_ctrl(op);
    instr = (is_i_type) ? encode_i_instr(op, b_or_imm) : encode_r_instr(op);
    
    #1;

    if (illegal_instr !== 1'b0) begin
      $fatal(1, "%s: unexpected illegal instruction", name);
    end
    if (alu_src !== expected_src) begin
      $fatal(1, "%s: alu_src mismatch: got %b, expected %b", name, alu_src, expected_src);
    end
    if (imm_sel !== expected_imm_sel) begin
      $fatal(1, "%s: imm_sel mismatch: got %b, expected %b", name, imm_sel, expected_imm_sel);
    end
    if (alu_ctrl !== expected_alu_ctrl) begin
      $fatal(1, "%s: alu_ctrl mismatch: got %b, expected %b", name, alu_ctrl, expected_alu_ctrl);
    end
    if (imm !== expected_imm) begin 
      $fatal(1, "%s: imm mismatch: got %h, expected %h", name, imm, expected_imm);
    end
    if (result !== expected_result) begin
      $fatal(1, "%s: result mismatch: got %h, expected %h", name, result, expected_result);
    end

    $display("%s: PASS", name);
  endtask

    initial begin
      run_case("ADD", RI_ADD, 32'h0000_0005, 32'h0000_0003);
      run_case("SUB", RI_SUB, 32'h0000_0005, 32'h0000_0003);
      run_case("AND", RI_AND, 32'h0000_00f0, 32'h0000_0f00);
      run_case("OR", RI_OR, 32'h0000_00f0, 32'h0000_0f00);
      run_case("XOR", RI_XOR, 32'h0000_00f0, 32'h0000_0f00);
      run_case("SLT", RI_SLT, 32'hffff_ffff, 32'h0000_0001);
      run_case("SLTU", RI_SLTU, 32'hffff_ffff, 32'h0000_0001);
      run_case("SLL", RI_SLL, 32'h0000_0001, 32'h0000_001f);
      run_case("SRL", RI_SRL, 32'h8000_0001, 32'h0000_001f);
      run_case("SRA", RI_SRA, 32'h8000_0001, 32'h0000_001f);

      run_case("ADDI", RI_ADDI, 32'h0000_0005, -32'sd3);
      run_case("ANDI", RI_ANDI, 32'h0000_00f0, -32'sd16);
      run_case("ORI", RI_ORI, 32'h0000_00f0, -32'sd16);
      run_case("XORI", RI_XORI, 32'h0000_00f0, -32'sd16);
      run_case("SLTI", RI_SLTI, 32'hffff_ffff, -32'sd1);
      run_case("SLTIU", RI_SLTIU, 32'hffff_ffff, -32'sd1);

      run_case("SLLI", RI_SLLI, 32'h0000_0001, 5);
      run_case("SRLI", RI_SRLI, 32'h8000_0001, 5);
      run_case("SRAI", RI_SRAI, 32'h8000_0001, 5);

      $display("TEST PASS: ri_directed");
      $finish;
    end
endmodule