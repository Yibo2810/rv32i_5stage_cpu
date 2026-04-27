.PHONY: all single pipeline clean

all: single pipeline

single:
	./scripts/run_single_cycle.sh

pipeline:
	./scripts/run_pipeline.sh

clean:
	rm -rf sim/build sim/*.vcd sim/*.log

