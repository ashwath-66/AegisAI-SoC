# AegisAI-SoC boot code. Ibex: reset vector = boot_addr + 0x80, traps/IRQs use
# a 32-entry vector table at boot_addr (exceptions -> entry 0, IRQ n -> entry n).
    .section .vectors, "ax"
    .option norvc
    .global _vectors
_vectors:
    .rept 32
    j   _trap
    .endr

    .section .text.start, "ax"
    .global _reset
_reset:
    la   sp, _stack_top
    # mtvec = vector table (vectored mode is forced by Ibex)
    la   t0, _vectors
    ori  t0, t0, 1
    csrw mtvec, t0
    call main
1:  wfi
    j    1b

_trap:
    # unexpected trap: report FAIL (SYS_EXIT = 2) and stop
    li   t0, 0x40020010
    li   t1, 2
    sw   t1, 0(t0)
2:  j    2b
