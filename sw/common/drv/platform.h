#ifndef PLATFORM_H
#define PLATFORM_H

#include <stdint.h>

#define UART0_BASE 0x10000000UL

#ifdef PLATFORM_SPIKE                  /* set by sw/Makefile for the _spike.elf build */
/* Spike's ns16550 (spike riscv/platform.h): NS16550_REG_SHIFT 0, NS16550_REG_IO_WIDTH 1. */
/* Spike faults any access whose width != reg-io-width, so it must be a byte access. */
#define UART_REG_SHIFT  0
typedef uint8_t  uart_reg_t;
#else
#define UART_REG_SHIFT  2              /* register n at base + (n << 2), DT reg-shift = <2> */
typedef uint32_t uart_reg_t;           /* lw/sw, DT reg-io-width = <4> */
#endif

#define CPU_CLK_HZ 25000000UL
#define UART_BAUD  115200UL

#endif