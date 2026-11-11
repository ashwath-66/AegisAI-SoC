# aegis_tcm - Accelerator tightly-coupled memory

**Top module:** `axi_tcm`   **Base address:** 0x1000_0000

## Function
axi_tcm + ping_pong_sram: two 8 KB banks of 128-bit words, AXI4 write port, GEMM read port with 1-cycle latency, block-RAM inferred (one array per bank).

## Interfaces
s_axi_* AXI4 slave (write used); g_en/g_bank/g_word/g_rdata GEMM read port

## RTL (see rtl.f)
- `rtl/axi_tcm.sv`
- `rtl/ping_pong_sram.sv`

## Testbenches (ip/aegis_tcm/tb)
- `tb_tcm.f`
- `tb_tcm.sv`

**Verification:** tb_tcm (random bursts + strobes, narrow access, DECERR/SLVERR, concurrent GEMM reads)

## Run
`flow/run_ip_tb.sh aegis_tcm`  |  synthesis: `flow/synth_ip.sh aegis_tcm`
