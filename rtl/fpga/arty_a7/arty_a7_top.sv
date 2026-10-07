module arty_a7_top (
    input logic clk_100mhz,
    input logic reset_n,
    input logic [1:0] sw,
    output logic [3:0] led,

    output logic led0_r,
    output logic led0_g,
    output logic led0_b,
    output logic led1_r,
    output logic led1_g,
    output logic led1_b
);
    wire clk25_mmcm;
    wire clk_25mhz;

    wire clkfb_mmcm;
    wire clkfb_bufg;

    wire mmcm_locked;

    wire reset_async;
    logic [1:0] rst_sync;
    wire rst;

    logic tohost_seen;
    logic [31:0] tohost;
    logic [31:0] trap_pc_q;
    logic [3:0] trap_cause_q;
    logic halted;
    logic pass;
    logic fail;
    logic bus_err;

    assign reset_async = !reset_n | !mmcm_locked;
    assign led1_b = bus_err;

    always_ff @(posedge clk_25mhz or posedge reset_async) begin
        if (reset_async)
            rst_sync <= 2'b11;
        else
            rst_sync <= {rst_sync[0], 1'b0};
    end

    assign rst = rst_sync[1];
    //------------------------------------------------------
    // Explain: how to see LED
    // sw               00                         01              10           11
    // LD4           mark_seen                  tohost[1]       cause[0]     heartbeat
    // LD5              PASS                    tohost[2]       cause[1]    tohost_seen
    // LD6     cause!=EBREAK but wrong          tohost[3]       cause[2]     core_rst
    // LD7             halted                   tohost[4]       cause[3]    MMCM locked
    //------------------------------------------------------
    logic [24:0] heartbeat_cnt;
    logic heartbeat;
    always_ff @(posedge clk_25mhz) begin
        if (rst) heartbeat_cnt <= '0;
        else heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end
    assign heartbeat = heartbeat_cnt[24]; // 25MHz f = 0.645Hz T = 1.34s
    always_comb begin
        unique case (sw)
            2'b00: led = {
                halted,
                error_trap,
                pass,
                mark_seen
            };

            2'b01: led = tohost[4:1];
            2'b10: led = trap_cause_q[3:0];
            2'b11: led = {
                mmcm_locked,
                rst,
                tohost_seen,
                heartbeat
            };
            default: led = 4'b0000;
        endcase
    end

    // RGB state light, useless but visiable :)
    localparam int unsigned TIMEOUT_CYCLES = 2_500_000;
    logic heartbeat_dim;
    logic timeout_blink;
    logic [21:0] timeout_cnt;
    logic timeout;
    assign timeout_blink = heartbeat_cnt[23];
    assign heartbeat_dim = (heartbeat_cnt[24:21] == 4'b0000);
    always_ff @(posedge clk_25mhz) begin
        if (rst) begin
            timeout_cnt <= '0;
            timeout     <= 1'b0;
        end else if (!halted && !timeout) begin
            if (timeout_cnt == TIMEOUT_CYCLES - 1) begin
                timeout <= 1'b1;
            end else begin
                timeout_cnt <= timeout_cnt + 1'b1;
            end
        end
    end

    assign led0_r = 1'b0;
    assign led0_g = heartbeat_dim;
    assign led0_b = 1'b0;
    assign led1_r = timeout ? timeout_blink : fail;
    assign led1_g = 1'b0;

    MMCME2_BASE #(
        .CLKIN1_PERIOD      (10.0),
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT_F    (10.0),
        .CLKOUT0_DIVIDE_F   (40.0)
    ) u_mmcm (
        .CLKIN1     (clk_100mhz),

        .CLKFBIN    (clkfb_bufg),
        .CLKFBOUT   (clkfb_mmcm),

        .CLKOUT0    (clk25_mmcm),

        .LOCKED     (mmcm_locked),

        .RST        (1'b0),
        .PWRDWN     (1'b0)
    );

    BUFG u_clkfb_bufg (
        .I(clkfb_mmcm),
        .O(clkfb_bufg)
    );

    BUFG u_clk25_bufg (
        .I(clk25_mmcm),
        .O(clk_25mhz)
    );

    fpga_sys u_sys (
        .clk(clk_25mhz),
        .rst(rst),
        .halted(halted),
        .trap_cause_q(trap_cause_q),
        .trap_pc_q(trap_pc_q),
        .tohost_seen(tohost_seen),
        .tohost(tohost),
        .pass(pass),
        .fail(fail),
        .mark_seen(mark_seen),
        .error_trap(error_trap),
        .bus_err(bus_err)
    );
endmodule