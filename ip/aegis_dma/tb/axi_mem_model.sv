`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axi_mem_model : AXI4 write-only memory slave (128-bit data) for DMA tests
//   random AWREADY/WREADY back-pressure, SLVERR injection, protocol checks:
//   WLAST position, AWSIZE/BURST, 4 KB rule, 256 B rule (design property of axi_dma)
//-----------------------------------------------------------------------------
module axi_mem_model #(
    parameter int MEM_BYTES = 65536
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [31:0]  awaddr,
    input  logic [7:0]   awlen,
    input  logic [2:0]   awsize,
    input  logic [1:0]   awburst,
    input  logic         awvalid,
    output logic         awready,
    input  logic [127:0] wdata,
    input  logic [15:0]  wstrb,
    input  logic         wlast,
    input  logic         wvalid,
    output logic         wready,
    output logic [1:0]   bresp,
    output logic         bvalid,
    input  logic         bready
);
    logic [7:0] mem [MEM_BYTES];

    int aw_pct = 100, w_pct = 100;     // readiness probability, set by the test
    bit err_next = 0;                  // next write response = SLVERR
    int proto_errors = 0;
    int aw_count = 0, beat_count = 0;
    int awlen_log [64];

    typedef enum logic [1:0] {ST_AW, ST_W, ST_B} st_t;
    st_t st;
    logic [31:0] addr;
    int          len, beat;

    initial for (int i = 0; i < MEM_BYTES; i++) mem[i] = 8'h00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_AW; awready <= 0; wready <= 0; bvalid <= 0; bresp <= 0;
        end else begin
            case (st)
                ST_AW: begin
                    awready <= ($urandom_range(0, 99) < aw_pct);
                    if (awvalid && awready) begin
                        addr = awaddr; len = awlen; beat = 0;
                        if (aw_count < 64) awlen_log[aw_count] = awlen;
                        aw_count++;
                        if (awsize !== 3'd4 || awburst !== 2'b01) begin proto_errors++; $display("[AXI] bad size/burst"); end
                        if ((awaddr[11:0] + (awlen + 1) * 16) > 4096) begin proto_errors++; $display("[AXI] 4KB boundary crossed"); end
                        if ((awaddr[7:0]  + (awlen + 1) * 16) > 256)  begin proto_errors++; $display("[AXI] 256B boundary crossed"); end
                        awready <= 0;
                        st <= ST_W;
                    end
                end
                ST_W: begin
                    wready <= ($urandom_range(0, 99) < w_pct);
                    if (wvalid && wready) begin
                        for (int i = 0; i < 16; i++)
                            if (wstrb[i]) mem[(addr + beat*16 + i) % MEM_BYTES] = wdata[i*8 +: 8];
                        beat_count++;
                        if (wlast !== (beat == len)) begin proto_errors++; $display("[AXI] WLAST wrong at beat %0d", beat); end
                        beat++;
                        if (wlast) begin
                            wready <= 0; bvalid <= 1;
                            bresp  <= err_next ? 2'b10 : 2'b00;
                            err_next = 0;
                            st <= ST_B;
                        end
                    end
                end
                ST_B: if (bvalid && bready) begin bvalid <= 0; st <= ST_AW; end
            endcase
        end
    end
endmodule
