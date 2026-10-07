`timescale 1ns/1ps

module pipeline_scoreboard;

    import pipeline_verif_pkg::*;

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
            logic [31:0] mask;
            mask = {
                {8{expected[i].wstrb[3]}},
                {8{expected[i].wstrb[2]}},
                {8{expected[i].wstrb[1]}},
                {8{expected[i].wstrb[0]}}
            };
        
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
                    if ((actual[i].wdata & mask) !== (expected[i].data & mask)) begin
                        $error("[%0d] WRITE: masked wdata mismatch, mask=0x%08h exp=0x%08h act=0x%08h pc=0x%08h",
                                i, mask,
                                expected[i].data & mask,
                                actual[i].wdata & mask,
                                actual[i].pc);
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
            $display("REGFILE FAIL: %s errors=%0d", test_name, errors);
            return 1'b0;
        end
        $display("REGFILE PASS: %s (x1..x31 match)", test_name);
        return 1'b1;
    endfunction

    function automatic bit check_retire(
        input string       name,
        input int unsigned dut_n, iss_n,
        input logic [31:0] dut_pc, iss_pc
    );
        bit ok = 1'b1;
        if (dut_n  !== iss_n)  begin $error("%s RETIRED  dut=%0d iss=%0d",         name, dut_n,  iss_n);  ok = 0; end
        if (dut_pc !== iss_pc) begin $error("%s FINAL-PC dut=0x%08h iss=0x%08h",   name, dut_pc, iss_pc); ok = 0; end
        return ok;
    endfunction

    function automatic bit check_commits(
        input string name,
        const ref commit_t dut_commits[$],
        const ref commit_t iss_commits[$]
    );
        bit ok = 1'b1;
        if (dut_commits.size() !== iss_commits.size()) begin
            $error("%s COMMITS size mismatch: dut=%0d iss=%0d", name, dut_commits.size(), iss_commits.size());
            ok = 0;
        end
        for (int i = 0; i < dut_commits.size(); i++) begin
            if (!commit_equal(dut_commits[i], iss_commits[i])) begin
                $error("%s COMMITS[%0d] mismatch, DUT: PC=0x%08h, INSTR=0x%08h, NEXT_PC=0x%08h, RD_WE=%b, RD_ADDR=%0d, RD_DATA=0x%08h. \nISS: PC=0x%08h, INSTR=0x%08h, NEXT_PC=0x%08h, RD_WE=%b, RD_ADDR=%0d, RD_DATA=0x%08h", 
                                                  name, i, dut_commits[i].pc, dut_commits[i].instr, dut_commits[i].next_pc, dut_commits[i].rd_we, dut_commits[i].rd_addr, dut_commits[i].rd_data,
                                                  iss_commits[i].pc, iss_commits[i].instr, iss_commits[i].next_pc, iss_commits[i].rd_we, iss_commits[i].rd_addr, iss_commits[i].rd_data);
                ok = 0;
            end
        end
        return ok;
    endfunction
    // will report fake mismatch when rd_We == 0, DUT's rd_data is WB mux(don't care).
    function automatic bit commit_equal(
        input commit_t dut,
        input commit_t iss
    );
    return
        (dut.pc      === iss.pc)      &&
        (dut.instr   === iss.instr)   &&
        (dut.next_pc === iss.next_pc) &&
        (dut.rd_we   === iss.rd_we)   &&
        ((dut.rd_we == 1'b0) || ((dut.rd_we == 1'b1) && (dut.rd_addr === iss.rd_addr) && (dut.rd_data === iss.rd_data)));
    endfunction

    function automatic bit check_addr_base(
        input string name,
        input logic [31:0] addr,
        input logic [31:0] data_base
    );
        bit ok = 1'b1;
        if (addr[31:10] != data_base[31:10]) begin
            $error("txn addr %08h outside data window %08h", addr, data_base);
            ok = 1'b0;
        end
        return ok;
    endfunction
endmodule
