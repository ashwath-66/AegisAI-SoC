`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axil_xbar : NM-master x NS-slave AXI4-Lite crossbar
//   - address decode: (addr & MASK[j]) == BASE[j]; no match -> internal DECERR slave
//   - per-slave registered arbitration (higher master index wins), the grant is
//     held until the response handshake, so AW/W and AR/R never interleave
//   - independent read and write paths per slave
//-----------------------------------------------------------------------------
module axil_xbar #(
    parameter int NM = 2,
    parameter int NS = 6,
    parameter logic [NS-1:0][31:0] BASE = '0,
    parameter logic [NS-1:0][31:0] MASK = '0
) (
    input  logic clk,
    input  logic rst_n,

    // ---- master side (NM ports) ----
    input  logic [NM-1:0][31:0] m_awaddr,  input  logic [NM-1:0] m_awvalid, output logic [NM-1:0] m_awready,
    input  logic [NM-1:0][31:0] m_wdata,   input  logic [NM-1:0][3:0] m_wstrb,
    input  logic [NM-1:0]       m_wvalid,  output logic [NM-1:0] m_wready,
    output logic [NM-1:0][1:0]  m_bresp,   output logic [NM-1:0] m_bvalid, input logic [NM-1:0] m_bready,
    input  logic [NM-1:0][31:0] m_araddr,  input  logic [NM-1:0] m_arvalid, output logic [NM-1:0] m_arready,
    output logic [NM-1:0][31:0] m_rdata,   output logic [NM-1:0][1:0] m_rresp,
    output logic [NM-1:0]       m_rvalid,  input  logic [NM-1:0] m_rready,

    // ---- slave side (NS ports) ----
    output logic [NS-1:0][31:0] s_awaddr,  output logic [NS-1:0] s_awvalid, input logic [NS-1:0] s_awready,
    output logic [NS-1:0][31:0] s_wdata,   output logic [NS-1:0][3:0] s_wstrb,
    output logic [NS-1:0]       s_wvalid,  input  logic [NS-1:0] s_wready,
    input  logic [NS-1:0][1:0]  s_bresp,   input  logic [NS-1:0] s_bvalid, output logic [NS-1:0] s_bready,
    output logic [NS-1:0][31:0] s_araddr,  output logic [NS-1:0] s_arvalid, input logic [NS-1:0] s_arready,
    input  logic [NS-1:0][31:0] s_rdata,   input  logic [NS-1:0][1:0] s_rresp,
    input  logic [NS-1:0]       s_rvalid,  output logic [NS-1:0] s_rready
);
    localparam int NT = NS + 1;                // + error slave
    localparam int MW = (NM > 1) ? $clog2(NM) : 1;

    // internal slave arrays (index NS = DECERR slave)
    logic [NT-1:0][31:0] t_awaddr, t_wdata, t_araddr, t_rdata;
    logic [NT-1:0][3:0]  t_wstrb;
    logic [NT-1:0]       t_awvalid, t_awready, t_wvalid, t_wready, t_bvalid, t_bready;
    logic [NT-1:0]       t_arvalid, t_arready, t_rvalid, t_rready;
    logic [NT-1:0][1:0]  t_bresp, t_rresp;

    for (genvar j = 0; j < NS; j++) begin : g_ext
        assign s_awaddr[j]  = t_awaddr[j];  assign s_awvalid[j] = t_awvalid[j];
        assign s_wdata[j]   = t_wdata[j];   assign s_wstrb[j]   = t_wstrb[j];  assign s_wvalid[j] = t_wvalid[j];
        assign s_bready[j]  = t_bready[j];
        assign s_araddr[j]  = t_araddr[j];  assign s_arvalid[j] = t_arvalid[j];
        assign s_rready[j]  = t_rready[j];
        assign t_awready[j] = s_awready[j]; assign t_wready[j]  = s_wready[j];
        assign t_bresp[j]   = s_bresp[j];   assign t_bvalid[j]  = s_bvalid[j];
        assign t_arready[j] = s_arready[j];
        assign t_rdata[j]   = s_rdata[j];   assign t_rresp[j]   = s_rresp[j];  assign t_rvalid[j] = s_rvalid[j];
    end

    axil_err_slave u_err (
        .clk(clk), .rst_n(rst_n),
        .awvalid(t_awvalid[NS]), .awready(t_awready[NS]),
        .wvalid(t_wvalid[NS]),   .wready(t_wready[NS]),
        .bresp(t_bresp[NS]), .bvalid(t_bvalid[NS]), .bready(t_bready[NS]),
        .arvalid(t_arvalid[NS]), .arready(t_arready[NS]),
        .rdata(t_rdata[NS]), .rresp(t_rresp[NS]), .rvalid(t_rvalid[NS]), .rready(t_rready[NS])
    );

    // ---------------- address decode --------------------------------------------
    function automatic logic [NT-1:0] decode(input logic [31:0] a);
        logic [NT-1:0] oh;
        oh = '0;
        for (int j = 0; j < NS; j++)
            if ((a & MASK[j]) == BASE[j]) oh[j] = 1'b1;
        if (oh[NS-1:0] == '0) oh[NS] = 1'b1;
        return oh;
    endfunction

    logic [NM-1:0][NT-1:0] aw_dec, ar_dec;
    always_comb
        for (int i = 0; i < NM; i++) begin
            aw_dec[i] = decode(m_awaddr[i]);
            ar_dec[i] = decode(m_araddr[i]);
        end

    // ---------------- per-slave arbitration + routing ---------------------------
    logic [NT-1:0]          w_busy, r_busy;
    logic [NT-1:0][MW-1:0]  w_own,  r_own;

    for (genvar j = 0; j < NT; j++) begin : g_slv
        logic         w_pick_v, r_pick_v;
        logic [MW-1:0] w_pick, r_pick;

        always_comb begin
            w_pick_v = 1'b0; w_pick = '0; r_pick_v = 1'b0; r_pick = '0;
            for (int i = 0; i < NM; i++) begin
                if (m_awvalid[i] && aw_dec[i][j]) begin w_pick_v = 1'b1; w_pick = MW'(i); end
                if (m_arvalid[i] && ar_dec[i][j]) begin r_pick_v = 1'b1; r_pick = MW'(i); end
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin w_busy[j] <= 0; w_own[j] <= '0; r_busy[j] <= 0; r_own[j] <= '0; end
            else begin
                if (!w_busy[j]) begin
                    if (w_pick_v) begin w_busy[j] <= 1'b1; w_own[j] <= w_pick; end
                end else if (t_bvalid[j] && t_bready[j]) w_busy[j] <= 1'b0;

                if (!r_busy[j]) begin
                    if (r_pick_v) begin r_busy[j] <= 1'b1; r_own[j] <= r_pick; end
                end else if (t_rvalid[j] && t_rready[j]) r_busy[j] <= 1'b0;
            end
        end

        // forward master -> slave
        assign t_awaddr[j]  = m_awaddr[w_own[j]];
        assign t_awvalid[j] = w_busy[j] && m_awvalid[w_own[j]];
        assign t_wdata[j]   = m_wdata[w_own[j]];
        assign t_wstrb[j]   = m_wstrb[w_own[j]];
        assign t_wvalid[j]  = w_busy[j] && m_wvalid[w_own[j]];
        assign t_bready[j]  = w_busy[j] && m_bready[w_own[j]];
        assign t_araddr[j]  = m_araddr[r_own[j]];
        assign t_arvalid[j] = r_busy[j] && m_arvalid[r_own[j]];
        assign t_rready[j]  = r_busy[j] && m_rready[r_own[j]];
    end

    // ---------------- slave -> master response routing -------------------------
    always_comb begin
        for (int i = 0; i < NM; i++) begin
            m_awready[i] = 1'b0; m_wready[i] = 1'b0; m_bvalid[i] = 1'b0; m_bresp[i] = '0;
            m_arready[i] = 1'b0; m_rvalid[i] = 1'b0; m_rdata[i] = '0;   m_rresp[i] = '0;
            for (int j = 0; j < NT; j++) begin
                if (w_busy[j] && w_own[j] == MW'(i)) begin
                    m_awready[i] |= t_awready[j];
                    m_wready[i]  |= t_wready[j];
                    if (t_bvalid[j]) begin m_bvalid[i] = 1'b1; m_bresp[i] = t_bresp[j]; end
                end
                if (r_busy[j] && r_own[j] == MW'(i)) begin
                    m_arready[i] |= t_arready[j];
                    if (t_rvalid[j]) begin m_rvalid[i] = 1'b1; m_rdata[i] = t_rdata[j]; m_rresp[i] = t_rresp[j]; end
                end
            end
        end
    end
endmodule
