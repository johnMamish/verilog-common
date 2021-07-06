`timescale 1ns/100ps

/**
 * Implements a "keep it simple, stupid" uart transmitter which has one start bit, one stop bit, and
 * no parity.
 *
 * input  clock
 * input  reset
 * input  data_valid  This signal should be strobed high for one 'clock' cycle when new data is
 *                    available.
 *
 *
 * parameter  baud_divisor   Determines by how much 'clock' should be divided to generate the bit
 *                           clock. For instance, if 'clock' is 12MHz and baud_divisor is 104, the
 *                           baud rate for the uart will be 115,385bps.
 */
module uart_tx_kiss(input             clock,
	            input             reset,

                    input             data_valid,
                    input [7:0]       data,

	            output reg        uart_tx,
	            output reg        uart_busy);
    parameter baud_divisor = 104;
    localparam baud_counter_width = $clog2(baud_divisor - 1);
    reg [(baud_counter_width - 1):0] baud_counter;

    reg [9:0] shift_register;
    reg [3:0] shift_count;

    always @(posedge clock) begin
        if (reset) begin
            baud_counter <= 'h0;
            shift_register <= 9'hxxx;
            shift_count <= 4'h0;
            uart_tx <= 1'b1;
            uart_busy <= 1'b0;
        end else begin
            baud_counter <= (baud_counter == (baud_divisor - 1)) ? 'h0 : baud_counter + 'h1;

            if (uart_busy) begin
                if (shift_count == 4'd10) begin
                    shift_register <= 10'hxxx;
                    shift_count <= 4'h0;
                    uart_busy <= 1'b0;
                    uart_tx <= uart_tx;
                end else begin
                    if (baud_counter == (baud_divisor - 1)) begin
                        shift_register <= { 1'b0, shift_register[9:1] };
                        shift_count <= shift_count + 4'h1;
                        uart_busy <= 1'b1;
                        uart_tx <= shift_register[0];
                    end else begin
                        shift_register <= shift_register;
                        shift_count <= shift_count;
                        uart_busy <= uart_busy;
                        uart_tx <= uart_tx;
                    end
                end
            end else begin
                uart_tx <= 1'b1;
                if (data_valid) begin
                    shift_register <= { 1'b1, data, 1'b0 };
                    shift_count <= 4'h0;
                    uart_busy <= 1'b1;
                end else begin
                    shift_register <= shift_register;
                    shift_count <= shift_count;
                    uart_busy <= uart_busy;
                end
            end
        end
    end
endmodule
