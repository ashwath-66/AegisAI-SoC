`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// apb_spi_master : APB CSR front-end + QSPI read engine + 128-bit RX stream
//
//  0x00 CTRL   [0] START (write 1)          [8] IRQ_EN
//  0x04 CFG    [7:0] CMD (EBh)  [8] ADDR_QUAD (1)  [12:9] DUMMY (4)  [23:16] DIV (1)
//  0x08 ADDR   [23:0] flash byte address
//  0x0C LEN    [24:0] bytes to read (multiple of 16)
//  0x10 STATUS [0] BUSY  [1] DONE (write 1 to clear)  [2] RX_EMPTY  [3] RX_FULL
//  0x20..0x2C  RX0..RX3  head 128-bit beat of the RX FIFO (little-endian words)
//  0x30 POP    write any value: pop the head beat (CPU polling path)
//
//  RX stream: valid/ready, 128-bit beats, byte0 in bits [7:0]   (to the DMA)
//  hw_start/hw_addr/hw_len: lets the DMA launch a read with the CFG settings
//-----------------------------------------------------------------------------
module apb_spi_master (
    input  logic         pclk,
    input  logic         presetn,

    input  logic         psel,
    input  logic         penable,
    input  logic         pwrite,
    input  logic [31:0]  paddr,
    input  logic [31:0]  pwdata,
    output logic [31:0]  prdata,
    output logic         pready,
    output logic         pslverr,

    output logic         irq,

    output logic         qspi_sck,
    output logic         qspi_cs_n,
    inout  wire  [3:0]   qspi_io,

    output logic         stream_valid_out,
    input  logic         stream_ready_in,
    output logic [127:0] stream_data_out,

    // hardware trigger (from the DMA): same read, but address/length come from the DMA
    input  logic         hw_start,
    input  logic [23:0]  hw_addr,
    input  logic [24:0]  hw_len,
    output logic         spi_busy,
    output logic         spi_done
);

    // ---------------- CSRs ----------------------------------------------------
    logic        irq_en, done_sticky;
    logic [7:0]  cfg_cmd, cfg_div;
    logic        cfg_addr_quad;
    logic [3:0]  cfg_dummy;
    logic [23:0] reg_addr;
    logic [24:0] reg_len;

    logic        eng_busy, eng_done;
    logic        start_pulse, pop_pulse;
    logic        fifo_full, fifo_empty;
    logic [127:0] fifo_dout;

    wire apb_wr = psel && penable &&  pwrite;
    wire apb_rd = psel && penable && !pwrite;

    assign pready = 1'b1;

    logic mapped;
    always_comb begin
        case (paddr[7:0])
            8'h00, 8'h04, 8'h08, 8'h0C, 8'h10,
            8'h20, 8'h24, 8'h28, 8'h2C, 8'h30: mapped = 1'b1;
            default:                           mapped = 1'b0;
        endcase
    end
    assign pslverr = psel && penable && !mapped;

    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            irq_en        <= 1'b0;
            cfg_cmd       <= 8'hEB;
            cfg_addr_quad <= 1'b1;
            cfg_dummy     <= 4'd4;
            cfg_div       <= 8'd1;
            reg_addr      <= '0;
            reg_len       <= '0;
            done_sticky   <= 1'b0;
            start_pulse   <= 1'b0;
            pop_pulse     <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            pop_pulse   <= 1'b0;
            if (eng_done) done_sticky <= 1'b1;

            if (apb_wr) begin
                case (paddr[7:0])
                    8'h00: begin
                        irq_en <= pwdata[8];
                        if (pwdata[0] && !eng_busy) start_pulse <= 1'b1;
                    end
                    8'h04: begin
                        cfg_cmd       <= pwdata[7:0];
                        cfg_addr_quad <= pwdata[8];
                        cfg_dummy     <= pwdata[12:9];
                        cfg_div       <= pwdata[23:16];
                    end
                    8'h08: reg_addr <= pwdata[23:0];
                    8'h0C: reg_len  <= pwdata[24:0];
                    8'h10: if (pwdata[1]) done_sticky <= 1'b0;
                    8'h30: pop_pulse <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        prdata = '0;
        case (paddr[7:0])
            8'h00: prdata = {23'b0, irq_en, 8'b0};
            8'h04: prdata = {8'b0, cfg_div, 3'b0, cfg_dummy, cfg_addr_quad, cfg_cmd};
            8'h08: prdata = {8'b0, reg_addr};
            8'h0C: prdata = {7'b0, reg_len};
            8'h10: prdata = {28'b0, fifo_full, fifo_empty, done_sticky, eng_busy};
            8'h20: prdata = fifo_dout[31:0];
            8'h24: prdata = fifo_dout[63:32];
            8'h28: prdata = fifo_dout[95:64];
            8'h2C: prdata = fifo_dout[127:96];
            default: prdata = '0;
        endcase
    end

    assign irq      = irq_en && done_sticky;
    assign spi_busy = eng_busy;
    assign spi_done = eng_done;

    // ---------------- engine + FIFO ------------------------------------------
    logic [3:0] io_o, io_oe, io_i;
    logic       beat_valid;
    logic [127:0] beat_data;

    qspi_shift u_engine (
        .clk(pclk), .rst_n(presetn),
        .start(start_pulse || hw_start),
        .cmd(cfg_cmd), .addr_quad(cfg_addr_quad), .dummy(cfg_dummy), .div(cfg_div),
        .addr(hw_start ? hw_addr : reg_addr),
        .beats(hw_start ? hw_len[24:4] : reg_len[24:4]),
        .busy(eng_busy), .done_pulse(eng_done),
        .sck(qspi_sck), .cs_n(qspi_cs_n),
        .io_o(io_o), .io_oe(io_oe), .io_i(io_i),
        .beat_valid(beat_valid), .beat_data(beat_data),
        .rx_full(fifo_full)
    );

    wire fifo_rd = (stream_ready_in && !fifo_empty) || pop_pulse;

    qspi_fifo #(.DATA_WIDTH(128), .DEPTH(4)) u_rx_fifo (
        .clk(pclk), .rst_n(presetn),
        .wr_en(beat_valid), .din(beat_data),
        .rd_en(fifo_rd), .dout(fifo_dout),
        .full(fifo_full), .empty(fifo_empty)
    );

    assign stream_valid_out = !fifo_empty;
    assign stream_data_out  = fifo_dout;

    // ---------------- pad tri-states (the only place they exist) --------------
    for (genvar i = 0; i < 4; i++) begin : g_pad
        assign qspi_io[i] = io_oe[i] ? io_o[i] : 1'bz;
        assign io_i[i]    = qspi_io[i];
    end

endmodule