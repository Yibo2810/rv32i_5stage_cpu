# Start-up code for fpga_sys. Placed at RESET_PC by link.ld (.text.init first).
# No gp: link.ld does not define __global_pointer$, so ld never relaxes to gp.
    .section .text.init, "ax"
    .globl _start
_start:
    la   sp, __stack_top          # 1. stack before any call
    la   t0, __bss_start          # 2. zero .bss
    la   t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:  call main                     # 3. run C
    slli a0, a0, 1                # 4. tohost = (ret << 1) | 1, so return 0 -> 1 = PASS
    ori  a0, a0, 1
    la   t0, tohost
    sw   a0, 0(t0)
    ebreak                        # 5. stop the core
