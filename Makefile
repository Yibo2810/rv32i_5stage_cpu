.PHONY: build run

BUILD_DIR := sim/build/core_vcs
SIMV      := $(BUILD_DIR)/simv
FILELIST  := tb/filelists/core_sv.f

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

run: build
	./$(SIMV) +SEED_OFFSET=$$(date +%s) $(ARGS) -l $(BUILD_DIR)/run.log