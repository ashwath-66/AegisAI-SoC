`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axil_sram : CPU scratch SRAM (stack, data, result copies), 32-bit, byte strobes
//   Behavioral array; replace with a foundry/OpenRAM macro for tape-out.
//-----------------------------------------------------------------------------
module axil_sram #(
    parameter int WORDS = 4096                     // 16 KB
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] s_awaddr,  input logic s_awvalid, output logic s_awready,
    input  logic [31:0] s_wdata,   input logic [3:0] s_wstrb,
    input  logic        s_wvalid,  output logic s_wready,
    output logic [1:0]  s_bresp,   output logic s_bvalid, input logic s_bready,
    input  logic [31:0] s_araddr,  input logic s_arvalid, output logic s_arready,
    output logic [31:0] s_rdata,   output logic [1:0] s_rresp,
    output logic        s_rvalid,  input logic s_rready
);
    localparam int AWB = $clog2(WORDS);
    logic [31:0] mem [WORDS];

    logic            wr_en, rd_en;
    logic [AWB+1:0]  wr_addr, rd_addr;
    logic [31:0]     wr_data, rd_q;
    logic [3:0]      wr_strb;

    axil_regif #(.AW(AWB+2)) u_if (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .wr_strb(wr_strb), .wr_err(1'b0),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_q), .rd_err(1'b0)
    );

    always_ff @(posedge clk) begin
        if (wr_en)
            for (int i = 0; i < 4; i++)
                if (wr_strb[i]) mem[wr_addr[AWB+1:2]][i*8 +: 8] <= wr_data[i*8 +: 8];
        rd_q <= mem[rd_addr[AWB+1:2]];
    end
endmodule
