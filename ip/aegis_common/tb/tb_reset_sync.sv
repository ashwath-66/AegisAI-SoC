`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_reset_sync : asynchronous assert, synchronous 2-FF de-assert
//   1. assert is asynchronous  (rst_n_out falls with no clock edge)
//   2. de-assert takes exactly 2 clock edges and is aligned to a clock edge
//   3. a sub-cycle reset glitch still resets the output
//   4. reset re-asserted before the 2nd edge: output never goes high
//-----------------------------------------------------------------------------
module tb_reset_sync;
    logic clk = 0;
    logic rst_n_in, rst_n_out;
    always #5 clk = ~clk;                         // posedge at 5, 15, 25 ...

    reset_sync dut (.clk(clk), .rst_n_in(rst_n_in), .rst_n_out(rst_n_out));

    int  errors = 0;
    time last_pos = 0;
    always @(posedge clk) last_pos = $time;
    always @(posedge rst_n_out)
        if ($time != last_pos) begin errors++; $display("[FAIL] release not aligned to clock edge (t=%0t)", $time); end

    task automatic expect_out(input logic exp, input string what);
        if (rst_n_out !== exp) begin errors++; $display("[FAIL] %s: rst_n_out=%b expected %b (t=%0t)", what, rst_n_out, exp, $time); end
    endtask

    initial begin
        rst_n_in = 1; #1; rst_n_in = 0;
        #22; expect_out(0, "held in reset");

        // 2) de-assert: 2 edges
        @(negedge clk); #1; rst_n_in = 1;
        expect_out(0, "right after release (no edge yet)");
        @(posedge clk); #1; expect_out(0, "after 1st edge");
        @(posedge clk); #1; expect_out(1, "after 2nd edge");
        repeat (3) @(posedge clk);
        expect_out(1, "stays released");

        // 1) async assert, mid-cycle (negedge+3 ns, next posedge is 5 ns after negedge)
        @(negedge clk); #3; rst_n_in = 0; #1;
        expect_out(0, "async assert (no clock edge)");

        // release again, then 3) glitch: 1 ns low pulse between edges
        @(negedge clk); #1; rst_n_in = 1;
        repeat (3) @(posedge clk);  #1; expect_out(1, "released again");
        @(negedge clk); #2; rst_n_in = 0; #1; rst_n_in = 1;
        #0.1; expect_out(0, "sub-cycle glitch resets");
        @(posedge clk); #1; expect_out(0, "glitch recovery 1st edge");
        @(posedge clk); #1; expect_out(1, "glitch recovery 2nd edge");

        // 4) re-assert before the 2nd edge: output must never rise
        @(negedge clk); #3; rst_n_in = 0; #3;
        @(negedge clk); #1; rst_n_in = 1;
        @(posedge clk); #1; expect_out(0, "abort: after 1st edge");
        @(negedge clk); #1; rst_n_in = 0;
        repeat (3) @(posedge clk); #1; expect_out(0, "abort: stays low");

        if (errors == 0) $display("\n[TB PASS] tb_reset_sync\n");
        else             $display("\n[TB FAIL] tb_reset_sync: %0d errors\n", errors);
        $finish;
    end
endmodule
