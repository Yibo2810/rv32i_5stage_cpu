+incdir+rtl/include

// ---- packages
rtl/include/core_pkg.sv
rtl/include/pipeline_pkg.sv

// ---- leaf units
rtl/pipeline/units/pc.v
rtl/pipeline/units/alu.sv
rtl/pipeline/units/regfile.sv
rtl/pipeline/units/imm_gen.sv
rtl/pipeline/units/control_unit.sv
rtl/pipeline/units/load_store_unit.sv

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