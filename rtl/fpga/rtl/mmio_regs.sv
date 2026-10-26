`timescale 1ns/1ps
module mmio_regs 
import peripherals::*;
(
  input  logic        clk, rst,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic        req_write,
  input  logic [31:0] req_addr,
  input  logic [31:0] req_wdata,
  input  logic [3:0]  req_wstrb,
  output logic        rsp_valid,
  input  logic        rsp_ready,
  output logic [31:0] rsp_rdata,

  // TOHOST
  output logic        tohost_seen,
  output logic [31:0] tohost,

  // UART_16550
  // TX
  output logic        uart_tx_valid,
  input  logic        uart_tx_busy,
  output logic [7:0]  uart_tx_data,
  // RX
  input  logic        uart_rx_valid,
  input  logic [7:0]  uart_rx_data,
  input  logic        uart_rx_err,

  // OLEDrgb COLOR and TXT
  output logic        oled_txt_wr,
  output logic [6:0]  oled_txt_idx,
  output logic [7:0]  oled_txt_data,
  output logic        oled_col_wr,
  output logic [2:0]  oled_col_idx,
  output logic [15:0] oled_col_data
);
    
    // TOHOST
    logic       fire;
    logic [9:0] word_off;                 // 4 KB = fpga_sys MMIO_AW (12): [MMIO_AW-1:2]
    assign fire     = req_valid && req_ready;
    assign word_off = req_addr[11:2];
    assign req_ready = 1'b1;
    // ================================================
    // UART
    logic [7:0] uart_rdata;
    logic uart_sel, uart_wr, uart_rd;
    assign uart_sel = (word_off[9:3] == MMIO_UART_BLOCK);
    assign uart_wr  = fire && req_write && uart_sel && req_wstrb[0];
    assign uart_rd = fire && !req_write && uart_sel;
    // =================================================
    // OLED
    logic txt_sel, col_sel;
    assign txt_sel = (word_off[9:7] == MMIO_TXT_BLOCK);   // 0x1000_0200/03FF -> req_addr[11:2]=001x_xxxx_xx(00)
    assign col_sel = (word_off[9:3] == MMIO_COLOR_BLOCK); // 0x1000_0400/041F -> req_addr[11:2]=0100_000x_xx(00)
    assign oled_txt_idx  = word_off[6:0];                 // (001)x_xxxx_xx(00), high3=row, low4=column
    assign oled_txt_data = req_wdata[7:0];                // from CPU, write in ASCII.
    assign oled_col_idx  = word_off[2:0];                 // Write which row
    assign oled_col_data = req_wdata[15:0];               // R[15:11], G[10:5], B[4:0]  RGB565
    assign oled_txt_wr   = fire && req_write && txt_sel && req_wstrb[0]; // req_wstrb = 4'b1111
    assign oled_col_wr   = fire && req_write && col_sel && (req_wstrb[1:0] == 2'b11);
    // =================================================
    always_ff @( posedge clk ) begin
        if (rst) begin
            tohost_seen <= 1'b0;
            tohost <= 32'b0;
            rsp_valid <= 1'b0;
            rsp_rdata <= 32'b0;
        end else begin
            rsp_valid <= fire;
            if (fire && req_write && word_off == MMIO_WOFF_TOHOST && req_wstrb == 4'b1111 && !tohost_seen) begin
                tohost <= req_wdata;
                tohost_seen <= 1'b1;
            end
            if (fire && !req_write) begin
                if (uart_sel) begin
                    rsp_rdata <= {24'b0, uart_rdata};
                end 
                else if (word_off == MMIO_WOFF_TOHOST) begin
                    rsp_rdata <= tohost;
                end
                else
                    rsp_rdata <= 32'b0;
            end
        end
    end

    uart_16550 u_uart (
        .clk(clk), 
        .rst(rst),
        .wr_en(uart_wr),
        .addr(req_addr[4:2]),
        .rdata(uart_rdata),
        .wdata(req_wdata[7:0]),
        .tx_data(uart_tx_data),
        .tx_valid(uart_tx_valid),
        .tx_busy(uart_tx_busy),
        .rd_en(uart_rd),
        .rx_valid(uart_rx_valid),
        .rx_data(uart_rx_data),
        .rx_frame_err(uart_rx_err)
    );

endmodule