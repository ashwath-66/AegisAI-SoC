# aegis_fabric - AXI4-Lite interconnect

**Top module:** `aegis_fabric`   **Base address:** -

## Function
2 masters -> 6 slaves, address map baked in, DECERR slave for unmapped addresses.

## Interfaces
m_* (2 master ports), s_* (6 slave ports), packed-array ports

## RTL (see rtl.f)
- `rtl/axil_xbar.sv`
- `rtl/axil_err_slave.sv`
- `rtl/aegis_fabric.sv`

## Testbenches (ip/aegis_fabric/tb)
- none stand-alone

**Verification:** TODO: stand-alone TB (currently verified through the SoC test)

## Run
`flow/run_ip_tb.sh aegis_fabric`  |  synthesis: `flow/synth_ip.sh aegis_fabric`
