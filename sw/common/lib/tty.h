#ifndef TTY_H
#define TTY_H
#include <stdint.h>

char tty_getc(void);
void tty_echo(char c);

#endif