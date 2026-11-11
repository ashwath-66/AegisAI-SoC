`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// aegis_qspi : QSPI flash read IP
//   = axil2apb bridge + apb_spi_master (shift engine + RX FIFO)
//   Interfaces : AXI4-Lite slave (CSRs, through an internal APB bridge)
//                QSPI pins qspi_sck / qspi_cs_n / qspi_io[3:0]
//                AXI-Stream master m_axis_*  (128-bit beats)
//                read-launch sideband rd_start/rd_addr/rd_len (from the DMA IP), rd_busy
//                irq
//-----------------------------------------------------------------------------
module aegis_qspi (
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

    // QSPI pins
    output logic         qspi_sck,
    output logic         qspi_cs_n,
    inout  wire  [3:0]   qspi_io,

    // AXI-Stream out
    output logic [127:0] m_axis_tdata,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,

    // read-launch sideband (from DMA)
    input  logic         rd_start,
    input  logic [23:0]  rd_addr,
    input  logic [24:0]  rd_len,
    output logic         rd_busy,

    output logic         irq
);
    logic        psel, penable, pwrite, pready, pslverr;
    logic [31:0] paddr, pwdata, prdata;

    axil2apb u_apb_bridge (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_axil_awaddr), .s_awvalid(s_axil_awvalid), .s_awready(s_axil_awready),
        .s_wdata(s_axil_wdata), .s_wstrb(s_axil_wstrb), .s_wvalid(s_axil_wvalid), .s_wready(s_axil_wready),
        .s_bresp(s_axil_bresp), .s_bvalid(s_axil_bvalid), .s_bready(s_axil_bready),
        .s_araddr(s_axil_araddr), .s_arvalid(s_axil_arvalid), .s_arready(s_axil_arready),
        .s_rdata(s_axil_rdata), .s_rresp(s_axil_rresp), .s_rvalid(s_axil_rvalid), .s_rready(s_axil_rready),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    apb_spi_master u_spi (
        .pclk(clk), .presetn(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr), .irq(irq),
        .qspi_sck(qspi_sck), .qspi_cs_n(qspi_cs_n), .qspi_io(qspi_io),
        .stream_valid_out(m_axis_tvalid), .stream_ready_in(m_axis_tready), .stream_data_out(m_axis_tdata),
        .hw_start(rd_start), .hw_addr(rd_addr), .hw_len(rd_len), .spi_busy(rd_busy), .spi_done()
    );
endmodule
