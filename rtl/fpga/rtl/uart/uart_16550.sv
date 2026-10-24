`timescale 1ns/1ps
module uart_16550 
import peripherals::*;
(
    input logic clk, rst,
    input logic wr_en,
    input logic [2:0] addr,
    input logic [7:0] wdata,
    // TX
    input logic tx_busy,
    output logic [7:0] rdata,
    output logic [7:0] tx_data,
    output logic tx_valid,
    // RX
    input  logic rd_en,
    input  logic rx_valid,
    input  logic [7:0] rx_data,
    input  logic rx_frame_err
);
    // ==========================================================
    // LCR, IER, MCR, SCR (DLL/DLM when DLAB = 1) are 'real' regs
    // THR, FCR are write actions(no regs)
    // LSR = {DR, OE, PE, FE, BI, THRE, TEMT, FIFO}, IIR
    // Regs
    logic [7:0] ier;
    logic [7:0] lcr;
    logic [7:0] mcr;
    logic [7:0] scr;

    logic [7:0] dll;
    logic [7:0] dlm;
    logic       dlab;
    lsr_e       lsr;
    logic [7:0] rbr;
    //assign lsr = {1'b0, temt, thre, 1'b0, fe, 1'b0, oe, dr};
    logic rbr_read, lsr_read;
    assign rbr_read = rd_en && !dlab && (addr == UART_RBR);
    assign lsr_read = rd_en && (addr == UART_LSR);
    assign dlab = lcr[LCR_DLAB];
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
            rbr <= 8'b0;
            // LSR
            lsr.dr <= 1'b0;
            lsr.oe <= 1'b0;
            lsr.fe <= 1'b0;
            lsr.fifo <= 1'b0;
            lsr.temt <= 1'b0;
            lsr.thre <= 1'b0;
            lsr.bi <= 1'b0;
            lsr.pe <= 1'b0;
        end else begin
            if (wr_en) begin
                case (addr)
                    UART_THR: if (dlab) dll <= wdata;
                    UART_IER: if (dlab) dlm <= wdata; else ier <= wdata;
                    //UART_FCR: 
                    UART_LCR: lcr <= wdata;
                    UART_MCR: mcr <= wdata;
                    //3'd5:
                    //3'd6:
                    UART_SCR: scr <= wdata; 
                    default: ;
                endcase
            end
            if (rbr_read) lsr.dr <= 1'b0;
            if (lsr_read) begin lsr.oe <= 1'b0; lsr.fe <= 1'b0; end
            if (rx_valid)  begin lsr.dr <= 1'b1; rbr <= rx_data; end
            if (rx_valid && lsr.dr && !rbr_read) lsr.oe <= 1;
            if (rx_valid && rx_frame_err) lsr.fe <= 1;
        end
    end
    // =============================================================
    // Read
    assign tx_valid = wr_en && !dlab && (addr == UART_RBR);

    always_comb begin
        rdata = 8'h00;
            case (addr)
                UART_RBR: rdata = dlab ? dll : rbr;
                UART_IER: rdata = dlab ? dlm : ier;
                UART_IIR: rdata = UART_IIR_NO_INT;
                UART_LCR: rdata = lcr;
                UART_MCR: rdata = mcr;
                UART_LSR: begin rdata = lsr; rdata[LSR_THRE] = !tx_busy; rdata[LSR_TEMT] = !tx_busy; end
                //UART_MSR: rdata = msr;
                UART_SCR: rdata = scr; 
                default: ;
            endcase
        end
endmodule