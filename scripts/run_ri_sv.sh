#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/sim/build/ri_sv}"
LOG_DIR="$BUILD_DIR/logs"
WAVE_DIR="$BUILD_DIR/waves"
SIM="$BUILD_DIR/ri_execute_tb.vvp"

die() {
    echo "run_ri_sv.sh: $*" >&2
    exit 1
}

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "cannot find $1. Install Icarus Verilog first."
}

need_file() {
    [ -f "$1" ] || die "missing file: $1"
}

compile_ri_sv() {
    mkdir -p "$BUILD_DIR" "$LOG_DIR" "$WAVE_DIR"

    need_tool iverilog
    need_tool vvp

    need_file "$REPO_ROOT/rtl/include/single_rv32i_pkg.sv"
    need_file "$REPO_ROOT/tb/sv/rv32i_ri_pkg.sv"
    need_file "$REPO_ROOT/tb/sv/ri_execute_tb.sv"

    iverilog -g2012 -Wall \
        -I "$REPO_ROOT/rtl/include" \
        -I "$REPO_ROOT/tb/sv" \
        -s ri_execute_tb \
        -o "$SIM" \
        "$REPO_ROOT/rtl/include/single_rv32i_pkg.sv" \
        "$REPO_ROOT/tb/sv/rv32i_ri_pkg.sv" \
        "$REPO_ROOT/rtl/single_cycle/control_unit.sv" \
        "$REPO_ROOT/rtl/single_cycle/imm_gen.sv" \
        "$REPO_ROOT/rtl/single_cycle/alu.sv" \
        "$REPO_ROOT/tb/sv/ri_execute_tb.sv"
}

run_test() {
    test_name=$1
    log="$LOG_DIR/$test_name.log"
    vcd="$WAVE_DIR/$test_name.vcd"

    echo "==> $test_name"
    if vvp "$SIM" "+TEST=$test_name" "+VCD=$vcd" > "$log" 2>&1; then
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
