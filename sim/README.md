# Simulation Artifacts

Generated simulation artifacts are written under `sim/build/`.

The v0.3.0 primary flow is the VCS SystemVerilog core regression:

```sh
./scripts/asm_to_hex.sh
./tools/rv32i_ref.py --all
make run
```

Generated directories include:

- `sim/build/asm/` for preprocessed assembly, object files, raw binaries, and
  disassembly dumps.
- `sim/build/core_vcs/` for the VCS executable, compile log, run log, and C
  source build directory.

Source-controlled verification artifacts live outside `sim/build/`:

- `programs/asm/*.S`
- `programs/hex/*.hex`
- `programs/expected/*.expected`
- `tb/sv/core/*.sv`
- `tools/rv32i_ref.py`

`sim/build/` is generated output and should stay ignored by Git.
