// Minimal security anchor buffer (upstream equivalent)
module prim_sec_anchor_buf #(
  parameter int Width = 1
) (
  input        [Width-1:0] in_i,
  output logic [Width-1:0] out_o
);
  prim_buf #(.Width(Width)) u_secure_anchor_buf (.in_i(in_i), .out_o(out_o));
endmodule
