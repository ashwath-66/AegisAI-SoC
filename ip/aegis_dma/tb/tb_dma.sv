`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_dma : flash(model) -> apb_spi_master -> axi_dma(+SPECK) -> AXI memory model
//   encrypted tiles are placed in the flash, the DMA decrypts them into "SRAM"
//   (axi_mem_model) and every byte is compared with the original plaintext.
//-----------------------------------------------------------------------------
module tb_dma;

    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    // AXI-Lite
    logic [31:0] s_awaddr, s_wdata, s_araddr, s_rdata;
    logic        s_awvalid, s_awready, s_wvalid, s_wready, s_bvalid, s_bready;
    logic [3:0]  s_wstrb;
    logic [1:0]  s_bresp, s_rresp;
    logic        s_arvalid, s_arready, s_rvalid, s_rready;
    // stream / spi
    logic        st_valid, st_ready, spi_start, spi_busy;
    logic [127:0] st_data;
    logic [23:0] spi_addr;
    logic [24:0] spi_len;
    // AXI master
    logic [31:0] awaddr; logic [7:0] awlen; logic [2:0] awsize; logic [1:0] awburst;
    logic        awvalid, awready, wlast, wvalid, wready, bvalid, bready;
    logic [127:0] wdata; logic [15:0] wstrb; logic [1:0] bresp;
    // sideband
    logic        auto_pf, fill_done, fill_bank, busy, irq;
    // qspi pins
    wire sck, cs_n; wire [3:0] io;

    apb_spi_master u_spi (
        .pclk(clk), .presetn(rst_n),
        .psel(1'b0), .penable(1'b0), .pwrite(1'b0), .paddr(32'b0), .pwdata(32'b0),
        .prdata(), .pready(), .pslverr(), .irq(),
        .qspi_sck(sck), .qspi_cs_n(cs_n), .qspi_io(io),
        .stream_valid_out(st_valid), .stream_ready_in(st_ready), .stream_data_out(st_data),
        .hw_start(spi_start), .hw_addr(spi_addr), .hw_len(spi_len),
        .spi_busy(spi_busy), .spi_done()
    );
    qspi_flash_model u_flash (.sck(sck), .cs_n(cs_n), .io(io));

    axi_dma u_dma (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(s_awaddr), .s_axil_awvalid(s_awvalid), .s_axil_awready(s_awready),
        .s_axil_wdata(s_wdata), .s_axil_wstrb(s_wstrb), .s_axil_wvalid(s_wvalid), .s_axil_wready(s_wready),
        .s_axil_bresp(s_bresp), .s_axil_bvalid(s_bvalid), .s_axil_bready(s_bready),
        .s_axil_araddr(s_araddr), .s_axil_arvalid(s_arvalid), .s_axil_arready(s_arready),
        .s_axil_rdata(s_rdata), .s_axil_rresp(s_rresp), .s_axil_rvalid(s_rvalid), .s_axil_rready(s_rready),
        .s_valid(st_valid), .s_ready(st_ready), .s_data(st_data),
        .spi_start(spi_start), .spi_addr(spi_addr), .spi_len(spi_len), .spi_busy(spi_busy),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .dma_auto_prefetch(auto_pf), .fill_done(fill_done), .fill_bank(fill_bank),
        .busy(busy), .irq(irq)
    );

    axi_mem_model u_axi (
        .clk(clk), .rst_n(rst_n),
        .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
        .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready)
    );

    // ---------------- SPECK software model (encrypt) -----------------------------
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

    // ---------------- AXI-Lite master tasks --------------------------------------
    task automatic axil_write(input logic [31:0] a, input logic [31:0] d);
        bit ad, wd;
        @(posedge clk); #1; s_awvalid = 1; s_awaddr = a; s_wvalid = 1; s_wdata = d; s_wstrb = 4'hF; s_bready = 1;
        ad = 0; wd = 0;
        do begin
            @(posedge clk);
            if (s_awvalid && s_awready) ad = 1;
            if (s_wvalid  && s_wready)  wd = 1;
            #1;
            if (ad) s_awvalid = 0;
            if (wd) s_wvalid  = 0;
        end while (!(ad && wd));
        do @(posedge clk); while (!s_bvalid);
        #1; s_bready = 0;
    endtask

    task automatic axil_read(input logic [31:0] a, output logic [31:0] d);
        bit got;
        @(posedge clk); #1; s_arvalid = 1; s_araddr = a; s_rready = 0; got = 0;
        do begin
            @(posedge clk);
            if (s_arvalid && s_arready) got = 1;
            #1; if (got) s_arvalid = 0;
        end while (!got);
        s_rready = 1;
        do @(posedge clk); while (!s_rvalid);   // handshake happens on this edge
        d = s_rdata;
        #1; s_rready = 0;
    endtask

    // ---------------- helpers -----------------------------------------------------
    int errors = 0;
    byte plain [16384];
    logic [127:0] key;

    task automatic put_encrypted(input int faddr, input int poff, input int n);
        for (int b = 0; b < n/8; b++) begin
            logic [63:0] pt, ct;
            for (int j = 0; j < 8; j++) pt[j*8 +: 8] = plain[poff + b*8 + j];
            ct = sw_encrypt(pt);
            for (int j = 0; j < 8; j++) u_flash.mem[faddr + b*8 + j] = ct[j*8 +: 8];
        end
    endtask
    task automatic put_plain(input int faddr, input int poff, input int n);
        for (int i = 0; i < n; i++) u_flash.mem[faddr + i] = plain[poff + i];
    endtask
    task automatic clear_mem(input int a, input int n);
        for (int i = 0; i < n; i++) u_axi.mem[a + i] = 8'hAA;
    endtask
    function automatic int compare(input int dst, input int poff, input int n);
        int bad = 0;
        for (int i = 0; i < n; i++)
            if (u_axi.mem[dst + i] !== plain[poff + i]) begin
                if (bad < 3) $display("   byte %0d: got %02h exp %02h", i, u_axi.mem[dst+i], plain[poff+i]);
                bad++;
            end
        return bad;
    endfunction

    task automatic cfg(input int src, input int len, input int dsta, input int dstb, input int stride, input int tiles);
        axil_write(32'h08, src);  axil_write(32'h0C, len);
        axil_write(32'h10, dsta); axil_write(32'h14, dstb);
        axil_write(32'h18, stride); axil_write(32'h1C, tiles);
    endtask

    task automatic wait_done(input string name, output logic [31:0] st);
        int t = 0;
        st = 0;
        while (!st[1] && t < 30000) begin axil_read(32'h04, st); t++; end
        if (!st[1]) begin $display("[FAIL] %s: timeout waiting for DONE", name); errors++; end
        repeat (4) @(posedge clk);
    endtask

    // ---------------- fill monitor -----------------------------------------------
    int  fill_cnt = 0;
    bit  last_fill_bank;
    int  check_mode = 0;                 // 1: ping-pong content check on every fill
    int  pp_base_a, pp_base_b, pp_tile_bytes, pp_plain_off;
    int  pp_bad = 0;
    always @(posedge clk) if (fill_done) begin
        if (check_mode) begin
            int base, b;
            base = fill_bank ? pp_base_b : pp_base_a;
            b = compare(base, pp_plain_off + fill_cnt * pp_tile_bytes, pp_tile_bytes);
            if (fill_bank !== (fill_cnt % 2 == 1)) begin $display("[FAIL] tile %0d filled bank %0d", fill_cnt, fill_bank); pp_bad++; end
            pp_bad += b;
        end
        fill_cnt++;
        last_fill_bank = fill_bank;
    end

    // ---------------- tests -------------------------------------------------------
    logic [31:0] st, r;
    int bad, t0, t1;

    initial begin
        rst_n = 0; s_awvalid = 0; s_wvalid = 0; s_bready = 0; s_arvalid = 0; s_rready = 0;
        s_awaddr = 0; s_wdata = 0; s_wstrb = 0; s_araddr = 0; auto_pf = 0;
        key = 128'h1b1a1918_13121110_0b0a0908_03020100;
        for (int i = 0; i < 16384; i++) plain[i] = $urandom;
        repeat (6) @(posedge clk); #1; rst_n = 1;
        repeat (3) @(posedge clk);

        // ---- key ----
        sw_keysched(key);
        axil_write(32'h20, key[31:0]);  axil_write(32'h24, key[63:32]);
        axil_write(32'h28, key[95:64]); axil_write(32'h2C, key[127:96]);
        axil_write(32'h30, 1);
        st = 0; while (!st[3]) axil_read(32'h04, st);
        $display("[TEST] key schedule done, KEY_VALID=1");
        axil_read(32'h20, r);
        if (r !== 0) begin $display("[FAIL] key register readable (%h)", r); errors++; end

        // ---- 1: one 256 B tile, 256B-aligned destination ----
        put_encrypted(32'h400, 0, 256); clear_mem(32'h1000, 256);
        cfg(32'h400, 256, 32'h1000, 32'h2000, 256, 0);
        t0 = $time;
        axil_write(32'h00, 32'h5);                 // START + DECRYPT_EN
        wait_done("tile1", st);
        t1 = $time;
        bad = compare(32'h1000, 0, 256);
        $display("[TEST] 256 B tile decrypt+write              %s  (%0d cycles)", bad ? "FAIL" : "ok", (t1 - t0) / 10);
        errors += bad;
        axil_write(32'h04, 32'h2);

        // ---- 2: destination not 256B-aligned -> bursts must split 12 + 4 ----
        u_axi.aw_count = 0;
        put_encrypted(32'h800, 256, 256); clear_mem(32'h3040, 256);
        axil_write(32'h34, 0);
        cfg(32'h800, 256, 32'h3040, 32'h4000, 256, 0);
        axil_write(32'h00, 32'h5);
        wait_done("tile2", st);
        bad = compare(32'h3040, 256, 256);
        if (u_axi.aw_count != 2 || u_axi.awlen_log[0] != 11 || u_axi.awlen_log[1] != 3) begin
            $display("[FAIL] burst split: %0d bursts, awlen %0d,%0d", u_axi.aw_count, u_axi.awlen_log[0], u_axi.awlen_log[1]); bad++;
        end
        $display("[TEST] unaligned dst splits at 256 B (12+4)   %s", bad ? "FAIL" : "ok");
        errors += bad;
        axil_write(32'h04, 32'h2);

        // ---- 3: bypass (no decrypt): plaintext in flash ----
        put_plain(32'hA00, 512, 128); clear_mem(32'h5000, 128);
        axil_write(32'h34, 0);
        cfg(32'hA00, 128, 32'h5000, 32'h6000, 128, 0);
        axil_write(32'h00, 32'h1);                 // START, DECRYPT_EN=0
        wait_done("bypass", st);
        bad = compare(32'h5000, 512, 128);
        $display("[TEST] bypass copy (decrypt off)             %s", bad ? "FAIL" : "ok");
        errors += bad;
        axil_write(32'h04, 32'h2);

        // ---- 4: random AXI back-pressure, 1 KB tile ----
        u_axi.aw_pct = 30; u_axi.w_pct = 30;
        put_encrypted(32'h1000, 1024, 1024); clear_mem(32'h8000, 1024);
        axil_write(32'h34, 0);
        cfg(32'h1000, 1024, 32'h8000, 32'h9000, 1024, 0);
        axil_write(32'h00, 32'h5);
        wait_done("backpressure", st);
        bad = compare(32'h8000, 1024, 1024);
        $display("[TEST] 1 KB tile, AXI ready only 30%%         %s", bad ? "FAIL" : "ok");
        errors += bad;
        axil_write(32'h04, 32'h2);
        u_axi.aw_pct = 100; u_axi.w_pct = 100;

        // ---- 5: ping-pong auto-prefetch, 4 tiles ----
        for (int k = 0; k < 4; k++) put_encrypted(32'h2000 + k*128, 2048 + k*128, 128);
        clear_mem(32'hA000, 128); clear_mem(32'hB000, 128);
        pp_base_a = 32'hA000; pp_base_b = 32'hB000; pp_tile_bytes = 128; pp_plain_off = 2048;
        fill_cnt = 0; pp_bad = 0; check_mode = 1;
        axil_write(32'h34, 0);                     // first tile -> bank A
        cfg(32'h2000, 128, 32'hA000, 32'hB000, 128, 3);
        axil_write(32'h00, 32'h7);                 // START + AUTO_EN + DECRYPT_EN
        repeat (30) @(posedge clk);
        @(posedge clk); #1; auto_pf = 1; @(posedge clk); #1; auto_pf = 0;      // while busy -> pending
        while (fill_cnt < 2) @(posedge clk);
        repeat (10) @(posedge clk);
        @(posedge clk); #1; auto_pf = 1; @(posedge clk); #1; auto_pf = 0;
        while (fill_cnt < 3) @(posedge clk);
        repeat (10) @(posedge clk);
        @(posedge clk); #1; auto_pf = 1; @(posedge clk); #1; auto_pf = 0;
        while (fill_cnt < 4) @(posedge clk);
        repeat (10) @(posedge clk);
        @(posedge clk); #1; auto_pf = 1; @(posedge clk); #1; auto_pf = 0;      // tiles exhausted -> ignored
        repeat (600) @(posedge clk);
        check_mode = 0;
        if (fill_cnt != 4) begin $display("[FAIL] ping-pong: %0d fills, expected 4", fill_cnt); errors++; end
        $display("[TEST] ping-pong auto-prefetch, 4 tiles A/B/A/B  %s", (pp_bad || fill_cnt != 4) ? "FAIL" : "ok");
        errors += pp_bad;
        axil_write(32'h04, 32'h2);

        // ---- 6: AXI error response ----
        axil_write(32'h34, 0);
        cfg(32'h400, 64, 32'h1000, 32'h2000, 0, 0);
        u_axi.err_next = 1;
        axil_write(32'h00, 32'h5);
        wait_done("axi_err", st);
        axil_read(32'h04, r);
        if (!r[2]) begin $display("[FAIL] SLVERR not reported (STATUS=%h)", r); errors++; end
        else $display("[TEST] AXI SLVERR reported in STATUS.ERR  ok");
        axil_write(32'h04, 32'h6);

        // ---- 7: bad length / missing key handling, nothing goes on the bus ----
        begin
            int aw_before;
            aw_before = u_axi.aw_count;
            cfg(32'h400, 20, 32'h1000, 32'h2000, 0, 0);
            axil_write(32'h00, 32'h5);
            repeat (30) @(posedge clk);
            axil_read(32'h04, r);
            if (!r[2] || u_axi.aw_count != aw_before || r[0]) begin $display("[FAIL] bad LEN not rejected (STATUS=%h)", r); errors++; end
            else $display("[TEST] LEN=20 rejected with ERR, no AXI traffic  ok");
            axil_write(32'h04, 32'h6);
        end

        // ---- 8: START twice quickly -> one tile only; IRQ ----
        begin
            int f0;
            f0 = fill_cnt;
            axil_write(32'h34, 0);
            put_encrypted(32'hC00, 0, 64); clear_mem(32'h1000, 64);
            cfg(32'hC00, 64, 32'h1000, 32'h2000, 0, 0);
            axil_write(32'h00, 32'hD);             // START + DECRYPT + IRQ_EN
            axil_write(32'h00, 32'hD);             // second START while busy
            wait_done("start_twice", st);
            repeat (200) @(posedge clk);
            if (fill_cnt - f0 != 1) begin $display("[FAIL] double START ran %0d tiles", fill_cnt - f0); errors++; end
            else $display("[TEST] START while busy ignored (1 tile)  ok");
            if (!irq) begin $display("[FAIL] irq not asserted"); errors++; end
            axil_write(32'h04, 32'h2);
            @(posedge clk); #1;
            if (irq) begin $display("[FAIL] irq not cleared"); errors++; end
            else $display("[TEST] DMA IRQ assert / clear  ok");
        end

        if (u_axi.proto_errors != 0) begin $display("[FAIL] %0d AXI protocol errors", u_axi.proto_errors); errors++; end
        else $display("[TEST] AXI protocol checks (WLAST, size, 4KB, 256B) clean");

        if (errors == 0) $display("\n[TB PASS] tb_dma\n");
        else             $display("\n[TB FAIL] tb_dma: %0d errors\n", errors);
        $finish;
    end

    initial begin #80_000_000; $display("[TB FAIL] global timeout"); $finish; end
endmodule