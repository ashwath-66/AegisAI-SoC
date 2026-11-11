`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// gemm_controller : tile sequencer + CSRs + result buffer for the 16x16 array
//                   (Innovation 2: CPU-bypassed DMA prefetch handshake)
//
//   TCM tile layout (16 B words): word 0..15 = W rows, word 16..16+ROWS-1 = A rows
//
//   Flow per tile (no CPU involvement):
//     DMA fill_done -> bank_ready[b] -> controller reads W (16 words) then A (ROWS
//     words) from the TCM GEMM port, feeds the array, captures ROWS result rows into
//     the result buffer, sets TILE_DONE.  dma_auto_prefetch (1-cycle pulse) tells the
//     DMA to fetch the next tile into the other bank:
//         CTRL.PREFETCH_EARLY=1 : pulse when the tile starts computing
//         CTRL.PREFETCH_EARLY=0 : pulse when the tile is finished (drain)
//     The next tile does not start until the CPU releases the result buffer.
//
//   CSR map (AXI4-Lite, 8 KB window)
//     0x000 CTRL     [0] ENABLE [1] IRQ_EN [2] PREFETCH_EARLY [3] AUTO_PF_EN
//     0x004 STATUS   [0] BUSY [1] TILE_DONE(w1c) [2] RES_FULL [3] ERR(w1c) [4] OVERRUN(w1c)
//                    [6:5] BANK_READY
//     0x008 ROWS     number of A rows, 1..64
//     0x00C TILES    completed tile counter (RO, cleared on ENABLE 0->1)
//     0x010 RELEASE  write 1: result buffer may be overwritten by the next tile
//     0x1000+4*(m*16+c)  result C[m][c], sign-extended 20->32 bit (RO)
//-----------------------------------------------------------------------------
module gemm_controller (
    input  logic         clk,
    input  logic         rst_n,

    // AXI4-Lite slave
    input  logic [31:0]  s_axil_awaddr,
    input  logic         s_axil_awvalid,
    output logic         s_axil_awready,
    input  logic [31:0]  s_axil_wdata,
    input  logic [3:0]   s_axil_wstrb,
    input  logic         s_axil_wvalid,
    output logic         s_axil_wready,
    output logic [1:0]   s_axil_bresp,
    output logic         s_axil_bvalid,
    input  logic         s_axil_bready,
    input  logic [31:0]  s_axil_araddr,
    input  logic         s_axil_arvalid,
    output logic         s_axil_arready,
    output logic [31:0]  s_axil_rdata,
    output logic [1:0]   s_axil_rresp,
    output logic         s_axil_rvalid,
    input  logic         s_axil_rready,

    // DMA handshake (Innovation 2)
    input  logic         fill_done,
    input  logic         fill_bank,
    output logic         dma_auto_prefetch,

    // TCM GEMM read port (1-cycle latency)
    output logic         g_en,
    output logic         g_bank,
    output logic [8:0]   g_word,
    input  logic [127:0] g_rdata,

    // systolic array
    output logic         w_load_en,
    output logic [3:0]   w_load_row,
    output logic [127:0] w_load_data,
    output logic         a_valid,
    output logic [127:0] a_row,
    input  logic         c_valid,
    input  logic [16*20-1:0] c_row,

    output logic         irq
);
    localparam int N        = 16;
    localparam int MAX_ROWS = 64;

    // ---------------- CSR / status state ----------------------------------------
    logic        enable, irq_en, pf_early, pf_en;
    logic [15:0] reg_rows;
    logic        tile_done, err, overrun, res_busy;
    logic [31:0] tiles_done;
    logic [1:0]  bank_ready;          // [0] bank A holds an unconsumed tile, [1] bank B

    // ---------------- sequencer state -------------------------------------------
    typedef enum logic [1:0] {S_IDLE, S_RUN, S_WAITC} state_t;
    state_t      state;
    logic        rd_bank, cur_bank;
    logic [6:0]  rows_q;
    logic [7:0]  rq, total_q;
    logic [6:0]  cap_cnt;
    logic        pf_pulse;
    logic        d_valid;
    logic [7:0]  d_idx;

    wire rows_bad   = (reg_rows == 16'd0) || (reg_rows > 16'(MAX_ROWS));
    wire start_cond = (state == S_IDLE) && enable && bank_ready[rd_bank] && !res_busy;
    wire last_req   = (rq == total_q - 8'd1);

    // bank release (consumed) vector
    logic [1:0] br_clr;
    always_comb begin
        br_clr = 2'b00;
        if (start_cond && rows_bad)         br_clr[rd_bank]  = 1'b1;   // dropped tile
        if (state == S_RUN && last_req)     br_clr[cur_bank] = 1'b1;   // last word requested
    end

    // ---------------- TCM / array data path -------------------------------------
    assign g_en   = (state == S_RUN);
    assign g_bank = cur_bank;
    assign g_word = 9'(rq);

    assign w_load_en   = d_valid && (d_idx < 8'd16);
    assign w_load_row  = d_idx[3:0];
    assign w_load_data = g_rdata;
    assign a_valid     = d_valid && (d_idx >= 8'd16);
    assign a_row       = g_rdata;

    assign dma_auto_prefetch = pf_pulse;
    assign irq               = irq_en && tile_done;

    // ---------------- result buffer (64 x 16 x 20 bit) --------------------------
    logic [16*20-1:0] rbuf [MAX_ROWS];
    logic [16*20-1:0] rd_row_q;

    always_ff @(posedge clk) begin
        if (c_valid && (state != S_IDLE)) rbuf[cap_cnt[5:0]] <= c_row;
    end

    // ---------------- AXI-Lite register interface ------------------------------
    logic        wr_en, rd_en;
    logic [12:0] wr_addr, rd_addr;
    logic [31:0] wr_data, rd_data;

    wire wr_ok = !wr_addr[12] && (wr_addr[11:0] inside {12'h000, 12'h004, 12'h008, 12'h010});
    wire rd_ok = rd_addr[12] || (rd_addr[11:0] inside {12'h000, 12'h004, 12'h008, 12'h00C, 12'h010});

    axil_regif #(.AW(13)) u_if (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(s_axil_awaddr), .s_awvalid(s_axil_awvalid), .s_awready(s_axil_awready),
        .s_wdata(s_axil_wdata), .s_wstrb(s_axil_wstrb), .s_wvalid(s_axil_wvalid), .s_wready(s_axil_wready),
        .s_bresp(s_axil_bresp), .s_bvalid(s_axil_bvalid), .s_bready(s_axil_bready),
        .s_araddr(s_axil_araddr), .s_arvalid(s_axil_arvalid), .s_arready(s_axil_arready),
        .s_rdata(s_axil_rdata), .s_rresp(s_axil_rresp), .s_rvalid(s_axil_rvalid), .s_rready(s_axil_rready),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .wr_strb(), .wr_err(!wr_ok),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data), .rd_err(!rd_ok)
    );

    // registered row read (rd_en is high exactly one cycle before rd_data is sampled)
    always_ff @(posedge clk) if (rd_en) rd_row_q <= rbuf[rd_addr[11:6]];

    logic [19:0] win_elem;
    always_comb begin
        win_elem = rd_row_q[20*int'(rd_addr[5:2]) +: 20];
        if (rd_addr[12]) rd_data = {{12{win_elem[19]}}, win_elem};
        else case (rd_addr[11:0])
            12'h000: rd_data = {28'b0, pf_en, pf_early, irq_en, enable};
            12'h004: rd_data = {25'b0, bank_ready, overrun, err, res_busy, tile_done, (state != S_IDLE)};
            12'h008: rd_data = {16'b0, reg_rows};
            12'h00C: rd_data = tiles_done;
            default: rd_data = 32'h0;
        endcase
    end

    // ---------------- main sequential block --------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable <= 0; irq_en <= 0; pf_early <= 0; pf_en <= 0; reg_rows <= '0;
            tile_done <= 0; err <= 0; overrun <= 0; res_busy <= 0; tiles_done <= '0;
            bank_ready <= 2'b00; state <= S_IDLE; rd_bank <= 0; cur_bank <= 0;
            rows_q <= '0; rq <= '0; total_q <= '0; cap_cnt <= '0; pf_pulse <= 0;
            d_valid <= 0; d_idx <= '0;
        end else begin
            pf_pulse <= 1'b0;
            d_valid  <= g_en;
            d_idx    <= rq;

            // ---- CSR writes (FSM events below take priority) -----------------
            if (wr_en && wr_ok) begin
                case (wr_addr[11:0])
                    12'h000: begin
                        enable   <= wr_data[0];
                        irq_en   <= wr_data[1];
                        pf_early <= wr_data[2];
                        pf_en    <= wr_data[3];
                        if (wr_data[0] && !enable) tiles_done <= '0;
                    end
                    12'h004: begin
                        if (wr_data[1]) tile_done <= 1'b0;
                        if (wr_data[3]) err       <= 1'b0;
                        if (wr_data[4]) overrun   <= 1'b0;
                    end
                    12'h008: reg_rows <= wr_data[15:0];
                    12'h010: if (wr_data[0]) res_busy <= 1'b0;
                    default: ;
                endcase
            end

            // ---- bank bookkeeping -------------------------------------------
            bank_ready <= (bank_ready & ~br_clr) | (fill_done ? (2'b01 << fill_bank) : 2'b00);
            if (fill_done && (bank_ready[fill_bank] || (state == S_RUN && cur_bank == fill_bank)))
                overrun <= 1'b1;

            // ---- capture counter --------------------------------------------
            if (c_valid && (state != S_IDLE)) cap_cnt <= cap_cnt + 1'b1;

            // ---- sequencer ----------------------------------------------------
            case (state)
                S_IDLE: if (start_cond) begin
                    if (rows_bad) begin
                        err     <= 1'b1;
                        rd_bank <= ~rd_bank;               // drop the tile, stay idle
                    end else begin
                        cur_bank <= rd_bank;
                        rows_q   <= reg_rows[6:0];
                        total_q  <= 8'd16 + reg_rows[7:0];
                        rq       <= '0;
                        cap_cnt  <= '0;
                        state    <= S_RUN;
                        if (pf_en && pf_early) pf_pulse <= 1'b1;
                    end
                end

                S_RUN: begin
                    rq <= rq + 1'b1;
                    if (last_req) state <= S_WAITC;
                end

                S_WAITC: if (cap_cnt == rows_q) begin
                    tile_done  <= 1'b1;
                    res_busy   <= 1'b1;
                    tiles_done <= tiles_done + 1'b1;
                    rd_bank    <= ~cur_bank;
                    state      <= S_IDLE;
                    if (pf_en && !pf_early) pf_pulse <= 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
