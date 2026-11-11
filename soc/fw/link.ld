OUTPUT_ARCH(riscv)
ENTRY(_reset)
MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 16K
}
SECTIONS
{
    .vectors 0x00000000 : { KEEP(*(.vectors)) } > ROM
    .text 0x00000080 :
    {
        KEEP(*(.text.start))
        *(.text .text.*)
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > ROM
    .bss (NOLOAD) : { *(.bss .bss.* .sbss .sbss.* COMMON) } > RAM
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
