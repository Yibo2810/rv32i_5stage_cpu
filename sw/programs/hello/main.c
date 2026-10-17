int fib_tab[10];                       /* .bss    : must start as 0               */
int scale = 3;                         /* .data   : initial value comes from image */
const char msg[] = "rv32i";            /* .rodata : read-only string              */
volatile int va = -1234, vb = 37;      /* volatile: values unknown at compile time */

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

int main(void)
{
    int sum = 0;
    for (int i = 0; i < 10; i++) {
        if (fib_tab[i] != 0) return 1;
        fib_tab[i] = fib(i);
        sum += fib_tab[i];
    }
    if (sum != 88)     return 2;
    if (scale != 3)    return 3;

    int a = va, b = vb;
    if (a * b != -45658) return 4;
    if (a / b != -33)    return 5;
    if (a % b != -13)    return 6;

    int len = 0;
    while (msg[len]) len++;
    if (len != 5 || msg[4] != 'i') return 7;
    return 0;
}