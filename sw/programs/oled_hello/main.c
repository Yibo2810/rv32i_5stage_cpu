#include "lib/print.h"
#include "drv/oled.h"

int main (void)
{
    oled_clear();
    oled_color(1,0xF800); // red
    oled_puts("Hello RV32I\n");
    oled_color(2,0xFFE0); // yellow
    oled_puts("from C\n");
    oled_puts("ABCDEFGHIJKL\n");
    oled_puts("0123456789ABCDEF\n");
    oled_goto(7, 0);
    oled_puts("goto ok");
    return 0;
}