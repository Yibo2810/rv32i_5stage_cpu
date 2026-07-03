`timescale 1ns/1ps

module core_scoreboard;

    import core_verif_pkg::*;

    function automatic bit check(
        input string test_name,
        const ref core_mem_expect_t  expected[$],
        const ref core_mem_txn_t actual[$]
    );
        int unsigned errors = 0; //only for automatic
        if (actual.size() != expected.size()) begin
            $display(
                "SCOREBOARD FAIL: %s expected %0d transactions, got %0d",
                test_name,
                expected.size(),
                actual.size()
            );
            return 1'b0;
        end

        foreach (expected[i]) begin
            case (expected[i].kind)
                MEM_EXPECT_WRITE: begin
                    if (actual[i].is_write !== 1'b1)begin
                        $error("[%0d] WRITE: expected a write transaction, pc=0x%08h", i, actual[i].pc);
                        errors++;
                    end
                    if (actual[i].addr !== expected[i].addr) begin
                        $error("[%0d] WRITE: addr mismatch, exp=0x%08h, act=0x%08h, pc=0x%08h",
                                i, expected[i].addr, actual[i].addr, actual[i].pc);
                        errors++;
                    end
                    if (actual[i].wdata !== expected[i].data) begin
                        $error("[%0d] WRITE: wdata mismatch, exp=0x%08h, act=0x%08h, pc=0x%08h",
                                i, expected[i].data, actual[i].wdata, actual[i].pc);
                        errors++;
                    end
                    if (actual[i].wstrb !== expected[i].wstrb) begin
                        for (int b = 0; b < 4; b++) begin
                            if (actual[i].wstrb[b] !== expected[i].wstrb[b])
                                $error("[%0d] WRITE: wstrb[%0d] mismatch at byte addr 0x%08h, exp=%b, act=%b, pc=0x%08h",
                                        i, b, expected[i].addr + b,
                                        expected[i].wstrb[b], actual[i].wstrb[b], actual[i].pc);
                        end
                        errors++;
                    end
                end

                MEM_EXPECT_READ: begin
                    if (actual[i].is_read !== 1'b1)begin
                        $error("[%0d] READ: expected a read transaction, pc=0x%08h", i, actual[i].pc);
                        errors++;
                    end

                    if (actual[i].addr  !== expected[i].addr) begin
                        $error("[%0d] READ: addr mismatch, exp=0x%08h, act=0x%08h, pc=0x%08h",
                                i, expected[i].addr, actual[i].addr, actual[i].pc);
                        errors++;
                    end
                    if (actual[i].rdata !== expected[i].data) begin
                        $error("[%0d] READ: rdata mismatch, exp=0x%08h, act=0x%08h, pc=0x%08h",
                                i, expected[i].data, actual[i].rdata, actual[i].pc);
                        errors++;
                    end
                end

                default: begin
                    $display(
                        "SCOREBOARD FAIL: %s TXN[%0d] invalid expected kind=%b",
                        test_name,
                        i,
                        expected[i].kind
                    );
                    errors++;
                end
            endcase
        end

        if (errors != 0) begin
            $display("SCOREBOARD FAIL: %s, errors=%0d", test_name, errors);
            return 1'b0;
        end

        $display("SCOREBOARD PASS: %s (%0d transactions)",
                test_name, actual.size());
        return 1'b1;
    endfunction

    function automatic bit check_regfile(
        input string       test_name,
        input logic [31:0] dut_regs[0:31],
        input logic [31:0] iss_regs[0:31]
    );
        int unsigned errors = 0;
        for (int i = 1; i < 32; i++) begin
            if (dut_regs[i] !== iss_regs[i]) begin
                $error("REGFILE mismatch x%0d: dut=0x%08h iss=0x%08h",
                        i, dut_regs[i], iss_regs[i]);
                errors++;
            end
        end
        if (errors != 0) begin
            $display(1, "REGFILE FAIL: %s errors=%0d", test_name, errors);
            return 1'b0;
        end
        $display("REGFILE PASS: %s (x1..x31 match)", test_name);
        return 1'b1;
    endfunction

    function automatic bit check_signature_word(
        input string       test_name,
        input logic [31:0] addr,
        input logic [31:0] expected,
        input logic [31:0] actual,
        input logic [31:0] pc
    );
        if (actual !== expected) begin
            $display("SIGNATURE FAIL: %s addr=0x%08h exp=0x%08h act=0x%08h pc=0x%08h",
                test_name, addr, expected, actual, pc);
            return 1'b0;
        end
        $display("SIGNATURE PASS: %s addr=0x%08h data=0x%08h pc=0x%08h",
                test_name, addr, actual, pc);
        return 1'b1;
    endfunction
endmodule
