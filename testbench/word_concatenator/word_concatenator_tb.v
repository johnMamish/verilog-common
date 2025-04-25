`timescale 1ns/100ps

module word_concatenator_tb();
    logic clock;
    logic reset;

    logic [7:0] data_i;
    logic data_valid_i;
    logic [31:0] accumulated_data_o;
    logic accumulated_data_valid_o;
    word_concatenator dut(
        .clk_i(clock), .reset_i(reset),
        .data_i, .data_valid_i,
        .accumulated_data_o, .accumulated_data_valid_o
    );
    defparam dut.INPUT_WIDTH = 8;
    defparam dut.NUM_WORDS_TO_CONCAT = 4;
    defparam dut.ENDIAN = "little";

    // generate clock
    always begin
        clock = 1'b0; #50; clock = 1'b1; #50;
    end

    integer i, j, randdelay;
    initial begin
        $dumpfile("word_concatenator_tb.vcd");
        $dumpvars(0, word_concatenator_tb);

        // hold reset high for a few clock cycles
        data_i <= 1'b0;
        reset <= #1 1'b1;
        @(posedge clock);  @(posedge clock); @(posedge clock);
        reset <= #1 1'b0;

        // just run it for a while and
        for (i = 0; i < 10000; i = i + 1) begin
            if (($random % 8) < 6) begin
                data_i <= data_i + 1;
                data_valid_i <= 1;
            end else begin
                data_valid_i <= 0;
            end

            @(posedge clock);
        end

        $finish;
    end

endmodule
