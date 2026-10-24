#include "lib/print.h"
#include "drv/uart.h"

int main(void)
{
    char c;
    uart_init();
    print_puts("echo ready\n");
    
    while (1)
    {
        c = uart_getc();
        
        if (c == 'q')
        {
            break;
        }

        uart_putc(c);
    }

    print_puts("\nbye\n");
    
    return 0;
}