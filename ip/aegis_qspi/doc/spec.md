# aegis_qspi - QSPI flash read IP

**Top module:** `aegis_qspi`   **Base address:** 0x4000_1000

## Function
axil2apb bridge + apb_spi_master (shift engine, 4-deep x 128-bit RX FIFO, back-pressure).

## Interfaces
s_axil_* CSR slave (4 KB); qspi_sck/qspi_cs_n/qspi_io[3:0]; m_axis_t{data,valid,ready} 128-bit stream out; rd_start/addr/len in, rd_busy out; irq

## RTL (see rtl.f)
- `rtl/axil2apb.sv`
- `rtl/apb_spi_master.sv`
- `rtl/qspi_shift.sv`
- `rtl/qspi_fifo.sv`
- `rtl/aegis_qspi.sv`

## Testbenches (ip/aegis_qspi/tb)
- `flash_model.sv`
- `tb_qspi.f`
- `tb_qspi.sv`

**Verification:** tb_qspi (EBh/6Bh reads, div 0..3, back-pressure, CPU pop path, IRQ, PSLVERR)

## Run
`flow/run_ip_tb.sh aegis_qspi`  |  synthesis: `flow/synth_ip.sh aegis_qspi`
