`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// pe : weight-stationary INT8 MAC processing element (Innovation 3)
//
//   Zero sensing, two exact mechanisms (results are bit-identical to a plain PE):
//   1. Operand isolation : if a==0 or w==0 the multiplier inputs are forced to 0
//      (skip=1), so the multiplier does not toggle.
//   2. Micro clock gating: the a_out / psum_out registers are clock-gated when
//      their next value equals the value they already hold. That is guaranteed
//      when the inputs are all-zero (a_in==0 && psum_in==0) and the registers
//      already hold zero ("quiet").  Zero inputs flow through the pipeline fill/
//      drain skew and sparse data, so the gate fires there.
//      A zero activation does NOT gate a PE whose psum_in is non-zero: the PE
//      must still forward psum_in down the column.
//
//   CLK_GATE = 0 : gating expressed as a clock-enable (FPGA, simulation baseline)
//   CLK_GATE = 1 : real latch-based ICG per PE (ASIC)
//-----------------------------------------------------------------------------
module pe #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 20,
    parameter bit CLK_GATE   = 1'b0
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         w_load,
    input  logic signed [DATA_WIDTH-1:0] w_in,

    input  logic signed [DATA_WIDTH-1:0] a_in,
    input  logic signed [ACC_WIDTH-1:0]  psum_in,
    output logic signed [DATA_WIDTH-1:0] a_out,
    output logic signed [ACC_WIDTH-1:0]  psum_out,

    output logic                         skip,    // multiplier isolated this cycle
    output logic                         gated    // a_out/psum_out clock gated this cycle
);
    logic signed [DATA_WIDTH-1:0]   w_reg;
    logic signed [DATA_WIDTH-1:0]   a_iso, w_iso;
    logic signed [2*DATA_WIDTH-1:0] product;
    logic signed [ACC_WIDTH-1:0]    psum_n;
    logic                           quiet;       // a_out == 0 and psum_out == 0

    wire in_zero = (a_in == '0) && (psum_in == '0);

    assign skip   = (a_in == '0) || (w_reg == '0);
    assign a_iso  = skip ? '0 : a_in;
    assign w_iso  = skip ? '0 : w_reg;
    assign product = a_iso * w_iso;
    assign psum_n  = psum_in + ACC_WIDTH'(product);
    assign gated   = quiet && in_zero;

    // weight register and quiet flag stay on the free-running clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_reg <= '0;
            quiet <= 1'b1;
        end else begin
            if (w_load) w_reg <= w_in;
            quiet <= in_zero;
        end
    end

    if (CLK_GATE) begin : g_icg
        logic gclk;
        icg_cell u_icg (.clk(clk), .enable(!gated), .clk_out(gclk));
        always_ff @(posedge gclk or negedge rst_n) begin
            if (!rst_n) begin a_out <= '0; psum_out <= '0; end
            else        begin a_out <= a_in; psum_out <= psum_n; end
        end
    end else begin : g_ce
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n)      begin a_out <= '0; psum_out <= '0; end
            else if (!gated) begin a_out <= a_in; psum_out <= psum_n; end
        end
    end
endmodule
