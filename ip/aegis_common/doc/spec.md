# aegis_common - Shared library

**Top module:** `-`   **Base address:** -

## Function
axil_regif (AXI4-Lite register-interface helper) and reset_sync (async-assert, sync-release reset). Used by several IPs; list each file once when combining IPs.

## Interfaces
-

## RTL (see rtl.f)
- `rtl/axil_regif.sv`
- `rtl/reset_sync.sv`

## Testbenches (ip/aegis_common/tb)
- none stand-alone

**Verification:** -

## Run
`flow/run_ip_tb.sh aegis_common`  |  synthesis: `flow/synth_ip.sh aegis_common`
