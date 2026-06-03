`timescale 1ns/1ps

import single_pkg::*;
import ri_pkg::*;

module ri_execute_tb;

  logic [31:0] src_a;
  logic [31:0] src_b;
  alu_ctrl_e alu_ctrl;
  logic [31:0] result;
  logic        zero;

  int total_cases;
  int failed_cases;
  string test_name;
  string vcd_path;

  alu dut (
    .src_a(src_a),
    .src_b(src_b),
    .alu_ctrl(alu_ctrl),
    .result(result),
    .zero(zero)
  );

  function automatic alu_ctrl_e alu_ctrl_for(input ri_op_e op);
    case (op)
      RI_ADD, RI_ADDI   : alu_ctrl_for = ALU_ADD;
      RI_SUB            : alu_ctrl_for = ALU_SUB;
      RI_AND, RI_ANDI   : alu_ctrl_for = ALU_AND;
      RI_OR, RI_ORI     : alu_ctrl_for = ALU_OR;
      RI_XOR, RI_XORI   : alu_ctrl_for = ALU_XOR;
      RI_SLT, RI_SLTI   : alu_ctrl_for = ALU_SLT;
      RI_SLTU, RI_SLTIU : alu_ctrl_for = ALU_SLTU;
      RI_SLL, RI_SLLI   : alu_ctrl_for = ALU_SLL;
      RI_SRL, RI_SRLI   : alu_ctrl_for = ALU_SRL;
      RI_SRA, RI_SRAI   : alu_ctrl_for = ALU_SRA;
      default           : alu_ctrl_for = ALU_ADD;
    endcase
  endfunction

  function automatic logic [31:0] golden_result(
    input ri_op_e op,
    input logic [31:0] a,
    input logic [31:0] b
  );
    case (op)
      RI_ADD, RI_ADDI   : golden_result = a + b;
      RI_SUB            : golden_result = a - b;
      RI_AND, RI_ANDI   : golden_result = a & b;
      RI_OR, RI_ORI     : golden_result = a | b;
      RI_XOR, RI_XORI   : golden_result = a ^ b;
      RI_SLT, RI_SLTI   : golden_result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      RI_SLTU, RI_SLTIU : golden_result = (a < b) ? 32'd1 : 32'd0;
      RI_SLL, RI_SLLI   : golden_result = a << b[4:0];
      RI_SRL, RI_SRLI   : golden_result = a >> b[4:0];
      RI_SRA, RI_SRAI   : golden_result = $signed(a) >>> b[4:0];
      default           : golden_result = 32'h0;
    endcase
  endfunction

  task automatic run_case(
    input string name,
    input ri_op_e op,
    input logic [31:0] a,
    input logic [31:0] b
  );
    logic [31:0] expected;
    logic expected_zero;
    begin
      src_a = a;
      src_b = b;
      alu_ctrl = alu_ctrl_for(op);
      expected = golden_result(op, a, b);
      expected_zero = (expected == 32'h0);
      #1;

      total_cases++;
      if ((result !== expected) || (zero !== expected_zero)) begin
        failed_cases++;
        $display(
          "CASE FAIL: %s op=%0d a=0x%08h b=0x%08h ctrl=0x%0h result=0x%08h expected=0x%08h zero=%0b expected_zero=%0b",
          name, op, a, b, alu_ctrl, result, expected, zero, expected_zero
        );
      end else begin
        $display("CASE PASS: %s result=0x%08h", name, result);
      end
    end
  endtask

  task automatic run_directed();
    begin
      run_case("add_simple", RI_ADD, 32'd7, 32'd5);
      run_case("add_overflow_wrap", RI_ADD, 32'hffff_ffff, 32'd1);
      run_case("sub_simple", RI_SUB, 32'd12, 32'd5);
      run_case("sub_zero", RI_SUB, 32'd8, 32'd8);

      run_case("and_mask", RI_AND, 32'hff00_0f0f, 32'h0ff0_ffff);
      run_case("or_bits", RI_OR, 32'h0000_ff00, 32'h00ff_000f);
      run_case("xor_bits", RI_XOR, 32'ha5a5_0000, 32'hffff_00ff);

      run_case("slt_negative_less", RI_SLT, 32'hffff_fffe, 32'd1);
      run_case("slt_positive_not_less", RI_SLT, 32'd5, 32'hffff_fffe);
      run_case("sltu_unsigned_less", RI_SLTU, 32'd1, 32'hffff_fffe);
      run_case("sltu_unsigned_not_less", RI_SLTU, 32'hffff_fffe, 32'd1);

      run_case("sll_shamt", RI_SLL, 32'h0000_0001, 32'd8);
      run_case("srl_shamt", RI_SRL, 32'h8000_0000, 32'd31);
      run_case("sra_shamt", RI_SRA, 32'h8000_0000, 32'd31);
      run_case("shift_masks_to_5_bits", RI_SLL, 32'h0000_0001, 32'd40);

      run_case("addi_negative_imm", RI_ADDI, 32'd10, 32'hffff_fffc);
      run_case("andi_mask", RI_ANDI, 32'hf0f0_ffff, 32'h0000_00ff);
      run_case("ori_bits", RI_ORI, 32'h0000_0010, 32'h0000_00f0);
      run_case("xori_bits", RI_XORI, 32'hffff_0000, 32'h0000_ffff);
      run_case("slti_negative", RI_SLTI, 32'd3, 32'hffff_ffff);
      run_case("sltiu_unsigned", RI_SLTIU, 32'hffff_ffff, 32'd1);
      run_case("slli_shamt", RI_SLLI, 32'h0000_0003, 32'd4);
      run_case("srli_shamt", RI_SRLI, 32'h8000_0000, 32'd4);
      run_case("srai_shamt", RI_SRAI, 32'h8000_0000, 32'd4);
    end
  endtask

  initial begin
    src_a = 32'h0;
    src_b = 32'h0;
    alu_ctrl = ALU_ADD;
    total_cases = 0;
    failed_cases = 0;

    if (!$value$plusargs("TEST=%s", test_name)) begin
      test_name = "ri_directed";
    end

    if ($value$plusargs("VCD=%s", vcd_path)) begin
      $dumpfile(vcd_path);
      $dumpvars(0, ri_execute_tb);
    end

    $display("TEST START: %s", test_name);

    if (test_name == "ri_directed") begin
      run_directed();
    end else begin
      failed_cases++;
      $display("TEST ERROR: unknown TEST '%s'", test_name);
    end

    if (failed_cases == 0) begin
      $display("TEST PASS: %s (%0d cases)", test_name, total_cases);
      $finish;
    end else begin
      $display("TEST FAIL: %s (%0d/%0d failed)", test_name, failed_cases, total_cases);
      $fatal(1, "ri_execute_tb failed");
    end
  end

endmodule
