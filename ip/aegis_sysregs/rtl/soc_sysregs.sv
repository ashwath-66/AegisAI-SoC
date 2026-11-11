`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// soc_sysregs : chip ID, scratch, interrupt status, debug character port and
//               simulation/bring-up exit flag
//   0x00 ID        RO  0xAE610001
//   0x04 TXCHAR    WO  low byte -> dbg_char (one-cycle dbg_char_valid pulse)
//   0x08 SCRATCH0  RW
//   0x0C IRQ_RAW   RO  [0] GEMM [1] DMA [2] SPI
//   0x10 EXIT      RW  1 = firmware PASS, 2 = firmware FAIL  (drives dbg_done/dbg_pass)
//   0x14 SCRATCH1  RW
//-----------------------------------------------------------------------------
module soc_sysregs (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] s_awaddr,  input logic s_awvalid, output logic s_awready,
    input  logic [31:0] s_wdata,   input logic [3:0] s_wstrb,
    input  logic        s_wvalid,  output logic s_wready,
    output logic [1:0]  s_bresp,   output logic s_bvalid, input logic s_bready,
    input  logic [31:0] s_araddr,  input logic s_arvalid, output logic s_arready,
    output logic [31:0] s_rdata,   output logic [1:0] s_rresp,
    output logic        s_rvalid,  input logic s_rready,

    input  logic [2:0]  irq_raw,
    output logic        dbg_char_valid,
    output logic [7:0]  dbg_char,
    output logic        dbg_done,
    output logic        dbg_pass
);
    localparam logic [31:0] CHIP_ID = 32'hAE61_0001;

    logic        wr_en, rd_en;
    logic [7:0]  wr_addr, rd_addr;
    logic [31:0] wr_data, rd_data;
    logic [31:0] scratch0, scratch1;
    logic [1:0]  exit_code;

    wire wr_ok = (wr_addr inside {8'h04, 8'h08, 8'h10, 8'h14});
    always_comb
        case (rd_addr)
            8'h00:   rd_data = CHIP_ID;
            8'h08:   rd_data = scratch0;
            8'h0C:   rd_data = {29'b0, irq_raw};
            8'h10:   rd_data = {30'b0, exit_code};
            8'h14:   rd_data = scratch1;
            default: rd_data = 32'h0;
        endcase
    wire rd_ok = (rd_addr inside {8'h00, 8'h08, 8'h0C, 8'h10, 8'h14});

    axil_regif #(.AW(8)) u_if (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .wr_strb(), .wr_err(!wr_ok),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data), .rd_err(!rd_ok)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scratch0 <= 0; scratch1 <= 0; exit_code <= 0; dbg_char_valid <= 0; dbg_char <= 0;
        end else begin
            dbg_char_valid <= 1'b0;
            if (wr_en) begin
                case (wr_addr)
                    8'h04: begin dbg_char <= wr_data[7:0]; dbg_char_valid <= 1'b1; end
                    8'h08: scratch0  <= wr_data;
                    8'h10: exit_code <= wr_data[1:0];
                    8'h14: scratch1  <= wr_data;
                    default: ;
                endcase
            end
        end
    end

    assign dbg_done = (exit_code != 2'b00);
    assign dbg_pass = (exit_code == 2'b01);
endmodule
