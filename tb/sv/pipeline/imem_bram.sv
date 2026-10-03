`timescale 1ns/1ps
// TB-only instruction memory model (not synthesizable).
module imem_bram #(
  parameter int DEPTH     = 256,
  parameter int MAX_DELAY = 5
) (
  input  logic        clk, rst,
  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_addr,
  output logic        rsp_valid,
  input  logic        rsp_ready,
  output logic [31:0] rsp_rdata
);
  localparam int AW = $clog2(DEPTH);
  logic [31:0]   mem [DEPTH];
  logic [AW-1:0] idx;
  logic          fire;
  logic          rsp_fire;
  logic          busy_q;
  logic          ready_rand_q;
  int unsigned   delay_q;
  int            seed_q = 1;
  int            rng_q;

  assign idx       = req_addr[AW+1:2];
  assign rsp_fire  = rsp_valid && rsp_ready;
  assign req_ready = (!busy_q || rsp_fire) && ready_rand_q;
  assign fire      = req_valid && req_ready;

  initial for (int k = 0; k < DEPTH; k++) mem[k] = 32'h0010_0073;

  function automatic void reseed(input int s);
    seed_q = s;
  endfunction

  always_ff @(posedge clk) begin
    int s;
    int unsigned d;
    if (rst) begin
      rng_q        <= seed_q;
      ready_rand_q <= 1'b0;
      busy_q       <= 1'b0;
      delay_q      <= '0;
      rsp_valid    <= 1'b0;
      rsp_rdata    <= '0;
    end else begin
      s = rng_q;
      ready_rand_q <= ($dist_uniform(s, 0, 4) != 0);   // ~80% ready
      // ~60% zero-wait (keeps instructions adjacent -> hazards), else 1..MAX_DELAY
      d = ($dist_uniform(s, 0, 9) < 6) ? 0 : $dist_uniform(s, 1, MAX_DELAY);
      rng_q <= s;

      // 1) current response leaves
      if (rsp_fire) begin
        rsp_valid <= 1'b0;
        busy_q    <= 1'b0;
      end

      // 2) accepted but not yet presented: count down
      if (busy_q && !rsp_valid) begin
        if (delay_q <= 1) rsp_valid <= 1'b1;
        if (delay_q != 0) delay_q   <= delay_q - 1;
      end

      // 3) new request, last so it wins over 1) in the same cycle
      if (fire) begin
        busy_q    <= 1'b1;
        rsp_rdata <= mem[idx];
        delay_q   <= d;
        rsp_valid <= (d == 0);
      end
    end
  end
endmodule
`default_nettype wire