`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// ping_pong_sram : two 128-bit-wide banks (default 512 words = 8 KB each)
//   - write port           : AXI side (byte strobes)          -> bank selected by w_bank
//   - read port A (AXI)    : granted only if GEMM is not reading the same bank
//   - read port B (GEMM)   : always wins
//   - synchronous read: data valid the cycle after the request (macro style)
//   Replace the behavioral arrays with OpenRAM/foundry macros for tape-out.
//-----------------------------------------------------------------------------
module ping_pong_sram #(
    parameter int WORDS = 512
) (
    input  logic         clk,

    input  logic         w_en,
    input  logic         w_bank,
    input  logic [8:0]   w_word,
    input  logic [15:0]  w_strb,
    input  logic [127:0] w_data,

    input  logic         ra_en,
    input  logic         ra_bank,
    input  logic [8:0]   ra_word,
    output logic         ra_grant,
    output logic [127:0] ra_data,

    input  logic         rb_en,
    input  logic         rb_bank,
    input  logic [8:0]   rb_word,
    output logic [127:0] rb_data
);

    logic [127:0] rd_q_bank [2];
    logic         ra_bank_q, rb_bank_q;

    // GEMM port has priority on a bank conflict
    assign ra_grant = ra_en && !(rb_en && (rb_bank == ra_bank));

    for (genvar b = 0; b < 2; b++) begin : g_bank
        (* ram_style = "block" *) logic [127:0] mem [WORDS];
        logic         gem_sel, axi_sel, rd_en;
        logic [8:0]   rd_word;
        logic [127:0] rd_q;
        assign gem_sel = rb_en && (rb_bank == b[0]);
        assign axi_sel = ra_grant && (ra_bank == b[0]);
        assign rd_en   = gem_sel || axi_sel;
        assign rd_word = gem_sel ? rb_word : ra_word;

        always_ff @(posedge clk) begin
            if (w_en && (w_bank == b[0]))
                for (int i = 0; i < 16; i++)
                    if (w_strb[i]) mem[w_word][i*8 +: 8] <= w_data[i*8 +: 8];
            if (rd_en) rd_q <= mem[rd_word];
        end
        assign rd_q_bank[b] = rd_q;
    end

    always_ff @(posedge clk) begin
        if (ra_grant) ra_bank_q <= ra_bank;
        if (rb_en)    rb_bank_q <= rb_bank;
    end

    assign ra_data = rd_q_bank[ra_bank_q];
    assign rb_data = rd_q_bank[rb_bank_q];

endmodule