#!/bin/bash
# Builds fw/boot.hex (one 32-bit word per line, ROM image) from main.c + crt0.S
# needs: sudo apt install gcc-riscv64-unknown-elf
set -e
cd "$(dirname "$0")"
CC=riscv64-unknown-elf-gcc
$CC -march=rv32imc_zicsr -mabi=ilp32 -Os -ffreestanding -nostdlib -fno-pic -Wall \
    -Wl,-T,link.ld -Wl,--gc-sections -o boot.elf crt0.S main.c
riscv64-unknown-elf-objcopy -O binary boot.elf boot.bin
python3 - <<'PY'
import struct
d=open('boot.bin','rb').read()
d+=b'\0'*((-len(d))%4)
with open('boot.hex','w') as f:
    for (w,) in struct.iter_unpack('<I',d): f.write('%08x\n'%w)
print('boot.hex: %d words (%d bytes)'%(len(d)//4,len(d)))
PY
riscv64-unknown-elf-objdump -d boot.elf > boot.lst
