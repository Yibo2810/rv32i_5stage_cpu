# Spike only. HTIF finds tohost by its ELF symbol and polls that RAM location;
# Spike has no device at the board's MMIO tohost (0x1000_0100).
    .section .tohost, "aw", @progbits
    .align 3
    .globl tohost
tohost:   .dword 0
    .globl fromhost
fromhost: .dword 0
