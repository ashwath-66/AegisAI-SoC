`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// aegis_dma : CPU-bypassed DMA IP with inline Speck-64/128 stream decryption
//   = axi_dma (CSRs, FSM, auto-prefetch) + speck_decryptor (inside axi_dma)
//   Interfaces : AXI4-Lite slave (CSRs)
//                AXI-Stream slave  s_axis_*   (128-bit beats from the QSPI IP)
//                read-launch sideband rd_start/rd_addr/rd_len/rd_busy (to QSPI IP)
//                AXI4 master (write only) m_axi_*  -> TCM
//                GEMM handshake dma_auto_prefetch (in), fill_done/fill_bank (out)
//                busy, irq
//-----------------------------------------------------------------------------
module aegis_dma (
    input  logic         clk,
    input  logic         rst_n,

    // AXI4-Lite slave
    input  logic [31:0]  s_axil_awaddr,
    input  logic         s_axil_awvalid,
    output logic         s_axil_awready,
    input  logic [31:0]  s_axil_wdata,
    input  logic [3:0]   s_axil_wstrb,
    input  logic         s_axil_wvalid,
    output logic         s_axil_wready,
    output logic [1:0]   s_axil_bresp,
    output logic         s_axil_bvalid,
    input  logic         s_axil_bready,
    input  logic [31:0]  s_axil_araddr,
    input  logic         s_axil_arvalid,
    output logic         s_axil_arready,
    output logic [31:0]  s_axil_rdata,
    output logic [1:0]   s_axil_rresp,
    output logic         s_axil_rvalid,
    input  logic         s_axil_rready,

    // AXI-Stream in (from QSPI)
    input  logic [127:0] s_axis_tdata,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,

    // read-launch sideband (to QSPI)
    output logic         rd_start,
    output logic [23:0]  rd_addr,
    output logic [24:0]  rd_len,
    input  logic         rd_busy,

    // AXI4 master, write-only
    output logic [31:0]  m_axi_awaddr,
    output logic [7:0]   m_axi_awlen,
    output logic [2:0]   m_axi_awsize,
    output logic [1:0]   m_axi_awburst,
    output logic         m_axi_awvalid,
    input  logic         m_axi_awready,
    output logic [127:0] m_axi_wdata,
    output logic [15:0]  m_axi_wstrb,
    output logic         m_axi_wlast,
    output logic         m_axi_wvalid,
    input  logic         m_axi_wready,
    input  logic [1:0]   m_axi_bresp,
    input  logic         m_axi_bvalid,
    output logic         m_axi_bready,

    // GEMM handshake
    input  logic         dma_auto_prefetch,
    output logic         fill_done,
    output logic         fill_bank,
    output logic         busy,
    output logic         irq
);
    axi_dma u_dma (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_axil_awaddr),
        .s_axil_awvalid(s_axil_awvalid),
        .s_axil_awready(s_axil_awready),
        .s_axil_wdata(s_axil_wdata),
        .s_axil_wstrb(s_axil_wstrb),
        .s_axil_wvalid(s_axil_wvalid),
        .s_axil_wready(s_axil_wready),
        .s_axil_bresp(s_axil_bresp),
        .s_axil_bvalid(s_axil_bvalid),
        .s_axil_bready(s_axil_bready),
        .s_axil_araddr(s_axil_araddr),
        .s_axil_arvalid(s_axil_arvalid),
        .s_axil_arready(s_axil_arready),
        .s_axil_rdata(s_axil_rdata),
        .s_axil_rresp(s_axil_rresp),
        .s_axil_rvalid(s_axil_rvalid),
        .s_axil_rready(s_axil_rready),
        .s_valid(s_axis_tvalid), .s_ready(s_axis_tready), .s_data(s_axis_tdata),
        .spi_start(rd_start), .spi_addr(rd_addr), .spi_len(rd_len), .spi_busy(rd_busy),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .dma_auto_prefetch(dma_auto_prefetch), .fill_done(fill_done), .fill_bank(fill_bank),
        .busy(busy), .irq(irq)
    );
endmodule
