#ifndef OLED_H
#define OLED_H
#include <stdint.h>

void oled_clear(void);
void oled_goto(int row, int col);
void oled_putc(char c);
void oled_puts(const char *s);
void oled_color(int row, uint16_t rgb565);

#endif