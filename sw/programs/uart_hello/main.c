#include "lib/print.h"
#include "drv/uart.h"

int main(void)
{
    uart_init();
    print_puts("Hello World\n");
    print_hex(0);
    print_puts("\n");
    print_hex(0xdeadbeef);
    print_puts("\n");
    print_hex(0x0000000a);
    print_puts("\n");
    return 0;
}
