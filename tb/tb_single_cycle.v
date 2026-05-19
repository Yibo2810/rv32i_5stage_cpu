`timescale 1ns/1ps

module tb_single_cycle;
  reg clk;
  reg rst;

  integer max_cycles;
  integer expect_addr;
  reg [31:0] expect_value;
  reg [31:0] actual_value;
  reg [1023:0] test_name;
  reg [1023:0] vcd_file;

  wire [31:0] imem_addr;
  wire [31:0] imem_rdata;

  wire [31:0] dmem_addr;
  wire [31:0] dmem_rdata;
  wire [31:0] dmem_wdata;
  wire        dmem_read;
  wire        dmem_write;

  initial begin
    clk = 0;
    rst = 1;

    if (!$value$plusargs("TEST=%s", test_name)) begin
      test_name = "single_cycle";
    end

    if (!$value$plusargs("EXPECT_ADDR=%d", expect_addr)) begin
      $display("ERROR: missing +EXPECT_ADDR=<data memory word index>");
      $fatal(1);
    end

    if (!$value$plusargs("EXPECT_VALUE=%h", expect_value)) begin
      $display("ERROR: missing +EXPECT_VALUE=<32-bit hex value>");
      $fatal(1);
    end

    if (!$value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
      max_cycles = 20;
    end

    if (!$value$plusargs("VCD=%s", vcd_file)) begin
      vcd_file = "sim/single_cycle.vcd";
    end

    if (expect_addr < 0 || expect_addr > 255) begin
      $display("ERROR: EXPECT_ADDR=%0d is outside dmem[0:255]", expect_addr);
      $fatal(1);
    end

    // dump wave
    $dumpfile(vcd_file);
    $dumpvars(0, tb_single_cycle);

    $display("RUN: %0s", test_name);
    $display("EXPECT: dmem[%0d] = %08h", expect_addr, expect_value);

    // reset
    repeat (2) @(posedge clk);
    rst = 0;

    // run fixed cycles and print useful trace
    repeat (max_cycles) begin
      @(posedge clk);
      #1;
      $display("pc=%h instr=%h dmem_we=%b dmem_addr=%h dmem_wdata=%h",
              imem_addr, imem_rdata, dmem_write, dmem_addr, dmem_wdata);
    end

    // check final signature
    actual_value = u_dmem.dmem[expect_addr];
    if (actual_value !== expect_value) begin
      $display("FAIL: %0s expected dmem[%0d]=%08h, got %08h",
               test_name, expect_addr, expect_value, actual_value);
      $fatal(1);
    end

    $display("PASS: %0s", test_name);
    $finish;
end

  always #5 clk = ~clk;

  core_single_cycle u_core(
    .clk(clk),
    .rst(rst),
    .imem_rdata(imem_rdata),
    .imem_addr(imem_addr),
    .dmem_read(dmem_read),
    .dmem_write(dmem_write),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_rdata(dmem_rdata)
  );
  
  instr_mem u_imem (
      .imem_addr(imem_addr),
      .imem_rdata(imem_rdata)
  );

  data_mem u_dmem (
      .clk(clk),
      .rst(rst),
      .dmem_read(dmem_read),
      .dmem_write(dmem_write),
      .dmem_addr(dmem_addr),
      .dmem_wdata(dmem_wdata),
      .dmem_rdata(dmem_rdata)
  );
endmodule
