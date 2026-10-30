/* Fail path: main returns 3, so crt0 writes tohost = (3 << 1) | 1 = 7.
 * fpga_sys_tb then expects tohost = 7 (expect_tohost.txt), no PASS, and the
 * "HALT FAIL ... tohost=00000007" panic line on the UART. */
int main(void)
{
    return 3;
}
