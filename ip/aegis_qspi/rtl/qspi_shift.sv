`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// qspi_shift : QSPI read engine (SPI mode 0)
//   cmd (1 line) -> address [+ mode byte] (1 or 4 lines) -> dummy -> data (4 lines)
//   - SCK is a registered signal (clk / (2*(div+1))), never a gated clock
//   - outputs launch on the SCK falling edge, inputs sample on the rising edge
//   - SCK is paused (held low, CS low) when the receive FIFO is full
//   - each completed 128-bit beat is pushed with beat_valid; byte0 = beat[7:0]
//-----------------------------------------------------------------------------
module qspi_shift (
    input  logic         clk,
    input  logic         rst_n,

    input  logic         start,
    input  logic [7:0]   cmd,
    input  logic         addr_quad,     // 1: addr+mode on 4 lines (8 clk), 0: addr on 1 line (24 clk)
    input  logic [3:0]   dummy,         // dummy SCK cycles
    input  logic [7:0]   div,
    input  logic [23:0]  addr,
    input  logic [20:0]  beats,         // number of 128-bit beats to read

    output logic         busy,
    output logic         done_pulse,

    output logic         sck,
    output logic         cs_n,
    output logic [3:0]   io_o,
    output logic [3:0]   io_oe,
    input  logic [3:0]   io_i,

    output logic         beat_valid,
    output logic [127:0] beat_data,
    input  logic         rx_full
);

    localparam logic [7:0] MODE_BYTE = 8'hFF;   // no continuous-read mode

    typedef enum logic [2:0] {S_IDLE, S_SETUP, S_XFER, S_HOLD, S_GAP} state_t;
    typedef enum logic [1:0] {PH_CMD, PH_ADDR, PH_DUMMY, PH_DATA} phase_t;

    state_t state;
    phase_t ph;

    logic [7:0]   cmd_r, div_r;
    logic [23:0]  addr_r;
    logic         addr_quad_r;
    logic [3:0]   dummy_r;
    logic [25:0]  data_cycles;      // beats*32
    logic [25:0]  pc;               // cycle counter inside phase
    logic [7:0]   div_cnt;
    logic         sck_q, cs_q;
    logic [3:0]   wait_cnt;
    logic [127:0] rx_acc;

    // ---------------- SCK generation ------------------------------------------
    logic stall, run, tick, rise_tick, fall_tick;
    assign stall     = (state == S_XFER) && (ph == PH_DATA) && (pc[4:0] == 5'd0) && !sck_q && rx_full;
    assign run       = (state == S_XFER) && !stall;
    assign tick      = run && (div_cnt == div_r);
    assign rise_tick = tick && !sck_q;
    assign fall_tick = tick &&  sck_q;

    assign sck  = sck_q;
    assign cs_n = !cs_q;

    // ---------------- output drive (combinational from registered state) ------
    logic [31:0] addr32;
    assign addr32 = {addr_r, MODE_BYTE};

    always_comb begin
        io_o  = 4'hF;
        io_oe = 4'h0;
        if (state == S_SETUP || state == S_XFER) begin
            case (ph)
                PH_CMD: begin
                    io_oe = 4'b1101;                       // IO0 drives, IO1 hi-z, IO2/IO3 held high
                    io_o  = {2'b11, 1'b0, cmd_r[3'd7 - pc[2:0]]};
                end
                PH_ADDR: begin
                    if (addr_quad_r) begin
                        io_oe = 4'hF;
                        io_o  = addr32[(5'd31 - {pc[2:0], 2'b00}) -: 4];
                    end else begin
                        io_oe = 4'b1101;
                        io_o  = {2'b11, 1'b0, addr_r[5'd23 - pc[4:0]]};
                    end
                end
                default: io_oe = 4'h0;                     // dummy / data: flash drives
            endcase
        end
    end

    // ---------------- receive nibble assembly ---------------------------------
    logic [127:0] beat_next;
    logic [4:0]   nib;
    assign nib = pc[4:0];
    always_comb begin
        beat_next = rx_acc;
        beat_next[{nib[4:1], 3'b000} + (nib[0] ? 7'd0 : 7'd4) +: 4] = io_i;
    end
    assign beat_valid = rise_tick && (ph == PH_DATA) && (nib == 5'd31);
    assign beat_data  = beat_next;

    // ---------------- control FSM ---------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            ph          <= PH_CMD;
            pc          <= '0;
            div_cnt     <= '0;
            sck_q       <= 1'b0;
            cs_q        <= 1'b0;
            wait_cnt    <= '0;
            rx_acc      <= '0;
            busy        <= 1'b0;
            done_pulse  <= 1'b0;
            cmd_r <= '0; div_r <= '0; addr_r <= '0; addr_quad_r <= 1'b0;
            dummy_r <= '0; data_cycles <= '0;
        end else begin
            done_pulse <= 1'b0;

            // SCK / divider
            if (state == S_XFER) begin
                if (tick) begin
                    div_cnt <= '0;
                    sck_q   <= ~sck_q;
                end else if (run) begin
                    div_cnt <= div_cnt + 1'b1;
                end
            end else begin
                div_cnt <= '0;
                sck_q   <= 1'b0;
            end

            if (rise_tick && ph == PH_DATA) rx_acc <= beat_next;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        if (beats == 0) begin
                            done_pulse <= 1'b1;
                        end else begin
                            cmd_r       <= cmd;
                            addr_r      <= addr;
                            addr_quad_r <= addr_quad;
                            dummy_r     <= dummy;
                            div_r       <= div;
                            data_cycles <= {beats, 5'b00000};
                            ph          <= PH_CMD;
                            pc          <= '0;
                            cs_q        <= 1'b1;
                            wait_cnt    <= '0;
                            busy        <= 1'b1;
                            state       <= S_SETUP;
                        end
                    end
                end

                S_SETUP: begin                    // CS setup before first SCK edge
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == 4'd3) state <= S_XFER;
                end

                S_XFER: begin
                    if (fall_tick) begin
                        case (ph)
                            PH_CMD:
                                if (pc == 26'd7) begin ph <= PH_ADDR; pc <= '0; end
                                else pc <= pc + 1'b1;
                            PH_ADDR:
                                if (pc == (addr_quad_r ? 26'd7 : 26'd23)) begin
                                    pc <= '0;
                                    ph <= (dummy_r != 0) ? PH_DUMMY : PH_DATA;
                                end else pc <= pc + 1'b1;
                            PH_DUMMY:
                                if (pc == 26'(dummy_r) - 1'b1) begin ph <= PH_DATA; pc <= '0; end
                                else pc <= pc + 1'b1;
                            PH_DATA:
                                if (pc == data_cycles - 1'b1) begin
                                    state    <= S_HOLD;
                                    wait_cnt <= '0;
                                end else pc <= pc + 1'b1;
                        endcase
                    end
                end

                S_HOLD: begin                     // CS hold after last SCK edge
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == 4'd3) begin
                        cs_q       <= 1'b0;
                        done_pulse <= 1'b1;
                        wait_cnt   <= '0;
                        state      <= S_GAP;
                    end
                end

                S_GAP: begin                      // minimum CS-high time
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == 4'd7) begin
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule