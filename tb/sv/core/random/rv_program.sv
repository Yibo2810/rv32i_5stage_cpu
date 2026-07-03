class rv_program;
    rand int unsigned instr_count;
    rv_instr instrs[$];

    function void build(int seed);
    function void load_imem(ref logic [31:0] imem[]);
    function void append_signature_dump();
endclass //rv_program