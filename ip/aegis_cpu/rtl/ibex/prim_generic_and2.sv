// Minimal generic AND2 (upstream lowRISC prim_generic_and2 equivalent)
module prim_generic_and2 #(
  parameter int Width = 1
) (
  input        [Width-1:0] in0_i,
  input        [Width-1:0] in1_i,
  output logic [Width-1:0] out_o
);
  assign out_o = in0_i & in1_i;
endmodule
