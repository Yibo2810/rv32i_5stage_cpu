#include <stdint.h>
#include "platform.h"
#include "oled.h"

#define OLED_TXT(r, c)  (((volatile uint32_t *)OLED_TXT_BASE)[(r) * OLED_STRIDE + (c)])
#define OLED_COLOR(r)   (((volatile uint32_t *)OLED_COLOR_BASE)[(r)])

static int cur_row, cur_col;

void oled_clear(void)
{
    for (int r = 1; r < OLED_ROWS; r++)
    {
        OLED_COLOR(r) = 0;
        for (int c = 0; c < OLED_COLS; c++)
        {
            OLED_TXT(r, c) = ' ';
        }
    }
    cur_row = 1;
    cur_col = 0;
}

static void clear_row(int r)
{
    for (int c = 0; c < OLED_COLS; c++)
    {
        OLED_TXT(r, c) = ' ';
    }
}

static void newline(void)
{
    cur_row++;
    cur_col = 0;
    if (cur_row == OLED_ROWS)
    {
        /* page flip: blank rows 1..7 and restart at row 1, row colors kept */
        cur_row = 1;
        for (int r = 2; r < OLED_ROWS; r++) clear_row(r);
    }
    clear_row(cur_row);
}

void oled_goto(int row, int col)
{
    if (row < 1) row = 1;
    if (row >= OLED_ROWS) row = OLED_ROWS - 1;
    if (col < 0) col = 0;
    if (col >= OLED_COLS) col = OLED_COLS - 1;
    cur_row = row;
    cur_col = col;
}

void oled_putc(char c)
{
    if (c == '\n')      newline();
    else if (c == '\r') cur_col = 0;
    else if (c == '\b')
    {
        if (cur_col > 0)
        {
            cur_col--;
            OLED_TXT(cur_row, cur_col) = ' ';
        }
    }
    
    else
    {
        if (cur_col == OLED_COLS)
        {
            newline();
        }
        
        OLED_TXT(cur_row, cur_col) = c;
        cur_col++;
    }
}

void oled_puts(const char *s)
{
    while (*s)
    {
        oled_putc(*s++);
    }
}

void oled_color(int row, uint16_t rgb565)
{
    if (row >= 0 && row < OLED_ROWS)
    {
        OLED_COLOR(row) = rgb565;
    }
}
