`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_fabric : aegis_fabric (2 masters -> 6 slaves + DECERR slave), full SoC address map
//   slave models answer reads with {8'hA0+ID, addr[23:0]}; slave 5 answers SLVERR (2'b10)
//   1. every slave window, from both masters (decode + data/resp routing)
//   2. window edges, holes and the TCM region -> DECERR (2'b11, 0xDEADBEEF), no slave touched
//   3. writes: address / data / strobe reach the right slave, response routed back
//   4. both masters hitting the SAME slave, and DIFFERENT slaves, at the same time
//   5. 2 x 400 random mixed transactions with random handshake delays, counters cross-checked
//-----------------------------------------------------------------------------
module tb_axil_slave #(
    parameter int ID  = 0,
    parameter int LAT = 1,
    parameter bit ERR = 1'b0
) (
    input  logic        clk, rst_n,
    input  logic [31:0] awaddr, input logic awvalid, output logic awready,
    input  logic [31:0] wdata,  input logic [3:0] wstrb, input logic wvalid, output logic wready,
    output logic [1:0]  bresp,  output logic bvalid, input logic bready,
    input  logic [31:0] araddr, input logic arvalid, output logic arready,
    output logic [31:0] rdata,  output logic [1:0] rresp, output logic rvalid, input logic rready,
    output int          wr_cnt, output int rd_cnt,
    output logic [31:0] last_waddr, output logic [31:0] last_wdata, output logic [3:0] last_wstrb
);
    logic aw_got, w_got, bpend, rpend;
    logic [31:0] aw_q, w_q, ar_q;
    logic [3:0]  ws_q;
    int bcnt, rcnt;

    assign awready = !aw_got && !bvalid && !bpend;
    assign wready  = !w_got  && !bvalid && !bpend;
    assign bresp   = ERR ? 2'b10 : 2'b00;
    assign arready = !rpend && !rvalid;
    assign rdata   = {8'(8'hA0 + ID), ar_q[23:0]};
    assign rresp   = ERR ? 2'b10 : 2'b00;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_got <= 0; w_got <= 0; bpend <= 0; bvalid <= 0; rpend <= 0; rvalid <= 0;
            aw_q <= 0; w_q <= 0; ar_q <= 0; ws_q <= 0; bcnt <= 0; rcnt <= 0;
            wr_cnt <= 0; rd_cnt <= 0; last_waddr <= 0; last_wdata <= 0; last_wstrb <= 0;
        end else begin
            if (awvalid && awready) begin aw_got <= 1; aw_q <= awaddr; end
            if (wvalid  && wready)  begin w_got  <= 1; w_q  <= wdata; ws_q <= wstrb; end
            if (aw_got && w_got && !bpend && !bvalid) begin
                bpend <= 1; bcnt <= LAT; aw_got <= 0; w_got <= 0;
                wr_cnt <= wr_cnt + 1; last_waddr <= aw_q; last_wdata <= w_q; last_wstrb <= ws_q;
            end
            if (bpend) begin
                if (bcnt == 0) begin bvalid <= 1; bpend <= 0; end else bcnt <= bcnt - 1;
            end
            if (bvalid && bready) bvalid <= 0;

            if (arvalid && arready) begin rpend <= 1; rcnt <= LAT; ar_q <= araddr; rd_cnt <= rd_cnt + 1; end
            if (rpend) begin
                if (rcnt == 0) begin rvalid <= 1; rpend <= 0; end else rcnt <= rcnt - 1;
            end
            if (rvalid && rready) rvalid <= 0;
        end
    end
endmodule

module tb_fabric;
    localparam int NM = 2, NS = 6;
    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    // masters
    logic [NM-1:0][31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
    logic [NM-1:0][3:0]  m_wstrb;
    logic [NM-1:0]       m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
    logic [NM-1:0]       m_arvalid, m_arready, m_rvalid, m_rready;
    logic [NM-1:0][1:0]  m_bresp, m_rresp;
    // slaves
    logic [NS-1:0][31:0] s_awaddr, s_wdata, s_araddr, s_rdata;
    logic [NS-1:0][3:0]  s_wstrb;
    logic [NS-1:0]       s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
    logic [NS-1:0]       s_arvalid, s_arready, s_rvalid, s_rready;
    logic [NS-1:0][1:0]  s_bresp, s_rresp;

    aegis_fabric #(.NM(NM), .NS(NS)) dut (
        .clk(clk), .rst_n(rst_n),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata), .m_rresp(m_rresp), .m_rvalid(m_rvalid), .m_rready(m_rready),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready)
    );

    int          s_wr_cnt [NS];
    int          s_rd_cnt [NS];
    logic [31:0] s_last_waddr [NS];
    logic [31:0] s_last_wdata [NS];
    logic [3:0]  s_last_wstrb [NS];

    for (genvar j = 0; j < NS; j++) begin : g_slv
        tb_axil_slave #(.ID(j), .LAT(j % 3), .ERR(j == 5)) u_s (
            .clk(clk), .rst_n(rst_n),
            .awaddr(s_awaddr[j]), .awvalid(s_awvalid[j]), .awready(s_awready[j]),
            .wdata(s_wdata[j]), .wstrb(s_wstrb[j]), .wvalid(s_wvalid[j]), .wready(s_wready[j]),
            .bresp(s_bresp[j]), .bvalid(s_bvalid[j]), .bready(s_bready[j]),
            .araddr(s_araddr[j]), .arvalid(s_arvalid[j]), .arready(s_arready[j]),
            .rdata(s_rdata[j]), .rresp(s_rresp[j]), .rvalid(s_rvalid[j]), .rready(s_rready[j]),
            .wr_cnt(s_wr_cnt[j]), .rd_cnt(s_rd_cnt[j]),
            .last_waddr(s_last_waddr[j]), .last_wdata(s_last_wdata[j]), .last_wstrb(s_last_wstrb[j])
        );
    end

    // ---- independent address model (same map as the SoC) ---------------------------
    logic [31:0] BASE_T [NS] = '{32'h0000_0000, 32'h2000_0000, 32'h4000_0000, 32'h4000_1000, 32'h4001_0000, 32'h4002_0000};
    logic [31:0] SIZE_T [NS] = '{32'h4000, 32'h4000, 32'h1000, 32'h1000, 32'h2000, 32'h1000};

    function automatic int tdec(input logic [31:0] a);
        for (int j = 0; j < NS; j++)
            if (a >= BASE_T[j] && a < BASE_T[j] + SIZE_T[j]) return j;
        return -1;
    endfunction

    int errors = 0;
    int exp_wr [NS];
    int exp_rd [NS];

    // ---- master BFM (drive at negedge, handshakes sampled at posedge) -----------------
    task automatic mwrite(input int m, input logic [31:0] a, input logic [31:0] d, input logic [3:0] s,
                          input int adly, input int wdly, input int bdly, output logic [1:0] resp);
        logic [1:0] seen;
        fork
            begin repeat (adly) @(negedge clk); m_awaddr[m] = a; m_awvalid[m] = 1;
                  do @(posedge clk); while (!m_awready[m]); @(negedge clk); m_awvalid[m] = 0; end
            begin repeat (wdly) @(negedge clk); m_wdata[m] = d; m_wstrb[m] = s; m_wvalid[m] = 1;
                  do @(posedge clk); while (!m_wready[m]);  @(negedge clk); m_wvalid[m] = 0; end
            begin
                m_bready[m] = 0;
                do @(posedge clk); while (!m_bvalid[m]);
                seen = m_bresp[m];
                repeat (bdly + 1) @(negedge clk);
                if (!m_bvalid[m] || m_bresp[m] !== seen) begin errors++; $display("[FAIL] m%0d B channel unstable", m); end
                resp = m_bresp[m]; m_bready[m] = 1;
                @(posedge clk); @(negedge clk); m_bready[m] = 0;
            end
        join
    endtask

    task automatic mread(input int m, input logic [31:0] a, input int ardly, input int rdly,
                         output logic [31:0] data, output logic [1:0] resp);
        logic [31:0] seen_d; logic [1:0] seen_r;
        fork
            begin repeat (ardly) @(negedge clk); m_araddr[m] = a; m_arvalid[m] = 1;
                  do @(posedge clk); while (!m_arready[m]); @(negedge clk); m_arvalid[m] = 0; end
            begin
                m_rready[m] = 0;
                do @(posedge clk); while (!m_rvalid[m]);
                seen_d = m_rdata[m]; seen_r = m_rresp[m];
                repeat (rdly + 1) @(negedge clk);
                if (!m_rvalid[m] || m_rdata[m] !== seen_d || m_rresp[m] !== seen_r) begin errors++; $display("[FAIL] m%0d R channel unstable", m); end
                data = m_rdata[m]; resp = m_rresp[m]; m_rready[m] = 1;
                @(posedge clk); @(negedge clk); m_rready[m] = 0;
            end
        join
    endtask

    // ---- checked accesses ---------------------------------------------------------------
    task automatic rd_check(input int m, input logic [31:0] a, input int ardly, input int rdly);
        logic [31:0] d, ed; logic [1:0] r, er; int sl;
        sl = tdec(a);
        if (sl < 0) begin ed = 32'hDEAD_BEEF; er = 2'b11; end
        else begin ed = {8'(8'hA0 + sl), a[23:0]}; er = (sl == 5) ? 2'b10 : 2'b00; exp_rd[sl]++; end
        mread(m, a, ardly, rdly, d, r);
        if (d !== ed || r !== er) begin errors++; $display("[FAIL] m%0d read %h: got %h/%b exp %h/%b", m, a, d, r, ed, er); end
    endtask

    task automatic wr_check(input int m, input logic [31:0] a, input logic [31:0] dat, input logic [3:0] st,
                            input int adly, input int wdly, input int bdly, input bit check_last);
        logic [1:0] r, er; int sl;
        sl = tdec(a);
        er = (sl < 0) ? 2'b11 : ((sl == 5) ? 2'b10 : 2'b00);
        if (sl >= 0) exp_wr[sl]++;
        mwrite(m, a, dat, st, adly, wdly, bdly, r);
        if (r !== er) begin errors++; $display("[FAIL] m%0d write %h: bresp=%b exp %b", m, a, r, er); end
        if (check_last && sl >= 0)
            if (s_last_waddr[sl] !== a || s_last_wdata[sl] !== dat || s_last_wstrb[sl] !== st) begin
                errors++; $display("[FAIL] m%0d write %h: slave %0d saw %h/%h/%b", m, a, sl, s_last_waddr[sl], s_last_wdata[sl], s_last_wstrb[sl]);
            end
    endtask

    function automatic logic [31:0] rand_addr();
        int sl, k;
        k  = $urandom_range(0, 9);
        sl = $urandom_range(0, NS - 1);
        if (k == 0)      return 32'($urandom) & 32'hFFFF_FFFC;                                  // anywhere (mostly holes)
        else if (k == 1) return 32'h1000_0000 + 32'($urandom_range(0, 'h3FFF) & 'h3FFC);        // TCM region (not on fabric)
        else             return BASE_T[sl] + (32'($urandom_range(0, SIZE_T[sl] - 1)) & 32'hFFFF_FFFC);
    endfunction

    task automatic stress(input int m, input int n);
        for (int k = 0; k < n; k++) begin
            logic [31:0] a;
            a = rand_addr();
            if ($urandom_range(0, 1)) wr_check(m, a, $urandom, 4'($urandom_range(0, 15)),
                                               $urandom_range(0, 3), $urandom_range(0, 3), $urandom_range(0, 3), 1'b0);
            else                      rd_check(m, a, $urandom_range(0, 3), $urandom_range(0, 3));
        end
    endtask

    initial begin
        $dumpfile("dump.vcd"); $dumpvars(0, tb_fabric);
        m_awvalid = '0; m_wvalid = '0; m_bready = '0; m_arvalid = '0; m_rready = '0;
        m_awaddr = '0; m_wdata = '0; m_wstrb = '0; m_araddr = '0;
        for (int j = 0; j < NS; j++) begin exp_wr[j] = 0; exp_rd[j] = 0; end
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (2) @(negedge clk);

        // 1) every window from both masters
        for (int j = 0; j < NS; j++)
            for (int m = 0; m < NM; m++)
                rd_check(m, BASE_T[j] + 32'h10 * (m + 1), 0, 0);
        $display("[TEST] decode: 6 windows x 2 masters             errors=%0d", errors);

        // 2) window edges, holes, TCM region
        for (int j = 0; j < NS; j++) begin
            rd_check(0, BASE_T[j] + SIZE_T[j] - 4, 0, 0);      // last word inside
            rd_check(1, BASE_T[j], 0, 0);                      // first word inside
        end
        rd_check(0, 32'h0000_4000, 0, 0);   // after ROM
        rd_check(1, 32'h1000_0000, 1, 1);   // TCM (accelerator-private)
        rd_check(0, 32'h2000_4000, 0, 0);   // after SRAM
        rd_check(1, 32'h4000_2000, 0, 0);   // between QSPI and GEMM
        rd_check(0, 32'h4001_2000, 0, 0);   // after GEMM
        rd_check(1, 32'h4002_1000, 0, 0);   // after SYS
        rd_check(0, 32'hFFFF_FFFC, 0, 0);
        wr_check(0, 32'h1000_0000, 32'h1234_5678, 4'hF, 0, 0, 0, 1'b0);   // write to a hole
        wr_check(1, 32'h5000_0000, 32'h8765_4321, 4'hF, 1, 2, 0, 1'b0);
        $display("[TEST] edges, holes, TCM region -> DECERR        errors=%0d", errors);

        // 3) writes with address / data / strobe check
        for (int j = 0; j < NS; j++)
            for (int m = 0; m < NM; m++)
                wr_check(m, BASE_T[j] + 32'h20 + 32'(4 * m), 32'hC0DE_0000 + 32'(j * 16 + m), 4'(4'h5 + j + m), m, 1 - m, j % 3, 1'b1);
        $display("[TEST] writes: addr/data/strobe + response       errors=%0d", errors);

        // 4) both masters at once: same slave, then different slaves
        for (int k = 0; k < 40; k++)
            fork
                rd_check(0, BASE_T[1] + 32'(4 * k), k % 3, k % 2);
                rd_check(1, BASE_T[1] + 32'h100 + 32'(4 * k), (k + 1) % 3, (k + 1) % 2);
            join
        for (int k = 0; k < 30; k++)
            fork
                rd_check(0, BASE_T[k % NS] + 32'h40, k % 2, 0);
                wr_check(1, BASE_T[(k + 3) % NS] + 32'h80, $urandom, 4'hF, 0, k % 2, 0, 1'b0);
            join
        $display("[TEST] simultaneous masters                      errors=%0d", errors);

        // 5) random stress, both masters in parallel
        fork
            stress(0, 400);
            stress(1, 400);
        join
        $display("[TEST] 2 x 400 random mixed transactions         errors=%0d", errors);

        repeat (10) @(negedge clk);
        for (int j = 0; j < NS; j++) begin
            if (s_wr_cnt[j] != exp_wr[j]) begin errors++; $display("[FAIL] slave %0d writes=%0d expected %0d", j, s_wr_cnt[j], exp_wr[j]); end
            if (s_rd_cnt[j] != exp_rd[j]) begin errors++; $display("[FAIL] slave %0d reads=%0d expected %0d", j, s_rd_cnt[j], exp_rd[j]); end
        end
        $display("[INFO] per-slave transactions (wr/rd): %0d/%0d %0d/%0d %0d/%0d %0d/%0d %0d/%0d %0d/%0d",
                 s_wr_cnt[0], s_rd_cnt[0], s_wr_cnt[1], s_rd_cnt[1], s_wr_cnt[2], s_rd_cnt[2],
                 s_wr_cnt[3], s_rd_cnt[3], s_wr_cnt[4], s_rd_cnt[4], s_wr_cnt[5], s_rd_cnt[5]);

        if (errors == 0) $display("\n[TB PASS] tb_fabric\n");
        else             $display("\n[TB FAIL] tb_fabric: %0d errors\n", errors);
        $finish;
    end

    initial begin #50_000_000; $display("[TB FAIL] tb_fabric: timeout (deadlock?)"); $finish; end
endmodule
