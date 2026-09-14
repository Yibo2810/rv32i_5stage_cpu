`timescale 1ns/1ps

interface pipeline_probe_if import single_pkg::*;(
    input logic clk,
    input logic rst
);
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;

    logic        dmem_req_ready;
    logic        dmem_req_valid;
    logic        dmem_req_write;
    logic [31:0] dmem_req_addr;
    logic [31:0] dmem_req_wdata;
    logic [3:0]  dmem_req_wstrb;

    logic [31:0] dmem_rsp_rdata;
    logic        dmem_rsp_ready;
    logic        dmem_rsp_valid;

    logic        trap_valid;
    exc_cause_e  trap_cause;
    logic[31:0]  trap_pc;
    logic        halted;

    logic [31:0] mem_pc;
    logic [31:0] mem_instr;

    logic        retire;
    logic        retire_exc;
    logic [31:0] retire_pc;
    logic [31:0] retire_instr;
    logic [31:0] retire_next_pc;

    logic        rd_we;
    logic [31:0] rd_addr;
    logic [31:0] rd_data;

    clocking cb @(posedge clk);
        default input #1step;
        input imem_addr, imem_rdata;
        input mem_pc, mem_instr;
        input dmem_req_ready, dmem_req_valid, dmem_req_write, dmem_req_addr, dmem_req_wdata, dmem_req_wstrb;
        input dmem_rsp_ready, dmem_rsp_rdata, dmem_rsp_valid;
        input trap_valid, trap_cause, trap_pc, halted;
        input retire, retire_exc, retire_pc, retire_instr, retire_next_pc;
        input rd_we, rd_addr, rd_data;
        input rst;
    endclocking

    modport pl_core (
        input clk,
        input rst,
        input imem_rdata,
        input dmem_rsp_rdata,
        input dmem_req_ready,
        input dmem_rsp_valid,

        output imem_addr,

        output dmem_req_valid,
        output dmem_req_write,
        output dmem_req_addr,
        output dmem_req_wdata,
        output dmem_req_wstrb,

        output dmem_rsp_ready,

        output trap_valid,
        output trap_cause,
        output trap_pc,
        output halted
    );

    modport bram (
        input clk,
        input rst,
        output imem_rdata,
        output dmem_rsp_rdata,
        output dmem_req_ready,
        output dmem_rsp_valid,

        input imem_addr,

        input dmem_req_valid,
        input dmem_req_write,
        input dmem_req_addr,
        input dmem_req_wdata,
        input dmem_req_wstrb,

        input dmem_rsp_ready
    );

    modport pipeline_monitor (
        clocking cb,
        input clk,
        input rst,
        input imem_rdata,
        input dmem_rsp_rdata,
        input dmem_req_ready,
        input dmem_rsp_valid,
        input imem_addr,
        input dmem_req_valid,
        input dmem_req_write,
        input dmem_req_addr,
        input dmem_req_wdata,
        input dmem_req_wstrb,
        input dmem_rsp_ready,
        input trap_valid,
        input trap_cause,
        input trap_pc,
        input halted,
        input mem_pc,
        input mem_instr,
        input retire,
        input retire_exc, 
        input retire_pc, 
        input retire_instr, 
        input retire_next_pc,
        input rd_we,
        input rd_addr,
        input rd_data
    );

  modport tb (
    clocking cb
  );
endinterface