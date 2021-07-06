`timescale 1ns/100ps

module uart_tx_kiss_tb();
    reg clock;
    reg reset;

    reg data_valid;
    reg [7:0] data;

    wire uart_tx;
    wire uart_busy;

    uart_tx_kiss utx(.clock(clock),
                     .reset(reset),

                     .data_valid(data_valid),
                     .data(data),

                     .uart_tx(uart_tx),
                     .uart_busy(uart_busy));
    defparam utx.baud_divisor = 4;

    // generate clock
    always begin
        clock = 1'b0; #500; clock = 1'b1; #500;
    end

    integer i, j, randdelay;
    initial begin
        $dumpfile("uart_tx_kiss_tb.vcd");
        $dumpvars(0, uart_tx_kiss_tb);

        // hold reset high for a few clock cycles
        reset = 1'b1;
        data_valid = 1'b0;
        data = 'hxx;
        @(posedge clock);  @(posedge clock); @(posedge clock);
        reset = 1'b0;

        // Just count from 0 to 255 with random interbyte delays.
        // This testbench is only a sanity check for manual inspection.
        for (i = 0; i < 256; i = i + 1) begin
            // clock data in
            data_valid = #1 1'b1;
            data = #1 i;

            @(posedge clock);

            data_valid = #1 1'b0;
            data = #1 'hxx;

            while (uart_busy) begin
                @(posedge clock);
            end


            // wait for either 0 cycles or quite a few cycles
            randdelay = ($random % 2) * 100;
            for (j = 0; j < randdelay; j = j + 1) @(posedge clock);
        end

        $finish;
    end

endmodule
