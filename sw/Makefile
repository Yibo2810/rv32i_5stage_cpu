# Bare-metal C for fpga_sys: sw/<PROG>/*.c + sw/common -> ELF -> bin -> hex -> .mem
#
#   make PROG=hello          rtl/fpga/build/hello.mem (padded to MEM_WORDS)
#   make PROG=hello spike    same sources on Spike; exit code = main() return value
#   make PROG=hello clean
#
# The board and Spike builds differ only in where tohost lives (see link.ld).

PROG      ?= hello
MEM_WORDS ?= 1024

ROOT   := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
COMMON := $(ROOT)/sw/common
SRC    := $(ROOT)/sw/$(PROG)
BUILD  ?= $(ROOT)/rtl/fpga/build

CROSS   ?= riscv64-unknown-elf-
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
NM      := $(CROSS)nm
SIZE    := $(CROSS)size
SPIKE   ?= spike

CFLAGS  := -march=rv32i -mabi=ilp32 -O2 -ffreestanding -nostdlib -Wall
LDFLAGS := -T $(COMMON)/link.ld -Wl,--no-warn-rwx-segments

SRCS := $(COMMON)/crt0.S $(wildcard $(SRC)/*.c) $(COMMON)/lib.c
DEPS := $(SRCS) $(COMMON)/link.ld

ELF       := $(BUILD)/$(PROG).elf
MEM       := $(BUILD)/$(PROG).mem
SPIKE_ELF := $(BUILD)/$(PROG)_spike.elf

.PHONY: all spike clean
.DELETE_ON_ERROR:
.SECONDARY:              # keep the intermediate .bin / .hex

all: $(MEM)
	@echo "built $(MEM)"

# Link, then refuse an image the core cannot run:
#   _start must sit on RESET_PC, and rv32i has no M-extension instructions.
define link_and_check
	@test -n "$(wildcard $(SRC)/*.c)" || { echo "no C sources in $(SRC)"; exit 1; }
	$(CC) $(CFLAGS) $(LDFLAGS) -Wl,-Map=$(@:.elf=.map) $(1) -lgcc -o $@
	$(OBJDUMP) -d $@ > $(@:.elf=.dump)
	@$(NM) $@ | grep -q '^80000000 T _start$$' || { echo "CHECK FAIL: _start is not at 0x80000000"; exit 1; }
	@! grep -qE '\s(mul|mulh|mulhu|mulhsu|div|divu|rem|remu)\s' $(@:.elf=.dump) || { echo "CHECK FAIL: M-extension instruction in $@"; exit 1; }
	@$(SIZE) $@
endef

$(ELF): $(DEPS) | $(BUILD)
	$(call link_and_check,$(SRCS))

$(SPIKE_ELF): $(DEPS) $(COMMON)/tohost_spike.S | $(BUILD)
	$(call link_and_check,$(SRCS) $(COMMON)/tohost_spike.S)

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

%.hex: %.bin
	hexdump -v -e '1/4 "%08x\n"' $< > $@

# Pad with ebreak so a stray jump inside the image traps instead of running zeros.
%.mem: %.hex
	awk -v N=$(MEM_WORDS) 'NF {print; n++} END {if (n > N) {print "too big: " n " words > MEM_WORDS=" N > "/dev/stderr"; exit 1} for (; n < N; n++) print "00100073"}' $< > $@

# Spike RAM = the board's RAM (64 KB at 0x8000_0000), so an out-of-RAM access faults there too.
spike: $(SPIKE_ELF)
	@timeout 30 $(SPIKE) --isa=rv32i -m0x80000000:0x10000 $<; rc=$$?; \
	if [ $$rc -eq 0 ]; then echo "SPIKE PASS: main returned 0"; \
	else echo "SPIKE FAIL: exit code $$rc (main return value, 124 = timeout)"; exit 1; fi

$(BUILD):
	mkdir -p $@

clean:
	rm -f $(BUILD)/$(PROG).elf $(BUILD)/$(PROG).map $(BUILD)/$(PROG).dump $(BUILD)/$(PROG).bin \
	      $(BUILD)/$(PROG).hex $(BUILD)/$(PROG).mem \
	      $(BUILD)/$(PROG)_spike.elf $(BUILD)/$(PROG)_spike.map $(BUILD)/$(PROG)_spike.dump
