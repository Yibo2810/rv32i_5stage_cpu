#!/usr/bin/env sh
set -eu

ARCH="${ARCH:-rv32i}"
ABI="${ABI:-ilp32}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

ASM_DIR="${ASM_DIR:-$REPO_ROOT/programs/asm}"
HEX_DIR="${HEX_DIR:-$REPO_ROOT/programs/hex}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/sim/build/asm}"

die() {
    echo "asm_to_hex.sh: $*" >&2
    exit 1
}

find_riscv_tool() {
    tool_name=$1

    if [ -n "${RISCV_PREFIX:-}" ] && command -v "${RISCV_PREFIX}${tool_name}" >/dev/null 2>&1; then
        printf '%s\n' "${RISCV_PREFIX}${tool_name}"
        return
    fi

    for prefix in riscv64-unknown-elf- riscv32-unknown-elf- riscv64-elf- riscv32-elf-; do
        if command -v "${prefix}${tool_name}" >/dev/null 2>&1; then
            printf '%s\n' "${prefix}${tool_name}"
            return
        fi
    done

    return 1
}

AS="${RISCV_AS:-$(find_riscv_tool as || true)}"
OBJCOPY="${RISCV_OBJCOPY:-$(find_riscv_tool objcopy || true)}"
OBJDUMP="${RISCV_OBJDUMP:-$(find_riscv_tool objdump || true)}"

[ -n "$AS" ] || die "cannot find RISC-V assembler. Install a RISC-V ELF binutils/gcc toolchain, or set RISCV_PREFIX/RISCV_AS."
[ -n "$OBJCOPY" ] || die "cannot find RISC-V objcopy. Install a RISC-V ELF binutils/gcc toolchain, or set RISCV_PREFIX/RISCV_OBJCOPY."
[ -n "$OBJDUMP" ] || die "cannot find RISC-V objdump. Install a RISC-V ELF binutils/gcc toolchain, or set RISCV_PREFIX/RISCV_OBJDUMP."
command -v hexdump >/dev/null 2>&1 || die "cannot find hexdump."

mkdir -p "$HEX_DIR" "$BUILD_DIR"

preprocess_asm() {
    src=$1
    out=$2

    {
        echo "    .option norvc"
        echo "    .text"
        echo "    .globl _start"
        echo "_start:"
        sed '/^[[:space:]]*expected:/d' "$src"
    } > "$out"
}

assemble_one() {
    input=$1

    case "$input" in
        *.S|*.s)
            src=$input
            ;;
        *)
            src="$ASM_DIR/$input.S"
            ;;
    esac

    [ -f "$src" ] || die "assembly file not found: $src"

    name=$(basename "$src")
    name=${name%.*}

    pp="$BUILD_DIR/$name.pre.S"
    obj="$BUILD_DIR/$name.o"
    bin="$BUILD_DIR/$name.bin"
    dump="$BUILD_DIR/$name.dump"
    hex="$HEX_DIR/$name.hex"

    preprocess_asm "$src" "$pp"

    "$AS" -march="$ARCH" -mabi="$ABI" -o "$obj" "$pp"
    "$OBJCOPY" -O binary -j .text "$obj" "$bin"
    hexdump -v -e '1/4 "%08x\n"' "$bin" > "$hex"
    "$OBJDUMP" -d "$obj" > "$dump"

    echo "generated $hex"
    echo "dumped    $dump"
}

if [ "$#" -eq 0 ]; then
    found=0
    for src in "$ASM_DIR"/*.S; do
        [ -e "$src" ] || continue
        found=1
        assemble_one "$src"
    done
    [ "$found" -eq 1 ] || die "no .S files found in $ASM_DIR"
else
    for input in "$@"; do
        assemble_one "$input"
    done
fi
