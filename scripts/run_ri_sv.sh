#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/sim/build/ri_sv}"
LOG_DIR="$BUILD_DIR/logs"
WAVE_DIR="$BUILD_DIR/waves"
SIM="$BUILD_DIR/ri_execute_tb"

die() {
    echo "run_ri_sv.sh: $*" >&2
    exit 1
}

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "cannot find $1. Install Verilator first."
}

need_file() {
    [ -f "$1" ] || die "missing file: $1"
}

compile_ri_sv() {
    mkdir -p "$BUILD_DIR" "$LOG_DIR" "$WAVE_DIR"

    need_tool verilator

    need_file "$REPO_ROOT/rtl/include/single_pkg.sv"
    need_file "$REPO_ROOT/tb/sv/ri_pkg.sv"
    need_file "$REPO_ROOT/tb/sv/ri_execute_tb.sv"

    verilator --binary --timing -Wall -Wno-fatal \
        --top-module ri_execute_tb \
        +incdir+"$REPO_ROOT/rtl/include" \
        +incdir+"$REPO_ROOT/tb/sv" \
        "$REPO_ROOT/rtl/include/single_pkg.sv" \
        "$REPO_ROOT/tb/sv/ri_pkg.sv" \
        "$REPO_ROOT/rtl/single_cycle/alu.sv" \
        "$REPO_ROOT/rtl/single_cycle/control_unit.sv" \
        "$REPO_ROOT/rtl/single_cycle/imm_gen.sv" \
        "$REPO_ROOT/tb/sv/ri_execute_tb.sv" \
        -o "$SIM" \
        -Mdir "$BUILD_DIR/obj_dir"
}

run_test() {
    test_name=$1
    log="$LOG_DIR/$test_name.log"
    vcd="$WAVE_DIR/$test_name.vcd"

    echo "==> $test_name"
    if "$SIM" "+TEST=$test_name" "+VCD=$vcd" > "$log" 2>&1; then
        if grep -q "TEST PASS: $test_name" "$log"; then
            echo "PASS $test_name"
        else
            cat "$log"
            die "$test_name finished without TEST PASS"
        fi
    else
        cat "$log"
        die "$test_name failed"
    fi
}

compile_ri_sv

if [ "$#" -eq 0 ]; then
    set -- ri_directed
fi

for test_name in "$@"; do
    run_test "$test_name"
done

echo "All R/I SV tests passed."
