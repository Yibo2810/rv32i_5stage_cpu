mmap_test:
  # ==========================================================================
  # Directed system test for the v0.7.1 address map (fpga_sys only, not the
  # core TB and not Spike: Spike has a UART at 0x1000_0000 and faults on the
  # unmapped access in case 5).
  #
  #   RAM   0x8000_0000 64 KB  text at the bottom, data window at +0x8000
  #   MMIO  0x1000_0000  4 KB  tohost at offset 0x100, other offsets read 0
  #   other                    unmapped: read 0, write dropped, bus_err = 1
  #
  # Verdict: tohost = 1 then ebreak. A failing case writes
  # tohost = (case << 1) | 1, so tohost[4:1] (sw = 01 on the board) is the
  # number of the first failing case. bus_err must end up 1 (case 5).
  #
  # Lives outside programs/asm on purpose: rv32i_ref.py --all has no MMIO and
  # no ebreak, so it must not pick this file up.
  #
  # Build (link at 0x8000_0000, then pad to 256 words with ebreak):
  #   LINK_BASE=0x80000000 ASM_DIR=programs/fpga/asm HEX_DIR=rtl/fpga/build \
  #     ./scripts/asm_to_hex.sh mmap_test
  # ==========================================================================
  .equ RAM_BASE,  0x80000000
  .equ DATA_WIN,  0x80008000      # RAM + 32 KB, far from the text
  .equ MMIO_BASE, 0x10000000
  .equ UNMAPPED,  0x20000000      # outside RAM and MMIO
  .equ ADDI_T3_7, 0x007e0e13      # addi t3, t3, 7
  .equ RET,       0x00008067      # jalr x0, 0(ra)

  li   s0, DATA_WIN
  li   s1, MMIO_BASE
  li   s2, UNMAPPED
  li   s3, RAM_BASE

  # ---- case 1: RAM word write / read back --------------------------------
  li   t6, 1
  li   t0, 0x12345678
  sw   t0, 0(s0)
  lw   t1, 0(s0)
  bne  t0, t1, fail

  # ---- case 2: byte / half lanes through xbar -> sys_ram wstrb -----------
  li   t6, 2
  li   t0, 0xa5
  sb   t0, 1(s0)                  # word = 0x1234a578
  lbu  t1, 1(s0)
  bne  t0, t1, fail
  lb   t1, 1(s0)
  li   t2, 0xffffffa5
  bne  t1, t2, fail
  li   t0, 0xbeef
  sh   t0, 2(s0)                  # word = 0xbeefa578
  lhu  t1, 2(s0)
  bne  t0, t1, fail
  lw   t1, 0(s0)
  li   t2, 0xbeefa578
  bne  t1, t2, fail

  # ---- case 3: an MMIO store must not reach RAM ---------------------------
  # 0x1000_0204 and 0x8000_0204 share idx = addr[15:2] = 1. If the xbar did
  # not gate ram_req_valid by sel, the store would overwrite the 2nd
  # instruction of this program.
  li   t6, 3
  lw   t0, 0x204(s3)              # 2nd instruction word, before
  li   t1, 0xdeadbeef
  sw   t1, 0x204(s1)              # offset 0x204: no register (low offsets reserved, Spike UART at 0x1000_0000)
  lw   t2, 0x204(s3)              # after
  bne  t0, t2, fail
  lw   t2, 0x204(s1)              # unimplemented MMIO offset reads 0
  bne  t2, zero, fail

  # ---- case 4: MMIO and RAM loads back to back, both orders ---------------
  # The response mux must follow sel_q. Note: on this core mem_stall holds
  # dmem_req_addr until the response, so a mux on sel would also pass here;
  # this case catches a swapped or missing response path, not sel vs sel_q.
  li   t6, 4
  li   t2, 0xbeefa578
  lw   t0, 0x100(s1)                  # tohost, still 0
  lw   t1, 0(s0)                      # RAM
  bne  t0, zero, fail
  bne  t1, t2, fail
  lw   t1, 0(s0)                      # RAM
  lw   t0, 0x100(s1)                  # tohost
  bne  t1, t2, fail
  bne  t0, zero, fail

  # ---- case 5: unmapped load / store: answered, no hang, RAM untouched ----
  # 0x2000_0000 has idx 0 in RAM: a misrouted access would read or overwrite
  # the 1st instruction.
  li   t6, 5
  lw   t0, 0(s3)                  # 1st instruction word, before
  lw   t1, 0(s2)                  # unmapped load -> 0
  bne  t1, zero, fail
  li   t1, 0x55aa55aa
  sw   t1, 0(s2)                  # unmapped store -> dropped
  lw   t2, 0(s3)
  bne  t0, t2, fail

  # ---- case 6: unified memory: run code written through the data port -----
  li   t6, 6
  li   t0, ADDI_T3_7
  sw   t0, 0x100(s0)
  li   t0, RET
  sw   t0, 0x104(s0)
  li   t3, 5
  addi t4, s0, 0x100
  jalr ra, 0(t4)                  # executes addi t3, t3, 7 ; ret
  li   t0, 12
  bne  t3, t0, fail

  # ---- pass ---------------------------------------------------------------
  li   t0, 1
  sw   t0, 0x100(s1)                  # tohost = 1
  ebreak

fail:
  slli t6, t6, 1
  ori  t6, t6, 1
  sw   t6, 0x100(s1)                  # tohost = (case << 1) | 1
  ebreak
