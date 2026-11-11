`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// aegis_gemm : INT8 GEMM accelerator IP
//   = gemm_controller (CSRs, tile sequencer, result buffer, prefetch handshake)
//   + systolic_array 16x16 with zero-sensing / micro-clock-gated PEs
//   Interfaces : AXI4-Lite slave (CSRs + result window, 8 KB)
//                TCM read port  (g_en/g_bank/g_word -> g_rdata, 1-cycle latency)
//                DMA handshake  (fill_done/fill_bank in, dma_auto_prefetch out)
//                irq, pe_gated (per-PE gated flag, for power statistics)
//-----------------------------------------------------------------------------
module aegis_gemm #(
    parameter bit PE_CLK_GATE = 1'b0      // 1 = latch ICG per PE (ASIC), 0 = clock-enable (FPGA)
) (
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

    // DMA handshake (Innovation 2)
    input  logic         fill_done,
    input  logic         fill_bank,
    output logic         dma_auto_prefetch,

    // TCM read port
    output logic         g_en,
    output logic         g_bank,
    output logic [8:0]   g_word,
    input  logic [127:0] g_rdata,

    output logic         irq,
    output logic [255:0] pe_gated
);
    logic         w_load_en, a_valid, c_valid;
    logic [3:0]   w_load_row;
    logic [127:0] w_load_data, a_row;
    logic [16*20-1:0] c_row;

    gemm_controller u_ctrl (
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
        .fill_done(fill_done), .fill_bank(fill_bank), .dma_auto_prefetch(dma_auto_prefetch),
        .g_en(g_en), .g_bank(g_bank), .g_word(g_word), .g_rdata(g_rdata),
        .w_load_en(w_load_en), .w_load_row(w_load_row), .w_load_data(w_load_data),
        .a_valid(a_valid), .a_row(a_row), .c_valid(c_valid), .c_row(c_row), .irq(irq)
    );

    systolic_array #(.CLK_GATE(PE_CLK_GATE)) u_array (
        .clk(clk), .rst_n(rst_n),
        .w_load_en(w_load_en), .w_load_row(w_load_row), .w_load_data(w_load_data),
        .a_valid(a_valid), .a_row(a_row), .c_valid(c_valid), .c_row(c_row),
        .pe_gated(pe_gated)
    );
endmodule
