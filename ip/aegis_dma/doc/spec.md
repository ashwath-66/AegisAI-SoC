# aegis_dma - CPU-bypassed DMA with inline Speck-64/128 decryption

**Top module:** `aegis_dma`   **Base address:** 0x4000_0000

## Function
axi_dma + speck_decryptor. QSPI stream in, decrypt (27 cycles per 128-bit beat), AXI burst write to TCM, ping-pong bank toggle, auto-prefetch on GEMM pulse.

## Interfaces
s_axil_* CSR slave (4 KB); s_axis_t{data,valid,ready} 128-bit stream in; rd_start/addr/len/busy to QSPI; m_axi_* write master; dma_auto_prefetch in; fill_done/fill_bank/busy/irq out

## RTL (see rtl.f)
- `rtl/axi_dma.sv`
- `rtl/speck_decryptor.sv`
- `rtl/aegis_dma.sv`

## Testbenches (ip/aegis_dma/tb)
- `axi_mem_model.sv`
- `tb_dma.f`
- `tb_dma.sv`
- `tb_speck.f`
- `tb_speck.sv`

**Verification:** tb_dma (13 scenarios), tb_speck (published vector + random + stall)

## Run
`flow/run_ip_tb.sh aegis_dma`  |  synthesis: `flow/synth_ip.sh aegis_dma`
