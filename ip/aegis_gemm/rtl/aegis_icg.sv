`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// icg_cell : latch-based integrated clock gate (generic RTL model)
//   enable is sampled while clk is LOW (latch transparent), so clk_out can never
//   glitch.  ASIC: replace the body with the library ICG cell (e.g. sky130
//   sky130_fd_sc_hd__dlclkp, TSMC CKLNQD*) and keep the same port list.
//   FPGA: do NOT use this; build with CLK_GATE=0 (clock-enable) or use BUFGCE.
//-----------------------------------------------------------------------------
module icg_cell (
    input  logic clk,
    input  logic enable,
    output logic clk_out
);
    logic latch_out;
    always_latch begin
        if (!clk) latch_out = enable;
    end
    assign clk_out = clk && latch_out;
endmodule
