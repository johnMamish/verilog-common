`timescale 1ns/100ps

/**
 * USING THIS MODULE TO DIVIDE A CLOCK IS ALMOST CERTAINLY A BAD IDEA.
 *
 * Generates a clock signal using synchonous logic. Note that you wouldn't want to try and have the
 * output controlled directly by combinational logic because glitching could result in extra edges
 * before the output settles.
 *
 * Note that even with synchronous logic, generating clocks using verilog like this isn't smart
 * for a few reasons:
 *   1. Your synthesis tool isn't guaranteed to recognize the output of this module as a clock
 *      and therefore may treat it inappropriately. Synthesis tools often treat clock signals as
 *      special and different from other signals in a design.
 *   2. Your synthesis tool may not (and probably won't) know what the output frequency of this
 *      module is and so won't be able to determine whether your design passes at the output
 *      frequency of this module.
 *   3. This module will introduce an unknown and uncontrolled amount of skew, making clock domain
 *      crossing more difficult.
 */
module divide_by_n(input clk,
	           input reset,
	           output reg out);
    parameter N = 2;
    localparam cwidth = $clog2(N - 1);
    reg [cwidth - 1:0] counter;

    always @(posedge clk) begin
	if (reset) begin
	    counter <= N - 1;
            out <= 1'b0;
	end else begin
	    if (counter == 0) begin
	        counter <= N - 1;
	    end else begin
	        counter <= counter - 1;
            end

            out <= (counter < (N >> 1)) ? 1'b1 : 1'b0;
        end
    end
endmodule

/**
 * Holds a reset signal high for a configurable number of clock cycles after system initialization
 * restores all registers to value 0.
 */
module resetter(input      clock,
                output     reset);
    parameter count_maxval = 255;
    localparam count_width = $clog2(count_maxval);

    reg [count_width - 1:0] reset_count;
    assign reset = (reset_count == count_maxval) ? 1'b0 : 1'b1;
    initial reset_count = 'h0;

    always @(posedge clock) begin
        reset_count <= (reset_count == count_maxval) ? count_maxval : reset_count + 'h01;
    end
endmodule

/**
 * After its reset signal is released, holds 'pulse' low for "pulse_delay" clock cycles, then holds
 * "pulse" high for "pulse_width" cycles.
 *
 * input  clock      Clock signal driving this module
 * input  reset      Active high reset signal
 *
 * output pulse      Stays low until "pulse_delay" cycles have elapsed after reset has been released
 *
 * reset|  pulse_delay    pulse_width_____
 * _____V_________________|               |______....
 */
module pulse_one(input clock,
                 input reset,
                 output reg pulse);
    parameter pulse_delay = 511;
    parameter pulse_width = 15;
    localparam pulse_maxval = pulse_delay + pulse_width + 1;
    localparam pulse_bitwidth = $clog2(pulse_maxval);

    reg [pulse_bitwidth - 1 : 0] count;
    initial count = {{pulse_bitwidth{1'b0}}};

    always @(posedge clock) begin
        if (reset) begin
            count <= {{pulse_bitwidth{1'b0}}};
            pulse <= 1'b0;
        end else begin
            count <= (count == pulse_maxval) ? pulse_maxval : count + 'h01;
            pulse <= ((count > pulse_delay) && (count < pulse_maxval));
        end
    end
endmodule

/**
 * Converts a 4-bit hex digit to its ascii equivalent
 *
 * input: 4'd12, output: 8'd99 (ascii for 'c')
 */
module hexdigit(input [3:0] num, output reg [7:0] ascii);
    always @* begin
        if (num < 4'd10) begin
            ascii = {4'h0, num} + 8'h30;
        end else begin
            ascii = {4'h0, num} + 8'h57;
        end
    end
endmodule
