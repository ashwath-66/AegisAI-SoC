#!/usr/bin/env python3
# Run from the project root:  python3 flow/patch_clockgate.py
# Makes the Ibex clock-gate bypass the DEFAULT (FPGA / packaged IP); define AEGIS_ASIC to get the real gate back.
p = 'ip/aegis_cpu/rtl/ibex/prim_generic_clock_gating.sv'
s = open(p).read()
if '`ifndef AEGIS_ASIC' in s:
    print("already patched")
elif '`ifdef AEGIS_FPGA' in s:
    s = s.replace('`ifdef AEGIS_FPGA', '`ifndef AEGIS_ASIC')
    s = s.replace("// FPGA build: no gated clock", "// Default (FPGA / packaged IP): no gated clock. Define AEGIS_ASIC to restore the latch-based gate.\n  //")
    open(p, 'w').write(s); print("patched: bypass is now the default")
else:
    print("PATTERN NOT FOUND"); raise SystemExit(1)
