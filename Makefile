.PHONY: build run cov-build cov-run cov-report cov-report-md urg-report cov \
        pl-run pl-cov-report clean-artifacts clean distclean \
        fs-build c-run c-spike uart-tx-test

BUILD_DIR := sim/build/core_vcs
SIMV      := $(BUILD_DIR)/simv
FILELIST  := tb/filelists/core_sv.f
CM_FLAGS  := -cm line+cond+tgl+branch+fsm+assert
COV_DIR   := $(BUILD_DIR)/simv.vdb
COV_RPT   := $(BUILD_DIR)/cov_report
PL_BUILD_DIR := sim/build/pipeline_vcs
PL_SIMV      := $(PL_BUILD_DIR)/simv
PL_FILELIST  := tb/filelists/pipeline.f
PL_COV_DIR   := $(PL_BUILD_DIR)/simv.vdb
PL_COV_RPT   := $(PL_BUILD_DIR)/cov_report
TOP_ARTIFACTS := \
	ucli.key \
	cm.log \
	urg.log \
	novas.conf \
	novas.rc \
	.fsm.sch.verilog.xml \
	vdCovLog \
	simv \
	simv.daidir \
	csrc

run: build
	./$(SIMV) +SEED_OFFSET=$$(date +%s) $(ARGS) -l $(BUILD_DIR)/run.log

build:
	@mkdir -p $(BUILD_DIR)/csrc
	vcs \
	  -full64 \
	  -sverilog \
	  -debug_access+all \
	  -top core_sv_tb \
	  -f $(FILELIST) \
	  -Mdir=$(BUILD_DIR)/csrc \
	  -o $(SIMV) \
	  -l $(BUILD_DIR)/compile.log

cov-build:
	@mkdir -p $(BUILD_DIR)/csrc
	vcs \
	  -full64 \
	  -sverilog \
	  -debug_access+all \
	  $(CM_FLAGS) \
	  -cm_dir $(COV_DIR) \
	  -cm_hier tb/filelists/cm_hier.config \
	  -top core_sv_tb \
	  -f $(FILELIST) \
	  -Mdir=$(BUILD_DIR)/csrc \
	  -o $(SIMV) \
	  -l $(BUILD_DIR)/compile.log

cov-run: cov-build
	./$(SIMV) +SEED_OFFSET=$$(date +%s) $(ARGS) \
	  $(CM_FLAGS) \
	  -cm_dir $(COV_DIR) \
	  -l $(BUILD_DIR)/run.log

cov-report:
	python3 scripts/cov_report.py -dir $(COV_DIR) -report $(COV_RPT) \
	  -format text $(COV_ARGS)

cov-report-md:
	python3 scripts/cov_report.py -dir $(COV_DIR) -report $(COV_RPT) \
	  -format md $(COV_ARGS)

urg-report:
	urg -full64 -dir $(COV_DIR) -report $(BUILD_DIR)/urg_report $(COV_ARGS)

cov: cov-run cov-report
	@echo "Coverage report: $(COV_RPT)/cov_report.txt"

clean-artifacts:
	rm -rf $(TOP_ARTIFACTS)

clean: clean-artifacts
	rm -rf $(BUILD_DIR)

distclean: clean-artifacts
	rm -rf sim/build

pl-lint:
	verilator --lint-only -Wall -Wno-fatal -sv -f tb/filelists/pipeline_rtl.f --top-module core_5stage

pl-build:
	@mkdir -p $(PL_BUILD_DIR)/csrc
	vcs -full64 \
	-sverilog \
	-debug_access+all \
	-top pipeline_tb \
	-f $(PL_FILELIST) \
	-Mdir=$(PL_BUILD_DIR)/csrc \
	-o $(PL_SIMV) \
	-l $(PL_BUILD_DIR)/compile.log \
	$(PL_VCS_ARGS)

pl-run: pl-build
	./$(PL_SIMV) +SEED_OFFSET=$$(date +%s) $(ARGS) -l $(PL_BUILD_DIR)/run.log

# Report from an existing pipeline vdb (collect with -cm flags first; the
# current pl-run does not pass any, so the script warns if the vdb is empty).
pl-cov-report:
	python3 scripts/cov_report.py -dir $(PL_COV_DIR) -report $(PL_COV_RPT) \
	  -format text $(COV_ARGS)

# ---- FPGA system testbench and bare-metal C (sw/Makefile builds the image) ----
#   make c-run PROG=hello      C program on fpga_sys_tb
#   make c-spike PROG=hello    same sources on Spike
FS_BUILD_DIR := sim/build/fpga_sys_vcs
FS_SIMV      := $(FS_BUILD_DIR)/simv
PROG         ?= hello

fs-build:
	@mkdir -p $(FS_BUILD_DIR)/csrc
	vcs -full64 \
	-sverilog \
	-debug_access+all \
	-top fpga_sys_tb \
	-f tb/filelists/pipeline_rtl.f \
	rtl/fpga/rtl/sys_ram.sv rtl/fpga/rtl/dmem_xbar.sv rtl/fpga/rtl/mmio_regs.sv \
	rtl/fpga/rtl/uart_tx.sv rtl/fpga/rtl/uart_16550.sv \
	rtl/fpga/rtl/fpga_sys.sv rtl/fpga/tb/uart_rx_model.sv rtl/fpga/tb/fpga_sys_tb.sv \
	-Mdir=$(FS_BUILD_DIR)/csrc \
	-o $(FS_SIMV) \
	-l $(FS_BUILD_DIR)/compile.log

# sw/programs/<PROG>/expect_uart.txt, if present, is the exact expected UART output.
UART_EXPECT = $(wildcard sw/programs/$(PROG)/expect_uart.txt)
MAX_CYCLES ?= 200000

c-run: fs-build
	$(MAKE) -C sw PROG=$(PROG)
	./$(FS_SIMV) +MEM=rtl/fpga/build/$(PROG).mem +MAX_CYCLES=$(MAX_CYCLES) \
	$(if $(UART_EXPECT),+EXPECT_UART_FILE=$(UART_EXPECT)) $(ARGS) -l $(FS_BUILD_DIR)/run.log

c-spike:
	$(MAKE) -C sw PROG=$(PROG) spike

# uart_tx unit test against the independent TB receiver model
uart-tx-test:
	@mkdir -p sim/build/uart_tx_vcs/csrc
	vcs -full64 -sverilog -debug_access+all -top uart_tx_tb \
	rtl/fpga/rtl/uart_tx.sv rtl/fpga/tb/uart_rx_model.sv rtl/fpga/tb/uart_tx_tb.sv \
	-Mdir=sim/build/uart_tx_vcs/csrc -o sim/build/uart_tx_vcs/simv \
	-l sim/build/uart_tx_vcs/compile.log
	./sim/build/uart_tx_vcs/simv -l sim/build/uart_tx_vcs/run.log
