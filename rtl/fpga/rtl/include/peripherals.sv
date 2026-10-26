`timescale 1ns/1ps
package peripherals;
    localparam int          SOC_CLK_HZ       = 25_000_000;
    localparam int          SOC_UART_BAUD    = 115_200;
    localparam int          SOC_UART_CPB     = SOC_CLK_HZ / SOC_UART_BAUD;

    localparam logic [31:0] SOC_RESET_PC     = 32'h8000_0000;
    localparam logic [31:0] SOC_RAM_BASE     = 32'h8000_0000;
    localparam int          SOC_RAM_AW       = 16;              // RAM = 2**16 B = 64 KB
    localparam logic [31:0] SOC_MMIO_BASE    = 32'h1000_0000;
    localparam int          SOC_MMIO_AW      = 12;              // MMIO = 4 KB, see mmio_regs word_off

    localparam logic [11:0] MMIO_OFF_UART    = 12'h000;
    localparam logic [11:0] MMIO_OFF_TOHOST  = 12'h100;     // 0x100 >> 2  tohost change to 0x100
    localparam logic [11:0] MMIO_OFF_TXT     = 12'h200;
    localparam logic [11:0] MMIO_OFF_COLOR   = 12'h400;
    localparam logic [31:0] SOC_UART0_BASE   = SOC_MMIO_BASE + 32'(MMIO_OFF_UART);
    localparam logic [31:0] SOC_TOHOST_ADDR  = SOC_MMIO_BASE + 32'(MMIO_OFF_TOHOST);
    localparam logic [31:0] SOC_TXT_ADDR     = SOC_MMIO_BASE + 32'(MMIO_OFF_TXT);
    localparam logic [31:0] SOC_COLOR_ADDR   = SOC_MMIO_BASE + 32'(MMIO_OFF_COLOR);
    localparam logic [9:0]  MMIO_WOFF_TOHOST = MMIO_OFF_TOHOST[11:2];
    localparam logic [6:0]  MMIO_UART_BLOCK  = MMIO_OFF_UART[11:5];

    localparam logic [2:0]  MMIO_TXT_BLOCK   = MMIO_OFF_TXT[11:9];    // word_off[9:7]
    localparam logic [6:0]  MMIO_COLOR_BLOCK = MMIO_OFF_COLOR[11:5];  // word_off[9:3]

    // ========================================================
    // OLEDrgb
    localparam int          OLED_ROWS        = 8;
    localparam int          OLED_COLS        = 12;
    localparam int          OLED_STRIDE      = 16;

    localparam logic [15:0] RGB_BLACK        = 16'h0000;
    localparam logic [15:0] RGB_WHITE        = 16'hFFFF;
    localparam logic [15:0] RGB_RED          = 16'hF800;
    localparam logic [15:0] RGB_GREEN        = 16'h07E0;
    localparam logic [15:0] RGB_YELLOW       = 16'hFFE0;
    localparam logic [15:0] RGB_BLUE         = 16'h001F;

    function automatic logic [7:0] hex_ch(input logic [3:0] n);
        return (n < 4'd10) ? 8'h30 + 8'(n) : 8'h57 + 8'(n);
    endfunction

    function automatic logic [63:0] hex8_str(input logic [31:0] v);
        for (int k = 0; k < 8; k++) hex8_str[8*k +: 8] = hex_ch(v[4*k +: 4]);
    endfunction
    // ==========================================================
    localparam int          UART_REG_SHIFT   = 2;

    localparam logic [2:0]  UART_RBR = 3'd0;
    localparam logic [2:0]  UART_THR = 3'd0;
    localparam logic [2:0]  UART_DLL = 3'd0;
    localparam logic [2:0]  UART_IER = 3'd1;
    localparam logic [2:0]  UART_DLM = 3'd1;
    localparam logic [2:0]  UART_IIR = 3'd2;
    localparam logic [2:0]  UART_FCR = 3'd2;
    localparam logic [2:0]  UART_LCR = 3'd3;
    localparam logic [2:0]  UART_MCR = 3'd4;
    localparam logic [2:0]  UART_LSR = 3'd5;
    localparam logic [2:0]  UART_MSR = 3'd6;
    localparam logic [2:0]  UART_SCR = 3'd7;

    localparam int IER_RDI  = 0;
    localparam int IER_THRI = 1;
    localparam int IER_RLSI = 2;
    localparam int IER_MSI  = 3;

    localparam int FCR_FIFO_EN  = 0;
    localparam int FCR_RX_RESET = 1;
    localparam int FCR_TX_RESET = 2;
    localparam int FCR_DMA_MODE = 3;

    localparam int LCR_WLS0 = 0;
    localparam int LCR_WLS1 = 1;
    localparam int LCR_STB  = 2;
    localparam int LCR_PEN  = 3;
    localparam int LCR_EPS  = 4;
    localparam int LCR_SPAR = 5;
    localparam int LCR_SBC  = 6;
    localparam int LCR_DLAB = 7;

    localparam int MCR_DTR  = 0;
    localparam int MCR_RTS  = 1;
    localparam int MCR_OUT1 = 2;
    localparam int MCR_OUT2 = 3;
    localparam int MCR_LOOP = 4;

    localparam int LSR_DR    = 0;
    localparam int LSR_OE    = 1;
    localparam int LSR_PE    = 2;
    localparam int LSR_FE    = 3;
    localparam int LSR_BI    = 4;
    localparam int LSR_THRE  = 5;
    localparam int LSR_TEMT  = 6;
    localparam int LSR_FIFOE = 7;

    localparam logic [7:0] UART_LCR_8N1    = 8'h03;
    localparam logic [7:0] UART_IIR_NO_INT = 8'h01;
    localparam logic [7:0] UART_LSR_RESET  = 8'h60;

    /*  
        bit	 name	                         when 1	                           when 0
        0	  DR	               uart_rx send a bit（rx_valid）	        CPU read RBR

        1	  OE	        new bit arrive, but last bit didn't leave	    CPU read LSR
            （overrun）            (DR still 1), new bit cover old bit

        3	  FE（framing error）	  when send: frame_err=1	            CPU read LSR

        5	  THRE	                    Transmitter idle 	
        6	  TEMT		
        2、4、7	PE / BI / FIFO error	do it when finish the CSR
    */
    typedef struct packed {
        logic fifo;
        logic temt;
        logic thre;
        logic bi;
        logic fe;
        logic pe;
        logic oe;
        logic dr;
    } lsr_e;
endpackage
