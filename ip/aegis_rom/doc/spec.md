# aegis_rom - Boot ROM

**Top module:** `axil_rom`   **Base address:** 0x0000_0000

## Function
16 KB, initialised from boot.hex ($readmemh), AXI4-Lite read-only, write returns SLVERR.

## Interfaces
s_* AXI4-Lite slave

## RTL (see rtl.f)
- `rtl/axil_rom.sv`
- `ip/aegis_common/rtl/axil_regif.sv`

## Testbenches (ip/aegis_rom/tb)
- none stand-alone

**Verification:** via SoC test

## Run
`flow/run_ip_tb.sh aegis_rom`  |  synthesis: `flow/synth_ip.sh aegis_rom`
