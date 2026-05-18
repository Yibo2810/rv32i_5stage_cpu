`timescale 1ns/1ps

module tb_single_cycle;
  reg clk;
  reg rst;

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

  always #5 clk = ~clk;
    // dump wave
    $dumpfile("sim/single_cycle.vcd");
    $dumpvars(0, tb_single_cycle);

    // reset
    repeat (2) @(posedge clk);
    rst = 0;

    // run fixed cycles and print useful trace
    repeat (20) begin
      @(posedge clk);
      #1;
      $display("pc=%h instr=%h dmem_we=%b dmem_addr=%h dmem_wdata=%h",
              imem_addr, imem_rdata, dmem_write, dmem_addr, dmem_wdata);
    end

    // check final signature
    if (u_dmem.dmem[0] !== 32'h0000000c) begin
      $display("FAIL: expected dmem[0]=0000000c, got %h", u_dmem.dmem[0]);
      $finish;
    end

    $display("PASS");
    $finish;
end


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

