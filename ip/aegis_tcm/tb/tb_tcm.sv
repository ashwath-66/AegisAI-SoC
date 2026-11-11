`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_tcm : axi_tcm / ping_pong_sram unit test
//   random INCR write/read bursts with partial strobes against a shadow memory,
//   DECERR / SLVERR responses, and concurrent GEMM-port reads (GEMM must always
//   win, AXI reads must still complete correctly).
//-----------------------------------------------------------------------------
module tb_tcm;
    localparam logic [31:0] BASE = 32'h1000_0000;

    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [31:0] awaddr, araddr; logic [7:0] awlen, arlen; logic [2:0] awsize, arsize; logic [1:0] awburst, arburst;
    logic awvalid, awready, wvalid, wready, wlast, bvalid, bready, arvalid, arready, rvalid, rready, rlast;
    logic [127:0] wdata, rdata; logic [15:0] wstrb; logic [1:0] bresp, rresp;
    logic g_en, g_bank; logic [8:0] g_word; logic [127:0] g_rdata;

    axi_tcm #(.BASE(BASE)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awlen(awlen), .s_axi_awsize(awsize), .s_axi_awburst(awburst),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arlen(arlen), .s_axi_arsize(arsize), .s_axi_arburst(arburst),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .g_en(g_en), .g_bank(g_bank), .g_word(g_word), .g_rdata(g_rdata)
    );

    byte shadow [16384];
    int errors = 0;

    task automatic write_burst(input logic [31:0] a, input int beats, input logic [2:0] size,
                               input logic [1:0] burst, output logic [1:0] resp);
        @(posedge clk); #1; awvalid = 1; awaddr = a; awlen = beats - 1; awsize = size; awburst = burst;
        do @(posedge clk); while (!awready);
        #1; awvalid = 0;
        for (int b = 0; b < beats; b++) begin
            logic [127:0] d; logic [15:0] s;
            d = {$urandom, $urandom, $urandom, $urandom};
            s = (size == 4) ? ($urandom_range(0, 3) == 0 ? 16'(($urandom)) : 16'hFFFF)
                            : (16'h1 << ((a + b*(1<<size)) % 16));
            wdata = d; wstrb = s; wlast = (b == beats - 1); wvalid = 1;
            do @(posedge clk); while (!wready);
            // model update (only for legal accesses)
            if (a[31:14] == BASE[31:14] && burst == 2'b01 && size <= 4)
                for (int i = 0; i < 16; i++)
                    if (s[i]) shadow[((a - BASE) + b*(1<<size)) / 16 * 16 + i] = d[i*8 +: 8];
            #1; wvalid = 0;
        end
        bready = 1;
        do @(posedge clk); while (!bvalid);
        resp = bresp;
        #1; bready = 0;
    endtask

    task automatic read_burst(input logic [31:0] a, input int beats, input logic [2:0] size,
                              input bit check, output logic [1:0] resp);
        @(posedge clk); #1; arvalid = 1; araddr = a; arlen = beats - 1; arsize = size; arburst = 2'b01;
        do @(posedge clk); while (!arready);
        #1; arvalid = 0; rready = 1;
        for (int b = 0; b < beats; b++) begin
            do @(posedge clk); while (!rvalid);
            resp = rresp;
            if (rlast !== (b == beats - 1)) begin errors++; $display("[FAIL] RLAST wrong"); end
            if (check && rresp == 0)
                for (int i = 0; i < 16; i++)
                    if (rdata[i*8 +: 8] !== shadow[((a - BASE) + b*(1<<size)) / 16 * 16 + i]) begin
                        if (errors < 6) $display("[FAIL] read @%h beat %0d byte %0d got %02h exp %02h", a, b, i,
                                                 rdata[i*8 +: 8], shadow[((a - BASE) + b*(1<<size))/16*16 + i]);
                        errors++;
                    end
            #1;
        end
        rready = 0;
    endtask

    // GEMM port reader: continuously reads bank A and checks against shadow
    int gem_reads = 0, gem_bad = 0;
    bit gem_run = 0;
    logic [8:0] gem_w_q; logic gem_v_q;
    always @(posedge clk) begin
        if (gem_run) begin
            g_en <= ($urandom_range(0, 99) < 60); g_bank <= 0; g_word <= $urandom_range(0, 511);   // 60% duty: GEMM wins, AXI still progresses
        end else g_en <= 0;
        gem_v_q <= g_en; gem_w_q <= g_word;
        if (gem_v_q) begin
            for (int i = 0; i < 16; i++)
                if (g_rdata[i*8 +: 8] !== shadow[gem_w_q*16 + i]) gem_bad++;
            gem_reads++;
        end
    end

    logic [1:0] resp;
    int n;
    initial begin
        rst_n = 0; awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0; wlast = 0;
        g_en = 0; g_bank = 0; g_word = 0;
        for (int i = 0; i < 16384; i++) shadow[i] = 8'h00;
        repeat (5) @(posedge clk); #1; rst_n = 1;

        // fill both banks completely with full-width writes
        for (int a = 0; a < 16384; a += 256) begin
            write_burst(BASE + a, 16, 4, 2'b01, resp);
            if (resp != 0) begin errors++; $display("[FAIL] fill resp %0d", resp); end
        end
        // fix shadow for the strobed lanes (done inside write_burst), now random traffic
        for (n = 0; n < 150; n++) begin
            int beats, off;
            beats = $urandom_range(1, 16);
            off   = $urandom_range(0, 16384 - beats*16) / 16 * 16;
            if ((off % 256) + beats * 16 > 256) beats = (256 - (off % 256)) / 16;     // stay inside 256 B
            write_burst(BASE + off, beats, 4, 2'b01, resp);
            if (resp != 0) begin errors++; $display("[FAIL] write resp %0d", resp); end
            read_burst(BASE + off, beats, 4, 1, resp);
        end
        $display("[TEST] 150 random write+readback bursts (partial strobes)  errors=%0d", errors);

        // narrow (32-bit) single writes and reads
        for (n = 0; n < 40; n++) begin
            int off = $urandom_range(0, 16380) / 4 * 4;
            write_burst(BASE + off, 1, 3'd2, 2'b01, resp);   // size 4 bytes, single lane strobe
            read_burst(BASE + off, 1, 3'd2, 1, resp);
        end
        $display("[TEST] narrow single-beat accesses                         errors=%0d", errors);

        // error responses
        write_burst(32'h2000_0000, 2, 4, 2'b01, resp);
        if (resp != 2'b11) begin errors++; $display("[FAIL] expected DECERR on write, got %0d", resp); end
        read_burst(32'h2000_0000, 1, 4, 0, resp);
        if (resp != 2'b11) begin errors++; $display("[FAIL] expected DECERR on read, got %0d", resp); end
        write_burst(BASE, 1, 3'd5, 2'b01, resp);
        if (resp != 2'b10) begin errors++; $display("[FAIL] expected SLVERR on size 5, got %0d", resp); end
        write_burst(BASE, 1, 4, 2'b10, resp);
        if (resp != 2'b10) begin errors++; $display("[FAIL] expected SLVERR on WRAP burst, got %0d", resp); end
        $display("[TEST] DECERR / SLVERR responses                           errors=%0d", errors);

        // concurrency: GEMM hammers bank A while AXI writes bank B and reads bank A
        gem_run = 1;
        for (n = 0; n < 60; n++) begin
            int off = 32'h2000 + ($urandom_range(0, 7) * 256);
            write_burst(BASE + off, 16, 4, 2'b01, resp);
            read_burst(BASE + off, 16, 4, 1, resp);               // other bank: no conflict
            read_burst(BASE + ($urandom_range(0, 31) * 256), 16, 4, 1, resp);  // bank A: arbitration
        end
        gem_run = 0;
        repeat (4) @(posedge clk);
        $display("[TEST] concurrent GEMM reads: %0d reads, %0d bad bytes, AXI errors=%0d", gem_reads, gem_bad, errors);
        errors += gem_bad;

        if (errors == 0 && gem_reads > 1000) $display("\n[TB PASS] tb_tcm\n");
        else                                 $display("\n[TB FAIL] tb_tcm: %0d errors, %0d gem reads\n", errors, gem_reads);
        $finish;
    end
    initial begin #60_000_000; $display("[TB FAIL] timeout"); $finish; end
endmodule
