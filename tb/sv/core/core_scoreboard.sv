`timescale 1ns/1ps

module core_scoreboard;

    import core_verif_pkg::*;

    task automatic check(
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
            $fatal(1);
        end

        foreach (expected[i]) begin
            case (expected[i].kind)

                MEM_EXPECT_WRITE: begin
                    if (actual[i].is_write !== 1'b1)begin
                        $error("[%0d] WRITE: expected a write transaction", i);
                        errors++;
                    end
                    if (actual[i].addr !== expected[i].addr) begin
                        $error("[%0d] WRITE: addr mismatch, exp=0x%08h, act=0x%08h",
                                i, expected[i].addr, actual[i].addr);
                        errors++;
                    end
                    if (actual[i].wdata !== expected[i].data) begin
                        $error("[%0d] WRITE: wdata mismatch, exp=0x%08h, act=0x%08h",
                                i, expected[i].data, actual[i].wdata);
                        errors++;
                    end
                    if (actual[i].wstrb !== expected[i].wstrb) begin
                        for (int b = 0; b < 4; b++) begin
                            if (actual[i].wstrb[b] !== expected[i].wstrb[b])
                                $error("[%0d] WRITE: wstrb[%0d] mismatch at byte addr 0x%08h, exp=%b, act=%b",
                                        i, b, expected[i].addr + b,
                                        expected[i].wstrb[b], actual[i].wstrb[b]);
                        end
                        errors++;
                    end
                end

                MEM_EXPECT_READ: begin
                    if (actual[i].is_read !== 1'b1)begin
                        $error("[%0d] READ: expected a read transaction", i);
                        errors++;
                    end

                    if (actual[i].addr  !== expected[i].addr) begin
                        $error("[%0d] READ: addr mismatch, exp=0x%08h, act=0x%08h",
                                i, expected[i].addr, actual[i].addr);
                        errors++;
                    end
                    if (actual[i].rdata !== expected[i].data) begin
                        $error("[%0d] READ: rdata mismatch, exp=0x%08h, act=0x%08h",
                                i, expected[i].data, actual[i].rdata);
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

        if (errors != 0)
            $fatal(1, "SCOREBOARD FAIL: %s, errors=%0d", test_name, errors);

        $display("SCOREBOARD PASS: %s (%0d transactions)",
                test_name, actual.size());
    endtask

    task automatic check_signature_word(
        input string       test_name,
        input logic [31:0] addr,
        input logic [31:0] expected,
        input logic [31:0] actual,
        input logic [31:0] pc
    );
        if (actual !== expected) begin
            $fatal(1,
                "SIGNATURE FAIL: %s addr=0x%08h exp=0x%08h act=0x%08h pc=0x%08h",
                test_name, addr, expected, actual, pc
            );
        end
        $display("SIGNATURE PASS: %s addr=0x%08h data=0x%08h pc=0x%08h",
                test_name, addr, actual, pc);
    endtask
endmodule
