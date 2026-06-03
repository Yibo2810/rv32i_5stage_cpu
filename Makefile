.PHONY: all single ri-sv pipeline clean

all: single pipeline

single:
	./scripts/run_single_cycle.sh

ri-sv:
	./scripts/run_ri_sv.sh

pipeline:
	./scripts/run_pipeline.sh

clean:
	rm -rf sim/build sim/*.vcd sim/*.log
