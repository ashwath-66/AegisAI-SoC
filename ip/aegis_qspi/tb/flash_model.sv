`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// qspi_flash_model : behavioral quad-SPI NOR flash (read only)
//   EBh  Fast Read Quad I/O   : cmd(1) addr24+mode8 (4 lines, 8 clk) dummy 4 -> data (4 lines)
//   6Bh  Fast Read Quad Output: cmd(1) addr24 (1 line, 24 clk) dummy 8       -> data (4 lines)
//   SPI mode 0: samples on SCK rising edge, drives on SCK falling edge.
//   mem[] is public so testbenches can preload / compare it.
//-----------------------------------------------------------------------------
module qspi_flash_model #(
    parameter int MEM_BYTES = 65536
) (
    input  wire       sck,
    input  wire       cs_n,
    inout  wire [3:0] io
);
    logic [7:0] mem [MEM_BYTES];

    initial begin
        for (int i = 0; i < MEM_BYTES; i++)
            mem[i] = 8'((i * 37) ^ (i >> 3) ^ 8'h5A);
    end

    typedef enum logic [1:0] {P_CMD, P_ADDR, P_DUMMY, P_DATA} ph_t;
    ph_t         ph;
    logic [7:0]  cmd;
    logic [31:0] asr;
    int          cnt, dummy_n;
    logic        quad_addr;
    int unsigned ptr;
    logic        hi_nib;
    logic [3:0]  o;
    logic        oe;

    assign io = oe ? o : 4'bzzzz;

    always @(negedge cs_n) begin
        ph = P_CMD; cnt = 0; cmd = '0; asr = '0; hi_nib = 1; oe = 0;
    end
    always @(posedge cs_n) begin
        oe = 0;
    end

    always @(posedge sck) if (!cs_n) begin
        case (ph)
            P_CMD: begin
                cmd = {cmd[6:0], io[0]};
                if (cnt == 7) begin
                    ph = P_ADDR; cnt = 0;
                    quad_addr = (cmd == 8'hEB);
                    dummy_n   = (cmd == 8'hEB) ? 4 : 8;
                end else cnt++;
            end
            P_ADDR: begin
                if (quad_addr) asr = {asr[27:0], io};
                else           asr = {asr[30:0], io[0]};
                if (cnt == (quad_addr ? 7 : 23)) begin
                    ptr = quad_addr ? asr[31:8] : asr[23:0];
                    cnt = 0; hi_nib = 1;
                    ph  = (dummy_n != 0) ? P_DUMMY : P_DATA;
                end else cnt++;
            end
            P_DUMMY: begin
                if (cnt == dummy_n - 1) begin ph = P_DATA; cnt = 0; hi_nib = 1; end
                else cnt++;
            end
            P_DATA: begin                       // master just sampled the nibble
                if (hi_nib) hi_nib = 0;
                else begin hi_nib = 1; ptr = (ptr + 1) % MEM_BYTES; end
            end
        endcase
    end

    always @(negedge sck) if (!cs_n && ph == P_DATA) begin
        o  = hi_nib ? mem[ptr % MEM_BYTES][7:4] : mem[ptr % MEM_BYTES][3:0];
        oe = 1;
    end

endmodule
