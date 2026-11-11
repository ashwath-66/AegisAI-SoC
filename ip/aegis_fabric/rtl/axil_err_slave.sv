`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axil_err_slave : answers every access with DECERR (unmapped address)
//-----------------------------------------------------------------------------
module axil_err_slave (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        awvalid, output logic awready,
    input  logic        wvalid,  output logic wready,
    output logic [1:0]  bresp,   output logic bvalid, input logic bready,
    input  logic        arvalid, output logic arready,
    output logic [31:0] rdata,   output logic [1:0] rresp,
    output logic        rvalid,  input  logic rready
);
    logic aw_got, w_got;
    assign awready = !aw_got && !bvalid;
    assign wready  = !w_got  && !bvalid;
    assign bresp   = 2'b11;
    assign rdata   = 32'hDEAD_BEEF;
    assign rresp   = 2'b11;
    assign arready = !rvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin aw_got <= 0; w_got <= 0; bvalid <= 0; rvalid <= 0; end
        else begin
            if (awvalid && awready) aw_got <= 1;
            if (wvalid  && wready)  w_got  <= 1;
            if (aw_got && w_got && !bvalid) begin bvalid <= 1; aw_got <= 0; w_got <= 0; end
            if (bvalid && bready) bvalid <= 0;
            if (arvalid && arready) rvalid <= 1;
            if (rvalid && rready)   rvalid <= 0;
        end
    end
endmodule
