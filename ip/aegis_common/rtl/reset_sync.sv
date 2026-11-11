`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// reset_sync : asynchronous assert, synchronous (2-FF) de-assert
//-----------------------------------------------------------------------------
module reset_sync (
    input  logic clk,
    input  logic rst_n_in,
    output logic rst_n_out
);
    logic q1, q2;
    always_ff @(posedge clk or negedge rst_n_in) begin
        if (!rst_n_in) begin q1 <= 1'b0; q2 <= 1'b0; end
        else           begin q1 <= 1'b1; q2 <= q1;   end
    end
    assign rst_n_out = q2;
endmodule
