`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_aegisai_soc : the whole chip, driven only by its own firmware
//   - flash holds a plaintext header + SPECK-encrypted tiles (W rows + A rows)
//   - Ibex boots from the ROM, reads the header, starts the DMA, copies results
//   - the TB checks the firmware verdict, every result word the CPU stored in its
//     SRAM against a software C = A x W, and that Ibex never raised an alert
//   run with:  +FW=<path to boot.hex>
//-----------------------------------------------------------------------------
module tb_aegisai_soc;
    localparam int NTILES = 4;
    localparam int ROWS   = 24;
    localparam int N      = 16;
    localparam int LEN    = 256 + 16*ROWS;
    localparam int HDR    = 16;
    localparam int TBASE  = 32'h100;

    logic clk = 0, rst_n;
    always #5 clk = ~clk;                          // 100 MHz

    wire        sck, cs_n;
    wire  [3:0] io;
    logic       dbg_char_valid, dbg_done, dbg_pass, cpu_sleep, cpu_alert;
    logic [7:0] dbg_char;

    aegisai_top u_soc (
        .clk(clk), .rst_n(rst_n),
        .qspi_sck(sck), .qspi_cs_n(cs_n), .qspi_io(io),
        .dbg_char_valid(dbg_char_valid), .dbg_char(dbg_char),
        .dbg_done(dbg_done), .dbg_pass(dbg_pass),
        .cpu_sleep(cpu_sleep), .cpu_alert(cpu_alert)
    );
    qspi_flash_model u_flash (.sck(sck), .cs_n(cs_n), .io(io));

    // ---------------- SPECK software model ------------------------------------------
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

    // ---------------- flash image ----------------------------------------------------
    int signed exp_c [NTILES][ROWS][N];
    byte tile [LEN];

    function automatic int signed rnd8(input int zero_pct);
        int r;
        if ($urandom_range(0, 99) < zero_pct) return 0;
        r = $urandom_range(0, 255);
        return (r > 127) ? r - 256 : r;
    endfunction

    task automatic build_flash();
        logic [127:0] key;
        key = 128'h1b1a1918_13121110_0b0a0908_03020100;       // same key the firmware loads
        sw_keysched(key);
        // header
        for (int i = 0; i < 4; i++) begin
            logic [31:0] w;
            w = (i == 0) ? 32'hAE615A15 : (i == 1) ? NTILES : (i == 2) ? ROWS : TBASE;
            for (int j = 0; j < 4; j++) u_flash.mem[i*4 + j] = w[j*8 +: 8];
        end
        for (int k = 0; k < NTILES; k++) begin
            int signed W [N][N];
            int signed A [ROWS][N];
            for (int r = 0; r < N; r++)
                for (int c = 0; c < N; c++) begin W[r][c] = rnd8(20); tile[r*16 + c] = W[r][c][7:0]; end
            for (int m = 0; m < ROWS; m++)
                for (int j = 0; j < N; j++) begin A[m][j] = rnd8(20); tile[256 + m*16 + j] = A[m][j][7:0]; end
            for (int m = 0; m < ROWS; m++)
                for (int c = 0; c < N; c++) begin
                    int acc = 0;
                    for (int j = 0; j < N; j++) acc += A[m][j] * W[j][c];
                    exp_c[k][m][c] = acc;
                end
            for (int b = 0; b < LEN/8; b++) begin
                logic [63:0] pt, ct;
                for (int j = 0; j < 8; j++) pt[j*8 +: 8] = tile[b*8 + j];
                ct = sw_encrypt(pt);
                for (int j = 0; j < 8; j++) u_flash.mem[TBASE + k*LEN + b*8 + j] = ct[j*8 +: 8];
            end
        end
    endtask

    // ---------------- console + alert monitor -------------------------------------------
    string console = "";
    always @(posedge clk) begin
        if (dbg_char_valid) begin
            console = {console, string'(dbg_char)};
            $write("%c", dbg_char);
        end
    end
    int alerts = 0;
    always @(posedge clk) if (rst_n && cpu_alert) alerts++;


    int dbg_rd = 0;
    always @(posedge clk) if (u_soc.s_arvalid[4] && u_soc.s_arready[4] && dbg_rd < 24)
        $display("[DBG] GEMM AR addr=%h", u_soc.s_araddr[4]);
    always @(posedge clk) if (u_soc.s_rvalid[4] && u_soc.s_rready[4] && dbg_rd < 24) begin
        $display("[DBG] GEMM R  data=%0d", $signed(u_soc.s_rdata[4])); dbg_rd++;
    end
    int errors = 0;
    int cyc = 0;
    always @(posedge clk) cyc++;

    initial begin
        int bad;
        rst_n = 1;                                   // real power-up: 1 -> 0 -> 1 so every async reset sees a falling edge
        build_flash();
        repeat (4) @(posedge clk);                    // let the synchronizer settle high
        #1 rst_n = 0;                                 // asynchronous assert (falling edge reaches Ibex)
        repeat (8) @(posedge clk); #1; rst_n = 1;
        $display("[SOC] reset released, Ibex boots from ROM");

        while (!dbg_done && cyc < 6_000_000) @(posedge clk);
        if (!dbg_done) begin $display("\n[FAIL] timeout, firmware never finished"); errors++; end
        repeat (50) @(posedge clk);
        $display("\n[SOC] firmware finished after %0d cycles", cyc);

        if (!dbg_pass) begin $display("[FAIL] firmware reported FAIL"); errors++; end
        if (!(console.substr(0, 11) == "AegisAI boot")) begin $display("[FAIL] banner missing"); errors++; end
        if (alerts != 0) begin $display("[FAIL] Ibex alert asserted %0d cycles", alerts); errors++; end

        // results stored by the CPU in its SRAM: tile-major, row-major, 16 words per row
        for (int i = 0; i < 8; i++) $display("[DBG] sram[%0d]=%0d  exp=%0d", i, $signed(u_soc.u_sram.mem[i]), exp_c[0][0][i]);
        bad = 0;
        for (int k = 0; k < NTILES; k++)
            for (int m = 0; m < ROWS; m++)
                for (int c = 0; c < N; c++) begin
                    int idx;
                    idx = (k*ROWS + m)*16 + c;
                    if ($signed(u_soc.u_sram.mem[idx]) !== exp_c[k][m][c]) begin
                        if (bad < 5) $display("   tile %0d C[%0d][%0d]: sram %0d exp %0d", k, m, c,
                                              $signed(u_soc.u_sram.mem[idx]), exp_c[k][m][c]);
                        bad++;
                    end
                end
        $display("[SOC] %0d result words compared against the software model: %0d mismatches", NTILES*ROWS*N, bad);
        errors += bad;

        if (errors == 0) $display("\n[TB PASS] tb_aegisai_soc: Ibex booted, DMA+SPECK+TCM+GEMM verified end to end\n");
        else             $display("\n[TB FAIL] tb_aegisai_soc: %0d errors\n", errors);
        $finish;
    end
endmodule