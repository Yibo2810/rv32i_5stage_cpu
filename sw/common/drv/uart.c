#include <stdint.h>
#include "platform.h"
#include "uart.h"

#define UART_REG(n)  (*(volatile uart_reg_t *)(UART0_BASE + ((n) << UART_REG_SHIFT)))

#define UART_RBR  UART_REG(0)   /* read,  DLAB=0 */
#define UART_THR  UART_REG(0)   /* write, DLAB=0 */
#define UART_DLL  UART_REG(0)   /* DLAB=1 */
#define UART_IER  UART_REG(1)   /* DLAB=0 */
#define UART_DLM  UART_REG(1)   /* DLAB=1 */
#define UART_FCR  UART_REG(2)   /* write */
#define UART_LCR  UART_REG(3)
#define UART_MCR  UART_REG(4)
#define UART_LSR  UART_REG(5)

#define LCR_DLAB  0x80
#define LCR_8N1   0x03          /* word length 8, 1 stop, no parity */
#define LSR_THRE  0x20          /* bit5: THR empty, can accept a byte */
#define LSR_TEMT  0x40          /* bit6: THR and shift register both empty */
#define LSR_DR    0x01

void uart_init (void)
{
    /* Actually, hardware has already defined the div, baudrate stabled on RTL */
    uint32_t div = (CPU_CLK_HZ + 8u * UART_BAUD) / (16u * UART_BAUD);  
    UART_IER = 0x00;
    UART_LCR = LCR_DLAB;
    UART_DLL = div & 0xFF;
    UART_DLM = div >> 8;
    UART_LCR = LCR_8N1;
    UART_FCR = 0x07;
}

void uart_putc(char c)
{
    while ((UART_LSR & LSR_THRE) == 0){}
    UART_THR = (uint8_t)c;
}

char uart_getc(void) {
    while ((UART_LSR & LSR_DR) == 0) {}
    return UART_RBR;
}
