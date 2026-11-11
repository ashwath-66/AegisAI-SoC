`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// speck_decryptor : SPECK-64/128 decryptor for a 128-bit stream beat
//   - 64-bit block = {x[31:0], y[31:0]}, 128-bit key = {l2, l1, l0, k0}
//   - 27 rounds; the round-key store is built by an on-chip key schedule
//     (27 cycles after key_load)
//   - a 128-bit beat = two independent 64-bit blocks (ECB), decrypted in
//     lock-step by two iterative round units, one round per cycle
//     => 27 cycles per 128 bits, i.e. faster than the 4 bit/cycle QSPI rate
//   - beat bit order: block0 = ct[63:0], block1 = ct[127:64]
//-----------------------------------------------------------------------------
module speck_decryptor (
    input  logic         clk,
    input  logic         rst_n,

    // key interface
    input  logic         key_load,        // pulse; key_in is sampled
    input  logic [127:0] key_in,
    output logic         key_valid,       // round keys ready

    // ciphertext in (valid/ready)
    input  logic         in_valid,
    output logic         in_ready,
    input  logic [127:0] ciphertext_in,

    // plaintext out (valid/ready)
    output logic         out_valid,
    input  logic         out_ready,
    output logic [127:0] plaintext_out
);

    localparam int ROUNDS = 27;

    function automatic logic [31:0] ror8(input logic [31:0] v); return {v[7:0],  v[31:8]};  endfunction
    function automatic logic [31:0] rol8(input logic [31:0] v); return {v[23:0], v[31:24]}; endfunction
    function automatic logic [31:0] ror3(input logic [31:0] v); return {v[2:0],  v[31:3]};  endfunction
    function automatic logic [31:0] rol3(input logic [31:0] v); return {v[28:0], v[31:29]}; endfunction

    // ---------------- key schedule -------------------------------------------
    logic [31:0] rk [ROUNDS];
    logic [31:0] k_cur, l0, l1, l2;
    logic [4:0]  ks_cnt;
    logic        ks_busy;

    logic [31:0] l_new;
    assign l_new = (k_cur + ror8(l0)) ^ 32'(ks_cnt);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_valid <= 1'b0;
            ks_busy   <= 1'b0;
            ks_cnt    <= '0;
            k_cur     <= '0;
            l0 <= '0; l1 <= '0; l2 <= '0;
        end else if (key_load) begin
            key_valid <= 1'b0;
            ks_busy   <= 1'b1;
            ks_cnt    <= '0;
            k_cur     <= key_in[31:0];
            l0        <= key_in[63:32];
            l1        <= key_in[95:64];
            l2        <= key_in[127:96];
        end else if (ks_busy) begin
            rk[ks_cnt] <= k_cur;
            if (ks_cnt == ROUNDS-1) begin
                ks_busy   <= 1'b0;
                key_valid <= 1'b1;
            end else begin
                k_cur  <= rol3(k_cur) ^ l_new;
                l0     <= l1;
                l1     <= l2;
                l2     <= l_new;
                ks_cnt <= ks_cnt + 1'b1;
            end
        end
    end

    // ---------------- decrypt engine -----------------------------------------
    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_t;
    state_t state;

    logic [31:0] x0, y0, x1, y1;
    logic [4:0]  rnd;                      // counts ROUNDS-1 .. 0

    logic [31:0] y0_n, x0_n, y1_n, x1_n;
    always_comb begin
        y0_n = ror3(y0 ^ x0);
        x0_n = rol8((x0 ^ rk[rnd]) - y0_n);
        y1_n = ror3(y1 ^ x1);
        x1_n = rol8((x1 ^ rk[rnd]) - y1_n);
    end

    assign in_ready      = (state == S_IDLE) && key_valid && !key_load;
    assign out_valid     = (state == S_DONE);
    assign plaintext_out = {x1, y1, x0, y0};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            rnd   <= '0;
            x0 <= '0; y0 <= '0; x1 <= '0; y1 <= '0;
        end else begin
            if (key_load) begin
                state <= S_IDLE;           // abandon any block in flight
            end else begin
                case (state)
                    S_IDLE: if (in_valid && in_ready) begin
                        x0 <= ciphertext_in[63:32];
                        y0 <= ciphertext_in[31:0];
                        x1 <= ciphertext_in[127:96];
                        y1 <= ciphertext_in[95:64];
                        rnd   <= 5'(ROUNDS-1);
                        state <= S_RUN;
                    end
                    S_RUN: begin
                        x0 <= x0_n; y0 <= y0_n;
                        x1 <= x1_n; y1 <= y1_n;
                        if (rnd == 0) state <= S_DONE;
                        else          rnd   <= rnd - 1'b1;
                    end
                    S_DONE: if (out_ready) state <= S_IDLE;
                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule