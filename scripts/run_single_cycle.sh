#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/sim/build}"
LOG_DIR="$BUILD_DIR/logs"
WAVE_DIR="$BUILD_DIR/waves"
SIM="$BUILD_DIR/single_cycle.vvp"
MAX_CYCLES="${MAX_CYCLES:-20}"

die() {
    echo "run_single_cycle.sh: $*" >&2
    exit 1
}

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "cannot find $1. Install Icarus Verilog first."
}

compile_single_cycle() {
    mkdir -p "$BUILD_DIR" "$LOG_DIR" "$WAVE_DIR"

    need_tool iverilog
    need_tool vvp

    iverilog -g2012 -Wall \
        -I "$REPO_ROOT/rtl/include" \
        -o "$SIM" \
        "$REPO_ROOT/rtl/include/single_pkg.sv" \
        "$REPO_ROOT/rtl/single_cycle/pc.v" \
        "$REPO_ROOT/rtl/single_cycle/alu.sv" \
        "$REPO_ROOT/rtl/single_cycle/regfile.v" \
        "$REPO_ROOT/rtl/single_cycle/imm_gen.v" \
        "$REPO_ROOT/rtl/single_cycle/control_unit.sv" \
        "$REPO_ROOT/rtl/single_cycle/core_single_cycle.v" \
        "$REPO_ROOT/tb/models/ideal_instr_mem.v" \
        "$REPO_ROOT/tb/models/ideal_data_mem.v" \
        "$REPO_ROOT/tb/tb_single_cycle.v"
}

run_test() {
    name=$1
    expect_addr=$2
    expect_value=$3

    hex="$REPO_ROOT/programs/hex/$name.hex"
    log="$LOG_DIR/$name.log"
    vcd="$WAVE_DIR/$name.vcd"

    [ -s "$hex" ] || die "missing or empty hex file: $hex"

    echo "==> $name"
    if vvp "$SIM" \
        "+TEST=$name" \
        "+HEX=$hex" \
        "+EXPECT_ADDR=$expect_addr" \
        "+EXPECT_VALUE=$expect_value" \
        "+MAX_CYCLES=$MAX_CYCLES" \
        "+VCD=$vcd" > "$log" 2>&1; then
        if grep -q "PASS: $name" "$log"; then
            echo "PASS $name"
        else
            cat "$log"
            die "$name finished without PASS"
        fi
    else
        cat "$log"
        die "$name failed"
    fi
}

run_named_test() {
    case "$1" in
        add_test)
            run_test add_test 0 0000000c
            ;;
        sub_test)
            run_test sub_test 0 00000005
            ;;
        load_store_test)
            run_test load_store_test 1 0000002a
            ;;
        branch_test)
            run_test branch_test 0 00000001
            ;;
        *)
            die "unknown test '$1'. Known tests: add_test sub_test load_store_test branch_test"
            ;;
    esac
}

if [ "${SKIP_ASM:-0}" != "1" ]; then
    "$REPO_ROOT/scripts/asm_to_hex.sh"
fi

compile_single_cycle

if [ "$#" -eq 0 ]; then
    set -- add_test sub_test load_store_test branch_test
fi

for test_name in "$@"; do
    run_named_test "$test_name"
done

echo "All single-cycle directed tests passed."
