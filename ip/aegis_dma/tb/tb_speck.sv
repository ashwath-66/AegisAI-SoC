`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_speck : SPECK-64/128 decryptor
//   1) published test vector (Beaulieu et al., NSA SPECK paper)
//   2) random round-trips against an independent software encrypt model
//   3) stalled output / gapped input, key reload, throughput
//-----------------------------------------------------------------------------
module tb_speck;

    logic         clk = 0;
    logic         rst_n;
    logic         key_load;
    logic [127:0] key_in;
    logic         key_valid;
    logic         in_valid, in_ready;
    logic [127:0] ciphertext_in;
    logic         out_valid, out_ready;
    logic [127:0] plaintext_out;

    speck_decryptor u_dut (.*);

    always #5 clk = ~clk;

    // ---------------- software reference (encrypt) -----------------------------
    function automatic logic [31:0] ror(input logic [31:0] v, input int n);
        return (v >> n) | (v << (32 - n));
    endfunction
    function automatic logic [31:0] rol(input logic [31:0] v, input int n);
        return (v << n) | (v >> (32 - n));
    endfunction

    logic [31:0] sw_rk [27];

    task automatic sw_keysched(input logic [127:0] key);
        logic [31:0] k, l [29];
        k    = key[31:0];
        l[0] = key[63:32]; l[1] = key[95:64]; l[2] = key[127:96];
        for (int i = 0; i < 27; i++) begin
            sw_rk[i] = k;
            if (i < 26) begin
                l[i+3] = (k + ror(l[i], 8)) ^ 32'(i);
                k      = rol(k, 3) ^ l[i+3];
            end
        end
    endtask

    function automatic logic [63:0] sw_encrypt(input logic [63:0] pt);
        logic [31:0] x, y;
        x = pt[63:32]; y = pt[31:0];
        for (int i = 0; i < 27; i++) begin
            x = (ror(x, 8) + y) ^ sw_rk[i];
            y = rol(y, 3) ^ x;
        end
        return {x, y};
    endfunction

    // ---------------- helpers --------------------------------------------------
    int errors = 0;

    task automatic load_key(input logic [127:0] k);
        @(negedge clk); key_in = k; key_load = 1;
        @(negedge clk); key_load = 0;
        wait (key_valid);
        @(negedge clk);
        sw_keysched(k);
    endtask

    // push one beat, wait for result, optional output stall
    task automatic decrypt_beat(input logic [127:0] ct, output logic [127:0] pt,
                                input int stall_cycles, output int cycles);
        @(negedge clk);
        ciphertext_in = ct; in_valid = 1;
        cycles = 0;
        while (!in_ready) begin @(negedge clk); end
        @(negedge clk);
        in_valid = 0;
        out_ready = 0;
        while (!out_valid) begin @(negedge clk); cycles++; end
        repeat (stall_cycles) @(negedge clk);
        pt = plaintext_out;
        out_ready = 1;
        @(negedge clk);
        out_ready = 0;
    endtask

    logic [127:0] pt, exp_pt, ct;
    int cyc;

    initial begin
        rst_n = 0; key_load = 0; key_in = '0; in_valid = 0; ciphertext_in = '0; out_ready = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        // ---- 1) published vector -------------------------------------------
        // Key  : 1b1a1918 13121110 0b0a0908 03020100
        // Plain: 3b726574 7475432d   Cipher: 8c6fa548 454e028b
        load_key(128'h1b1a1918_13121110_0b0a0908_03020100);
        if (sw_encrypt(64'h3b726574_7475432d) !== 64'h8c6fa548_454e028b) begin
            $display("[FAIL] software model does not match published vector"); errors++;
        end
        ct = {64'h8c6fa548_454e028b, 64'h8c6fa548_454e028b};
        decrypt_beat(ct, pt, 0, cyc);
        if (pt !== {64'h3b726574_7475432d, 64'h3b726574_7475432d}) begin
            $display("[FAIL] published vector: got %h", pt); errors++;
        end else
            $display("[TEST] published SPECK-64/128 vector decrypts correctly (%0d cycles/beat)", cyc);

        // ---- 2) random round-trips, different blocks per half --------------
        for (int n = 0; n < 200; n++) begin
            exp_pt = {$urandom, $urandom, $urandom, $urandom};
            ct     = {sw_encrypt(exp_pt[127:64]), sw_encrypt(exp_pt[63:0])};
            decrypt_beat(ct, pt, 0, cyc);
            if (pt !== exp_pt) begin
                if (errors < 5) $display("[FAIL] round-trip %0d: got %h exp %h", n, pt, exp_pt);
                errors++;
            end
        end
        $display("[TEST] 200 random round-trips done, errors so far = %0d", errors);

        // ---- 3) output stalls ----------------------------------------------
        for (int n = 0; n < 20; n++) begin
            exp_pt = {$urandom, $urandom, $urandom, $urandom};
            ct     = {sw_encrypt(exp_pt[127:64]), sw_encrypt(exp_pt[63:0])};
            decrypt_beat(ct, pt, $urandom_range(0, 9), cyc);
            if (pt !== exp_pt) begin errors++; $display("[FAIL] stalled beat %0d", n); end
        end
        $display("[TEST] stalled-output beats done, errors so far = %0d", errors);

        // ---- 4) key reload ---------------------------------------------------
        load_key({$urandom, $urandom, $urandom, $urandom});
        for (int n = 0; n < 20; n++) begin
            exp_pt = {$urandom, $urandom, $urandom, $urandom};
            ct     = {sw_encrypt(exp_pt[127:64]), sw_encrypt(exp_pt[63:0])};
            decrypt_beat(ct, pt, 0, cyc);
            if (pt !== exp_pt) begin errors++; $display("[FAIL] reloaded-key beat %0d", n); end
        end
        $display("[TEST] key-reload beats done, errors so far = %0d", errors);

        // ---- 5) throughput: continuous input, always-ready output ----------
        begin
            int beats;
            beats = 0;
            @(negedge clk);
            ciphertext_in = {$urandom, $urandom, $urandom, $urandom};
            in_valid = 1; out_ready = 1;
            repeat (2900) begin
                @(posedge clk);
                if (out_valid && out_ready) beats++;
            end
            in_valid = 0; out_ready = 0;
            $display("[INFO] %0d beats in 2900 cycles = %0d cycles per 128-bit beat (QSPI delivers one per 32)",
                     beats, 2900 / beats);
        end

        if (errors == 0) $display("\n[TB PASS] tb_speck\n");
        else             $display("\n[TB FAIL] tb_speck: %0d errors\n", errors);
        $finish;
    end

    initial begin #5_000_000; $display("[TB FAIL] timeout"); $finish; end
endmodule