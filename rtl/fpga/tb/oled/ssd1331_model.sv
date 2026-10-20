`timescale 1ns/1ps
// Behavioral SSD1331 (the controller on the Pmod OLEDrgb), enough for our flow:
//   - SPI mode 3 receiver: shifts mosi in on sclk rising edges while cs_n = 0, MSB first;
//     D/C# is sampled with the 8th bit
//   - command parser with the parameter count of every command the Digilent init sends
//   - 96x64 RGB565 GDDRAM, column/row window (15h / 75h), horizontal increment with wrap,
//     clear window (25h), display on/off (AFh/AEh)
// It does not model remap (A0h) orientation: pixel (col,row) is stored as written.
// Byte log (bytes/dcs) is public so a TB can check the exact stream.
module ssd1331_model (
    input logic cs_n,
    input logic sclk,
    input logic mosi,
    input logic dc,
    input logic res_n,
    input logic vccen,
    input logic pmoden
);
    localparam int W = 96, H = 64;

    logic [15:0] fb [H][W];
    logic [7:0]  bytes[$];
    bit          dcs[$];
    bit          display_on = 1'b0;
    int unsigned bad_cmds   = 0;
    int unsigned pixels     = 0;

    // window and write pointer
    int c0 = 0, c1 = W-1, r0 = 0, r1 = H-1, col = 0, row = 0;

    // command in progress
    logic [7:0] cmd;
    logic [7:0] par[4];
    int         need = 0, have = 0;
    logic [7:0] pix_hi;
    bit         pix_half = 1'b0;

    function automatic int params_of(input logic [7:0] c);
        case (c)
            8'hAE, 8'hAF, 8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'h2E, 8'h2F, 8'hE3, 8'hBC, 8'hBD: return 0;
            8'hFD, 8'hA0, 8'hA1, 8'hA2, 8'hA8, 8'hAD, 8'hB0, 8'hB1, 8'hB3,
            8'h8A, 8'h8B, 8'h8C, 8'hBB, 8'hBE, 8'h87, 8'h81, 8'h82, 8'h83:     return 1;
            8'h15, 8'h75:                                                      return 2;
            8'h25:                                                             return 4;
            default:                                                           return -1;
        endcase
    endfunction

    task automatic exec_cmd();
        case (cmd)
            8'h15: begin c0 = par[0]; c1 = par[1]; col = c0; end
            8'h75: begin r0 = par[0]; r1 = par[1]; row = r0; end
            8'h25: for (int r = par[1]; r <= par[3] && r < H; r++)
                       for (int c = par[0]; c <= par[2] && c < W; c++) fb[r][c] = 16'h0000;
            8'hAF: display_on = 1'b1;
            8'hAE: display_on = 1'b0;
            default: ;
        endcase
    endtask

    task automatic on_byte(input logic [7:0] b, input bit d);
        bytes.push_back(b);
        dcs.push_back(d);
        if (d) begin
            if (!pix_half) begin
                pix_hi   = b;
                pix_half = 1'b1;
            end else begin
                fb[row][col] = {pix_hi, b};
                pixels++;
                pix_half = 1'b0;
                if (col >= c1) begin
                    col = c0;
                    row = (row >= r1) ? r0 : row + 1;
                end else begin
                    col++;
                end
            end
        end else if (need > have) begin
            par[have] = b;
            have++;
            if (have == need) exec_cmd();
        end else begin
            cmd  = b;
            have = 0;
            need = params_of(b);
            if (need < 0) begin
                bad_cmds++;
                $display("SSD1331 MODEL: unknown command %02h", b);
                need = 0;
            end else if (need == 0) begin
                exec_cmd();
            end
        end
    endtask

    logic [7:0]  rx;
    int unsigned nbits = 0;
    always @(posedge sclk) if (cs_n === 1'b0) begin
        rx = {rx[6:0], mosi};
        nbits++;
        if (nbits == 8) begin
            on_byte(rx, dc);
            nbits = 0;
        end
    end
    always @(posedge cs_n) nbits = 0;

    initial for (int r = 0; r < H; r++) for (int c = 0; c < W; c++) fb[r][c] = 16'hxxxx;

    // P3 PPM, RGB565 expanded to 8 bits per channel; unwritten pixels are drawn magenta
    task automatic dump_ppm(input string path);
        int fd = $fopen(path, "w");
        if (fd == 0) begin
            $display("SSD1331 MODEL: cannot open %s", path);
            return;
        end
        $fwrite(fd, "P3\n%0d %0d\n255\n", W, H);
        for (int r = 0; r < H; r++) begin
            for (int c = 0; c < W; c++) begin
                logic [15:0] p = fb[r][c];
                if ($isunknown(p)) $fwrite(fd, "255 0 255 ");
                else $fwrite(fd, "%0d %0d %0d ", {p[15:11], p[15:13]}, {p[10:5], p[10:9]}, {p[4:0], p[4:2]});
            end
            $fwrite(fd, "\n");
        end
        $fclose(fd);
    endtask
endmodule
