`timescale 1ns/100ps

module i2s_controller_tb();
    reg clock;
    reg reset;

    reg data_in;

    wire data_valid;
    wire [31:0] data;

    wire bck, lrck;

    i2s_controller i2s_controller(.clock(clock),
            .reset(reset),

            .data_valid(data_valid),
            .data_out_0(data),
            .data_out_1(),

            .i2s_data(data_in),

            .bck(bck),
            .lrck(lrck));

    defparam i2s_controller.bck_divisor = 20;

    // generate clock
    always begin
        clock = 1'b0; #50; clock = 1'b1; #50;
    end

    // simulate an i2s peripheral device listening on lrck phase 0
    reg [31:0] data_in_reg = 0;
    reg [5:0] bitcnt;
    reg lrck_prev;
    always @(posedge bck) begin
        lrck_prev <= #1 lrck;
        if (lrck == 0) begin
            data_in <= #1 data_in_reg[31 - bitcnt];
            bitcnt <= #1 bitcnt + 1;
        end else begin
            if (lrck_prev == 0) begin
                data_in_reg <= #1 data_in_reg + 1;
            end else begin
                data_in_reg <= #1 data_in_reg;
            end

            data_in <= #1 1'bz;
            bitcnt <= #1 'h0;
        end
    end



    integer i, j, randdelay;
    initial begin
        $dumpfile("i2s_controller_tb.vcd");
        $dumpvars(0, i2s_controller_tb);

        // hold reset high for a few clock cycles
        data_in <= 1'b0;
        reset <= #1 1'b1;
        @(posedge clock);  @(posedge clock); @(posedge clock);
        reset <= #1 1'b0;

        // just run it for 64 frames and see what it does.
        for (i = 0; i < 100000; i = i + 1) begin
            // loop lrck back into data_in for sanity checking.
            @(posedge clock);
        end

        $finish;
    end

endmodule
