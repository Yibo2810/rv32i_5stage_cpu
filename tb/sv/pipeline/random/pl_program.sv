class pl_program;
    rand int unsigned instr_count;
    pl_instr instrs[$];
    localparam int JUMP_WINDOW = 8;
    localparam int IMEM_WORDS = 256;
    localparam int LOOP_N_MAX = 8;
    localparam int LOOP_K_MAX = 6;
    localparam int LOOP_PCT   = 20;
    logic [31:0] text_base = 32'h0;   // instrs[0] address = core RESET_PC; only emit_jalr uses it

    function void load_imem(ref logic [31:0] imem [0:255]);
        foreach (instrs[k]) begin
            imem[k] = instrs[k].encode();
    end
    endfunction

    function void build(int seed);
        instr_kind_e br_kinds[6] = '{INSTR_BEQ, INSTR_BNE, INSTR_BLT, INSTR_BGE, INSTR_BLTU, INSTR_BGEU};
        if (text_base[11:0] != 12'h0)
            $fatal(1, "pl_program: text_base %08h must be 4 KB aligned (lui + addi jalr target)", text_base);
        this.srandom(seed);
        process::self().srandom(seed);
        instrs.delete();

        if (!std::randomize(instr_count) with { instr_count inside {[20:40]}; })
            $fatal(1, "instr_count randomize failed");

        while (instrs.size() < instr_count) begin
            randcase
                45: push_straightline();
                15: begin
                    int unsigned N = $urandom_range(LOOP_N_MAX, 0);
                    int unsigned K = $urandom_range(LOOP_K_MAX, 1);
                    if (instrs.size() + (K + 4) <= IMEM_WORDS)
                        emit_bounded_loop(N, K);
                    else
                        push_straightline();
                end
                25: begin
                    instr_kind_e br = br_kinds[$urandom_range(5, 0)];
                    bit          tk = $urandom_range(1, 0);
                    int unsigned M = $urandom_range(3, 1);
                    logic [1:0]  prelude;
                    randcase
                        25: prelude = 2'b00;
                        25: prelude = 2'b01;
                        25: prelude = 2'b10;
                        25: prelude = 2'b11;
                    endcase
                            if (instrs.size() + (M + 5) <= IMEM_WORDS)
                                emit_fwd_branch(br, tk, M, prelude);
                            else
                                push_straightline();
                end
                5: begin
                    int unsigned M = $urandom_range(3, 1);
                    bit jal_sw;
                    randcase
                        50: jal_sw = 1'b0;
                        50: jal_sw = 1'b1;
                    endcase
                    if (instrs.size() + (M + 5) <= IMEM_WORDS)
                        emit_jalr(M, jal_sw);
                    else
                        push_straightline();
                end
                10: begin
                    if (instrs.size() + 4 <= IMEM_WORDS)
                        randcase
                            50: emit_store_load_pair();
                            50: emit_mem_base();
                        endcase
                end
            endcase
        end
    endfunction

    function automatic pl_instr mk_fixed(
        instr_kind_e kind, logic [4:0] rd, logic [4:0] rs1, logic [4:0] rs2, logic [31:0] imm32
    );
        pl_instr t = new();
        t.kind  = kind;
        t.rd    = rd;
        t.rs1   = rs1;
        t.rs2   = rs2;
        t.imm32 = imm32;
        t.locked = 1'b1;
        return t;
    endfunction

    function automatic void push_straightline();
        logic [4:0] c;
        pl_instr t = new();
        bit do_bias = ($urandom_range(99, 0) < 50) && pick_recent_rd(c);
            if (!t.randomize() with {
                !(kind inside {INSTR_BEQ, INSTR_BNE, INSTR_BLT, INSTR_BGE, INSTR_BLTU, INSTR_BGEU, INSTR_JAL, INSTR_JALR});
                if (do_bias) {
                !(kind inside {INSTR_LB, INSTR_LH, INSTR_LW, INSTR_LBU, INSTR_LHU, INSTR_SB, INSTR_SH, INSTR_SW}) -> rs1 ==c;
                (kind inside {INSTR_SB, INSTR_SH, INSTR_SW}) -> rs2 == c;
                }
            })                
            $fatal(1, "loop body and hazard/forwarding randomize failed");
            t.locked = 1'b0;
            instrs.push_back(t);
    endfunction

    function automatic void emit_bounded_loop (int unsigned N, int unsigned K);
        int base, loop_top, back_idx, loop_end;
        int guard_off, back_off;
        bit use_branch_backedge;
        int unsigned loop_n;

        use_branch_backedge = $urandom_range(1, 0);
        loop_n = N;

        // Make the branch-backedge variant actually take at least once.
        if (use_branch_backedge && (loop_n < 2))
            loop_n = 2;

        base     = instrs.size();
        loop_top = base + 1;
        back_idx = base + 3 + K;
        loop_end = base + 4 + K;

        guard_off = (loop_end - loop_top) * 4;
        back_off  = (loop_top - back_idx) * 4;

        if (back_idx + back_off/4 != loop_top)
            $fatal(1, "loop back-edge target wrong");

        instrs.push_back(mk_fixed(INSTR_ADDI, 5'd31, 5'd0,  5'd0, loop_n));
        instrs.push_back(mk_fixed(INSTR_BEQ,  5'd0,  5'd31, 5'd0, guard_off));
        for (int j = 0; j < K; j++) push_straightline();

        instrs.push_back(mk_fixed(INSTR_ADDI, 5'd31, 5'd31, 5'd0, -1));

        if (use_branch_backedge)
            instrs.push_back(mk_fixed(INSTR_BNE, 5'd0, 5'd31, 5'd0, back_off));
        else
            instrs.push_back(mk_fixed(INSTR_JAL, 5'd0, 5'd0,  5'd0, back_off));
    endfunction

    function automatic void emit_mem_base();
        logic [4:0]  xB   = 5'd25;
        logic [4:0]  xT   = 5'd24;
        logic [4:0]  xD   = 5'd23;
        int unsigned base = 4 * $urandom_range(64, 0);
        int unsigned off  = 4 * $urandom_range(63, 0);
        int unsigned ptr  = 4 * $urandom_range(127, 0);
        bit          st   = $urandom_range(1, 0);
        instr_kind_e k    = st ? INSTR_SW : INSTR_LW;
        logic [4:0]  rd   = st ? 5'd0 : xD;

        randcase
            40: begin
                instrs.push_back(mk_fixed(INSTR_ADDI, xB, 5'd0, 5'd0, base));
                instrs.push_back(mk_fixed(k, rd, xB, xD, off));
            end
            30: begin
                instrs.push_back(mk_fixed(INSTR_ADDI, xB, 5'd0, 5'd0, base));
                instrs.push_back(mk_fixed(INSTR_ADDI, 5'd0, 5'd0, 5'd0, 0));
                instrs.push_back(mk_fixed(k, rd, xB, xD, off));
            end
            30: begin
                instrs.push_back(mk_fixed(INSTR_ADDI, xT, 5'd0, 5'd0, base));
                instrs.push_back(mk_fixed(INSTR_SW,   5'd0, 5'd0, xT, ptr));
                instrs.push_back(mk_fixed(INSTR_LW,   xB, 5'd0, 5'd0, ptr));
                instrs.push_back(mk_fixed(k, rd, xB, xD, off));
            end
        endcase
    endfunction

    function automatic void emit_store_load_pair();
        logic [4:0]  xData = 5'd27;
        logic [4:0]  xLoad = 5'd26;
        int unsigned mode;
        int unsigned addr;
        logic [31:0] value;
        logic [31:0] hi_imm;
        logic [31:0] lo_imm;
        instr_kind_e st_kind;
        instr_kind_e ld_kind;

        mode  = $urandom_range(2, 0);
        value = $urandom();
        if (value == 32'b0)
            value = 32'h0000_0001;

        case (mode)
            0: begin
                st_kind = INSTR_SB;
                if ($urandom_range(1, 0)) ld_kind = INSTR_LBU;
                else                      ld_kind = INSTR_LB;

                addr = $urandom_range(508, 0);
                if (value[7:0] == 8'h00)
                    value[7:0] = 8'h5a;
            end

            1: begin
                st_kind = INSTR_SH;
                if ($urandom_range(1, 0)) ld_kind = INSTR_LHU;
                else                      ld_kind = INSTR_LH;

                addr = 2 * $urandom_range(254, 0);
                if (value[15:0] == 16'h0000)
                    value[15:0] = 16'h5aa5;
            end

            default: begin
                st_kind = INSTR_SW;
                ld_kind = INSTR_LW;

                addr = 4 * $urandom_range(127, 0);
            end
        endcase

        hi_imm = value + 32'h0000_0800;
        lo_imm = {{20{value[11]}}, value[11:0]};

        instrs.push_back(mk_fixed(INSTR_LUI,  xData, 5'd0,  5'd0,  hi_imm));
        instrs.push_back(mk_fixed(INSTR_ADDI, xData, xData, 5'd0,  lo_imm));
        instrs.push_back(mk_fixed(st_kind,    5'd0,  5'd0,  xData, addr));
        instrs.push_back(mk_fixed(ld_kind,    xLoad, 5'd0,  5'd0,  addr));
    endfunction

    function automatic void emit_fwd_branch(instr_kind_e br, bit taken, int unsigned M, logic [1:0] prelude);
        logic [4:0] S1 = 5'd29;
        logic [4:0] S2 = 5'd30;
        int base, br_idx, skip_end, br_off;
        int a, b;

        base     = instrs.size();
        br_idx   = base + 2;
        skip_end = base + 3 + M;
        br_off   = (M + 1) * 4;

        pick_operands(br, taken, a, b);
        if (prelude == 2'b00) begin
            instrs.push_back(mk_fixed(INSTR_ADDI, S1, 5'd0, 5'd0, a));
            instrs.push_back(mk_fixed(INSTR_ADDI, S2, 5'd0, 5'd0, b));
            instrs.push_back(mk_fixed(br, 5'd0, S1, S2, br_off));
        end else if (prelude == 2'b01) begin
            instrs.push_back(mk_fixed(INSTR_ADDI, S1, 5'd0, 5'd0, a));
            instrs.push_back(mk_fixed(INSTR_ADDI, S2, 5'd0, 5'd0, b));
            instrs.push_back(mk_fixed(INSTR_SB, 5'd0, 5'd0, 5'd0, 32));
            instrs.push_back(mk_fixed(br, 5'd0, S1, S2, br_off));
        end else if (prelude == 2'b10) begin
            instrs.push_back(mk_fixed(INSTR_ADDI, S1, 5'd0, 5'd0, a));
            instrs.push_back(mk_fixed(INSTR_SW, 5'd0, 5'd0, S1, 128));
            instrs.push_back(mk_fixed(INSTR_ADDI, S2, 5'd0, 5'd0, b));
            instrs.push_back(mk_fixed(INSTR_LW, S1, 5'd0, 5'd0, 128));
            instrs.push_back(mk_fixed(br, 5'd0, S1, S2, br_off));
        end else begin 
            instrs.push_back(mk_fixed(INSTR_ADDI, S2, 5'd0, 5'd0, b));
            instrs.push_back(mk_fixed(INSTR_ADDI, S1, 5'd0, 5'd0, a));
            instrs.push_back(mk_fixed(br, 5'd0, S1, S2, br_off));
         end
        for (int j = 0; j < M; j++) push_straightline();
    endfunction

    function automatic void emit_jalr(int unsigned M, bit jal_sw);
        logic [4:0] xS = 5'd28;
        logic [4:0] xT = 5'd27;
        int base, jalr_idx, land_idx, abs;
        int ext = (text_base != 32'h0);   // extra lui for the upper target bits
        base     = instrs.size();
        if (jal_sw == 1'b0) begin
            jalr_idx = base + 1 + ext;
            land_idx = base + 2 + M + ext;
            abs      = 4 * land_idx;
            if (abs > 2047) begin push_straightline(); return; end
            if (ext) begin
                instrs.push_back(mk_fixed(INSTR_LUI,  xS, 5'd0, 5'd0, text_base));
                instrs.push_back(mk_fixed(INSTR_ADDI, xS, xS,   5'd0, abs));
            end else
                instrs.push_back(mk_fixed(INSTR_ADDI, xS,   5'd0, 5'd0, abs));
                instrs.push_back(mk_fixed(INSTR_JALR, 5'd1, xS,   5'd0, 0));
        end 
        else if (jal_sw == 1'b1) begin
            jalr_idx = base + 3 + ext;
            land_idx = base + 4 + M + ext;
            abs      = 4 * land_idx;
            if (abs > 2047) begin push_straightline(); return; end
            if (ext) begin
                instrs.push_back(mk_fixed(INSTR_LUI,  xT, 5'd0, 5'd0, text_base));
                instrs.push_back(mk_fixed(INSTR_ADDI, xT, xT,   5'd0, abs));
            end else
                instrs.push_back(mk_fixed(INSTR_ADDI, xT,   5'd0, 5'd0, abs));
                instrs.push_back(mk_fixed(INSTR_SW, 5'd0, 5'd0, xT, 64));
                instrs.push_back(mk_fixed(INSTR_LW, xS, 5'd0, 5'd0, 64));
                instrs.push_back(mk_fixed(INSTR_JALR, 5'd1, xS,   5'd0, 0));
        end 
        for (int j = 0; j < M; j++) push_straightline();
    endfunction

    function automatic void pick_operands (
        input instr_kind_e br,
        input bit taken,
        output int signed  a,
        output int signed  b
        );

        unique case (br)
            INSTR_BEQ: begin
                if (taken) begin
                    a = 5;
                    b = 5;
                end
                else begin
                    a = 5;
                    b = 7;
                end
            end
            INSTR_BNE: begin
                if (taken) begin
                    a = 5;
                    b = 7;
                end
                else begin
                    a = 5;
                    b = 5;
                end
            end
            INSTR_BLT: begin
                if (taken) begin
                    a = -1;
                    b = 1;
                end
                else begin
                    a = 1;
                    b = -1;
                end
            end
            INSTR_BLTU: begin
                if (taken) begin
                    a = 1;
                    b = -1;
                end
                else begin
                    a = -1;
                    b = 1;
                end
            end
            INSTR_BGEU: begin
                if (taken) begin
                    a = -1;
                    b = 1;
                end
                else begin
                    a = 1;
                    b = -1;
                end
            end
            INSTR_BGE: begin
                if (taken) begin
                    a = 1;
                    b = -1;
                end
                else begin
                    a = -1;
                    b = 1;
                end
            end
            default: begin
                $fatal(1, "pick_operands: unsupported branch kind %0d", br);
            end
        endcase
    endfunction

    function automatic bit pick_recent_rd(output logic [4:0] r);
        logic [4:0] cands[$];
        for (int d = 1; d <= 3; d++) begin
            if (instrs.size() >= d && writes_rd(instrs[$-(d)+1].kind) && instrs[$-(d)+1].rd != 5'd0)
                cands.push_back(instrs[$-(d)+1].rd);
        end
        if (cands.size() == 0) begin r = 5'd0; return 1'b0; end
        r = cands[$urandom_range(cands.size()-1, 0)];
        return 1'b1;
    endfunction
endclass