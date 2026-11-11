# aegis_sram - CPU SRAM

**Top module:** `axil_sram`   **Base address:** 0x2000_0000

## Function
16 KB, byte-strobe AXI4-Lite slave.

## Interfaces
s_* AXI4-Lite slave

## RTL (see rtl.f)
- `rtl/axil_sram.sv`
- `ip/aegis_common/rtl/axil_regif.sv`

## Testbenches (ip/aegis_sram/tb)
- none stand-alone

**Verification:** via SoC test

## Run
`flow/run_ip_tb.sh aegis_sram`  |  synthesis: `flow/synth_ip.sh aegis_sram`
