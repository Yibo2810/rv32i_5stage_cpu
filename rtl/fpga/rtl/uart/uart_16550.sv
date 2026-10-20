`timescale 1ns/1ps
module uart_16550 #(
    parameter int CLKS_PER_BIT = 217    
) (
    input logic clk, rst,
    input logic wr_en,
    input logic [2:0] addr,
    input logic [7:0] wdata,
    input logic tx_busy,
    output logic [7:0] rdata,
    output logic [7:0] tx_data,
    output logic tx_valid
);
    // ==========================================================
    // LCR, IER, MCR, SCR (DLL/DLM when DLAB = 1) are 'real' regs
    // THR, FCR are write actions(no regs)
    // LSR = {1'b0, -busy, -busy, 5'b0}, IIR
    // Regs
    logic [7:0] ier;
    logic [7:0] lcr;
    logic [7:0] mcr;
    logic [7:0] scr;

    logic [7:0] dll;
    logic [7:0] dlm;
    logic       dlab;
    assign dlab = lcr[7];
    // ============================================================
    // Write
    assign tx_data = tx_valid ? wdata : 8'b0;
    always_ff @( posedge clk ) begin
        if (rst) begin
            ier <= 8'b0;
            lcr <= 8'b0;
            mcr <= 8'b0;
            scr <= 8'b0;
            dll <= 8'b0;
            dlm <= 8'b0;
        end else begin
            if (wr_en) begin
                case (addr)
                    3'd0: if (dlab) dll <= wdata;
                    3'd1: if (dlab) dlm <= wdata; else ier <= wdata;
                    //3'd2: 
                    3'd3: lcr <= wdata;
                    3'd4: mcr <= wdata;
                    //3'd5:
                    //3'd6:
                    3'd7: scr <= wdata; 
                    default: ;
                endcase
            end
        end
    end
    // =============================================================
    // Read
    logic [7:0] lsr;
    
    assign tx_valid = wr_en && !dlab && (addr == 3'd0);
    assign lsr = tx_busy ? 8'h00 : 8'h60;

    always_comb begin
        rdata = 8'h00;
            case (addr)
                3'd0: if (dlab) rdata = dll;
                3'd1: rdata = dlab ? dlm : ier;
                3'd2: rdata = 8'h01;
                3'd3: rdata = lcr;
                3'd4: rdata = mcr;
                3'd5: rdata = lsr;
                //3'd6: rdata = msr;
                3'd7: rdata = scr; 
                default: ;
            endcase
        end
endmodule