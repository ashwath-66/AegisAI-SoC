`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_gemm_subsys : the whole accelerator data path, driven like firmware would
//
//   encrypted tiles in QSPI flash -> DMA (SPECK decrypt) -> AXI -> TCM bank A/B
//   -> gemm_controller -> 16x16 systolic array -> result buffer -> CPU read-back
//
//   Every result element of every tile is compared with a software C = A x W.
//   Ping-pong prefetch is driven by the controller (dma_auto_prefetch), the "CPU"
//   only starts the first tile, reads results and releases the result buffer.
//-----------------------------------------------------------------------------
module tb_gemm_subsys;
    localparam logic [31:0] TCM_BASE = 32'h1000_0000;
    localparam int N = 16;

    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    // ---- two AXI4-Lite master channels: 0 = DMA CSRs, 1 = GEMM CSRs ----
    logic [31:0] k_awaddr [2], k_wdata [2], k_araddr [2], k_rdata [2];
    logic        k_awvalid [2], k_awready [2], k_wvalid [2], k_wready [2], k_bvalid [2], k_bready [2];
    logic        k_arvalid [2], k_arready [2], k_rvalid [2], k_rready [2];
    logic [1:0]  k_bresp [2], k_rresp [2];

    // ---- stream / spi / dma master / tcm / array ----
    logic st_valid, st_ready, spi_start, spi_busy; logic [127:0] st_data; logic [23:0] spi_addr; logic [24:0] spi_len;
    logic [31:0] awaddr; logic [7:0] awlen; logic [2:0] awsize; logic [1:0] awburst; logic awvalid, awready, wlast, wvalid, wready, bvalid, bready;
    logic [127:0] wdata; logic [15:0] wstrb; logic [1:0] bresp;
    logic fill_done, fill_bank, dma_busy, dma_irq, auto_pf, gem_irq;
    logic g_en, g_bank; logic [8:0] g_word; logic [127:0] g_rdata;
    logic w_load_en; logic [3:0] w_load_row; logic [127:0] w_load_data;
    logic a_valid; logic [127:0] a_row; logic c_valid; logic [N*20-1:0] c_row;
    wire sck, cs_n; wire [3:0] io;

    apb_spi_master u_spi (
        .pclk(clk), .presetn(rst_n),
        .psel(1'b0), .penable(1'b0), .pwrite(1'b0), .paddr(32'b0), .pwdata(32'b0),
        .prdata(), .pready(), .pslverr(), .irq(),
        .qspi_sck(sck), .qspi_cs_n(cs_n), .qspi_io(io),
        .stream_valid_out(st_valid), .stream_ready_in(st_ready), .stream_data_out(st_data),
        .hw_start(spi_start), .hw_addr(spi_addr), .hw_len(spi_len), .spi_busy(spi_busy), .spi_done()
    );
    qspi_flash_model u_flash (.sck(sck), .cs_n(cs_n), .io(io));

    axi_dma u_dma (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(k_awaddr[0]), .s_axil_awvalid(k_awvalid[0]), .s_axil_awready(k_awready[0]),
        .s_axil_wdata(k_wdata[0]), .s_axil_wstrb(4'hF), .s_axil_wvalid(k_wvalid[0]), .s_axil_wready(k_wready[0]),
        .s_axil_bresp(k_bresp[0]), .s_axil_bvalid(k_bvalid[0]), .s_axil_bready(k_bready[0]),
        .s_axil_araddr(k_araddr[0]), .s_axil_arvalid(k_arvalid[0]), .s_axil_arready(k_arready[0]),
        .s_axil_rdata(k_rdata[0]), .s_axil_rresp(k_rresp[0]), .s_axil_rvalid(k_rvalid[0]), .s_axil_rready(k_rready[0]),
        .s_valid(st_valid), .s_ready(st_ready), .s_data(st_data),
        .spi_start(spi_start), .spi_addr(spi_addr), .spi_len(spi_len), .spi_busy(spi_busy),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .dma_auto_prefetch(auto_pf), .fill_done(fill_done), .fill_bank(fill_bank), .busy(dma_busy), .irq(dma_irq)
    );

    axi_tcm #(.BASE(TCM_BASE)) u_tcm (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awlen(awlen), .s_axi_awsize(awsize), .s_axi_awburst(awburst),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(32'b0), .s_axi_arlen(8'b0), .s_axi_arsize(3'd4), .s_axi_arburst(2'b01),
        .s_axi_arvalid(1'b0), .s_axi_arready(), .s_axi_rdata(), .s_axi_rresp(), .s_axi_rlast(),
        .s_axi_rvalid(), .s_axi_rready(1'b1),
        .g_en(g_en), .g_bank(g_bank), .g_word(g_word), .g_rdata(g_rdata)
    );

    gemm_controller u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(k_awaddr[1]), .s_axil_awvalid(k_awvalid[1]), .s_axil_awready(k_awready[1]),
        .s_axil_wdata(k_wdata[1]), .s_axil_wstrb(4'hF), .s_axil_wvalid(k_wvalid[1]), .s_axil_wready(k_wready[1]),
        .s_axil_bresp(k_bresp[1]), .s_axil_bvalid(k_bvalid[1]), .s_axil_bready(k_bready[1]),
        .s_axil_araddr(k_araddr[1]), .s_axil_arvalid(k_arvalid[1]), .s_axil_arready(k_arready[1]),
        .s_axil_rdata(k_rdata[1]), .s_axil_rresp(k_rresp[1]), .s_axil_rvalid(k_rvalid[1]), .s_axil_rready(k_rready[1]),
        .fill_done(fill_done), .fill_bank(fill_bank), .dma_auto_prefetch(auto_pf),
        .g_en(g_en), .g_bank(g_bank), .g_word(g_word), .g_rdata(g_rdata),
        .w_load_en(w_load_en), .w_load_row(w_load_row), .w_load_data(w_load_data),
        .a_valid(a_valid), .a_row(a_row), .c_valid(c_valid), .c_row(c_row), .irq(gem_irq)
    );

    systolic_array u_array (
        .clk(clk), .rst_n(rst_n),
        .w_load_en(w_load_en), .w_load_row(w_load_row), .w_load_data(w_load_data),
        .a_valid(a_valid), .a_row(a_row), .c_valid(c_valid), .c_row(c_row)
    );

    // ---------------- AXI-Lite master tasks ---------------------------------------
    task automatic axil_write(input int ch, input logic [31:0] a, input logic [31:0] d);
        bit ad, wd;
        @(posedge clk); #1; k_awvalid[ch] = 1; k_awaddr[ch] = a; k_wvalid[ch] = 1; k_wdata[ch] = d; k_bready[ch] = 1;
        ad = 0; wd = 0;
        do begin
            @(posedge clk);
            if (k_awvalid[ch] && k_awready[ch]) ad = 1;
            if (k_wvalid[ch]  && k_wready[ch])  wd = 1;
            #1;
            if (ad) k_awvalid[ch] = 0;
            if (wd) k_wvalid[ch]  = 0;
        end while (!(ad && wd));
        do @(posedge clk); while (!k_bvalid[ch]);
        #1; k_bready[ch] = 0;
    endtask

    task automatic axil_read(input int ch, input logic [31:0] a, output logic [31:0] d);
        bit got;
        @(posedge clk); #1; k_arvalid[ch] = 1; k_araddr[ch] = a; k_rready[ch] = 0; got = 0;
        do begin
            @(posedge clk);
            if (k_arvalid[ch] && k_arready[ch]) got = 1;
            #1; if (got) k_arvalid[ch] = 0;
        end while (!got);
        k_rready[ch] = 1;
        do @(posedge clk); while (!k_rvalid[ch]);
        d = k_rdata[ch];
        #1; k_rready[ch] = 0;
    endtask

    // ---------------- SPECK software model ----------------------------------------
    function automatic logic [31:0] ror(input logic [31:0] v, input int n); return (v >> n) | (v << (32 - n)); endfunction
    function automatic logic [31:0] rol(input logic [31:0] v, input int n); return (v << n) | (v >> (32 - n)); endfunction
    logic [31:0] sw_rk [27];
    task automatic sw_keysched(input logic [127:0] key);
        logic [31:0] k, l [29];
        k = key[31:0]; l[0] = key[63:32]; l[1] = key[95:64]; l[2] = key[127:96];
        for (int i = 0; i < 27; i++) begin
            sw_rk[i] = k;
            if (i < 26) begin l[i+3] = (k + ror(l[i], 8)) ^ 32'(i); k = rol(k, 3) ^ l[i+3]; end
        end
    endtask
    function automatic logic [63:0] sw_encrypt(input logic [63:0] pt);
        logic [31:0] x, y; x = pt[63:32]; y = pt[31:0];
        for (int i = 0; i < 27; i++) begin x = (ror(x, 8) + y) ^ sw_rk[i]; y = rol(y, 3) ^ x; end
        return {x, y};
    endfunction

    // ---------------- scenario machinery -----------------------------------------
    localparam int MAXT = 6;
    int errors = 0;
    int signed exp_c [MAXT][64][N];
    byte tile [8192];
    logic [127:0] key = 128'h1b1a1918_13121110_0b0a0908_03020100;

    function automatic int signed rnd8(input int zero_pct);
        int r;
        if ($urandom_range(0, 99) < zero_pct) return 0;
        r = $urandom_range(0, 255);
        return (r > 127) ? r - 256 : r;
    endfunction

    // build one tile (W then A rows), compute expected C, encrypt into flash
    task automatic make_tile(input int k, input int M, input int zero_pct, input int faddr);
        int signed W [N][N];
        int signed A [64][N];
        int len;
        len = 256 + 16*M;
        for (int r = 0; r < N; r++)
            for (int c = 0; c < N; c++) begin W[r][c] = rnd8(zero_pct); tile[r*16 + c] = W[r][c][7:0]; end
        for (int m = 0; m < M; m++)
            for (int j = 0; j < N; j++) begin A[m][j] = rnd8(zero_pct); tile[256 + m*16 + j] = A[m][j][7:0]; end
        for (int m = 0; m < M; m++)
            for (int c = 0; c < N; c++) begin
                int acc = 0;
                for (int j = 0; j < N; j++) acc += A[m][j] * W[j][c];
                exp_c[k][m][c] = acc;
            end
        for (int b = 0; b < len/8; b++) begin
            logic [63:0] pt, ct;
            for (int j = 0; j < 8; j++) pt[j*8 +: 8] = tile[b*8 + j];
            ct = sw_encrypt(pt);
            for (int j = 0; j < 8; j++) u_flash.mem[faddr + b*8 + j] = ct[j*8 +: 8];
        end
    endtask

    int fills = 0;
    always @(posedge clk) if (fill_done) fills++;

    task automatic do_reset();
        rst_n = 0;
        for (int i = 0; i < 2; i++) begin
            k_awvalid[i] = 0; k_wvalid[i] = 0; k_bready[i] = 0; k_arvalid[i] = 0; k_rready[i] = 0;
            k_awaddr[i] = 0; k_wdata[i] = 0; k_araddr[i] = 0;
        end
        repeat (5) @(posedge clk); #1; rst_n = 1; repeat (3) @(posedge clk);
    endtask

    task automatic run_scenario(input string name, input int M, input int ntiles, input int zero_pct,
                                input bit early, input int ack_delay);
        int len, bad, t_start, t_end;
        logic [31:0] st, r;
        int tiles_ok;
        len = 256 + 16*M;
        do_reset();
        fills = 0;
        sw_keysched(key);
        for (int k = 0; k < ntiles; k++) make_tile(k, M, zero_pct, 32'h1000 + k*len);

        // CPU firmware: key, DMA, GEMM
        axil_write(0, 32'h20, key[31:0]);  axil_write(0, 32'h24, key[63:32]);
        axil_write(0, 32'h28, key[95:64]); axil_write(0, 32'h2C, key[127:96]);
        axil_write(0, 32'h30, 1);
        st = 0; while (!st[3]) axil_read(0, 32'h04, st);

        axil_write(1, 32'h08, M);
        axil_write(1, 32'h00, early ? 32'hD : 32'h9);          // ENABLE | PF_EN | (PREFETCH_EARLY)
        axil_write(0, 32'h08, 32'h1000);                       // flash address of tile 0
        axil_write(0, 32'h0C, len);
        axil_write(0, 32'h10, TCM_BASE);                       // bank A
        axil_write(0, 32'h14, TCM_BASE + 32'h2000);            // bank B
        axil_write(0, 32'h18, len);                            // stride = tile length
        axil_write(0, 32'h1C, ntiles - 1);                     // auto tiles after the first
        t_start = $time;
        axil_write(0, 32'h00, 32'h7);                          // START | AUTO_EN | DECRYPT_EN

        bad = 0;
        for (int k = 0; k < ntiles; k++) begin
            int t = 0;
            st = 0;
            while (!st[1] && t < 200000) begin axil_read(1, 32'h04, st); t++; end
            if (!st[1]) begin $display("[FAIL] %s: tile %0d never finished", name, k); bad++; break; end
            for (int m = 0; m < M; m++)
                for (int c = 0; c < N; c++) begin
                    axil_read(1, 32'h1000 + 4*(m*16 + c), r);
                    if ($signed(r) !== exp_c[k][m][c]) begin
                        if (bad < 5) $display("   tile %0d C[%0d][%0d]: got %0d exp %0d", k, m, c, $signed(r), exp_c[k][m][c]);
                        bad++;
                    end
                end
            axil_write(1, 32'h04, 32'h2);                      // clear TILE_DONE
            repeat (ack_delay) @(posedge clk);
            axil_write(1, 32'h10, 1);                          // release result buffer
        end
        t_end = $time;
        axil_read(1, 32'h04, st);
        axil_read(1, 32'h0C, r);
        if (st[3] || st[4]) begin $display("[FAIL] %s: ERR/OVERRUN set (STATUS=%h)", name, st); bad++; end
        if (r != ntiles)    begin $display("[FAIL] %s: tiles_done=%0d", name, r); bad++; end
        if (fills != ntiles) begin $display("[FAIL] %s: %0d DMA fills, expected %0d", name, fills, ntiles); bad++; end
        $display("[TEST] %-44s %0d tiles x %0d rows  %s  (%0d cycles)", name, ntiles, M, bad ? "FAIL" : "ok", (t_end - t_start)/10);
        errors += bad;
    endtask

    initial begin
        do_reset();
        run_scenario("dense, 4 tiles, 16 rows, drain prefetch", 16, 4, 0, 0, 0);
        run_scenario("sparse 50%, 4 tiles, 40 rows",             40, 4, 50, 0, 0);
        run_scenario("early prefetch, 5 tiles, 32 rows",         32, 5, 10, 1, 0);
        run_scenario("slow CPU ack (result-buffer backpressure)", 24, 4, 20, 0, 3000);
        run_scenario("max rows 64, 2 tiles",                     64, 2, 0, 0, 0);
        run_scenario("single tile, 1 row",                        1, 1, 0, 0, 0);

        // invalid ROWS -> ERR, tile dropped without hanging the array
        begin
            logic [31:0] st;
            do_reset();
            axil_write(1, 32'h08, 0);
            axil_write(1, 32'h00, 32'h1);
            force u_ctrl.bank_ready = 2'b01; #1; release u_ctrl.bank_ready;   // pretend bank A is filled
            repeat (20) @(posedge clk);
            axil_read(1, 32'h04, st);
            if (!st[3] || st[0]) begin $display("[FAIL] invalid ROWS not flagged (STATUS=%h)", st); errors++; end
            else $display("[TEST] ROWS=0 flagged with ERR, controller stays idle     ok");
        end

        if (errors == 0) $display("\n[TB PASS] tb_gemm_subsys: flash -> decrypt -> TCM -> GEMM all match\n");
        else             $display("\n[TB FAIL] tb_gemm_subsys: %0d errors\n", errors);
        $finish;
    end
    initial begin #400_000_000; $display("[TB FAIL] global timeout"); $finish; end
endmodule
