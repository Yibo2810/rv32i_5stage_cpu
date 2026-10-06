.PHONY: build run cov-build cov-run cov-report cov-report-md urg-report cov \
        pl-run pl-cov-report clean-artifacts clean distclean

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
