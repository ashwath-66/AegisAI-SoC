`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axil2apb : AXI4-Lite slave -> APB master (one APB slave, PADDR = low 12 bits)
//-----------------------------------------------------------------------------
module axil2apb (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] s_awaddr,  input logic s_awvalid, output logic s_awready,
    input  logic [31:0] s_wdata,   input logic [3:0] s_wstrb,
    input  logic        s_wvalid,  output logic s_wready,
    output logic [1:0]  s_bresp,   output logic s_bvalid, input logic s_bready,
    input  logic [31:0] s_araddr,  input logic s_arvalid, output logic s_arready,
    output logic [31:0] s_rdata,   output logic [1:0] s_rresp,
    output logic        s_rvalid,  input logic s_rready,

    output logic        psel,
    output logic        penable,
    output logic        pwrite,
    output logic [31:0] paddr,
    output logic [31:0] pwdata,
    input  logic [31:0] prdata,
    input  logic        pready,
    input  logic        pslverr
);
    typedef enum logic [2:0] {A_IDLE, A_SETUP, A_ACCESS, A_RESP} st_t;
    st_t st;

    logic aw_got, w_got, is_wr;
    logic [31:0] addr_q, data_q;

    assign s_awready = (st == A_IDLE) && !aw_got;
    assign s_wready  = (st == A_IDLE) && !w_got;
    assign s_arready = (st == A_IDLE) && !aw_got && !w_got && !s_awvalid && !s_wvalid;

    assign psel    = (st == A_SETUP) || (st == A_ACCESS);
    assign penable = (st == A_ACCESS);
    assign pwrite  = is_wr;
    assign paddr   = {20'b0, addr_q[11:0]};
    assign pwdata  = data_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= A_IDLE; aw_got <= 0; w_got <= 0; is_wr <= 0; addr_q <= 0; data_q <= 0;
            s_bvalid <= 0; s_bresp <= 0; s_rvalid <= 0; s_rdata <= 0; s_rresp <= 0;
        end else begin
            case (st)
                A_IDLE: begin
                    if (s_awvalid && s_awready) begin aw_got <= 1; addr_q <= s_awaddr; end
                    if (s_wvalid  && s_wready)  begin w_got  <= 1; data_q <= s_wdata; end
                    if (aw_got && w_got) begin is_wr <= 1; st <= A_SETUP; end
                    else if (s_arvalid && s_arready) begin
                        addr_q <= s_araddr; is_wr <= 0; st <= A_SETUP;
                    end
                end
                A_SETUP:  st <= A_ACCESS;
                A_ACCESS: if (pready) begin
                    if (is_wr) begin s_bvalid <= 1; s_bresp <= pslverr ? 2'b10 : 2'b00; end
                    else       begin s_rvalid <= 1; s_rdata <= prdata; s_rresp <= pslverr ? 2'b10 : 2'b00; end
                    aw_got <= 0; w_got <= 0;
                    st <= A_RESP;
                end
                A_RESP: begin
                    if (s_bvalid && s_bready) begin s_bvalid <= 0; st <= A_IDLE; end
                    if (s_rvalid && s_rready) begin s_rvalid <= 0; st <= A_IDLE; end
                end
                default: st <= A_IDLE;
            endcase
        end
    end
endmodule
