#include "lib/print.h"
#include "drv/uart.h"
#include "drv/oled.h"
#include "lib/tty.h"

int main (void)
{
    char c;
    uart_init();
    oled_clear();
    print_puts("oled ready\n");
    while (1)
    {
        c = tty_getc();
        if (c == '~') break;
        oled_putc(c);
        tty_echo(c);
    }
    print_puts("\nbye\n");
    return 0;
}