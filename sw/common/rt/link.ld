OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K   /* = fpga_sys RAM_BASE, 2**RAM_AW */
}

/* Board: tohost is the MMIO register at MMIO_BASE + 0x100 (an address, not a
 * section). Spike build links tohost_spike.S, whose tohost in .tohost wins. */
PROVIDE(tohost = 0x10000100);

SECTIONS
{
  .text : {
    KEEP(*(.text.init))                           /* crt0 _start first: lands on RESET_PC */
    *(.text .text.*)
  } > RAM

  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > RAM
  .data   : { *(.data .data.* .sdata .sdata.*) } > RAM
  .tohost : ALIGN(8) { KEEP(*(.tohost)) } > RAM   /* Spike only; empty on the board */

  .bss (NOLOAD) : ALIGN(4) {
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM

  __stack_top = ORIGIN(RAM) + LENGTH(RAM);        /* stack grows down, 16-byte aligned */
}
