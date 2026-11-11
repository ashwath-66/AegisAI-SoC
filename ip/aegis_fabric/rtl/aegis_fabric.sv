`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// aegis_fabric : AXI4-Lite interconnect IP, SoC address map baked in
//   2 masters (0 = CPU instr, 1 = CPU data) -> 6 slaves, DECERR slave for holes
//     slave 0 ROM    0x0000_0000  16 KB      slave 3 QSPI  0x4000_1000  4 KB
//     slave 1 SRAM   0x2000_0000  16 KB      slave 4 GEMM  0x4001_0000  8 KB
//     slave 2 DMA    0x4000_0000  4 KB       slave 5 SYS   0x4002_0000  4 KB
//   (TCM at 0x1000_0000 is accelerator-private and not on this fabric)
//-----------------------------------------------------------------------------
module aegis_fabric #(
    parameter int NM = 2,
    parameter int NS = 6
) (
    input  logic clk,
    input  logic rst_n,

    input  logic [NM-1:0][31:0] m_awaddr,  input  logic [NM-1:0] m_awvalid, output logic [NM-1:0] m_awready,
    input  logic [NM-1:0][31:0] m_wdata,   input  logic [NM-1:0][3:0] m_wstrb,
    input  logic [NM-1:0]       m_wvalid,  output logic [NM-1:0] m_wready,
    output logic [NM-1:0][1:0]  m_bresp,   output logic [NM-1:0] m_bvalid, input logic [NM-1:0] m_bready,
    input  logic [NM-1:0][31:0] m_araddr,  input  logic [NM-1:0] m_arvalid, output logic [NM-1:0] m_arready,
    output logic [NM-1:0][31:0] m_rdata,   output logic [NM-1:0][1:0] m_rresp,
    output logic [NM-1:0]       m_rvalid,  input  logic [NM-1:0] m_rready,

    output logic [NS-1:0][31:0] s_awaddr,  output logic [NS-1:0] s_awvalid, input logic [NS-1:0] s_awready,
    output logic [NS-1:0][31:0] s_wdata,   output logic [NS-1:0][3:0] s_wstrb,
    output logic [NS-1:0]       s_wvalid,  input  logic [NS-1:0] s_wready,
    input  logic [NS-1:0][1:0]  s_bresp,   input  logic [NS-1:0] s_bvalid, output logic [NS-1:0] s_bready,
    output logic [NS-1:0][31:0] s_araddr,  output logic [NS-1:0] s_arvalid, input logic [NS-1:0] s_arready,
    input  logic [NS-1:0][31:0] s_rdata,   input  logic [NS-1:0][1:0] s_rresp,
    input  logic [NS-1:0]       s_rvalid,  output logic [NS-1:0] s_rready
);
    localparam logic [5:0][31:0] XBASE = {32'h4002_0000, 32'h4001_0000, 32'h4000_1000,
                                           32'h4000_0000, 32'h2000_0000, 32'h0000_0000};
    localparam logic [5:0][31:0] XMASK = {32'hFFFF_F000, 32'hFFFF_E000, 32'hFFFF_F000,
                                           32'hFFFF_F000, 32'hFFFF_C000, 32'hFFFF_C000};

    axil_xbar #(.NM(NM), .NS(NS), .BASE(XBASE), .MASK(XMASK)) u_xbar (
        .clk(clk), .rst_n(rst_n),
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
endmodule
