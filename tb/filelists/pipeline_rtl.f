+incdir+rtl/include

// ---- packages
rtl/include/single_pkg.sv
rtl/include/pipeline_pkg.sv

// ---- shared leaf RTL
rtl/single_cycle/pc.v
rtl/single_cycle/alu.sv
rtl/single_cycle/regfile.sv
rtl/single_cycle/imm_gen.sv
rtl/single_cycle/control_unit.sv
rtl/single_cycle/load_store_unit.sv

// ---- pipeline RTL
rtl/pipeline/pipeline_regs.sv
rtl/pipeline/if_stage.sv
rtl/pipeline/id_stage.sv
rtl/pipeline/ex_stage.sv
rtl/pipeline/mem_stage.sv
rtl/pipeline/wb_stage.sv
rtl/pipeline/hazard_unit.sv
rtl/pipeline/forwarding_unit.sv
rtl/pipeline/core_5stage.sv
rtl/pipeline/memory/dmem_bram.sv