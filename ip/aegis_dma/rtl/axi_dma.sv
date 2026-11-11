`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axi_dma : QSPI -> SPECK-64/128 decrypt -> AXI4 write DMA with ping-pong
//           auto-prefetch (Innovation 1 + 2)
//
//   CPU programs it through AXI4-Lite CSRs. A "tile" = LEN bytes read from the
//   flash at SRC, decrypted on the fly, and written as 128-bit AXI4 INCR bursts
//   (max 16 beats, never crossing a 256 B boundary) into bank A or bank B.
//   The destination bank alternates after every tile. dma_auto_prefetch (from the
//   GEMM controller) launches the next tile without the CPU.
//
//   CSR map (AXI4-Lite, 32-bit):
//    0x00 CTRL    [0] START(w1)  [1] AUTO_EN  [2] DECRYPT_EN (reset 1)  [3] IRQ_EN
//    0x04 STATUS  [0] BUSY [1] DONE(w1c) [2] ERR(w1c) [3] KEY_VALID [4] TILE_BANK
//    0x08 SRC     flash byte address of the next tile [23:0]
//    0x0C LEN     tile length in bytes (multiple of 16) [24:0]
//    0x10 DST_A   AXI address of bank A (16 B aligned)
//    0x14 DST_B   AXI address of bank B (16 B aligned)
//    0x18 STRIDE  added to SRC after every tile
//    0x1C TILES   number of auto tiles still allowed
//    0x20..0x2C   KEY0..KEY3 (write-only; KEY0 = key[31:0])
//    0x30 KEY_LOAD write any value: start the key schedule
//    0x34 BANK    [0] bank the next tile will fill (rw)
//-----------------------------------------------------------------------------
module axi_dma (
    input  logic         clk,
    input  logic         rst_n,

    // ---------------- AXI4-Lite slave (CSRs) ----------------------------------
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

    // ---------------- QSPI RX stream + read launch ----------------------------
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [127:0] s_data,
    output logic         spi_start,
    output logic [23:0]  spi_addr,
    output logic [24:0]  spi_len,
    input  logic         spi_busy,

    // ---------------- AXI4 master (write only) --------------------------------
    output logic [31:0]  m_axi_awaddr,
    output logic [7:0]   m_axi_awlen,
    output logic [2:0]   m_axi_awsize,
    output logic [1:0]   m_axi_awburst,
    output logic         m_axi_awvalid,
    input  logic         m_axi_awready,
    output logic [127:0] m_axi_wdata,
    output logic [15:0]  m_axi_wstrb,
    output logic         m_axi_wlast,
    output logic         m_axi_wvalid,
    input  logic         m_axi_wready,
    input  logic [1:0]   m_axi_bresp,
    input  logic         m_axi_bvalid,
    output logic         m_axi_bready,

    // ---------------- sideband -------------------------------------------------
    input  logic         dma_auto_prefetch,   // from GEMM controller (pulse)
    output logic         fill_done,           // pulse: a tile is fully in SRAM
    output logic         fill_bank,           // bank that was just filled (0=A, 1=B)
    output logic         busy,
    output logic         irq
);

    // ---------------- CSR state ------------------------------------------------
    logic        auto_en, dec_en, irq_en;
    logic [23:0] reg_src;
    logic [24:0] reg_len;
    logic [31:0] reg_dst_a, reg_dst_b, reg_stride;
    logic [31:0] reg_tiles;
    logic [127:0] key_reg;
    logic        key_load, key_valid;
    logic        bank_sel;
    logic        done_sticky, err_sticky;
    logic        start_pending, auto_pending, auto_q;

    // ---------------- AXI4-Lite write channel ----------------------------------
    logic        aw_got, w_got;
    logic [7:0]  aw_addr_q;
    logic [31:0] w_data_q;
    logic        csr_wr;
    assign s_axil_awready = !aw_got && !s_axil_bvalid;
    assign s_axil_wready  = !w_got  && !s_axil_bvalid;
    assign csr_wr         = aw_got && w_got && !s_axil_bvalid;
    assign s_axil_rresp   = 2'b00;

    function automatic logic wr_mapped(input logic [7:0] a);
        case (a)
            8'h00, 8'h04, 8'h08, 8'h0C, 8'h10, 8'h14, 8'h18, 8'h1C,
            8'h20, 8'h24, 8'h28, 8'h2C, 8'h30, 8'h34: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    // ---------------- transfer FSM ---------------------------------------------
    typedef enum logic [2:0] {S_IDLE, S_KICK, S_AW, S_W, S_B, S_FIN} state_t;
    state_t state;

    logic [31:0] cur_addr;
    logic [20:0] beats_left;
    logic [4:0]  chunk_r;
    logic [4:0]  w_cnt;
    logic        tile_bank, dec_lat;
    logic [23:0] src_lat;
    logic [24:0] len_lat;

    logic [4:0] to_bdry, chunk;
    assign to_bdry = 5'd16 - {1'b0, cur_addr[7:4]};
    assign chunk   = (beats_left >= 21'(to_bdry)) ? to_bdry : beats_left[4:0];

    assign busy = (state != S_IDLE);

    // ---------------- datapath: stream -> (decrypt) -> AXI W -------------------
    logic         dec_in_ready, dec_out_valid, dec_out_ready;
    logic [127:0] dec_pt;

    speck_decryptor u_speck (
        .clk(clk), .rst_n(rst_n),
        .key_load(key_load), .key_in(key_reg), .key_valid(key_valid),
        .in_valid(s_valid && dec_lat && busy), .in_ready(dec_in_ready),
        .ciphertext_in(s_data),
        .out_valid(dec_out_valid), .out_ready(dec_out_ready),
        .plaintext_out(dec_pt)
    );

    wire w_phase = (state == S_W);
    assign m_axi_wdata   = dec_lat ? dec_pt : s_data;
    assign m_axi_wvalid  = w_phase && (dec_lat ? dec_out_valid : s_valid);
    assign dec_out_ready = w_phase && m_axi_wready;
    assign s_ready       = busy && (dec_lat ? dec_in_ready : (w_phase && m_axi_wready));
    assign m_axi_wstrb   = 16'hFFFF;
    assign m_axi_wlast   = (w_cnt == chunk_r - 1'b1);

    assign m_axi_awaddr  = cur_addr;
    assign m_axi_awlen   = 8'(chunk - 1'b1);
    assign m_axi_awsize  = 3'd4;                 // 16 bytes per beat
    assign m_axi_awburst = 2'b01;                // INCR
    assign m_axi_awvalid = (state == S_AW);
    assign m_axi_bready  = (state == S_B);

    assign spi_addr = src_lat;
    assign spi_len  = len_lat;

    wire w_fire = m_axi_wvalid && m_axi_wready;

    wire bad_cfg = (reg_len[3:0] != 0) || (reg_len == 0) || (reg_dst_a[3:0] != 0) || (reg_dst_b[3:0] != 0);
    wire launch_start = start_pending;
    wire launch_auto  = !start_pending && auto_pending && auto_en && (reg_tiles != 0);

    // ---------------- main sequential block ------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            auto_en <= 0; dec_en <= 1; irq_en <= 0;
            reg_src <= '0; reg_len <= '0; reg_dst_a <= '0; reg_dst_b <= '0;
            reg_stride <= '0; reg_tiles <= '0; key_reg <= '0; key_load <= 0;
            bank_sel <= 0; done_sticky <= 0; err_sticky <= 0;
            start_pending <= 0; auto_pending <= 0; auto_q <= 0;
            aw_got <= 0; w_got <= 0; aw_addr_q <= '0; w_data_q <= '0;
            s_axil_bvalid <= 0; s_axil_bresp <= 0;
            s_axil_arready <= 0; s_axil_rvalid <= 0; s_axil_rdata <= '0;
            state <= S_IDLE; cur_addr <= '0; beats_left <= '0; chunk_r <= '0; w_cnt <= '0;
            tile_bank <= 0; dec_lat <= 1; src_lat <= '0; len_lat <= '0;
            spi_start <= 0; fill_done <= 0; fill_bank <= 0;
        end else begin
            key_load  <= 1'b0;
            spi_start <= 1'b0;
            fill_done <= 1'b0;
            auto_q    <= dma_auto_prefetch;
            if (dma_auto_prefetch && !auto_q) auto_pending <= 1'b1;   // rising edge

            // ---- AXI-Lite write handshakes ---------------------------------
            if (s_axil_awvalid && s_axil_awready) begin aw_got <= 1; aw_addr_q <= s_axil_awaddr[7:0]; end
            if (s_axil_wvalid  && s_axil_wready)  begin w_got  <= 1; w_data_q  <= s_axil_wdata; end
            if (csr_wr) begin
                aw_got <= 0; w_got <= 0;
                s_axil_bvalid <= 1;
                s_axil_bresp  <= wr_mapped(aw_addr_q) ? 2'b00 : 2'b10;
                case (aw_addr_q)
                    8'h00: begin
                        auto_en <= w_data_q[1]; dec_en <= w_data_q[2]; irq_en <= w_data_q[3];
                        if (w_data_q[0] && !busy && !start_pending && !auto_pending) start_pending <= 1'b1;  // no START while an auto tile is queued
                    end
                    8'h04: begin
                        if (w_data_q[1]) done_sticky <= 1'b0;
                        if (w_data_q[2]) err_sticky  <= 1'b0;
                    end
                    8'h08: reg_src    <= w_data_q[23:0];
                    8'h0C: reg_len    <= w_data_q[24:0];
                    8'h10: reg_dst_a  <= w_data_q;
                    8'h14: reg_dst_b  <= w_data_q;
                    8'h18: reg_stride <= w_data_q;
                    8'h1C: reg_tiles  <= w_data_q;
                    8'h20: key_reg[31:0]    <= w_data_q;
                    8'h24: key_reg[63:32]   <= w_data_q;
                    8'h28: key_reg[95:64]   <= w_data_q;
                    8'h2C: key_reg[127:96]  <= w_data_q;
                    8'h30: key_load <= 1'b1;
                    8'h34: bank_sel <= w_data_q[0];
                    default: ;
                endcase
            end
            if (s_axil_bvalid && s_axil_bready) s_axil_bvalid <= 1'b0;

            // ---- AXI-Lite read channel -------------------------------------
            s_axil_arready <= 1'b0;
            if (s_axil_arvalid && !s_axil_arready && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                case (s_axil_araddr[7:0])
                    8'h00: s_axil_rdata <= {28'b0, irq_en, dec_en, auto_en, 1'b0};
                    8'h04: s_axil_rdata <= {27'b0, tile_bank, key_valid, err_sticky, done_sticky, busy};
                    8'h08: s_axil_rdata <= {8'b0, reg_src};
                    8'h0C: s_axil_rdata <= {7'b0, reg_len};
                    8'h10: s_axil_rdata <= reg_dst_a;
                    8'h14: s_axil_rdata <= reg_dst_b;
                    8'h18: s_axil_rdata <= reg_stride;
                    8'h1C: s_axil_rdata <= reg_tiles;
                    8'h34: s_axil_rdata <= {31'b0, bank_sel};
                    default: s_axil_rdata <= '0;
                endcase
            end
            if (s_axil_rvalid && s_axil_rready) s_axil_rvalid <= 1'b0;

            // ---- transfer FSM ------------------------------------------------
            case (state)
                S_IDLE: begin
                    if (launch_start || launch_auto) begin
                        if (bad_cfg || (dec_en && !key_valid)) begin
                            err_sticky <= 1'b1;
                            if (launch_start) start_pending <= 1'b0;
                            else              auto_pending  <= 1'b0;
                        end else begin
                            if (launch_start) start_pending <= 1'b0;
                            else begin auto_pending <= 1'b0; reg_tiles <= reg_tiles - 1'b1; end
                            tile_bank  <= bank_sel;
                            cur_addr   <= bank_sel ? reg_dst_b : reg_dst_a;
                            beats_left <= reg_len[24:4];
                            src_lat    <= reg_src;
                            len_lat    <= reg_len;
                            dec_lat    <= dec_en;
                            state      <= S_KICK;
                        end
                    end else if (auto_pending && (!auto_en || reg_tiles == 0)) begin
                        auto_pending <= 1'b0;             // not allowed: drop
                    end
                end

                S_KICK: if (!spi_busy) begin
                    spi_start <= 1'b1;
                    state     <= S_AW;
                end

                S_AW: if (m_axi_awready) begin
                    chunk_r <= chunk;
                    w_cnt   <= '0;
                    state   <= S_W;
                end

                S_W: if (w_fire) begin
                    if (m_axi_wlast) state <= S_B;
                    else             w_cnt <= w_cnt + 1'b1;
                end

                S_B: if (m_axi_bvalid) begin
                    if (m_axi_bresp != 2'b00) err_sticky <= 1'b1;
                    beats_left <= beats_left - 21'(chunk_r);
                    cur_addr   <= cur_addr + {23'b0, chunk_r, 4'b0};
                    state      <= (beats_left == 21'(chunk_r)) ? S_FIN : S_AW;
                end

                S_FIN: begin
                    done_sticky <= 1'b1;
                    fill_done   <= 1'b1;
                    fill_bank   <= tile_bank;
                    bank_sel    <= ~tile_bank;
                    reg_src     <= reg_src + reg_stride[23:0];
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign irq = irq_en && done_sticky;

endmodule