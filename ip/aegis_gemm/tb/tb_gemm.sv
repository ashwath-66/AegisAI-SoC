`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_gemm : self-checking test of the 16x16 weight-stationary systolic array
//   dense / sparse / gapped-stream / extreme-value / weight-reload tests,
//   every output row compared against a software reference (C = A x W).
//-----------------------------------------------------------------------------
module tb_gemm;

    localparam int N       = 16;
    localparam int DW      = 8;
    localparam int AW      = 20;
    localparam int LATENCY = 2*N - 1;
    localparam int MAXROWS = 256;

    logic                      clk = 0;
    logic                      rst_n;
    logic                      w_load_en;
    logic [$clog2(N)-1:0]      w_load_row;
    logic [N*DW-1:0]           w_load_data;
    logic                      a_valid;
    logic [N*DW-1:0]           a_row;
    logic                      c_valid;
    logic [N*AW-1:0]           c_row;

    `ifdef GATE
    localparam bit CG = 1'b1;     // run with +define+GATE to test the latch ICG version
`else
    localparam bit CG = 1'b0;
`endif
    systolic_array #(.ARRAY_SIZE(N), .DATA_WIDTH(DW), .ACC_WIDTH(AW), .CLK_GATE(CG)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .w_load_en(w_load_en), .w_load_row(w_load_row), .w_load_data(w_load_data),
        .a_valid(a_valid), .a_row(a_row),
        .c_valid(c_valid), .c_row(c_row), .pe_gated()
    );

    always #5 clk = ~clk;   // 100 MHz

    // ---------------- reference model / scoreboard ----------------------------
    int signed Wm [N][N];
    int signed exp_mem [MAXROWS][N];
    int exp_wr, exp_rd;
    int errors, checked;
    longint skip_cnt, pe_cycles;
    bit measure;

    // ---------------- output monitor ------------------------------------------
    always @(posedge clk) begin
        if (rst_n && c_valid) begin
            if (exp_rd >= exp_wr) begin
                $display("[%0t] ERROR: unexpected c_valid (no expected row)", $time);
                errors++;
            end else begin
                for (int c = 0; c < N; c++) begin
                    logic signed [AW-1:0] got;
                    got = c_row[c*AW +: AW];
                    if (int'(got) !== exp_mem[exp_rd][c]) begin
                        if (errors < 10)
                            $display("[%0t] MISMATCH row %0d col %0d : got %0d exp %0d",
                                     $time, exp_rd, c, int'(got), exp_mem[exp_rd][c]);
                        errors++;
                    end
                end
                exp_rd++;
                checked++;
            end
        end
        if (rst_n && measure) begin
            skip_cnt  += $countones(u_dut.skip_vec);
            pe_cycles += N*N;
        end
    end

    // ---------------- helpers --------------------------------------------------
    function automatic int signed rnd_int8(input int zero_pct);
        int r;
        if ($urandom_range(0, 99) < zero_pct) return 0;
        r = $urandom_range(0, 255);
        return (r > 127) ? r - 256 : r;
    endfunction

    task automatic load_weights(input int zero_pct, input int fixed, input int fixed_val);
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++)
                Wm[r][c] = fixed ? fixed_val : rnd_int8(zero_pct);
        for (int r = 0; r < N; r++) begin
            @(negedge clk);
            w_load_en  = 1;
            w_load_row = r[$clog2(N)-1:0];
            for (int c = 0; c < N; c++)
                w_load_data[c*DW +: DW] = DW'(Wm[r][c]);
        end
        @(negedge clk);
        w_load_en = 0;
    endtask

    // stream 'rows' rows of A; gap_pct = % chance of an idle cycle before a row
    task automatic stream_rows(input int rows, input int zero_pct, input int gap_pct,
                               input int fixed, input int fixed_val);
        int signed arow [N];
        measure = 1;
        for (int m = 0; m < rows; m++) begin
            while ($urandom_range(0, 99) < gap_pct) begin
                @(negedge clk);
                a_valid = 0;
                a_row   = $urandom;     // garbage must be ignored when invalid
            end
            for (int k = 0; k < N; k++)
                arow[k] = fixed ? fixed_val : rnd_int8(zero_pct);
            for (int c = 0; c < N; c++) begin
                int acc;
                acc = 0;
                for (int k = 0; k < N; k++) acc += arow[k] * Wm[k][c];
                exp_mem[exp_wr][c] = acc;
            end
            exp_wr++;
            @(negedge clk);
            a_valid = 1;
            for (int k = 0; k < N; k++) a_row[k*DW +: DW] = DW'(arow[k]);
        end
        @(negedge clk);
        a_valid = 0;
        a_row   = '0;
        repeat (LATENCY + 4) @(negedge clk);
        measure = 0;
    endtask

    task automatic report(input string name);
        $display("[TEST] %-34s rows checked=%0d  total errors=%0d  PE idle=%0.1f%%",
                 name, checked, errors,
                 pe_cycles ? 100.0*real'(skip_cnt)/real'(pe_cycles) : 0.0);
        if (exp_rd != exp_wr) begin
            $display("   ERROR: %0d rows expected, %0d received", exp_wr, exp_rd);
            errors++;
        end
        exp_wr = 0; exp_rd = 0; skip_cnt = 0; pe_cycles = 0;
    endtask

    // ---------------- test sequence -------------------------------------------
    initial begin
        rst_n = 0; w_load_en = 0; w_load_row = 0; w_load_data = '0;
        a_valid = 0; a_row = '0; measure = 0;
        exp_wr = 0; exp_rd = 0; errors = 0; checked = 0; skip_cnt = 0; pe_cycles = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        load_weights(0, 0, 0);
        stream_rows(64, 0, 0, 0, 0);
        report("dense random");

        load_weights(50, 0, 0);
        stream_rows(64, 50, 0, 0, 0);
        report("sparse 50% zeros");

        load_weights(0, 0, 0);
        stream_rows(64, 0, 40, 0, 0);
        report("dense, gapped stream (40% idle)");

        load_weights(0, 1, -128);
        stream_rows(8, 0, 0, 1, -128);
        report("extreme: all -128 x -128");

        load_weights(0, 1, 127);
        stream_rows(8, 0, 0, 1, -128);
        report("extreme: -128 x 127");

        load_weights(90, 0, 0);
        stream_rows(64, 90, 10, 0, 0);
        report("very sparse 90% zeros");

        load_weights(0, 0, 0);          // weight reload after previous run
        stream_rows(32, 20, 20, 0, 0);
        report("weight reload, mixed");

        if (errors == 0) $display("\n[TB PASS] tb_gemm: all %0d rows matched.\n", checked);
        else             $display("\n[TB FAIL] tb_gemm: %0d errors.\n", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("[TB FAIL] timeout");
        $finish;
    end

endmodule