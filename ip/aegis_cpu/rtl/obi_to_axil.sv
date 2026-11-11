`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// obi_to_axil : Ibex OBI-style memory port -> AXI4-Lite master
//   One outstanding transaction. gnt is given when idle; the response
//   (rvalid/rdata/err) is a registered pulse after the AXI response.
//   READ_ONLY=1 for the instruction port (never drives the write channels).
//-----------------------------------------------------------------------------
module obi_to_axil #(
    parameter bit READ_ONLY = 1'b0
) (
    input  logic        clk,
    input  logic        rst_n,

    // OBI side (Ibex)
    input  logic        req,
    output logic        gnt,
    input  logic        we,
    input  logic [3:0]  be,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic        rvalid,
    output logic [31:0] rdata,
    output logic        err,

    // AXI4-Lite master
    output logic [31:0] m_awaddr,
    output logic        m_awvalid,
    input  logic        m_awready,
    output logic [31:0] m_wdata,
    output logic [3:0]  m_wstrb,
    output logic        m_wvalid,
    input  logic        m_wready,
    input  logic [1:0]  m_bresp,
    input  logic        m_bvalid,
    output logic        m_bready,
    output logic [31:0] m_araddr,
    output logic        m_arvalid,
    input  logic        m_arready,
    input  logic [31:0] m_rdata,
    input  logic [1:0]  m_rresp,
    input  logic        m_rvalid,
    output logic        m_rready
);
    typedef enum logic [2:0] {S_IDLE, S_WR, S_B, S_AR, S_R} state_t;
    state_t state;

    logic [31:0] addr_q, wdata_q;
    logic [3:0]  be_q;
    logic        aw_done, w_done;

    assign gnt = (state == S_IDLE) && req;

    assign m_awaddr  = addr_q;
    assign m_awvalid = !READ_ONLY && (state == S_WR) && !aw_done;
    assign m_wdata   = wdata_q;
    assign m_wstrb   = be_q;
    assign m_wvalid  = !READ_ONLY && (state == S_WR) && !w_done;
    assign m_bready  = (state == S_B);
    assign m_araddr  = addr_q;
    assign m_arvalid = (state == S_AR);
    assign m_rready  = (state == S_R);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; addr_q <= '0; wdata_q <= '0; be_q <= '0;
            aw_done <= 0; w_done <= 0; rvalid <= 0; rdata <= '0; err <= 0;
        end else begin
            rvalid <= 1'b0;
            case (state)
                S_IDLE: if (req) begin
                    addr_q  <= addr;
                    wdata_q <= wdata;
                    be_q    <= be;
                    aw_done <= 0; w_done <= 0;
                    state   <= (we && !READ_ONLY) ? S_WR : S_AR;
                end
                S_WR: begin
                    if (m_awvalid && m_awready) aw_done <= 1'b1;
                    if (m_wvalid  && m_wready)  w_done  <= 1'b1;
                    if ((aw_done || (m_awvalid && m_awready)) && (w_done || (m_wvalid && m_wready)))
                        state <= S_B;
                end
                S_B: if (m_bvalid) begin
                    rvalid <= 1'b1; rdata <= '0; err <= (m_bresp != 2'b00);
                    state  <= S_IDLE;
                end
                S_AR: if (m_arready) state <= S_R;
                S_R: if (m_rvalid) begin
                    rvalid <= 1'b1; rdata <= m_rdata; err <= (m_rresp != 2'b00);
                    state  <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
