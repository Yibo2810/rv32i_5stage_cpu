class rv_ref_model;
    logic [31:0] regs[32];
    logic [31:0] dmem[256];
    //logic [31:0] imem[256];
    logic [31:0] pc;
    int unsigned retired;
    core_mem_expect_t expected_txns[$];
    localparam int WATCHDOG = 100000;

    function void reset();
        foreach(regs[i]) regs[i] = 32'b0;
        foreach (dmem[i]) dmem[i] = 32'b0;
        pc = 32'b0;
        expected_txns.delete();
    endfunction

    function void run_iss(const ref logic [31:0] img[0:255],
                          input int unsigned program_words = 256);
        int unsigned steps = 0;
        reset();
        while (steps < WATCHDOG) begin
            int unsigned idx = pc >> 2;
            logic [31:0] w;
            if (idx >= program_words) break;
            if (idx >= 256)
                $fatal(1, "ISS PC escaped imem: pc=%08h idx=%0d", pc, idx);
            if (pc[1:0] != 2'b00)
                $fatal(1, "ISS misaligned PC: pc=%08h", pc);
            w = img[idx];
            exec(w);
            steps++;
        end
        if (steps == WATCHDOG) $fatal(1, "ISS watchdog: program never terminated");
        retired = steps;
    endfunction

    function void exec(logic [31:0] w);
        logic [6:0]  opcode;
        logic [2:0]  funct3;
        logic [6:0]  funct7;
        logic [4:0]  rd;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [31:0] imm_i;
        logic [31:0] imm_s;
        logic [31:0] imm_b;
        logic [31:0] imm_u;
        logic [31:0] imm_j;
        logic [31:0] rs1_val;
        logic [31:0] rs2_val;
        logic [31:0] result;
        logic [31:0] addr;
        logic [31:0] data;
        logic [31:0] next_pc;
        logic        reg_we;

        opcode = w[6:0];
        funct3 = w[14:12];
        funct7 = w[31:25];
        rd     = w[11:7];
        rs1    = w[19:15];
        rs2    = w[24:20];

        imm_i = {{20{w[31]}}, w[31:20]};
        imm_s = {{20{w[31]}}, w[31:25], w[11:7]};
        imm_b = {{20{w[31]}}, w[7], w[30:25], w[11:8], 1'b0};
        imm_u = {w[31:12], 12'b0};
        imm_j = {{12{w[31]}}, w[19:12], w[20], w[30:21], 1'b0};
        rs1_val = regs[rs1];
        rs2_val = regs[rs2];

        result  = 32'b0;
        reg_we  = 1'b1;
        next_pc = pc + 32'd4;

        case (opcode)
            OPCODE_R_TYPE: begin
                case (funct3)
                    FUNCT3_ADD_SUB: begin
                        if (funct7 == FUNCT7_ADD)
                            result = rs1_val + rs2_val;
                        else if (funct7 == FUNCT7_SUB)
                            result = rs1_val - rs2_val;
                        else
                            $fatal(1, "ISS unsupported R-type ADD/SUB funct7: instr=%08h", w);
                    end
                    FUNCT3_SLL: begin
                        if (funct7 != FUNCT7_SLL)
                            $fatal(1, "ISS unsupported SLL funct7: instr=%08h", w);
                        result = rs1_val << rs2_val[4:0];
                    end
                    FUNCT3_SLT: begin
                        if (funct7 != FUNCT7_SLT)
                            $fatal(1, "ISS unsupported SLT funct7: instr=%08h", w);
                        result = ($signed(rs1_val) < $signed(rs2_val)) ? 32'd1 : 32'd0;
                    end
                    FUNCT3_SLTU: begin
                        if (funct7 != FUNCT7_SLTU)
                            $fatal(1, "ISS unsupported SLTU funct7: instr=%08h", w);
                        result = (rs1_val < rs2_val) ? 32'd1 : 32'd0;
                    end
                    FUNCT3_XOR: begin
                        if (funct7 != FUNCT7_XOR)
                            $fatal(1, "ISS unsupported XOR funct7: instr=%08h", w);
                        result = rs1_val ^ rs2_val;
                    end
                    FUNCT3_SRL: begin
                        if (funct7 == FUNCT7_SRL)
                            result = rs1_val >> rs2_val[4:0];
                        else if (funct7 == FUNCT7_SRA)
                            result = $signed(rs1_val) >>> rs2_val[4:0];
                        else
                            $fatal(1, "ISS unsupported SRL/SRA funct7: instr=%08h", w);
                    end
                    FUNCT3_OR: begin
                        if (funct7 != FUNCT7_OR)
                            $fatal(1, "ISS unsupported OR funct7: instr=%08h", w);
                        result = rs1_val | rs2_val;
                    end
                    FUNCT3_AND: begin
                        if (funct7 != FUNCT7_AND)
                            $fatal(1, "ISS unsupported AND funct7: instr=%08h", w);
                        result = rs1_val & rs2_val;
                    end
                    default:
                        $fatal(1, "ISS unsupported R-type funct3: instr=%08h", w);
                endcase
            end

            OPCODE_I_TYPE: begin
                case (funct3)
                    FUNCT3_ADDI:  result = rs1_val + imm_i;
                    FUNCT3_SLTI:  result = ($signed(rs1_val) < $signed(imm_i)) ? 32'd1 : 32'd0;
                    FUNCT3_SLTIU: result = (rs1_val < imm_i) ? 32'd1 : 32'd0;
                    FUNCT3_XORI:  result = rs1_val ^ imm_i;
                    FUNCT3_ORI:   result = rs1_val | imm_i;
                    FUNCT3_ANDI:  result = rs1_val & imm_i;
                    FUNCT3_SLLI: begin
                        if (funct7 != FUNCT7_SLLI)
                            $fatal(1, "ISS unsupported SLLI funct7: instr=%08h", w);
                        result = rs1_val << w[24:20];
                    end
                    FUNCT3_SRLI: begin
                        if (funct7 == FUNCT7_SRLI)
                            result = rs1_val >> w[24:20];
                        else if (funct7 == FUNCT7_SRAI)
                            result = $signed(rs1_val) >>> w[24:20];
                        else
                            $fatal(1, "ISS unsupported SRLI/SRAI funct7: instr=%08h", w);
                    end
                    default:
                        $fatal(1, "ISS unsupported I-type funct3: instr=%08h", w);
                endcase
            end

            OPCODE_LOAD: begin
                core_mem_expect_t txn;
                logic [1:0] off;
                txn.kind = MEM_EXPECT_READ;
                addr = rs1_val + imm_i;
                off = addr[1:0];
                data = dmem[addr[9:2]];
                txn.addr = addr;
                txn.data = data;
                txn.wstrb = 4'b0000;
                case (funct3)
                    FUNCT3_LB: begin
                        logic [7:0] b;
                        b = data[off*8 +: 8];
                        result = {{24{b[7]}}, b};
                    end
                    FUNCT3_LH: begin
                        logic [15:0] h;
                        h = data[off*8 +: 16];
                        result = {{16{h[15]}}, h};
                    end
                    FUNCT3_LW:
                        result = data;
                    FUNCT3_LBU: begin
                        logic [7:0] b;
                        b = data[off*8 +: 8];
                        result = {24'b0, b};
                    end
                    FUNCT3_LHU: begin
                        logic [15:0] h;
                        h = data[off*8 +: 16];
                        result = {16'b0, h};
                    end
                    default:
                        $fatal(1, "ISS unsupported LOAD funct3: instr=%08h", w);
                endcase
                expected_txns.push_back(txn);
            end

            OPCODE_STORE: begin
                core_mem_expect_t txn;
                logic [1:0] off;
                reg_we = 1'b0;
                txn.kind = MEM_EXPECT_WRITE;
                addr = rs1_val + imm_s;
                off = addr[1:0];
                txn.addr = addr;
                case (funct3)
                    FUNCT3_SB: begin
                        dmem[addr[9:2]][off*8 +: 8] = rs2_val[7:0];
                        txn.data = ({24'b0, rs2_val[7:0]} << (off*8));
                        txn.wstrb = (4'b0001 << off);
                    end
                    FUNCT3_SH: begin
                        dmem[addr[9:2]][off*8 +: 16] = rs2_val[15:0];
                        txn.data = ({16'b0, rs2_val[15:0]} << (off*8));
                        txn.wstrb = (4'b0011 << off);
                    end
                    FUNCT3_SW: begin
                        dmem[addr[9:2]] = rs2_val;
                        txn.data = rs2_val;
                        txn.wstrb = 4'b1111;
                    end
                    default:
                        $fatal(1, "ISS unsupported STORE funct3: instr=%08h", w);
                endcase
                expected_txns.push_back(txn);
            end

            OPCODE_BRANCH: begin
                reg_we = 1'b0;
                case (funct3)
                    FUNCT3_BEQ:  if (rs1_val == rs2_val) next_pc = pc + imm_b;
                    FUNCT3_BNE:  if (rs1_val != rs2_val) next_pc = pc + imm_b;
                    FUNCT3_BLT:  if ($signed(rs1_val) < $signed(rs2_val)) next_pc = pc + imm_b;
                    FUNCT3_BGE:  if ($signed(rs1_val) >= $signed(rs2_val)) next_pc = pc + imm_b;
                    FUNCT3_BLTU: if (rs1_val < rs2_val) next_pc = pc + imm_b;
                    FUNCT3_BGEU: if (rs1_val >= rs2_val) next_pc = pc + imm_b;
                    default:
                        $fatal(1, "ISS unsupported BRANCH funct3: instr=%08h", w);
                endcase
            end

            OPCODE_JAL: begin
                next_pc = pc + imm_j;
                result = pc + 32'd4;
            end

            OPCODE_JALR: begin
                next_pc = (rs1_val + imm_i) & 32'hffff_fffe;
                result = pc + 32'd4;
            end

            OPCODE_LUI:
                result = imm_u;

            OPCODE_AUIPC:
                result = pc + imm_u;

            OPCODE_SYSTEM: begin
                reg_we = 1'b0;
                if (!((funct3 == FUNCT3_ECALL_EBREAK) &&
                      ((w[31:20] == 12'h000) || (w[31:20] == 12'h001))))
                    $fatal(1, "ISS unsupported SYSTEM instr=%08h", w);
            end

            default:
                $fatal(1, "ISS unsupported opcode: instr=%08h", w);
        endcase

        if (reg_we)
            regs[rd] = result;
        regs[0] = 32'b0;
        pc = next_pc;
    endfunction

    function void step(rv_instr i);
        logic [31:0] rs1_val;
        logic [31:0] rs2_val;
        logic [31:0] result;
        logic [31:0] imm_u;
        logic [31:0] imm_i;
        logic [31:0] imm_b;
        logic [31:0] imm_j;
        logic [31:0] addr;
        logic [31:0] data;
        logic [31:0] next_pc;
        logic reg_we;

        imm_u = {i.imm32[31:12], 12'b0};
        imm_i = {{20{i.imm32[11]}}, i.imm32[11:0]};
        imm_b = {{19{i.imm32[12]}}, i.imm32[12:1], 1'b0};
        imm_j = {{11{i.imm32[20]}}, i.imm32[20:1], 1'b0};
        rs1_val = regs[i.rs1];
        rs2_val = regs[i.rs2];

        reg_we = 1'b1;
        next_pc = pc + 32'd4;

        case (i.kind)
            INSTR_ADD:  result = rs1_val + rs2_val;
            INSTR_SUB:  result = rs1_val - rs2_val;
            INSTR_AND:  result = rs1_val & rs2_val;
            INSTR_OR:   result = rs1_val | rs2_val;
            INSTR_XOR:  result = rs1_val ^ rs2_val;
            INSTR_SLL:  result = rs1_val << rs2_val[4:0];
            INSTR_SRL:  result = rs1_val >> rs2_val[4:0];
            INSTR_SRA:  result = $signed(rs1_val) >>> rs2_val[4:0];
            INSTR_SLT:  result = ($signed(rs1_val) < $signed(rs2_val)) ? 32'd1 : 32'd0;
            INSTR_SLTU: result = (rs1_val < rs2_val) ? 32'd1 : 32'd0;
            INSTR_ADDI: result = rs1_val + imm_i;
            INSTR_ANDI: result = rs1_val & imm_i;
            INSTR_ORI:  result = rs1_val | imm_i;
            INSTR_XORI: result = rs1_val ^ imm_i;
            INSTR_SLLI: result = rs1_val << imm_i[4:0];
            INSTR_SRLI: result = rs1_val >> imm_i[4:0];
            INSTR_SRAI: result = $signed(rs1_val) >>> imm_i[4:0];
            INSTR_SLTI: result = ($signed(rs1_val) < $signed(imm_i)) ? 32'd1 : 32'd0;
            INSTR_SLTIU: result = (rs1_val < imm_i) ? 32'd1 : 32'd0;
            INSTR_LB: begin
                core_mem_expect_t txn;
                logic [1:0] off;
                logic [7:0] b;
                txn.kind = MEM_EXPECT_READ;
                addr = rs1_val + imm_i;
                off = addr[1:0];
                data = dmem[addr[9:2]];
                b = data[off*8 +: 8];
                result = {{24{b[7]}}, b};
                txn.addr = addr;
                txn.data = data;
                txn.wstrb = 4'b0000;
                expected_txns.push_back(txn);
            end
            INSTR_LH: begin
                core_mem_expect_t txn;
                logic [1:0] off;
                logic [15:0] b;
                txn.kind = MEM_EXPECT_READ;
                addr = rs1_val + imm_i;
                off = addr[1:0];
                data = dmem[addr[9:2]];
                b = data[off*8 +: 16];
                result = {{16{b[15]}}, b};
                txn.addr = addr;
                txn.data = data;
                txn.wstrb = 4'b0000;
                expected_txns.push_back(txn);
            end
            INSTR_LW: begin
                core_mem_expect_t txn;
                txn.kind = MEM_EXPECT_READ;
                addr = rs1_val + imm_i;
                data = dmem[addr[9:2]];
                result = data;
                txn.addr = addr;
                txn.data = data;
                txn.wstrb = 4'b0000;
                expected_txns.push_back(txn);
            end
            INSTR_LBU: begin
                core_mem_expect_t txn;
                logic [1:0] off;
                logic [7:0] b;
                txn.kind = MEM_EXPECT_READ;
                addr = rs1_val + imm_i;
                off = addr[1:0];
                data = dmem[addr[9:2]];
                b = data[off*8 +: 8];
                result = {24'b0, b};
                txn.addr = addr;
                txn.data = data;
                txn.wstrb = 4'b0000;
                expected_txns.push_back(txn);
            end
            INSTR_LHU: begin
                core_mem_expect_t txn;
                logic [1:0] off;
                logic [15:0] b;
                txn.kind = MEM_EXPECT_READ;
                addr = rs1_val + imm_i;
                off = addr[1:0];
                data = dmem[addr[9:2]];
                b = data[off*8 +: 16];
                result = {16'b0, b};
                txn.addr = addr;
                txn.data = data;
                txn.wstrb = 4'b0000;
                expected_txns.push_back(txn);
            end
            INSTR_SB: begin
                core_mem_expect_t txn;
                logic [1:0] off;
                reg_we = 1'b0;
                txn.kind = MEM_EXPECT_WRITE;
                addr = rs1_val + imm_i;
                off = addr[1:0];
                dmem[addr[9:2]][off*8 +: 8] = rs2_val[7:0];
                txn.addr = addr;
                txn.data = ({24'b0, rs2_val[7:0]} << (off*8));
                txn.wstrb = (4'b0001 << off);
                expected_txns.push_back(txn);
            end
            INSTR_SH: begin
                core_mem_expect_t txn;
                logic [1:0] off;
                reg_we = 1'b0;
                txn.kind = MEM_EXPECT_WRITE;
                addr = rs1_val + imm_i;
                off = addr[1:0];
                dmem[addr[9:2]][off*8 +: 16] = rs2_val[15:0];
                txn.addr = addr;
                txn.data = ({16'b0, rs2_val[15:0]} << (off*8));
                txn.wstrb = (4'b0011 << off);
                expected_txns.push_back(txn);
            end
            INSTR_SW: begin
                core_mem_expect_t txn;
                reg_we = 1'b0;
                txn.kind = MEM_EXPECT_WRITE;
                addr = rs1_val + imm_i;
                dmem[addr[9:2]] = rs2_val;
                txn.addr = addr;
                txn.data = rs2_val;
                txn.wstrb = 4'b1111;
                expected_txns.push_back(txn);
            end
            INSTR_BEQ: begin
                reg_we = 1'b0;
                if (rs1_val == rs2_val)
                    next_pc = pc + imm_b;
            end
            INSTR_BNE: begin
                reg_we = 1'b0;
                if (rs1_val != rs2_val)
                    next_pc = pc + imm_b;
            end
            INSTR_BLT: begin
                reg_we = 1'b0;
                if ($signed(rs1_val) < $signed(rs2_val))
                    next_pc = pc + imm_b;
            end
            INSTR_BGE: begin
                reg_we = 1'b0;
                if ($signed(rs1_val) >= $signed(rs2_val))
                    next_pc = pc + imm_b;
            end
            INSTR_BLTU: begin
                reg_we = 1'b0;
                if (rs1_val < rs2_val)
                    next_pc = pc + imm_b;
            end
            INSTR_BGEU: begin
                reg_we = 1'b0;
                if (rs1_val >= rs2_val)
                    next_pc = pc + imm_b;
            end
            INSTR_JAL: begin
                next_pc = pc + imm_j;
                result = pc + 32'd4;
            end
            INSTR_JALR: begin
                logic [31:0] tmp;
                tmp = rs1_val + imm_i;
                next_pc = {tmp[31:1], 1'b0};
                result = pc + 32'd4;
            end
            INSTR_LUI: result = imm_u;
            INSTR_AUIPC: result = pc + imm_u;
            default:    result = 32'bx;
        endcase
        if (reg_we)
            regs[i.rd] = result;
        regs[0] = 32'b0;
        pc = next_pc;
    endfunction
endclass //rv_ref_model
