// Elaboration stub only (never selected: Impl == ImplGeneric). Keeps strict tools happy.
module prim_xilinx_clock_gating #(
  parameter bit NoFpgaGate = 1'b0,
  parameter bit FpgaBufGlobal = 1'b0
) (
  input  clk_i,
  input  en_i,
  input  test_en_i,
  output logic clk_o
);
  logic en_latch;
  always_latch if (!clk_i) en_latch = en_i | test_en_i;
  assign clk_o = clk_i & en_latch;
endmodule
