`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_pe : PE zero-sensing / micro clock-gating check
//   - golden model = plain always-clocked weight-stationary MAC
//   - DUT0 CLK_GATE=0 (clock-enable) and DUT1 CLK_GATE=1 (latch ICG) must match the
//     golden model on every cycle, with a stimulus rich in zeros
//   - the gate must actually fire (gated cycles > 0) and must NOT fire when psum_in != 0
//-----------------------------------------------------------------------------
module tb_pe;
    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    logic               w_load;
    logic signed [7:0]  w_in, a_in;
    logic signed [19:0] psum_in;

    logic signed [7:0]  a0, a1;
    logic signed [19:0] p0, p1;
    logic               skip0, skip1, g0, g1;

    pe #(.CLK_GATE(1'b0)) u_ce  (.clk(clk), .rst_n(rst_n), .w_load(w_load), .w_in(w_in), .a_in(a_in),
                                 .psum_in(psum_in), .a_out(a0), .psum_out(p0), .skip(skip0), .gated(g0));
    pe #(.CLK_GATE(1'b1)) u_icg (.clk(clk), .rst_n(rst_n), .w_load(w_load), .w_in(w_in), .a_in(a_in),
                                 .psum_in(psum_in), .a_out(a1), .psum_out(p1), .skip(skip1), .gated(g1));

    // golden model
    logic signed [7:0]  gw, ga;
    logic signed [19:0] gp;
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin gw <= 0; ga <= 0; gp <= 0; end
        else begin
            if (w_load) gw <= w_in;
            ga <= a_in;
            gp <= psum_in + a_in * gw;
        end

    int errors = 0, cycles = 0, gated_cycles = 0, bad_gate = 0;

    function automatic int signed r8(input int zp);
        int r;
        if ($urandom_range(0, 99) < zp) return 0;
        r = $urandom_range(0, 255);
        return (r > 127) ? r - 256 : r;
    endfunction

    task automatic drive(input int zp_a, input int zp_p, input int zp_w);
        w_load  = ($urandom_range(0, 99) < 6);
        w_in    = 8'(r8(zp_w));
        a_in    = 8'(r8(zp_a));
        psum_in = ($urandom_range(0, 99) < zp_p) ? 20'sd0 : 20'($urandom_range(0, 32'hFFFFF));
    endtask

    // monitor samples at posedge (pre-NBA: outputs/flags of the previous edge, inputs stable since negedge)
    always @(posedge clk) if (rst_n) begin
        cycles++;
        if (a0 !== ga || p0 !== gp) begin errors++; if (errors < 6) $display("[%0t] CE  mismatch a=%0d/%0d p=%0d/%0d", $time, a0, ga, p0, gp); end
        if (a1 !== ga || p1 !== gp) begin errors++; if (errors < 6) $display("[%0t] ICG mismatch a=%0d/%0d p=%0d/%0d", $time, a1, ga, p1, gp); end
        if (g0 !== g1) begin errors++; $display("[%0t] gated flag differs CE vs ICG", $time); end
        if (g1) gated_cycles++;
        if (g1 && (psum_in !== 0 || a_in !== 0)) bad_gate++;
    end

    initial begin
        $dumpfile("dump.vcd"); $dumpvars(0, tb_pe);
        rst_n = 0; w_load = 0; w_in = 0; a_in = 0; psum_in = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;

        // directed: weight 5, a=3 -> psum 15 ; a=4 psum_in=100 -> 120
        @(negedge clk); w_load = 1; w_in = 5; a_in = 0; psum_in = 0;
        @(negedge clk); w_load = 0; a_in = 3; psum_in = 0;
        @(negedge clk); a_in = 4; psum_in = 100;
        @(negedge clk);   // outputs now hold 100 + 4*5
        if (p0 !== 120 || p1 !== 120) begin errors++; $display("[FAIL] directed MAC: got %0d/%0d exp 120", p0, p1); end
        else $display("[PASS] directed MAC = 120");
        a_in = 0; psum_in = 0;

        // random phases: dense, sparse, very sparse, idle bursts
        repeat (3000) begin @(negedge clk); drive(0, 0, 0);   end
        repeat (3000) begin @(negedge clk); drive(50, 50, 10); end
        repeat (3000) begin @(negedge clk); drive(85, 90, 30); end
        repeat (2000) begin @(negedge clk); drive(100, 100, 5); end
        repeat (3000) begin @(negedge clk); drive(60, 70, 60); end
        @(negedge clk); @(negedge clk);

        $display("cycles=%0d gated=%0d (%0.1f%%)", cycles, gated_cycles, 100.0*gated_cycles/cycles);
        if (gated_cycles == 0) begin errors++; $display("[FAIL] clock gate never fired"); end
        if (bad_gate != 0)     begin errors++; $display("[FAIL] gate fired with non-zero inputs %0d times", bad_gate); end
        if (errors == 0) $display("\n[TB PASS] tb_pe: clock-gated PE is bit-exact with the plain PE\n");
        else             $display("\n[TB FAIL] tb_pe: %0d errors\n", errors);
        $finish;
    end
endmodule
