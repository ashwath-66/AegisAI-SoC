`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_regif : axil_regif (AXI4-Lite slave -> register interface), AW = 8
//   register-file model behind it: 16 words, byte strobes; addresses >= 0x40 return SLVERR
//   - AW-first / W-first / same-cycle writes, delayed B / R acceptance (back-pressure)
//   - byte strobes, error responses (state unchanged), read-after-write
//   - wr_en / rd_en are exactly one cycle per transaction
//   - 400 random transactions against a scoreboard
//-----------------------------------------------------------------------------
module tb_regif;
    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [31:0] awaddr, wdata, araddr, rdata;
    logic [3:0]  wstrb;
    logic [1:0]  bresp, rresp;
    logic        awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready;

    logic        wr_en, rd_en, wr_err, rd_err;
    logic [7:0]  wr_addr, rd_addr;
    logic [31:0] wr_data, rd_data;
    logic [3:0]  wr_strb;

    axil_regif #(.AW(8)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr(awaddr), .s_awvalid(awvalid), .s_awready(awready),
        .s_wdata(wdata), .s_wstrb(wstrb), .s_wvalid(wvalid), .s_wready(wready),
        .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
        .s_araddr(araddr), .s_arvalid(arvalid), .s_arready(arready),
        .s_rdata(rdata), .s_rresp(rresp), .s_rvalid(rvalid), .s_rready(rready),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .wr_strb(wr_strb), .wr_err(wr_err),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data), .rd_err(rd_err)
    );

    // ---- register-file model --------------------------------------------------
    logic [31:0] regs [16];
    assign wr_err  = (wr_addr >= 8'h40);
    assign rd_err  = (rd_addr >= 8'h40);
    assign rd_data = regs[rd_addr[5:2]];
    always_ff @(posedge clk)
        if (wr_en && !wr_err)
            for (int i = 0; i < 4; i++)
                if (wr_strb[i]) regs[wr_addr[5:2]][i*8 +: 8] <= wr_data[i*8 +: 8];

    // ---- scoreboard / counters --------------------------------------------------
    logic [31:0] exp_regs [16];
    int errors = 0, n_wr = 0, n_rd = 0, wr_en_cycles = 0, rd_en_cycles = 0;
    logic wr_en_q = 0, rd_en_q = 0;
    always @(posedge clk) begin
        if (wr_en) wr_en_cycles++;
        if (rd_en) rd_en_cycles++;
        if (wr_en && wr_en_q) begin errors++; $display("[FAIL] wr_en high for more than one cycle"); end
        if (rd_en && rd_en_q) begin errors++; $display("[FAIL] rd_en high for more than one cycle"); end
        wr_en_q <= wr_en; rd_en_q <= rd_en;
    end

    // ---- AXI4-Lite master tasks (drive at negedge, handshake seen at posedge) -------
    task automatic do_write(input [31:0] a, input [31:0] d, input [3:0] s,
                            input int adly, input int wdly, input int bdly, output logic [1:0] resp);
        logic [1:0] seen;
        fork
            begin repeat (adly) @(negedge clk); awaddr = a; awvalid = 1;
                  do @(posedge clk); while (!awready); @(negedge clk); awvalid = 0; end
            begin repeat (wdly) @(negedge clk); wdata = d; wstrb = s; wvalid = 1;
                  do @(posedge clk); while (!wready);  @(negedge clk); wvalid = 0; end
            begin
                bready = 0;
                do @(posedge clk); while (!bvalid);
                seen = bresp;
                repeat (bdly + 1) @(negedge clk);
                if (!bvalid || bresp !== seen) begin errors++; $display("[FAIL] B channel not stable while stalled"); end
                resp = bresp; bready = 1;
                @(posedge clk); @(negedge clk); bready = 0;
            end
        join
        n_wr++;
    endtask

    task automatic do_read(input [31:0] a, input int ardly, input int rdly,
                           output logic [31:0] data, output logic [1:0] resp);
        logic [31:0] seen_d; logic [1:0] seen_r;
        fork
            begin repeat (ardly) @(negedge clk); araddr = a; arvalid = 1;
                  do @(posedge clk); while (!arready); @(negedge clk); arvalid = 0; end
            begin
                rready = 0;
                do @(posedge clk); while (!rvalid);
                seen_d = rdata; seen_r = rresp;
                repeat (rdly + 1) @(negedge clk);
                if (!rvalid || rdata !== seen_d || rresp !== seen_r) begin errors++; $display("[FAIL] R channel not stable while stalled"); end
                data = rdata; resp = rresp; rready = 1;
                @(posedge clk); @(negedge clk); rready = 0;
            end
        join
        n_rd++;
    endtask

    task automatic wr_check(input [31:0] a, input [31:0] d, input [3:0] s, input int adly, input int wdly, input int bdly);
        logic [1:0] r; logic exp_err;
        exp_err = (a[7:0] >= 8'h40);
        do_write(a, d, s, adly, wdly, bdly, r);
        if (r !== (exp_err ? 2'b10 : 2'b00)) begin errors++; $display("[FAIL] write %h bresp=%b", a, r); end
        if (!exp_err) for (int i = 0; i < 4; i++) if (s[i]) exp_regs[a[5:2]][i*8 +: 8] = d[i*8 +: 8];
    endtask

    task automatic rd_check(input [31:0] a, input int ardly, input int rdly);
        logic [31:0] d; logic [1:0] r; logic exp_err;
        exp_err = (a[7:0] >= 8'h40);
        do_read(a, ardly, rdly, d, r);
        if (r !== (exp_err ? 2'b10 : 2'b00)) begin errors++; $display("[FAIL] read %h rresp=%b", a, r); end
        if (!exp_err && d !== exp_regs[a[5:2]]) begin errors++; $display("[FAIL] read %h = %h expected %h", a, d, exp_regs[a[5:2]]); end
    endtask

    initial begin
        $dumpfile("dump.vcd"); $dumpvars(0, tb_regif);
        awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
        awaddr = 0; wdata = 0; wstrb = 0; araddr = 0;
        for (int i = 0; i < 16; i++) begin regs[i] = 32'h0; exp_regs[i] = 32'h0; end
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

        // directed: write then read back
        wr_check(32'h04, 32'hDEADBEEF, 4'hF, 0, 0, 0);
        rd_check(32'h04, 0, 0);
        $display("[TEST] write / read back                         errors=%0d", errors);

        // channel ordering: AW first, W first, same cycle
        wr_check(32'h08, 32'h11112222, 4'hF, 0, 6, 0);
        wr_check(32'h0C, 32'h33334444, 4'hF, 6, 0, 0);
        wr_check(32'h10, 32'h55556666, 4'hF, 2, 2, 0);
        for (int a = 8; a <= 16; a += 4) rd_check(a, 0, 0);
        $display("[TEST] AW-first / W-first / simultaneous         errors=%0d", errors);

        // byte strobes
        wr_check(32'h14, 32'hFFFFFFFF, 4'hF, 0, 0, 0);
        wr_check(32'h14, 32'h00AA00BB, 4'b0101, 0, 0, 0);
        wr_check(32'h14, 32'hCC000000, 4'b1000, 0, 0, 0);
        rd_check(32'h14, 0, 0);
        $display("[TEST] byte strobes                              errors=%0d", errors);

        // errors: state must not change
        wr_check(32'h44, 32'h12345678, 4'hF, 0, 0, 0);
        rd_check(32'h44, 0, 0);
        rd_check(32'h04, 0, 0);
        $display("[TEST] SLVERR on out-of-range, state unchanged   errors=%0d", errors);

        // back-pressure on B and R
        wr_check(32'h18, 32'hA5A5A5A5, 4'hF, 0, 0, 7);
        rd_check(32'h18, 0, 9);
        $display("[TEST] stalled B / R channels                    errors=%0d", errors);

        // random
        for (int k = 0; k < 400; k++) begin
            logic [31:0] a;
            a = {24'b0, 2'($urandom_range(0, 3)) == 2'd3 ? 8'($urandom_range(8'h40, 8'hFC)) : 8'($urandom_range(0, 15) * 4)};
            if ($urandom_range(0, 1)) wr_check(a, $urandom, 4'($urandom_range(0, 15)), $urandom_range(0, 3), $urandom_range(0, 3), $urandom_range(0, 3));
            else                      rd_check(a, $urandom_range(0, 3), $urandom_range(0, 3));
        end
        $display("[TEST] 400 random transactions                   errors=%0d", errors);

        repeat (5) @(negedge clk);
        // wr_en / rd_en : exactly one cycle per transaction
        if (wr_en_cycles != n_wr) begin errors++; $display("[FAIL] wr_en cycles=%0d writes=%0d", wr_en_cycles, n_wr); end
        if (rd_en_cycles != n_rd) begin errors++; $display("[FAIL] rd_en cycles=%0d reads=%0d", rd_en_cycles, n_rd); end
        $display("[INFO] %0d writes, %0d reads, wr_en cycles=%0d rd_en cycles=%0d", n_wr, n_rd, wr_en_cycles, rd_en_cycles);

        if (errors == 0) $display("\n[TB PASS] tb_regif\n");
        else             $display("\n[TB FAIL] tb_regif: %0d errors\n", errors);
        $finish;
    end

    initial begin #20_000_000; $display("[TB FAIL] tb_regif: timeout"); $finish; end
endmodule
