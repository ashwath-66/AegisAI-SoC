`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// Module: qspi_fifo
// Description: 128-bit wide FIFO buffer matching AXI DMA data width
//-----------------------------------------------------------------------------

module qspi_fifo #(
    parameter int DATA_WIDTH = 128,
    parameter int DEPTH      = 16
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] din,
    output logic [DATA_WIDTH-1:0] dout,
    input  logic                  rd_en,
    output logic                  full,
    output logic                  empty
);

    logic [DATA_WIDTH-1:0] fifo_mem [DEPTH-1:0];
    logic [$clog2(DEPTH):0] wr_ptr, rd_ptr;

    assign full  = (wr_ptr[$clog2(DEPTH)] != rd_ptr[$clog2(DEPTH)]) && (wr_ptr[$clog2(DEPTH)-1:0] == rd_ptr[$clog2(DEPTH)-1:0]);
    assign empty = (wr_ptr == rd_ptr);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (wr_en && !full) begin
                fifo_mem[wr_ptr[$clog2(DEPTH)-1:0]] <= din;
                wr_ptr <= wr_ptr + 1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end

    assign dout = fifo_mem[rd_ptr[$clog2(DEPTH)-1:0]];

endmodule