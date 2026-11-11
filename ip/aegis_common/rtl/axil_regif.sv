`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axil_regif : AXI4-Lite slave -> simple register/memory interface
//   write : wr_en pulses for one cycle with address/data/strobes
//   read  : rd_en pulses for one cycle; rd_data must be valid ONE cycle later
//           (synchronous memory, or combinational data from a held rd_addr)
//   wr_err / rd_err (sampled with the strobe) turn the response into SLVERR
//-----------------------------------------------------------------------------
module axil_regif #(
    parameter int AW = 16
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] s_awaddr,  input logic s_awvalid, output logic s_awready,
    input  logic [31:0] s_wdata,   input logic [3:0] s_wstrb,
    input  logic        s_wvalid,  output logic s_wready,
    output logic [1:0]  s_bresp,   output logic s_bvalid, input logic s_bready,
    input  logic [31:0] s_araddr,  input logic s_arvalid, output logic s_arready,
    output logic [31:0] s_rdata,   output logic [1:0] s_rresp,
    output logic        s_rvalid,  input logic s_rready,

    output logic            wr_en,
    output logic [AW-1:0]   wr_addr,
    output logic [31:0]     wr_data,
    output logic [3:0]      wr_strb,
    input  logic            wr_err,
    output logic            rd_en,
    output logic [AW-1:0]   rd_addr,
    input  logic [31:0]     rd_data,
    input  logic            rd_err
);
    logic aw_got, w_got;
    logic [AW-1:0] aw_q;
    logic [31:0]   w_q;
    logic [3:0]    ws_q;

    typedef enum logic [1:0] {R_IDLE, R_LAT, R_RESP} rs_t;
    rs_t rs;
    logic [AW-1:0] ar_q;
    logic          rd_err_q;

    assign s_awready = !aw_got && !s_bvalid;
    assign s_wready  = !w_got  && !s_bvalid;
    assign wr_en     = aw_got && w_got && !s_bvalid;
    assign wr_addr   = aw_q;
    assign wr_data   = w_q;
    assign wr_strb   = ws_q;

    assign s_arready = (rs == R_IDLE) && !s_rvalid;
    assign rd_en     = (rs == R_LAT);
    assign rd_addr   = ar_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_got <= 0; w_got <= 0; aw_q <= '0; w_q <= '0; ws_q <= '0;
            s_bvalid <= 0; s_bresp <= 0;
            rs <= R_IDLE; ar_q <= '0; s_rvalid <= 0; s_rdata <= '0; s_rresp <= 0; rd_err_q <= 0;
        end else begin
            if (s_awvalid && s_awready) begin aw_got <= 1; aw_q <= s_awaddr[AW-1:0]; end
            if (s_wvalid  && s_wready)  begin w_got  <= 1; w_q  <= s_wdata; ws_q <= s_wstrb; end
            if (wr_en) begin
                aw_got <= 0; w_got <= 0; s_bvalid <= 1; s_bresp <= wr_err ? 2'b10 : 2'b00;
            end
            if (s_bvalid && s_bready) s_bvalid <= 0;

            case (rs)
                R_IDLE: if (s_arvalid && s_arready) begin ar_q <= s_araddr[AW-1:0]; rs <= R_LAT; end
                R_LAT:  rs <= R_RESP;                         // rd_en is high in this cycle
                R_RESP: begin
                    s_rdata  <= rd_data;
                    s_rresp  <= rd_err ? 2'b10 : 2'b00;
                    s_rvalid <= 1'b1;
                    rs       <= R_IDLE;
                end
            endcase
            if (s_rvalid && s_rready) s_rvalid <= 0;
        end
    end
endmodule
