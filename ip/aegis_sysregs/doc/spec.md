# aegis_sysregs - System registers

**Top module:** `soc_sysregs`   **Base address:** 0x4002_0000

## Function
chip ID, scratch regs, IRQ status, debug console / pass-fail pins.

## Interfaces
s_* AXI4-Lite slave; irq_raw[2:0]; dbg_*

## RTL (see rtl.f)
- `rtl/soc_sysregs.sv`
- `ip/aegis_common/rtl/axil_regif.sv`

## Testbenches (ip/aegis_sysregs/tb)
- none stand-alone

**Verification:** via SoC test

## Run
`flow/run_ip_tb.sh aegis_sysregs`  |  synthesis: `flow/synth_ip.sh aegis_sysregs`
