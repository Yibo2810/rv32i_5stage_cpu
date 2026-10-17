#ifndef PRINT_H
#define PRINT_H
#include <stdint.h>

void print_puts(const char *s);     /* text ：'\n' → "\r\n" */
void print_hex(uint32_t v);         /* Hex output only requires shifting and bitwise AND. */

#endif