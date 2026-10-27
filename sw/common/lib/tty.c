#include <stdint.h>
#include "drv/uart.h"
#include "tty.h"

char tty_getc(void)
{
    char c;
    c = uart_getc();
    if (c == '\r') c = '\n';
    else if (c == 0x7F) c = '\b';
    return c;
}

void tty_echo(char c)
{
    if (c == '\n') {
        uart_putc('\r');
        uart_putc('\n');
    }
    else if (c == '\b') {
        uart_putc('\b');
        uart_putc(' ');
        uart_putc('\b');
    }
    else {
        uart_putc(c);
    }
}