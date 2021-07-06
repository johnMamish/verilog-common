`timescale 1ns/100ps

/**
 * Implements an i2s controller.
 *
 * input  clock      Digital clock that drives this module
 * input  reset      Active-high reset signal
 * output data_valid Strobe that indicates when there is valid data on 'data_out' that must be read.
 *                   Failure to read data out on the same cycle that 'data_valid' is high will
 *                   result in dropped data.
 * output data_out_0 Port from which i2s data for lrck = 0 phase is to be read by other FPGA
 *                   circuitry.
 * output data_out_1 Same as data_out_0, but for lrck = 1 phase.
 * input  i2s_data   Reads the data line of the i2s bus.
 * output bck        Drives the bitclock line of the i2s bus.
 * output lrck       Drives the lrck line of the i2s bus.
 *
 * parameter bits_per_word    Number of bits in each lrck
 * parameter bck_divisor      Amount by which to divide 'clock' to get bck. Must be at least 2 and
 *                            must be even.
 */
module i2s_controller
  #(parameter bits_per_word = 32,
    parameter bck_divisor = 4)
    (input      clock,
     input      reset,

     // outputs to rest of FPGA system
     output reg                           data_valid,
     output reg [(bits_per_word - 1) : 0] data_out_0,
     output reg [(bits_per_word - 1) : 0] data_out_1,

     // inputs from i2s peripheral
     input      i2s_data,

     // outputs to i2s peripheral
     output reg bck,
     output reg lrck);

    localparam bck_divisor_even  = (bck_divisor >> 1) << 1;
    localparam bck_counter_width = $clog2(bck_divisor_even - 1);
    reg [(bck_counter_width - 1):0] bck_counter;

    // Keeps track of how many bits have been read in for this cycle of lrck.
    // This counter is incremented on falling edges of bck.
    localparam bits_per_frame = bits_per_word * 2;
    localparam lrck_counter_width = $clog2(bits_per_frame - 1);
    reg [(lrck_counter_width - 1):0] lrck_bitcounter;

    always @(posedge clock) begin
        if (reset) begin
            data_valid <= 'h0;
            data_out_0 <= 'h0;
            data_out_1 <= 'h0;

            bck <= 'b0;
            lrck <= 'b0;

            bck_counter <= 'h0;
            lrck_bitcounter <= 'h0;
        end else begin
            if (bck_counter == (bck_divisor_even - 1)) begin
                // bitclock rising edge
                data_valid <= 'h0;

                // clock a bit into the data_out register
                if (lrck_bitcounter < bits_per_word) begin
                    data_out_0 <= {data_out_0, i2s_data};
                    data_out_1 <= data_out_1;
                end else begin
                    data_out_0 <= data_out_0;
                    data_out_1 <= {data_out_1, i2s_data};
                end

                bck <= 1'b1;
                lrck <= lrck;

                bck_counter <= 'h0;
                lrck_bitcounter <= lrck_bitcounter;
            end else if (bck_counter == (bck_divisor_even >> 1) - 1) begin
                // bitclock falling edge
                // data becomes valid for a single clock cycle when entire frame has been read.
                data_valid <= (lrck_bitcounter == (bits_per_frame - 1)) ? 'b1 : 'b0;

                data_out_0 <= data_out_0;
                data_out_1 <= data_out_1;

                bck <= 1'b0;

                if (lrck_bitcounter == (bits_per_frame - 2)) begin
                    lrck <= 1'b0;
                end else if (lrck_bitcounter == (bits_per_frame >> 1) - 2) begin
                    lrck <= 1'b1;
                end else begin
                    lrck <= lrck;
                end

                bck_counter <= bck_counter + 'h1;
                lrck_bitcounter <= (lrck_bitcounter == (bits_per_frame - 1)) ?
                                   'h0 : lrck_bitcounter + 1;
            end else begin
                data_valid <= 1'b0;

                data_out_0 <= data_out_0;
                data_out_1 <= data_out_1;

                bck <= bck;
                lrck <= lrck;

                bck_counter <= bck_counter + 'h1;
                lrck_bitcounter <= lrck_bitcounter;
            end

        end
    end
endmodule
