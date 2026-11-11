# aegis_gemm - INT8 GEMM accelerator

**Top module:** `aegis_gemm`   **Base address:** 0x4001_0000

## Function
gemm_controller (CSRs, tile FSM, 64x16x20-bit result buffer, prefetch handshake, ERR/OVERRUN, IRQ) + 16x16 weight-stationary systolic array. PE zero-sensing: operand isolation + exact micro clock gating (param PE_CLK_GATE).

## Interfaces
s_axil_* CSR + result window (8 KB); fill_done/fill_bank in, dma_auto_prefetch out; g_en/g_bank/g_word/g_rdata TCM port; irq; pe_gated[255:0]

## RTL (see rtl.f)
- `rtl/gemm_controller.sv`
- `rtl/systolic_array.sv`
- `rtl/pe.sv`
- `rtl/aegis_icg.sv`
- `rtl/aegis_gemm.sv`
- `ip/aegis_common/rtl/axil_regif.sv`

## Testbenches (ip/aegis_gemm/tb)
- `tb_gemm.f`
- `tb_gemm.sv`
- `tb_gemm_subsys.f`
- `tb_gemm_subsys.sv`
- `tb_pe.f`
- `tb_pe.sv`

**Verification:** tb_pe (gating bit-exact), tb_gemm (304 rows, both gating modes), tb_gemm_subsys (flash->decrypt->TCM->GEMM, 7 scenarios)

## Run
`flow/run_ip_tb.sh aegis_gemm`  |  synthesis: `flow/synth_ip.sh aegis_gemm`
