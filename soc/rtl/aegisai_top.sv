`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// aegisai_top : AegisAI-SoC integration (pure IP instantiation, no logic of its own)
//
//   aegis_cpu --m_axil_i/d--> aegis_fabric --> ROM / SRAM / aegis_dma CSR / aegis_qspi CSR /
//                                              aegis_gemm CSR+result / soc_sysregs
//   aegis_qspi --AXI-Stream--> aegis_dma (Speck decrypt) --AXI4--> axi_tcm (bank A/B)
//   axi_tcm GEMM port <--> aegis_gemm ;  aegis_gemm.dma_auto_prefetch --> aegis_dma
//
//   Memory map  0x0000_0000 ROM 16K | 0x1000_0000 TCM 2x8K (accelerator-private) |
//               0x2000_0000 SRAM 16K | 0x4000_0000 DMA | 0x4000_1000 QSPI |
//               0x4001_0000 GEMM 8K | 0x4002_0000 SYS
//   IRQs: irq_fast[0] GEMM tile done, [1] DMA done, [2] QSPI done
//-----------------------------------------------------------------------------
module aegisai_top (
    input  logic        clk,
    input  logic        rst_n,

    output logic        qspi_sck,
    output logic        qspi_cs_n,
    inout  wire  [3:0]  qspi_io,

    output logic        dbg_char_valid,
    output logic [7:0]  dbg_char,
    output logic        dbg_done,
    output logic        dbg_pass,
    output logic        cpu_sleep,
    output logic        cpu_alert
);
    localparam bit PE_CLK_GATE = 1'b0;   // 1 = per-PE latch ICG (ASIC flow only)
    localparam int NM = 2;
    localparam int NS = 6;
    localparam int S_ROM = 0, S_SRAM = 1, S_DMA = 2, S_SPI = 3, S_GEMM = 4, S_SYS = 5;

    logic rst_ns;
    reset_sync u_rst (.clk(clk), .rst_n_in(rst_n), .rst_n_out(rst_ns));

    logic [14:0] irq_fast;
    logic        spi_irq, dma_irq, gem_irq;

    // fabric masters / slaves
    logic [NM-1:0][31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
    logic [NM-1:0][3:0]  m_wstrb;
    logic [NM-1:0]       m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
    logic [NM-1:0]       m_arvalid, m_arready, m_rvalid, m_rready;
    logic [NM-1:0][1:0]  m_bresp, m_rresp;

    logic [NS-1:0][31:0] s_awaddr, s_wdata, s_araddr, s_rdata;
    logic [NS-1:0][3:0]  s_wstrb;
    logic [NS-1:0]       s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
    logic [NS-1:0]       s_arvalid, s_arready, s_rvalid, s_rready;
    logic [NS-1:0][1:0]  s_bresp, s_rresp;

    // ---------------- IP: CPU --------------------------------------------------
    aegis_cpu u_cpu (
        .clk(clk), .rst_n(rst_ns), .irq_fast(irq_fast), .cpu_sleep(cpu_sleep), .cpu_alert(cpu_alert),
        .m_axil_i_awaddr(m_awaddr[0]),
        .m_axil_i_awvalid(m_awvalid[0]),
        .m_axil_i_awready(m_awready[0]),
        .m_axil_i_wdata(m_wdata[0]),
        .m_axil_i_wstrb(m_wstrb[0]),
        .m_axil_i_wvalid(m_wvalid[0]),
        .m_axil_i_wready(m_wready[0]),
        .m_axil_i_bresp(m_bresp[0]),
        .m_axil_i_bvalid(m_bvalid[0]),
        .m_axil_i_bready(m_bready[0]),
        .m_axil_i_araddr(m_araddr[0]),
        .m_axil_i_arvalid(m_arvalid[0]),
        .m_axil_i_arready(m_arready[0]),
        .m_axil_i_rdata(m_rdata[0]),
        .m_axil_i_rresp(m_rresp[0]),
        .m_axil_i_rvalid(m_rvalid[0]),
        .m_axil_i_rready(m_rready[0]),
        .m_axil_d_awaddr(m_awaddr[1]),
        .m_axil_d_awvalid(m_awvalid[1]),
        .m_axil_d_awready(m_awready[1]),
        .m_axil_d_wdata(m_wdata[1]),
        .m_axil_d_wstrb(m_wstrb[1]),
        .m_axil_d_wvalid(m_wvalid[1]),
        .m_axil_d_wready(m_wready[1]),
        .m_axil_d_bresp(m_bresp[1]),
        .m_axil_d_bvalid(m_bvalid[1]),
        .m_axil_d_bready(m_bready[1]),
        .m_axil_d_araddr(m_araddr[1]),
        .m_axil_d_arvalid(m_arvalid[1]),
        .m_axil_d_arready(m_arready[1]),
        .m_axil_d_rdata(m_rdata[1]),
        .m_axil_d_rresp(m_rresp[1]),
        .m_axil_d_rvalid(m_rvalid[1]),
        .m_axil_d_rready(m_rready[1])
    );

    // ---------------- IP: fabric ------------------------------------------------
    aegis_fabric #(.NM(NM), .NS(NS)) u_fabric (
        .clk(clk), .rst_n(rst_ns),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rvalid(m_rvalid), .m_rready(m_rready),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready)
    );

    // ---------------- IP: ROM / SRAM -------------------------------------------
    axil_rom #(.WORDS(4096), .INIT_FILE("boot.hex")) u_rom (
        .clk(clk), .rst_n(rst_ns),
        .s_awaddr(s_awaddr[S_ROM]),
        .s_awvalid(s_awvalid[S_ROM]),
        .s_awready(s_awready[S_ROM]),
        .s_wdata(s_wdata[S_ROM]),
        .s_wstrb(s_wstrb[S_ROM]),
        .s_wvalid(s_wvalid[S_ROM]),
        .s_wready(s_wready[S_ROM]),
        .s_bresp(s_bresp[S_ROM]),
        .s_bvalid(s_bvalid[S_ROM]),
        .s_bready(s_bready[S_ROM]),
        .s_araddr(s_araddr[S_ROM]),
        .s_arvalid(s_arvalid[S_ROM]),
        .s_arready(s_arready[S_ROM]),
        .s_rdata(s_rdata[S_ROM]),
        .s_rresp(s_rresp[S_ROM]),
        .s_rvalid(s_rvalid[S_ROM]),
        .s_rready(s_rready[S_ROM])
    );
    axil_sram #(.WORDS(4096)) u_sram (
        .clk(clk), .rst_n(rst_ns),
        .s_awaddr(s_awaddr[S_SRAM]),
        .s_awvalid(s_awvalid[S_SRAM]),
        .s_awready(s_awready[S_SRAM]),
        .s_wdata(s_wdata[S_SRAM]),
        .s_wstrb(s_wstrb[S_SRAM]),
        .s_wvalid(s_wvalid[S_SRAM]),
        .s_wready(s_wready[S_SRAM]),
        .s_bresp(s_bresp[S_SRAM]),
        .s_bvalid(s_bvalid[S_SRAM]),
        .s_bready(s_bready[S_SRAM]),
        .s_araddr(s_araddr[S_SRAM]),
        .s_arvalid(s_arvalid[S_SRAM]),
        .s_arready(s_arready[S_SRAM]),
        .s_rdata(s_rdata[S_SRAM]),
        .s_rresp(s_rresp[S_SRAM]),
        .s_rvalid(s_rvalid[S_SRAM]),
        .s_rready(s_rready[S_SRAM])
    );

    // ---------------- accelerator IPs --------------------------------------------
    logic [127:0] axis_tdata;
    logic         axis_tvalid, axis_tready;
    logic         rd_start, rd_busy;
    logic [23:0]  rd_addr;
    logic [24:0]  rd_len;

    logic [31:0] d_awaddr; logic [7:0] d_awlen; logic [2:0] d_awsize; logic [1:0] d_awburst; logic d_awvalid, d_awready;
    logic [127:0] d_wdata; logic [15:0] d_wstrb; logic d_wlast, d_wvalid, d_wready;
    logic [1:0] d_bresp; logic d_bvalid, d_bready;
    logic fill_done, fill_bank, dma_busy, auto_pf;
    logic g_en, g_bank; logic [8:0] g_word; logic [127:0] g_rdata;

    aegis_dma u_dma (
        .clk(clk), .rst_n(rst_ns),
        .s_axil_awaddr(s_awaddr[S_DMA]),
        .s_axil_awvalid(s_awvalid[S_DMA]),
        .s_axil_awready(s_awready[S_DMA]),
        .s_axil_wdata(s_wdata[S_DMA]),
        .s_axil_wstrb(s_wstrb[S_DMA]),
        .s_axil_wvalid(s_wvalid[S_DMA]),
        .s_axil_wready(s_wready[S_DMA]),
        .s_axil_bresp(s_bresp[S_DMA]),
        .s_axil_bvalid(s_bvalid[S_DMA]),
        .s_axil_bready(s_bready[S_DMA]),
        .s_axil_araddr(s_araddr[S_DMA]),
        .s_axil_arvalid(s_arvalid[S_DMA]),
        .s_axil_arready(s_arready[S_DMA]),
        .s_axil_rdata(s_rdata[S_DMA]),
        .s_axil_rresp(s_rresp[S_DMA]),
        .s_axil_rvalid(s_rvalid[S_DMA]),
        .s_axil_rready(s_rready[S_DMA]),
        .s_axis_tdata(axis_tdata), .s_axis_tvalid(axis_tvalid), .s_axis_tready(axis_tready),
        .rd_start(rd_start), .rd_addr(rd_addr), .rd_len(rd_len), .rd_busy(rd_busy),
        .m_axi_awaddr(d_awaddr), .m_axi_awlen(d_awlen), .m_axi_awsize(d_awsize), .m_axi_awburst(d_awburst),
        .m_axi_awvalid(d_awvalid), .m_axi_awready(d_awready),
        .m_axi_wdata(d_wdata), .m_axi_wstrb(d_wstrb), .m_axi_wlast(d_wlast), .m_axi_wvalid(d_wvalid), .m_axi_wready(d_wready),
        .m_axi_bresp(d_bresp), .m_axi_bvalid(d_bvalid), .m_axi_bready(d_bready),
        .dma_auto_prefetch(auto_pf), .fill_done(fill_done), .fill_bank(fill_bank), .busy(dma_busy), .irq(dma_irq)
    );

    axi_tcm #(.BASE(32'h1000_0000)) u_tcm (
        .clk(clk), .rst_n(rst_ns),
        .s_axi_awaddr(d_awaddr), .s_axi_awlen(d_awlen), .s_axi_awsize(d_awsize), .s_axi_awburst(d_awburst),
        .s_axi_awvalid(d_awvalid), .s_axi_awready(d_awready),
        .s_axi_wdata(d_wdata), .s_axi_wstrb(d_wstrb), .s_axi_wlast(d_wlast), .s_axi_wvalid(d_wvalid), .s_axi_wready(d_wready),
        .s_axi_bresp(d_bresp), .s_axi_bvalid(d_bvalid), .s_axi_bready(d_bready),
        .s_axi_araddr(32'b0), .s_axi_arlen(8'b0), .s_axi_arsize(3'd4), .s_axi_arburst(2'b01),
        .s_axi_arvalid(1'b0), .s_axi_arready(), .s_axi_rdata(), .s_axi_rresp(), .s_axi_rlast(),
        .s_axi_rvalid(), .s_axi_rready(1'b1),
        .g_en(g_en), .g_bank(g_bank), .g_word(g_word), .g_rdata(g_rdata)
    );

    aegis_gemm #(.PE_CLK_GATE(PE_CLK_GATE)) u_gemm (
        .clk(clk), .rst_n(rst_ns),
        .s_axil_awaddr(s_awaddr[S_GEMM]),
        .s_axil_awvalid(s_awvalid[S_GEMM]),
        .s_axil_awready(s_awready[S_GEMM]),
        .s_axil_wdata(s_wdata[S_GEMM]),
        .s_axil_wstrb(s_wstrb[S_GEMM]),
        .s_axil_wvalid(s_wvalid[S_GEMM]),
        .s_axil_wready(s_wready[S_GEMM]),
        .s_axil_bresp(s_bresp[S_GEMM]),
        .s_axil_bvalid(s_bvalid[S_GEMM]),
        .s_axil_bready(s_bready[S_GEMM]),
        .s_axil_araddr(s_araddr[S_GEMM]),
        .s_axil_arvalid(s_arvalid[S_GEMM]),
        .s_axil_arready(s_arready[S_GEMM]),
        .s_axil_rdata(s_rdata[S_GEMM]),
        .s_axil_rresp(s_rresp[S_GEMM]),
        .s_axil_rvalid(s_rvalid[S_GEMM]),
        .s_axil_rready(s_rready[S_GEMM]),
        .fill_done(fill_done), .fill_bank(fill_bank), .dma_auto_prefetch(auto_pf),
        .g_en(g_en), .g_bank(g_bank), .g_word(g_word), .g_rdata(g_rdata),
        .irq(gem_irq), .pe_gated()
    );

    aegis_qspi u_qspi (
        .clk(clk), .rst_n(rst_ns),
        .s_axil_awaddr(s_awaddr[S_SPI]),
        .s_axil_awvalid(s_awvalid[S_SPI]),
        .s_axil_awready(s_awready[S_SPI]),
        .s_axil_wdata(s_wdata[S_SPI]),
        .s_axil_wstrb(s_wstrb[S_SPI]),
        .s_axil_wvalid(s_wvalid[S_SPI]),
        .s_axil_wready(s_wready[S_SPI]),
        .s_axil_bresp(s_bresp[S_SPI]),
        .s_axil_bvalid(s_bvalid[S_SPI]),
        .s_axil_bready(s_bready[S_SPI]),
        .s_axil_araddr(s_araddr[S_SPI]),
        .s_axil_arvalid(s_arvalid[S_SPI]),
        .s_axil_arready(s_arready[S_SPI]),
        .s_axil_rdata(s_rdata[S_SPI]),
        .s_axil_rresp(s_rresp[S_SPI]),
        .s_axil_rvalid(s_rvalid[S_SPI]),
        .s_axil_rready(s_rready[S_SPI]),
        .qspi_sck(qspi_sck), .qspi_cs_n(qspi_cs_n), .qspi_io(qspi_io),
        .m_axis_tdata(axis_tdata), .m_axis_tvalid(axis_tvalid), .m_axis_tready(axis_tready),
        .rd_start(rd_start), .rd_addr(rd_addr), .rd_len(rd_len), .rd_busy(rd_busy),
        .irq(spi_irq)
    );

    // ---------------- IP: system registers -----------------------------------------
    soc_sysregs u_sys (
        .clk(clk), .rst_n(rst_ns),
        .s_awaddr(s_awaddr[S_SYS]),
        .s_awvalid(s_awvalid[S_SYS]),
        .s_awready(s_awready[S_SYS]),
        .s_wdata(s_wdata[S_SYS]),
        .s_wstrb(s_wstrb[S_SYS]),
        .s_wvalid(s_wvalid[S_SYS]),
        .s_wready(s_wready[S_SYS]),
        .s_bresp(s_bresp[S_SYS]),
        .s_bvalid(s_bvalid[S_SYS]),
        .s_bready(s_bready[S_SYS]),
        .s_araddr(s_araddr[S_SYS]),
        .s_arvalid(s_arvalid[S_SYS]),
        .s_arready(s_arready[S_SYS]),
        .s_rdata(s_rdata[S_SYS]),
        .s_rresp(s_rresp[S_SYS]),
        .s_rvalid(s_rvalid[S_SYS]),
        .s_rready(s_rready[S_SYS]),
        .irq_raw({spi_irq, dma_irq, gem_irq}),
        .dbg_char_valid(dbg_char_valid), .dbg_char(dbg_char), .dbg_done(dbg_done), .dbg_pass(dbg_pass)
    );

    assign irq_fast = {12'b0, spi_irq, dma_irq, gem_irq};
endmodule
