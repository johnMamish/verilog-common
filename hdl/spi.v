`timescale 1ns/100ps

/**
 * ready      - this line goes high when the shifter is ready to accept new data
 * tx_data    - this should be used to write the data that is to be transmitted.
 * data_valid - for each cycle where "ready" is high, this line being high signals that
 *              there is new data to be transmitted on tx_data.
 * rx_data    -
 */
module spi(input                      clock,
           input                      reset,

           // internal interface
           output reg                 ready,
           input [7:0]                tx_data,
           input                      data_valid,
           output reg [7:0]           rx_data,

           // external interface
           output reg                 mem_clk,
           output reg                 mem_copi,
           input                      mem_cipo);
    localparam clock_prescale = 'd1;

    localparam STATE_IDLE = 0;
    localparam STATE_TRANSMITTING = 1;

    reg state;

    reg [2:0] bitcount;
    reg [7:0] clockdiv;

    reg [7:0] tx_reg;
    reg [7:0] rx_reg;

    reg ready_internal;

    always @* begin
        // WARNING: this output is derived from combinational logic involving an input. There is
        // high risk for generating an inferred latch when working with this output.
        ready = !data_valid && ready_internal;
    end

    always @(posedge clock) begin
        if (reset) begin
            rx_reg <= 8'hxx;
            rx_data <= 8'hxx;
            tx_reg <= 8'hxx;

            bitcount <= 'h0;
            clockdiv <= 'h0;

            ready_internal <= 1'b1;

            mem_clk <= 1'b0;
            mem_copi <= 1'b0;

            state <= STATE_IDLE;
        end else begin
            clockdiv <= (clockdiv == (clock_prescale - 1)) ? 'h0 : clockdiv + 'h1;

            case (state)
                STATE_IDLE: begin
                    if (data_valid) begin
                        // initiate a transfer
                        state <= STATE_TRANSMITTING;
                        bitcount <= 3'd7;
                        ready_internal <= 1'b0;
                        rx_data <= rx_reg;
                        rx_reg <= rx_reg;

                        mem_clk <= 1'b0;
                        mem_copi <= 1'bx;

                        mem_copi <= tx_data[7];
                        tx_reg <= {tx_data[6:0], 1'bx};
                    end else begin
                        state <= STATE_IDLE;
                        bitcount <= 3'd7;
                        ready_internal <= 1'b1;
                        tx_reg <= 8'hxx;
                        rx_data <= rx_reg;
                        rx_reg <= rx_reg;

                        mem_clk <= 1'b0;
                        mem_copi <= 1'bx;
                    end
                end

                STATE_TRANSMITTING: begin
                    if (clockdiv == (clock_prescale - 1)) begin
                        mem_clk <= ~mem_clk;

                        if (mem_clk == 1'b1) begin
                            // shift out one msb on falling edge of mem_clk
                            mem_copi <= tx_reg[7];
                            tx_reg <= {tx_reg[6:0], 1'bx};

                            if (bitcount == 'h7) begin
                                state <= STATE_IDLE;
                                ready_internal <= 1'b1;
                            end else begin
                                state <= STATE_TRANSMITTING;
                                ready_internal <= 1'b0;
                            end
                        end else begin
                            // shift in one lsb and advance state on rising edge of mem_clk
                            rx_reg <= {rx_reg[6:0], mem_cipo};

                            bitcount <= bitcount - 'h1;
                            state <= STATE_TRANSMITTING;
                        end
                    end else begin
                        state <= STATE_TRANSMITTING;
                        bitcount <= bitcount;
                        ready_internal <= 1'b0;

                        mem_clk <= mem_clk;
                    end
                end
            endcase
        end
    end
endmodule
