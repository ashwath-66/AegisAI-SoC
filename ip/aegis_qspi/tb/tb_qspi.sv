`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_qspi : apb_spi_master + qspi_shift against qspi_flash_model
//   EBh and 6Bh reads, several SCK dividers, back-pressure, CPU pop path,
//   SCK cycle-count check, back-to-back transactions, IRQ, APB error response.
//-----------------------------------------------------------------------------
module tb_qspi;

    logic        clk = 0;
    logic        rst_n;
    logic        psel, penable, pwrite;
    logic [31:0] paddr, pwdata, prdata;
    logic        pready, pslverr, irq;
    wire         sck, cs_n;
    wire  [3:0]  io;
    logic        stream_valid, stream_ready;
    logic [127:0] stream_data;

    apb_spi_master u_dut (
        .pclk(clk), .presetn(rst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr), .irq(irq),
        .qspi_sck(sck), .qspi_cs_n(cs_n), .qspi_io(io),
        .stream_valid_out(stream_valid), .stream_ready_in(stream_ready),
        .stream_data_out(stream_data),
        .hw_start(1'b0), .hw_addr(24'b0), .hw_len(25'b0), .spi_busy(), .spi_done()
    );

    qspi_flash_model u_flash (.sck(sck), .cs_n(cs_n), .io(io));

    always #5 clk = ~clk;

    int errors = 0;

    // ---------------- APB master ----------------------------------------------
    task automatic apb_write(input logic [31:0] a, input logic [31:0] d);
        @(posedge clk); #1; psel = 1; penable = 0; pwrite = 1; paddr = a; pwdata = d;
        @(posedge clk); #1; penable = 1;
        @(posedge clk); #1; psel = 0; penable = 0; pwrite = 0;
    endtask

    task automatic apb_read(input logic [31:0] a, output logic [31:0] d);
        @(posedge clk); #1; psel = 1; penable = 0; pwrite = 0; paddr = a;
        @(posedge clk); #1; penable = 1;
        @(posedge clk); d = prdata; #1; psel = 0; penable = 0;
    endtask

    // ---------------- stream consumer -----------------------------------------
    byte rx_buf [4096];
    int  rx_n;
    int  ready_pct;              // probability (%) that the consumer is ready
    bit  consumer_on;

    always @(negedge clk) begin
        stream_ready <= consumer_on && ($urandom_range(0, 99) < ready_pct);
    end
    always @(posedge clk) begin
        if (stream_valid && stream_ready) begin
            for (int j = 0; j < 16; j++) rx_buf[rx_n + j] = stream_data[j*8 +: 8];
            rx_n += 16;
        end
    end

    // ---------------- SCK cycle counter ----------------------------------------
    int sck_cycles;
    always @(posedge sck) if (!cs_n) sck_cycles++;

    // ---------------- one full read -------------------------------------------
    task automatic do_read(input string name, input int addr, input int len,
                           input logic [7:0] cmd, input bit quad, input int dummy,
                           input int div, input int pct);
        logic [31:0] st;
        int exp_cycles, an, bad;
        rx_n = 0; sck_cycles = 0; ready_pct = pct; consumer_on = 1;
        apb_write(32'h04, {8'b0, 8'(div), 3'b0, 4'(dummy), quad, cmd});
        apb_write(32'h08, addr);
        apb_write(32'h0C, len);
        apb_write(32'h00, 32'h1);                      // START
        st = 1;
        while (st[0] || st[1] == 0) begin              // busy or not done yet
            apb_read(32'h10, st);
            if (st[0] === 1'bx) begin $display("X on STATUS"); errors++; break; end
            if (!st[0] && st[1]) break;
        end
        repeat (40) @(posedge clk);                    // drain consumer
        bad = 0;
        for (int i = 0; i < len; i++)
            if (rx_buf[i] !== u_flash.mem[addr + i]) begin
                if (bad < 4) $display("   [%s] byte %0d: got %02h exp %02h", name, i, rx_buf[i], u_flash.mem[addr+i]);
                bad++;
            end
        an = quad ? 8 : 24;
        exp_cycles = 8 + an + dummy + 2*len;
        if (rx_n != len)               begin $display("   [%s] received %0d bytes, expected %0d", name, rx_n, len); bad++; end
        if (sck_cycles != exp_cycles)  begin $display("   [%s] SCK cycles %0d, expected %0d", name, sck_cycles, exp_cycles); bad++; end
        if (cs_n !== 1'b1)             begin $display("   [%s] CS not released", name); bad++; end
        $display("[TEST] %-34s %0d bytes  div=%0d  rdy=%0d%%  %s", name, len, div, pct, bad ? "FAIL" : "ok");
        errors += bad;
        apb_write(32'h10, 32'h2);                      // clear DONE
        consumer_on = 0;
    endtask

    logic [31:0] r;

    initial begin
        rst_n = 0; psel = 0; penable = 0; pwrite = 0; paddr = 0; pwdata = 0;
        stream_ready = 0; consumer_on = 0; ready_pct = 100; rx_n = 0; sck_cycles = 0;
        repeat (5) @(posedge clk); #1; rst_n = 1;
        repeat (3) @(posedge clk);

        // CSR reset values
        apb_read(32'h04, r);
        if (r !== 32'h0001_09EB) begin $display("[FAIL] CFG reset value %h", r); errors++; end
        apb_read(32'h10, r);
        if (r[3:0] !== 4'b0100) begin $display("[FAIL] STATUS reset value %h", r); errors++; end

        // EBh quad I/O reads, several dividers
        do_read("EBh 64B  div1",         32'h100,   64, 8'hEB, 1, 4, 1, 100);
        do_read("EBh 256B div0",         32'h0A00, 256, 8'hEB, 1, 4, 0, 100);
        do_read("EBh 256B div3",         32'h1230, 256, 8'hEB, 1, 4, 3, 100);

        // 6Bh quad output (address on one line, 8 dummy)
        do_read("6Bh 128B (1-line addr)", 32'h2A0,  128, 8'h6B, 0, 8, 1, 100);

        // consumer that is mostly stalled -> FIFO fills, SCK pauses, nothing lost
        do_read("EBh 512B  slow consumer", 32'h3000, 512, 8'hEB, 1, 4, 0, 15);

        // back-to-back transactions
        do_read("back-to-back A",         32'h4000,  32, 8'hEB, 1, 4, 1, 100);
        do_read("back-to-back B",         32'h4400,  32, 8'hEB, 1, 4, 1, 100);

        // explicit back-pressure check: nobody reads, FIFO must fill and hold
        rx_n = 0; consumer_on = 0;
        apb_write(32'h04, 32'h0001_09EB);
        apb_write(32'h08, 32'h5000);
        apb_write(32'h0C, 32'd256);
        apb_write(32'h00, 32'h1);
        repeat (1500) @(posedge clk);
        apb_read(32'h10, r);
        if (!(r[0] && r[3])) begin $display("[FAIL] expected BUSY & RX_FULL, STATUS=%h", r); errors++; end
        else $display("[TEST] back-pressure: engine paused with RX FIFO full (STATUS=%h)", r);
        // CPU pop path: read the head beat through RX0..RX3 and pop, 16 beats
        for (int b = 0; b < 16; b++) begin
            logic [31:0] w [4];
            apb_read(32'h10, r);
            while (r[2]) begin apb_read(32'h10, r); end  // wait until not empty
            apb_read(32'h20, w[0]); apb_read(32'h24, w[1]);
            apb_read(32'h28, w[2]); apb_read(32'h2C, w[3]);
            for (int j = 0; j < 16; j++)
                if (w[j/4][(j%4)*8 +: 8] !== u_flash.mem[32'h5000 + b*16 + j]) begin
                    errors++; if (errors < 8) $display("[FAIL] pop path beat %0d byte %0d", b, j);
                end
            apb_write(32'h30, 1);
        end
        repeat (80) @(posedge clk);
        apb_read(32'h10, r);
        if (r[0] || !r[1]) begin $display("[FAIL] STATUS after pop-path read = %h", r); errors++; end
        else $display("[TEST] CPU pop path: 256 bytes read through RX0..RX3 ok");
        apb_write(32'h10, 32'h2);

        // IRQ
        apb_write(32'h00, 32'h100);                    // IRQ_EN
        apb_write(32'h0C, 32'd16);
        apb_write(32'h08, 32'h6000);
        consumer_on = 1; ready_pct = 100;
        apb_write(32'h00, 32'h101);
        repeat (400) @(posedge clk);
        if (!irq) begin $display("[FAIL] irq not asserted"); errors++; end
        apb_write(32'h10, 32'h2);
        @(posedge clk); #1;
        if (irq) begin $display("[FAIL] irq not cleared"); errors++; end
        else $display("[TEST] IRQ assert / clear ok");

        // APB error on unmapped register
        @(posedge clk); #1; psel = 1; penable = 0; pwrite = 0; paddr = 32'h7C;
        @(posedge clk); #1; penable = 1; #1;
        if (!pslverr) begin $display("[FAIL] no PSLVERR on unmapped address"); errors++; end
        @(posedge clk); #1; psel = 0; penable = 0;
        $display("[TEST] PSLVERR on unmapped register ok");

        if (errors == 0) $display("\n[TB PASS] tb_qspi\n");
        else             $display("\n[TB FAIL] tb_qspi: %0d errors\n", errors);
        $finish;
    end

    initial begin #50_000_000; $display("[TB FAIL] timeout"); $finish; end
endmodule