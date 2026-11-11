# aegis_cpu - CPU subsystem

**Top module:** `aegis_cpu`   **Base address:** -

## Function
lowRISC Ibex RV32IMC (RV32M fast, no ICache/PMP/debug) + two OBI->AXI4-Lite shims (instruction read-only, data r/w).

## Interfaces
clk, rst_n, irq_fast[14:0]; m_axil_i_* (AXI4-Lite master, fetch); m_axil_d_* (AXI4-Lite master, load/store); cpu_sleep, cpu_alert

## RTL (see rtl.f)
- `rtl/obi_to_axil.sv`
- `rtl/aegis_cpu.sv`
- `rtl/ibex/*` (Ibex core, vendored)

## Testbenches (ip/aegis_cpu/tb)
- none stand-alone

**Verification:** none (third-party core). Verified through the SoC test tb_aegisai_soc.

## Run
`flow/run_ip_tb.sh aegis_cpu`  |  synthesis: `flow/synth_ip.sh aegis_cpu`
