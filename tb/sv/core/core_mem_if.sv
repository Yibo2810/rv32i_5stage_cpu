`timescale 1ns/1ps

interface core_mem_if(
  input logic clk, 
  input logic rst
  );

  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;

  logic        dmem_read;
  logic        dmem_write;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [3:0]  dmem_wstrb;
  logic [31:0] dmem_rdata;

  clocking cb @(posedge clk);
      default input #1step;
      input  imem_addr, imem_rdata;
      input  dmem_read, dmem_write, dmem_addr, dmem_wdata, dmem_wstrb, dmem_rdata;
      input rst;
  endclocking

  modport core (
    input  clk,
    input  rst,
    input  imem_rdata,
    input  dmem_rdata,
    output imem_addr,
    output dmem_read,
    output dmem_write,
    output dmem_addr,
    output dmem_wdata,
    output dmem_wstrb
  );

  modport mem_model (
    input  clk,
    input  rst,
    input  imem_addr,
    input  dmem_read,
    input  dmem_write,
    input  dmem_addr,
    input  dmem_wdata,
    input  dmem_wstrb,
    output imem_rdata,
    output dmem_rdata
  );

  modport monitor (
    clocking cb,
    input clk,
    input rst,
    input imem_addr,
    input imem_rdata,
    input dmem_read,
    input dmem_write,
    input dmem_addr,
    input dmem_wdata,
    input dmem_wstrb,
    input dmem_rdata
  );

  modport tb (
    clocking cb
  );
endinterface