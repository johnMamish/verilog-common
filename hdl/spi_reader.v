`timescale 1ns/100ps

`include "spi.v"

/**
 * This module is a very simple, programmable, SPI-bus controller. It can issue a sequence of
 * fixed commands to SPI bus devices and then read the resulting data into a system memory.
 *
 * TODO:
 *  - state change around spi_ready could be tightened up by 1-2 clock cycles.
 *  - make CPOL and CPHA configurable. Right now, we assume that CPOL=0 and CPHA=0.
 *
 * These are the clock and active-high reset for the module. This clock is just used to advance
 * internal logic; the output serial clock will always be a divided-down version of this clock.
 * input     clock
 * input     reset
 *
 * These are the SPI connections
 * output       mem_clk
 * output       mem_ps
 * output       mem_copi
 * input        mem_cipo
 *
 * These connections output the data read from the device on the SPI bus.
 * output [output_address_length]     write_address
 * output                             write_enable
 *
 * This output goes high when all data has been read.
 * output       done
 */
module spi_reader
  #(parameter output_address_length = 24)
    (input                   clock,
     input                   reset,

     output                  mem_clk,
     output reg              mem_ps,
     output                  mem_copi,
     input                   mem_cipo,

     output reg [(output_address_length - 1) : 0] write_address,
     output reg                                   write_enable,

     output reg              done);

    ////////////////////////////////////////////////
    // opcodes
    localparam SPI_READER_OPCODE_SET_PS    = 4'b0000;
    localparam SPI_READER_OPCODE_DONE      = 4'b0001;
    localparam SPI_READER_OPCODE_WRITE     = 4'b0101;
    localparam SPI_READER_OPCODE_READ      = 4'b0110;
    localparam SPI_READER_OPCODE_WRITEREAD = 4'b0111;

    ////////////////////////////////////////////////
    // "program" memory
    parameter num_states                   = 32;
    reg [35:0] commands [0:(num_states - 1)];
    initial begin
        // instruction length is 4 + 8 + 24 = 36?
        commands[ 0] = {SPI_READER_OPCODE_SET_PS, 8'h01, 24'd100};
        commands[ 1] = {SPI_READER_OPCODE_SET_PS, 8'h00, 24'd1000};
        commands[ 2] = {SPI_READER_OPCODE_WRITE,  8'ha5, 24'hxx_xxxx};
        commands[ 3] = {SPI_READER_OPCODE_SET_PS, 8'h00, 24'd1000};

        commands[ 4] = {SPI_READER_OPCODE_SET_PS, 8'h01, 24'd1000};
        commands[ 5] = {SPI_READER_OPCODE_SET_PS, 8'h00, 24'h0};
        commands[ 6] = {SPI_READER_OPCODE_WRITE,  8'hb5, 24'd0};
        commands[ 7] = {SPI_READER_OPCODE_WRITE,  8'h02, 24'd0};
        commands[ 8] = {SPI_READER_OPCODE_WRITE,  8'h00, 24'd0};
        commands[ 9] = {SPI_READER_OPCODE_WRITE,  8'h00, 24'd0};
        commands[10] = {SPI_READER_OPCODE_SET_PS, 8'h01, 24'd100};

        commands[11] = {SPI_READER_OPCODE_SET_PS, 8'h00, 24'd100};
        commands[12] = {SPI_READER_OPCODE_READ,   8'hxx, 24'd76799};
        commands[13] = {SPI_READER_OPCODE_SET_PS, 8'h01, 24'd100};

        commands[14] = {SPI_READER_OPCODE_DONE,   8'hxx, 24'hxx_xxxx};
    end

    ////////////////////////////////////////////////
    // state variables
    reg [($clog2(num_states) - 1) : 0]    state_pointer;
    reg [(output_address_length - 1) : 0] state_counter;
    reg [35:0] command;

    ////////////////////////////////////////////////
    // spi transmitter
    reg [7:0] spi_txdata;
    reg spi_data_valid;

    wire spi_ready;
    wire [7:0] spi_rxdata;
    spi s(.clock(clock), .reset(reset),
          .ready(spi_ready), .tx_data(spi_txdata), .data_valid(spi_data_valid), .rx_data(spi_rxdata),
          .mem_clk(mem_clk), .mem_copi(mem_copi), .mem_cipo(mem_cipo));

    always @(posedge clock) begin
        if (reset) begin
            spi_txdata <= 8'hxx;
            spi_data_valid <= 0;

            command <= commands[0];
            state_pointer <= 0;
            state_counter <= 0;

            mem_ps <= 0;

            write_address <= 0;
            write_enable <= 0;
            done <= 0;
        end else begin
            case(command[35-:4])
                SPI_READER_OPCODE_SET_PS: begin
                    mem_ps <= command[24];

                    if (state_counter >= command[23:0]) begin
                        command <= commands[state_pointer + 1];
                        state_pointer <= state_pointer + 1;
                        state_counter <= 0;
                    end else begin
                        state_counter <= state_counter + 1;
                    end
                end

                SPI_READER_OPCODE_DONE: begin
                    spi_txdata <= 8'hxx;
                    spi_data_valid <= 0;

                    command <= command;
                    state_pointer <= 0;
                    state_counter <= 0;

                    mem_ps <= mem_ps;

                    write_address <= 0;
                    write_enable <= 0;
                    done <= 1;
                end

                SPI_READER_OPCODE_WRITE: begin
                    spi_txdata <= command[24+:8];

                    write_address <= 0;
                    write_enable <= 0;
                    done <= 0;

                    if (spi_ready) begin
                        if (state_counter < command[0+:24]) begin
                            spi_data_valid <= 1;
                            write_enable <= 1;
                        end else if (state_counter == command[0+:24])begin
                            // advance state
                            command <= commands[state_pointer + 1];
                            state_pointer <= state_pointer + 1;
                            state_counter <= 0;
                        end
                    end else begin
                        write_enable <= 0;
                    end
                end

                SPI_READER_OPCODE_READ: begin

                end

                SPI_READER_OPCODE_WRITEREAD: begin

                end

                default: begin
                    spi_txdata <= 8'hxx;
                    spi_data_valid <= 0;

                    command <= commands[0];
                    state_pointer <= 0;
                    state_counter <= 0;

                    mem_ps <= 0;

                    write_address <= 0;
                    write_enable <= 0;
                    done <= 0;
                end
            endcase
        end

    end
endmodule
