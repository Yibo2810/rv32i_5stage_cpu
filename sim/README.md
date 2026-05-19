# Simulation Artifacts

Generated simulation artifacts are written under `sim/build/`.

The current single-cycle runner creates:

- `sim/build/asm/` for preprocessed assembly, object files, raw binaries, and disassembly dumps.
- `sim/build/logs/` for per-test simulation logs.
- `sim/build/waves/` for per-test VCD waveforms.
- `sim/build/single_cycle.vvp` for the compiled Icarus Verilog simulation image.

These files are generated outputs and are ignored by Git.
