#include <stdint.h>
#include "print.h"
#include "drv/uart.h"

void print_puts(const char *s)
{
    while (*s)
    {
        if (*s == '\n')
            uart_putc('\r');
        uart_putc(*s++);
    }
}

void print_hex(uint32_t v)
{
    const char hex[] = "0123456789abcdef";

    for (int i = 7; i >= 0; i--)
    {
        uint32_t n = (v >> (i * 4)) & 0xF;

        uart_putc(hex[n]);
        
    }
}