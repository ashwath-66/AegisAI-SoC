// Minimal generic clock mux (upstream equivalent). Only used by ibex_lockstep (SecureIbex=0 -> unused)
module prim_generic_clock_mux2 #(
  parameter bit NoFpgaBufG = 1'b0
) (
  input        clk0_i,
  input        clk1_i,
  input        sel_i,
  output logic clk_o
);
  assign clk_o = sel_i ? clk1_i : clk0_i;
endmodule
