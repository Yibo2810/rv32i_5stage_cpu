.PHONY: pl-lint pl-build pl-run pl-cov-report clean-artifacts clean distclean \
        fs-build c-run c-spike c-load mmap-test uart-tx-test oled-spi-test oled-seq-test oled-ctrl-test uart-rx-test uart-16550-test oled-text-test oled-render-test loader-test

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

clean-artifacts:
	rm -rf $(TOP_ARTIFACTS)

clean: clean-artifacts
	rm -rf sim/build

distclean: clean
	rm -rf rtl/fpga/build

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

# Random regression. The seed offset is time-based unless given:
#   make pl-run SEED_OFFSET=1 NUM_SEEDS=500    release regression (fixed seeds)
#   make pl-run ARGS=+SINGLE_SEED=<n>          reproduce one seed
SEED_OFFSET ?= $(shell date +%s)
NUM_SEEDS   ?= 30
pl-run: pl-build
	./$(PL_SIMV) +SEED_OFFSET=$(SEED_OFFSET) +NUM_SEEDS=$(NUM_SEEDS) $(ARGS) -l $(PL_BUILD_DIR)/run.log

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
	rtl/fpga/rtl/include/peripherals.sv \
	rtl/fpga/rtl/sys_ram.sv rtl/fpga/rtl/dmem_xbar.sv rtl/fpga/rtl/mmio_regs.sv \
	rtl/fpga/rtl/uart/uart_tx.sv rtl/fpga/rtl/uart/uart_rx.sv rtl/fpga/rtl/uart/uart_16550.sv rtl/fpga/rtl/uart/uart_loader.sv rtl/fpga/rtl/halt_reporter.sv \
	rtl/fpga/rtl/oled/oled_spi.sv rtl/fpga/rtl/oled/oled_seq.sv rtl/fpga/rtl/oled/oled_font.sv rtl/fpga/rtl/oled/oled_text.sv \
	rtl/fpga/rtl/oled/oled_render.sv rtl/fpga/rtl/oled/oled_ctrl.sv \
	rtl/fpga/rtl/fpga_sys.sv rtl/fpga/tb/uart/uart_rx_model.sv rtl/fpga/tb/oled/ssd1331_model.sv rtl/fpga/tb/fpga_sys_tb.sv \
	-Mdir=$(FS_BUILD_DIR)/csrc \
	-o $(FS_SIMV) \
	-l $(FS_BUILD_DIR)/compile.log

# sw/programs/<PROG>/expect_uart.txt, if present, is the exact expected UART output.
UART_EXPECT = $(wildcard sw/programs/$(PROG)/expect_uart.txt)
# sw/programs/<PROG>/uart_rx.txt, if present, is typed into uart_rxd (echo-paced) by fpga_sys_tb.
UART_RX_IN  = $(wildcard sw/programs/$(PROG)/uart_rx.txt)
# sw/programs/<PROG>/expect_oled.txt, if present, is the expected screen (rows 1-7) after a PASS halt.
OLED_EXPECT = $(wildcard sw/programs/$(PROG)/expect_oled.txt)
# sw/programs/<PROG>/expect_tohost.txt, if present, is the expected tohost (hex); default 1 = PASS.
TOHOST_EXPECT = $(wildcard sw/programs/$(PROG)/expect_tohost.txt)
MAX_CYCLES ?= 200000

c-run: fs-build
	$(MAKE) -C sw PROG=$(PROG)
	./$(FS_SIMV) +MEM=rtl/fpga/build/$(PROG).mem +MAX_CYCLES=$(MAX_CYCLES) \
	$(if $(UART_EXPECT),+EXPECT_UART_FILE=$(UART_EXPECT)) $(if $(UART_RX_IN),+UART_RX_FILE=$(UART_RX_IN)) \
	$(if $(OLED_EXPECT),+EXPECT_OLED_FILE=$(OLED_EXPECT)) $(if $(TOHOST_EXPECT),+EXPECT_TOHOST=$(shell cat $(TOHOST_EXPECT))) \
	$(ARGS) -l $(FS_BUILD_DIR)/run.log

c-spike:
	$(MAKE) -C sw PROG=$(PROG) spike

# Assembly address-map test (RAM / MMIO / unmapped); expects one bus error at 0x2000_0000
mmap-test: fs-build
	./scripts/asm_to_hex.sh mmap_test
	awk -v N=256 'NF {print; n++} END {if (n > N) exit 1; for (; n < N; n++) print "00100073"}' \
	  rtl/fpga/build/mmap_test.hex > rtl/fpga/build/mmap_test.mem
	./$(FS_SIMV) +MEM=rtl/fpga/build/mmap_test.mem +EXPECT_BUS_ERR=1 +EXPECT_BUS_ERR_ADDR=20000000 \
	  -l $(FS_BUILD_DIR)/mmap.log

# Same program, but sent over UART to uart_loader (sw[2] mode) instead of $readmemh;
# the frame comes from tools/uart_load.py, the same script used on the board.
#   make c-load PROG=oled_term                 RAM must equal the .bin, then the usual checks
#   make c-load PROG=hello ARGS=+LOAD_CORRUPT=1   one byte flipped: loader must end in ERR
c-load: fs-build
	$(MAKE) -C sw PROG=$(PROG)
	python3 tools/uart_load.py $(PROG) --out $(FS_BUILD_DIR)/$(PROG).frame
	./$(FS_SIMV) +LOAD_BIN=rtl/fpga/build/$(PROG).bin +LOAD_FRAME=$(FS_BUILD_DIR)/$(PROG).frame +MAX_CYCLES=$(MAX_CYCLES) \
	$(if $(UART_EXPECT),+EXPECT_UART_FILE=$(UART_EXPECT)) $(if $(UART_RX_IN),+UART_RX_FILE=$(UART_RX_IN)) \
	$(if $(OLED_EXPECT),+EXPECT_OLED_FILE=$(OLED_EXPECT)) $(if $(TOHOST_EXPECT),+EXPECT_TOHOST=$(shell cat $(TOHOST_EXPECT))) \
	$(ARGS) -l $(FS_BUILD_DIR)/load.log

# OLED unit tests (TB plays the SSD1331; oled-ctrl-test writes frame.ppm)
oled-spi-test:
	@mkdir -p sim/build/oled_spi_vcs/csrc
	vcs -full64 -sverilog -debug_access+all -top oled_spi_tb \
	rtl/fpga/rtl/oled/oled_spi.sv rtl/fpga/tb/oled/oled_spi_tb.sv \
	-Mdir=sim/build/oled_spi_vcs/csrc -o sim/build/oled_spi_vcs/simv \
	-l sim/build/oled_spi_vcs/compile.log
	./sim/build/oled_spi_vcs/simv -l sim/build/oled_spi_vcs/run.log

oled-seq-test:
	@mkdir -p sim/build/oled_seq_vcs/csrc
	vcs -full64 -sverilog -debug_access+all -top oled_seq_tb \
	rtl/fpga/rtl/oled/oled_spi.sv rtl/fpga/rtl/oled/oled_seq.sv rtl/fpga/tb/oled/oled_seq_tb.sv \
	-Mdir=sim/build/oled_seq_vcs/csrc -o sim/build/oled_seq_vcs/simv \
	-l sim/build/oled_seq_vcs/compile.log
	./sim/build/oled_seq_vcs/simv -l sim/build/oled_seq_vcs/run.log

oled-ctrl-test:
	@mkdir -p sim/build/oled_ctrl_vcs/csrc
	vcs -full64 -sverilog -debug_access+all -top oled_ctrl_tb \
	rtl/fpga/rtl/include/peripherals.sv rtl/fpga/rtl/oled/oled_spi.sv rtl/fpga/rtl/oled/oled_seq.sv \
	rtl/fpga/rtl/oled/oled_font.sv rtl/fpga/rtl/oled/oled_text.sv rtl/fpga/rtl/oled/oled_render.sv \
	rtl/fpga/rtl/oled/oled_ctrl.sv rtl/fpga/tb/oled/ssd1331_model.sv rtl/fpga/tb/oled/oled_ctrl_tb.sv \
	-Mdir=sim/build/oled_ctrl_vcs/csrc -o sim/build/oled_ctrl_vcs/simv \
	-l sim/build/oled_ctrl_vcs/compile.log
	./sim/build/oled_ctrl_vcs/simv -l sim/build/oled_ctrl_vcs/run.log

# uart_rx: behavioral sender on real time, random phase, +-3 % baud; CPB 12 and 217
uart-rx-test:
	@mkdir -p sim/build/uart_rx_vcs/csrc sim/build/uart_rx_vcs/csrc217
	vcs -full64 -sverilog -debug_access+all -top uart_rx_tb \
	rtl/fpga/rtl/include/peripherals.sv rtl/fpga/rtl/uart/uart_rx.sv rtl/fpga/tb/uart/uart_rx_tb.sv \
	-Mdir=sim/build/uart_rx_vcs/csrc -o sim/build/uart_rx_vcs/simv \
	-l sim/build/uart_rx_vcs/compile.log
	./sim/build/uart_rx_vcs/simv -l sim/build/uart_rx_vcs/run.log
	vcs -full64 -sverilog -top uart_rx_tb -pvalue+uart_rx_tb.CPB=217 \
	rtl/fpga/rtl/include/peripherals.sv rtl/fpga/rtl/uart/uart_rx.sv rtl/fpga/tb/uart/uart_rx_tb.sv \
	-Mdir=sim/build/uart_rx_vcs/csrc217 -o sim/build/uart_rx_vcs/simv217 \
	-l sim/build/uart_rx_vcs/compile217.log
	./sim/build/uart_rx_vcs/simv217 -l sim/build/uart_rx_vcs/run217.log

oled-text-test:
	@mkdir -p sim/build/oled_text_vcs/csrc
	vcs -full64 -sverilog -debug_access+all -top oled_text_tb \
	rtl/fpga/rtl/include/peripherals.sv rtl/fpga/rtl/oled/oled_text.sv rtl/fpga/tb/oled/oled_text_tb.sv \
	-Mdir=sim/build/oled_text_vcs/csrc -o sim/build/oled_text_vcs/simv \
	-l sim/build/oled_text_vcs/compile.log
	./sim/build/oled_text_vcs/simv -l sim/build/oled_text_vcs/run.log

oled-render-test:
	@mkdir -p sim/build/oled_render_vcs/csrc
	vcs -full64 -sverilog -debug_access+all -top oled_render_tb \
	rtl/fpga/rtl/include/peripherals.sv rtl/fpga/rtl/oled/oled_font.sv rtl/fpga/rtl/oled/oled_text.sv \
	rtl/fpga/rtl/oled/oled_render.sv rtl/fpga/rtl/oled/oled_spi.sv \
	rtl/fpga/tb/oled/ssd1331_model.sv rtl/fpga/tb/oled/oled_render_tb.sv \
	-Mdir=sim/build/oled_render_vcs/csrc -o sim/build/oled_render_vcs/simv \
	-l sim/build/oled_render_vcs/compile.log
	./sim/build/oled_render_vcs/simv -l sim/build/oled_render_vcs/run.log

# uart_16550 register-level unit test (status-bit corners, same-cycle set/clear)
uart-16550-test:
	@mkdir -p sim/build/uart_16550_vcs/csrc
	vcs -full64 -sverilog -debug_access+all -top uart_16550_tb \
	rtl/fpga/rtl/include/peripherals.sv rtl/fpga/rtl/uart/uart_16550.sv rtl/fpga/tb/uart/uart_16550_tb.sv \
	-Mdir=sim/build/uart_16550_vcs/csrc -o sim/build/uart_16550_vcs/simv \
	-l sim/build/uart_16550_vcs/compile.log
	./sim/build/uart_16550_vcs/simv -l sim/build/uart_16550_vcs/run.log

# uart_tx unit test against the independent TB receiver model
uart-tx-test:
	@mkdir -p sim/build/uart_tx_vcs/csrc
	vcs -full64 -sverilog -debug_access+all -top uart_tx_tb \
	rtl/fpga/rtl/uart/uart_tx.sv rtl/fpga/tb/uart/uart_rx_model.sv rtl/fpga/tb/uart/uart_tx_tb.sv \
	-Mdir=sim/build/uart_tx_vcs/csrc -o sim/build/uart_tx_vcs/simv \
	-l sim/build/uart_tx_vcs/compile.log
	./sim/build/uart_tx_vcs/simv -l sim/build/uart_tx_vcs/run.log

loader-test:
	@mkdir -p sim/build/uart_loader_vcs/csrc
	vcs -full64 -sverilog -debug_access+all -top uart_loader_tb \
	rtl/fpga/rtl/include/peripherals.sv rtl/fpga/rtl/uart/uart_loader.sv rtl/fpga/tb/uart/uart_loader_tb.sv \
	-Mdir=sim/build/uart_loader_vcs/csrc -o sim/build/uart_loader_vcs/simv \
	-l sim/build/uart_loader_vcs/compile.log
	./sim/build/uart_loader_vcs/simv -l sim/build/uart_loader_vcs/run.log
