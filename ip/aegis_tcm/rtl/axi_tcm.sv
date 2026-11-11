`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axi_tcm : 16 KB dual-bank TCM with an AXI4 slave port (128-bit) and a
//           dedicated GEMM read port (g_*).
//   Bank A = BASE + 0x0000..0x1FFF, Bank B = BASE + 0x2000..0x3FFF
//   AXI: INCR bursts, AxSIZE <= 4, byte strobes on writes.
//        out-of-range -> DECERR, bad burst/size -> SLVERR (data is consumed).
//-----------------------------------------------------------------------------
module axi_tcm #(
    parameter logic [31:0] BASE = 32'h1000_0000
) (
    input  logic         clk,
    input  logic         rst_n,

    input  logic [31:0]  s_axi_awaddr,
    input  logic [7:0]   s_axi_awlen,
    input  logic [2:0]   s_axi_awsize,
    input  logic [1:0]   s_axi_awburst,
    input  logic         s_axi_awvalid,
    output logic         s_axi_awready,
    input  logic [127:0] s_axi_wdata,
    input  logic [15:0]  s_axi_wstrb,
    input  logic         s_axi_wlast,
    input  logic         s_axi_wvalid,
    output logic         s_axi_wready,
    output logic [1:0]   s_axi_bresp,
    output logic         s_axi_bvalid,
    input  logic         s_axi_bready,

    input  logic [31:0]  s_axi_araddr,
    input  logic [7:0]   s_axi_arlen,
    input  logic [2:0]   s_axi_arsize,
    input  logic [1:0]   s_axi_arburst,
    input  logic         s_axi_arvalid,
    output logic         s_axi_arready,
    output logic [127:0] s_axi_rdata,
    output logic [1:0]   s_axi_rresp,
    output logic         s_axi_rlast,
    output logic         s_axi_rvalid,
    input  logic         s_axi_rready,

    // GEMM read port (1-cycle latency)
    input  logic         g_en,
    input  logic         g_bank,
    input  logic [8:0]   g_word,
    output logic [127:0] g_rdata
);

    function automatic logic in_range(input logic [31:0] a);
        return (a[31:14] == BASE[31:14]);
    endfunction

    // ---------------- write channel ---------------------------------------------
    typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} wstate_t;
    wstate_t     wstate;
    logic [31:0] w_addr;
    logic [2:0]  w_size;
    logic        w_ok_range, w_ok_fmt;

    assign s_axi_awready = (wstate == W_IDLE);
    assign s_axi_wready  = (wstate == W_DATA);

    logic        sram_w_en;
    assign sram_w_en = s_axi_wvalid && s_axi_wready && w_ok_range && w_ok_fmt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wstate <= W_IDLE; s_axi_bvalid <= 0; s_axi_bresp <= 0;
            w_addr <= '0; w_size <= '0; w_ok_range <= 0; w_ok_fmt <= 0;
        end else begin
            case (wstate)
                W_IDLE: if (s_axi_awvalid) begin
                    w_addr     <= s_axi_awaddr;
                    w_size     <= s_axi_awsize;
                    w_ok_range <= in_range(s_axi_awaddr);
                    w_ok_fmt   <= (s_axi_awburst == 2'b01) && (s_axi_awsize <= 3'd4);
                    wstate     <= W_DATA;
                end
                W_DATA: if (s_axi_wvalid) begin
                    w_addr <= w_addr + (32'd1 << w_size);
                    if (s_axi_wlast) begin
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= !w_ok_range ? 2'b11 : (!w_ok_fmt ? 2'b10 : 2'b00);
                        wstate       <= W_RESP;
                    end
                end
                W_RESP: if (s_axi_bready) begin
                    s_axi_bvalid <= 1'b0;
                    wstate       <= W_IDLE;
                end
                default: wstate <= W_IDLE;
            endcase
        end
    end

    // ---------------- read channel ----------------------------------------------
    typedef enum logic [1:0] {R_IDLE, R_REQ, R_WAIT, R_DATA} rstate_t;
    rstate_t     rstate;
    logic [31:0] r_addr;
    logic [2:0]  r_size;
    logic [7:0]  r_left;
    logic        r_ok_range, r_ok_fmt;
    logic [127:0] r_data_q;

    logic        ra_en, ra_grant;
    logic [127:0] ra_data;
    assign ra_en = (rstate == R_REQ) && r_ok_range && r_ok_fmt;

    assign s_axi_arready = (rstate == R_IDLE);
    assign s_axi_rvalid  = (rstate == R_DATA);
    assign s_axi_rdata   = r_data_q;
    assign s_axi_rlast   = (r_left == 0);
    assign s_axi_rresp   = !r_ok_range ? 2'b11 : (!r_ok_fmt ? 2'b10 : 2'b00);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate <= R_IDLE; r_addr <= '0; r_size <= '0; r_left <= '0;
            r_ok_range <= 0; r_ok_fmt <= 0; r_data_q <= '0;
        end else begin
            case (rstate)
                R_IDLE: if (s_axi_arvalid) begin
                    r_addr     <= s_axi_araddr;
                    r_size     <= s_axi_arsize;
                    r_left     <= s_axi_arlen;
                    r_ok_range <= in_range(s_axi_araddr);
                    r_ok_fmt   <= (s_axi_arburst == 2'b01) && (s_axi_arsize <= 3'd4);
                    rstate     <= R_REQ;
                end
                R_REQ: begin
                    if (!(r_ok_range && r_ok_fmt)) begin
                        r_data_q <= '0;
                        rstate   <= R_DATA;
                    end else if (ra_grant) begin
                        rstate <= R_WAIT;
                    end
                end
                R_WAIT: begin
                    r_data_q <= ra_data;
                    rstate   <= R_DATA;
                end
                R_DATA: if (s_axi_rready) begin
                    if (r_left == 0) rstate <= R_IDLE;
                    else begin
                        r_left <= r_left - 1'b1;
                        r_addr <= r_addr + (32'd1 << r_size);
                        rstate <= R_REQ;
                    end
                end
            endcase
        end
    end

    // ---------------- SRAM -------------------------------------------------------
    ping_pong_sram u_sram (
        .clk(clk),
        .w_en(sram_w_en), .w_bank(w_addr[13]), .w_word(w_addr[12:4]),
        .w_strb(s_axi_wstrb), .w_data(s_axi_wdata),
        .ra_en(ra_en), .ra_bank(r_addr[13]), .ra_word(r_addr[12:4]),
        .ra_grant(ra_grant), .ra_data(ra_data),
        .rb_en(g_en), .rb_bank(g_bank), .rb_word(g_word), .rb_data(g_rdata)
    );

endmodule
