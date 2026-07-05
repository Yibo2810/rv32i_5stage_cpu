class rv_program;
    rand int unsigned instr_count;
    rv_instr instrs[$];
    localparam int JUMP_WINDOW = 8;

    function void load_imem(ref logic [31:0] imem [0:255]);
        foreach (instrs[k]) begin
            imem[k] = instrs[k].encode();
    end
    endfunction

    function void fixup_control_flow();
        for (int k = 0; k < instr_count; k++) begin
            int lo, hi, target;
            lo = (k - JUMP_WINDOW < 0) ? 0 : k - JUMP_WINDOW;
            hi = (k + JUMP_WINDOW > instr_count) ? instr_count : k + JUMP_WINDOW;
            if (instrs[k].kind inside {INSTR_BEQ, INSTR_BNE, INSTR_BLT, INSTR_BGE, INSTR_BLTU, INSTR_BGEU, INSTR_JAL}) begin
                int target;
                target = $urandom_range(hi, lo);
                instrs[k].imm32 = (target - k) * 4;
            end
            else if (instrs[k].kind == INSTR_JALR) begin
                int target;
                target = $urandom_range(hi, lo);
                instrs[k].rs1   = 5'd0;
                instrs[k].imm32 = target * 4;
            end
        end
    endfunction

    function void build(int seed);
        rv_instr t;
        this.srandom(seed);
        process::self().srandom(seed);
        instrs.delete();

        if (!std::randomize(instr_count) with { instr_count inside {[20:40]}; })
            $fatal(1, "instr_count randomize failed");
            
        for (int k = 0; k < instr_count; k++) begin
            t = new();
            if (!t.randomize()) $fatal(1, "instr randomize failed @%0d", k);
            instrs.push_back(t);
        end
        fixup_control_flow();
    endfunction
endclass //rv_program