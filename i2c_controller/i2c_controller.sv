/**
 * Copyright (c) 2020, 2025 John Mamish and Julian Richey
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the “Software”), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/**
 * This file contains an i2c transmitter and a programmable controller that can actuate it.
 *
 * It can perform simple initializations, reads, and polling behavior with no microcontroller.
 */


/**
 * This 'i2c transmitter' sends a single i2c frame over the i2c bus. This transmitter is agnostic
 * to whether a frame contains a device address or device data.
 *
 * Each i2c frame can be programmed to have no end condition (the transmitter is ready for another
 * byte right away), a repeated start end condition, or a stop end condition.
 */
`define I2C_TRANSMITTER_END_CONDITION_NONE 2'b00
`define I2C_TRANSMITTER_END_CONDITION_REPEATED_START 2'b01
`define I2C_TRANSMITTER_END_CONDITION_STOP 2'b10

`define I2C_TRANSMITTER_MODE_WRITE 1'b0
`define I2C_TRANSMITTER_MODE_READ 1'b1

module i2c_transmitter #(
    parameter SCL_DIV = 60
)  (
    input clock_i,
    input reset_i,

    // Control bus //////////////////////////////
    // What type of transaction should this frame be? read or write?
    input frame_mode_i,

    // What end condition should we drive? none, repeated start, or stop?
    input [1:0] frame_end_condition_i,

    // This tells us whether we should ack the read or not
    input do_rd_ack_i,

    // What data should be transmitted?
    input [7:0] wr_data_i,

    // This input should be strobed when the i2c transmitter is to begin a new frame
    input start_frame_strobe_i,

    // This output tells whether the transmitter is ready to handle a new frame request.
    // nak_o is valid on the rising edge of ready_o. It will contain new information about a nak.
    output logic ready_o,

    // This output tells whether a nak was recieved during the most recent write.
    // it's only valid when the nak_in_valid_o strobe is high.
    output logic nak_in_o,
    output logic nak_in_valid_o,

    // Output bus for recieved data /////////////
    // read_data_o tells us what data has been read from the i2c device.
    output logic [7:0] read_data_o,

    // read_data_valid_o is strobed high for one clock cycle when read_data_o is valid.
    output logic read_data_valid_o,

    // i2c bus
    inout sda_io,
    inout scl_io
);

    reg sda, scl;
    assign sda_io = sda ? 1'bz : 1'b0;
    assign scl_io = scl ? 1'bz : 1'b0;

    // kind of hacky, but simple: rising and falling edge detection for divided clock
    logic [15:0] scl_counter;
    logic scl_freq, scl_freq_prev, scl_freq_rose, scl_freq_fell;
    always_ff @(posedge clock) begin
        // advance scl counter
        scl_counter <= scl_counter + 1;
        if (scl_counter == (SCL_DIV - 1)) begin
            scl_counter <= 0;
        end

        // detect where we should put rising and falling edges
        {scl_freq_rose, scl_freq_fell} <= '0;
        if (scl_counter == 0) scl_freq_fell <= 1;
        if (scl_counter == (SCL_DIV >> 1)) scl_freq_rose <= 1;

        if (reset) scl_counter <= 0;
    end

    enum logic [2:0] {
        IDLE=0,
        PRE_START_COND=1,
        START_COND=2,
        TX_FRAME = 3,
        RX_FRAME = 4,
        TERMINATE_REGULAR_COND = 5,
        TERMINATE_RS_COND = 6,
        TERMINATE_STOP_COND = 7
    } state;

    logic frame_mode_latch;
    logic [1:0] frame_end_condition_latch;
    logic do_rd_ack_latch;
    logic [7:0] wr_data_latch;
    logic [7:0] rd_data_latch;
    logic start_cond_needed;

    always_ff @(posedge clock) begin
        // These output strobes are always low except for the 1 cycle when they're used.
        nak_in_valid_o <= 0;
        read_data_valid_o <= 0;

        case (state)
            IDLE: begin
                scl <= start_cond_needed ? '1 : '0;
                ready <= '1;

                // latch settings for this frame.
                frame_mode_latch <= frame_mode_i;
                frame_end_condition_latch <= frame_end_condition_i;
                do_rd_ack_latch <= do_rd_ack_i;
                wr_data_latch <= wr_data_i;

                // start transmitting if the user requested it
                if (start_frame_strobe_i) begin
                    ready_o <= '0;
                    state <= PRE_START_COND;
                end
            end

            PRE_START_COND: begin
                // we need to wait until the scl serial clock has had a falling edge before we
                // move to the next state.
                if (scl_freq_fell) state <= START_COND;
            end

            START_COND: begin
                // on rising edge of scl serial clock, we bring sda low and advance to the next state.
                if (scl_freq_rose) begin
                    sda <= '0;
                    //if (frame_mode_i == `I2C_TRANSMITTER_MODE_WRITE) state <= TX_FRAME;
                    //if (frame_mode_i == `I2C_TRANSMITTER_MODE_READ) state <= RX_FRAME;
                    state <= TXRX_FRAME;
                    bit_addr <= '0;
                end
            end

            TXRX_FRAME: begin
                logic in_rx_mode;
                in_rx_mode = (frame_mode_latch == `I2C_TRANSMITTER_MODE_READ);
                if (scl_freq_fell) begin
                    // bring scl low and advance the bit address
                    scl <= '0;
                    bit_addr <= bit_addr + 1;

                    if (bit_addr == 4'h8) begin
                        // allow NAK to happen, unless we are in rx mode and we want to ack it.
                        sda <= 1'b1;
                        if (in_rx_mode && do_rd_ack_latch) sda <= 1'b0;

                        // If we're in rx mode, we can output the accumulated data now
                        if (in_rx_mode) begin
                            read_data_o <= rd_data_latch;
                            read_data_valid_o <= '1;
                        end
                    end else begin
                        if (in_rx_mode) sda <= '1;
                        else sda <= wr_data_latch[7 - bit_addr];
                    end
                end

                if (scl_freq_rose) begin
                    scl <= '1;

                    if (bit_addr == 4'h9) begin
                        // If we're in tx mode, sample nak.
                        if (!in_rx_mode) {nak_in_o, nak_in_valid_o} <= {sda, 1'b1};

                        // Done transmitting, terminate the frame.
                        case (frame_end_condition_latch)
                            `I2C_TRANSMITTER_END_CONDITION_NONE: state <= TERMINATE_REGULAR_COND;
                            `I2C_TRANSMITTER_END_CONDITION_REPEATED_START: state <= TERMINATE_RS_COND;
                            `I2C_TRANSMITTER_END_CONDITION_STOP: state <= TERMINATE_STOP_COND;
                        endcase
                        bit_addr <= '0;
                    end else begin
                        // If we're reading data, shift it into the latch
                        if (in_rx_mode) rd_data_latch[7 - bit_addr] <= sda;
                    end
                end
            end

            TERMINATE_REGULAR_COND: begin
                // just wait for one clock cycle with SDA high
                scl <= '0;
                sda <= '1;

                if (scl_freq_fell) begin
                    bit_addr <= bit_addr + 1;
                end

                if (scl_freq_rose) begin
                    start_cond_needed <= '0;
                    bit_addr <= 0;
                    state <= IDLE;
                end
            end

            TERMINATE_RS_COND: begin
                // Need to generate a repeated start.
                if (scl_freq_fell) begin
                    bit_addr <= bit_addr + 1;

                    sda <= (bit_addr >= 1) ? '1 : '0;
                    scl <= (bit_addr >= 2) ? '1 : '0;
                end

                if (scl_freq_rose) begin
                    if (bit_addr == 2) begin
                        start_cond_needed <= '1;
                        state <= IDLE;
                        ready <= '1;
                    end
                end
            end

            TERMINATE_STOP_COND: begin
                // generate a stop condition.
                if (scl_freq_fell) begin
                    bit_addr <= bit_addr + 1;

                    if (bit_addr == 0) scl <= '0;
                    sda <= (bit_addr >= 2) ? '1 : '0;
                end

                if (scl_freq_rose) begin
                    scl <= '1;

                    if (bit_addr == 2) begin
                        start_cond_needed <= '1;
                        state <= IDLE;
                        ready <= '1;
                        sda <= '1;
                    end
                end
            end
        endcase // case (state)

        if (reset) begin
            state <= IDLE;
            sda <= '1;
            scl <= '1;
            start_cond_needed <= '1;
        end
    end
endmodule


/**
 * Sends a bunch of i2c write requests.
 *
 * Instruction encoding (all instrs are 16b and presented in big endian. Some instrs have args which
 * also must be padded to 16b):
 *
 * i2c frame transfer
 * wait until i2c controller is ready, then immediately read or write an i2c frame.
 *     0000 abcc LEN[7:0] <data> <data> .... <data>
 *  a  - if this is a 'read', and 'a' is 1, then we cap off the last frame with a nak.
 *  b  - if a is '0', the frame is a write. If a is '1', then the frame is a read.
 *  cc - determines the end condition:
 *      bb = 2'b00: no end condition
 *      bb = 2'b01: repeated start
 *      bb = 2'b10: stop
 *  LEN[7:0] how many 8b words of data should be transferred?
 *
 * This instruction should be followed by words of data to transfer. The words must be padded to 16b.
 *
 * set read tag
 * Each time a byte is yielded from a read, an associated tag is also presented so that the gateware
 * which reads the tag knows which read yields the byte. After each read, the tag is incremented.
 * This instruction sets the value of the read tag.
 *     0001 ARG[11:0]
 *
 * const delay
 * delay for 2^ARG2 * ARG1 clock cycles
 *     0100 ARG2[3:0] ARG1[11:0]
 *
 * wait for trigger input from external signal, then advance to next instruction
 *     0101 llll llhh hhhh
 *
 * The trigger signals are a bitmask; setting the corresponding bit in 'hh' waits for a high
 * signal on the corresponding bit. Setting the bit in 'll' waits for a low signal on the
 * corresponding bit.
 *
 * for instance, the following waits for a low signal on input 3.
 *     0101 0010 0000 0000
 *
 * And the following sequence of 2 instructions waits for a falling edge on signal 5
 *     0101 0000 0010 0000   // wait for signal 5 to go high
 *     0101 1000 0000 0000   // wait for signal 5 to go low
 *
 * Write trigger outputs to lsbits value.
 * This can be used to indicate to other modules that a certain event has passed in the i2c
 * controller (e.g. initialization has completed).
 *     0110 xxxx xxtt tttt
 *
 * jump to address ARG immediately
 *     1000 ARG[11:0]
 *
 * relative jump to pc + (signed ARG[11:0]) immediately
 *     1001 ARG[11:0]
 *
 * branch not-equal
 * relative jump to pc + (signed ARG[11:0])
 * this instruction branches if the most recently read i2c byte does not match the bitmask specified
 * by ll hh
 *     1010 ARG[11:0] llll llll hhhh hhhh
 *
 *
 */
module i2c_transmitter_controller #(
    parameter INITIAL_DEV_ID = 7'h35,
    parameter MEM_NUM_WORDS = 512,
    parameter INIT_FILE = "i2c_initializer.hex"
)  (
    input clock,
    input reset,

    // control bus to i2c transmitter //////////////////////////
    // See port documentation for 'i2c_transmitter' for info on ports.
    output logic frame_mode_o,
    output logic [1:0] frame_end_condition_o,
    output logic do_rd_ack_o,
    output logic [7:0] wr_data_o,
    output logic start_frame_strobe_o,
    input i2c_transmitter_ready_i,

    input nak_in_i,
    input nak_in_valid_i,

    // results of read data
    input [7:0] transmitter_read_data_i,
    input transmitter_read_data_valid_i,

    // outputs the most recently read byte from the i2c alongside a tag.
    output logic [11:0] read_tag_o,
    output logic [7:0] read_data_o,
    output logic read_data_valid_o,

    // Trigger i/os
    output logic [5:0] trigger_o,
    input [5:0] trigger_i
);
    reg [15:0] mem [MEM_NUM_WORDS];

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    ////////////////////////////////////////////////////////////////
    // opcodes
    localparam logic [3:0] OPCODE_XFER = 4'b0000;

    localparam logic [3:0] OPCODE_WAIT = 4'b0100;
    localparam logic [3:0] OPCODE_TRIG = 4'b0101;
    localparam logic [3:0] OPCODE_OUTPUT_TRIG = 4'b0110;

    localparam logic [3:0] OPCODE_JMP = 4'b1000;
    localparam logic [3:0] OPCODE_JMP_RELATIVE = 4'b1001;
    localparam logic [3:0] OPCODE_JMP_COND = 4'b1010;

    ////////////////////////////////////////////////////////////////
    // state variables
    signed logic [11:0] pc;
    logic [15:0] ir;
    logic [31:0] arg;
    logic [7:0] arg_count;
    logic [23:0] cycle_count;

    enum logic [3:0] {
        FETCH=0,
        DECODE=1,
        XFER_FETCH=2,
        XFER_EX=3,
        COND_BRANCH_EX=4
    } state;

    // latch the trigger signals to provide a little timing slack
    logic [5:0] trigger_signals;

    always_ff @(posedge clock) begin
        data_valid_o <= '0;
        rw_bit_o <= '0;
        trigger_signals <= trigger_i;

        cycle_count <= cycle_count + 1;
        case (state)
            FETCH: begin
                ir <= mem[pc];
                pc <= pc + 1;
                state <= DECODE;
                cycle_count <= '0;
            end

            DECODE: begin
                case (ir[12 +: 4])
                    OPCODE_XFER: begin
                        // set up the args that will remain 'constant'
                        if (ir[10] == 0) frame_mode_o <= `I2C_TRANSMITTER_MODE_WRITE;
                        else frame_mode_o <= `I2C_TRANSMITTER_MODE_READ;

                        // just go directly to the XFER_FETCH stage
                        arg_count <= 0;
                        state <= XFER_FETCH;
                    end

                    OPCODE_WAIT: begin
                        if (cycle_count == 0) arg <= ir[0 +: 8] << ir [8 +: 4];
                        if ((cycle_count == arg) || (arg == 0)) state <= FETCH;
                    end

                    OPCODE_TRIG: begin
                        logic high_sig_detected;
                        logic low_sig_detected;
                        high_sig_detected = |(ir[0 +: 6] & trigger_signals);
                        low_sig_detected = |(ir[6 +: 6] & ~trigger_signals);
                        if (high_sig_detected || low_sig_detected) begin
                            state <= FETCH;
                        end
                    end

                    OPCODE_OUTPUT_TRIG: begin
                        trigger_o <= ir[0 +: 6];
                        state <= FETCH;
                    end

                    OPCODE_JMP_RELATIVE: begin
                        pc <= signed'(pc) + signed'(ir[0 +: 12]);
                        state <= FETCH;
                    end

                    OPCODE_JMP: begin
                        pc <= ir[0 +: 12];
                        state <= FETCH;
                    end

                    OPCODE_JMP_COND: begin
                        if (i2c_transmitter_ready) begin
                            // need to wait until the i2c transmitter isn't busy, otherwise we
                            // may not have rx'd the data that we need.
                            // check bitmask against rx'd byte
                            arg <= mem[pc];
                            pc <= pc + 1;
                        end
                    end

                    default: begin
                        state <= FETCH;
                    end
                endcase
            end

            XFER_FETCH: begin
                arg <= mem[pc];
                pc <= pc + 1;
                state <= XFER_EX;
            end

            XFER_EX: begin
                start_frame_strobe_o <= 0;

                if (i2c_transmitter_ready_i) begin
                    // initiate a new xfer
                    if ((arg_count + 1) == ir[0 +: 8]) begin
                        case (ir[8 +: 2])
                            2'b00: frame_end_condition_o <= `I2C_TRANSMITTER_END_CONDITION_NONE;
                            2'b01: frame_end_condition_o <= `I2C_TRANSMITTER_END_CONDITION_REPEATED_START;
                            2'b10: frame_end_condition_o <= `I2C_TRANSMITTER_END_CONDITION_STOP;
                        endcase
                        do_rd_ack_o <= 0;
                    end else begin
                        frame_end_condition_o <= `I2C_TRANSMITTER_END_CONDITION_NONE;
                        do_rd_ack_o <= 1;
                    end

                    wr_data_o <= arg_count[0] ? arg[8 +: 8] : arg[0 +: 8];
                    start_frame_strobe_o <= 1;

                    // advance to the next argument and re-fetch if needed.
                    arg_count <= arg_count + 1;
                    if ((arg_count + 1) == ir[0 +: 8]) state <= FETCH;
                    else if (arg_count[0] == '1) state <= XFER_FETCH;
                    else state <= XFER_EX;
                end
            end

            COND_BRANCH_EX: begin
                logic high_bits_ok;
                logic low_bits_ok;
                high_bits_ok = &((read_data_o & arg[0 +: 8]) | ~arg[0 +: 8]);
                low_bits_ok  = &((~read_data_o & arg[8 +: 8]) | ~arg[8 +: 8]);
                if (!(high_bits_ok && low_bits_ok)) begin
                    pc <= signed'(pc) + signed'(ir[0 +: 12]);
                end else begin
                    // pc just advances normally.
                    // it's already advanced from the FETCH stage.
                end

                state <= FETCH;
            end
        endcase

        if (reset) begin
            pc <= 0;
            state <= FETCH;
            trigger_o <= 0;
        end
    end

    // We don't stall in the RX state to wait for the data to arrive.
    // This block latches the RX data when it's ready so it can be read off.
    always_ff @(posedge clk) begin
        read_data_valid_o <= 0;

        if (transmitter_read_data_valid_i) begin
            read_data_o <= transmitter_read_data_i;
            read_data_valid_o <= 1;
        end
    end
endmodule // i2c_transmitter_controller


/**
 * combination of the i2c transmitter and controller
 */
module i2c_controller #(
    parameter SCL_DIV = 60,
    parameter INITIAL_DEV_ID = 7'h35,
    parameter MEM_NUM_WORDS = 512,
    parameter INIT_FILE = "i2c_initializer.hex"
)  (
    input clk_i,
    input reset_i,

    // i2c output
    inout sda_io,
    inout scl_io,

    // outputs the most recently read byte from the i2c alongside a tag.
    output logic [15:0] read_tag_o,
    output logic [7:0] read_data_o,
    output logic nak_o,
    output logic read_data_valid_o,

    // Trigger i/os
    output logic [5:0] trigger_o,
    input [5:0] trigger_i
);

    // control bus between controller and transmitter
    wire frame_mode;
    wire [1:0] frame_end_condition;
    wire do_rd_ack;
    wire [7:0] wr_data;
    wire start_frame_strobe;
    wire i2c_transmitter_ready;

    wire nak_in;
    wire nak_in_valid;

    wire [7:0] transmitter_read_data;
    wire transmitter_read_data_valid;

    i2c_transmitter_controller controller (
        .clock(clk_i), .reset(reset_i),

        .frame_mode_o(frame_mode), .frame_end_condition_o(frame_end_condition),
        .do_rd_ack_o(do_rd_ack), .wr_data_o(wr_data), .start_frame_strobe_o(start_frame_strobe),
        .i2c_transmitter_ready_i(i2c_transmitter_ready),

        .nak_in_i(nak_in), .nak_in_valid_i(nak_in_valid),

        .transmitter_read_data_i(transmitter_read_data),
        .transmitter_read_data_valid_i(transmitter_read_data_valid),

        .read_tag_o, .read_data_o, .nak_o, .read_data_valid_o,
        .trigger_o, .trigger_i
    );
    defparam INITIAL_DEV_ID = INITIAL_DEV_ID;
    defparam MEM_NUM_WORDS = MEM_NUM_WORDS;
    defparam INIT_FILE = INIT_FILE;

    i2c_transmitter transmitter (
        .clock(clk_i), .reset(reset_i),

        .frame_mode_i(frame_mode), .frame_end_condition_i(frame_end_condition),
        .do_rd_ack_i(do_rd_ack), .wr_data_i(wr_data), .start_frame_strobe_i(start_frame_strobe),
        .ready_o(i2c_transmitter_ready),

        .nak_in_o(nak_in), .nak_in_valid_o(nak_in_valid),

        .read_data_o(transmitter_read_data), .read_data_valid_o(transmitter_read_data_valid),

        .sda_io, .scl_io
    );
    defparam transmitter.SCL_DIV = SCL_DIV;

endmodule
