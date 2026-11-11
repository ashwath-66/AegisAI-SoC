`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// systolic_array : NxN weight-stationary INT8 GEMM core (default 16x16)
//
//   C[m][c] = sum_k A[m][k] * W[k][c]
//
//   Weights : load one row of W per cycle (w_load_en / w_load_row / w_load_data,
//             element c of w_load_data = W[row][c]).
//   A input : one row of A per cycle (a_valid / a_row, element k = A[m][k]).
//   C output: one row of C per cycle (c_valid / c_row, element c = C[m][c]),
//             exactly LATENCY cycles after the matching A row.
//   Input skew and output unskew are inside this module.
//-----------------------------------------------------------------------------
module systolic_array #(
    parameter int ARRAY_SIZE = 16,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 20,
    parameter bit CLK_GATE   = 1'b0     // 1 = per-PE latch ICG (ASIC), 0 = clock-enable (FPGA/sim)
) (
    input  logic                                   clk,
    input  logic                                   rst_n,

    input  logic                                   w_load_en,
    input  logic [$clog2(ARRAY_SIZE)-1:0]          w_load_row,
    input  logic [ARRAY_SIZE*DATA_WIDTH-1:0]       w_load_data,

    input  logic                                   a_valid,
    input  logic [ARRAY_SIZE*DATA_WIDTH-1:0]       a_row,

    output logic                                   c_valid,
    output logic [ARRAY_SIZE*ACC_WIDTH-1:0]        c_row,
    output logic [ARRAY_SIZE*ARRAY_SIZE-1:0]       pe_gated   // per-PE "clock gated this cycle" (power stats)
);

    localparam int N       = ARRAY_SIZE;
    localparam int LATENCY = 2*N - 1;

    // ---------------- input gating + skew (row k delayed by k cycles) --------
    logic [DATA_WIDTH-1:0] a_skew [N];

    for (genvar k = 0; k < N; k++) begin : g_skew
        logic [DATA_WIDTH-1:0] a_now;
        assign a_now = a_valid ? a_row[k*DATA_WIDTH +: DATA_WIDTH] : '0;

        if (k == 0) begin : g_nodelay
            assign a_skew[k] = a_now;
        end else begin : g_delay
            logic [DATA_WIDTH-1:0] dly [k];
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int i = 0; i < k; i++) dly[i] <= '0;
                end else begin
                    dly[0] <= a_now;
                    for (int i = 1; i < k; i++) dly[i] <= dly[i-1];
                end
            end
            assign a_skew[k] = dly[k-1];
        end
    end

    // ---------------- PE grid -------------------------------------------------
    logic signed [DATA_WIDTH-1:0] a_wire [N][N+1];
    logic signed [ACC_WIDTH-1:0]  p_wire [N+1][N];
    logic [N*N-1:0]               skip_vec;   // per-PE "multiplier isolated" flags
    logic [N*N-1:0]               gated_vec;  // per-PE "clock gated" flags
    assign pe_gated = gated_vec;

    for (genvar r = 0; r < N; r++) begin : g_row
        assign a_wire[r][0] = a_skew[r];
    end
    for (genvar c = 0; c < N; c++) begin : g_top
        assign p_wire[0][c] = '0;
    end

    for (genvar r = 0; r < N; r++) begin : g_r
        for (genvar c = 0; c < N; c++) begin : g_c
            pe #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .CLK_GATE(CLK_GATE)) u_pe (
                .clk      (clk),
                .rst_n    (rst_n),
                .w_load   (w_load_en && (w_load_row == r)),
                .w_in     (w_load_data[c*DATA_WIDTH +: DATA_WIDTH]),
                .a_in     (a_wire[r][c]),
                .psum_in  (p_wire[r][c]),
                .a_out    (a_wire[r][c+1]),
                .psum_out (p_wire[r+1][c]),
                .skip     (skip_vec[r*N + c]),
                .gated    (gated_vec[r*N + c])
            );
        end
    end

    // ---------------- output unskew (column c delayed by N-1-c cycles) -------
    for (genvar c = 0; c < N; c++) begin : g_unskew
        if (c == N-1) begin : g_nodelay
            assign c_row[c*ACC_WIDTH +: ACC_WIDTH] = p_wire[N][c];
        end else begin : g_delay
            localparam int D = N-1-c;
            logic [ACC_WIDTH-1:0] dly [D];
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int i = 0; i < D; i++) dly[i] <= '0;
                end else begin
                    dly[0] <= p_wire[N][c];
                    for (int i = 1; i < D; i++) dly[i] <= dly[i-1];
                end
            end
            assign c_row[c*ACC_WIDTH +: ACC_WIDTH] = dly[D-1];
        end
    end

    // ---------------- valid pipeline ------------------------------------------
    logic [LATENCY-1:0] v_pipe;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) v_pipe <= '0;
        else        v_pipe <= {v_pipe[LATENCY-2:0], a_valid};
    end
    assign c_valid = v_pipe[LATENCY-1];

endmodule