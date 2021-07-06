/**
 * Copyright John Mamish and Julian Richey, 2021
 *
 * This module is an i2c peripheral which accepts i2c connections and turns them into parallel
 * memory writes for EBRs.
 *
 * Each i2c message is expected to contain
 *     <i2c start condition>
 *     1 Byte:        peripheral address (read/!write bit assumed to be 0)
 *     1 Byte:        memory address
 *     1 - 255 Bytes: data
 *     <i2c stop condition>
 *
 * Note that there is NO stop or restart condition between the memory address and the data being
 * sent. One can optionally be added.
 *
 * TODO: expand 'memory address' phase to N bytes.
 */

`timescale 1ns/100ps

module i2c_memory_writer_peripheral(input            clock,
                                    input            reset,

                                    input            copi_scl,
                                    input            copi_sda,
                                    output           cipo_scl, //not doing any stretching
                                    output reg       cipo_sda,

                                    output reg       ebr_select,
                                    output reg       ebr_wren,
                                    output reg [7:0] ebr_data_out,
                                    output reg [7:0] ebr_addr_out);
    parameter device_address = 8'hfe;

    // wait here. When a start condition is detected, goto STATE_DEVADDR.
    localparam STATE_IDLE = 2'h0;

    // Read in peripheral device address.
    // If the read byte matches parameter device_address, send an ack and goto STATE_EBRADDR.
    // If a start condition is detected, reset state and goto STATE_DEVADDR.
    // If a stop condition is detected, goto STATE_IDLE.
    // otherwise, goto STATE_IDLE.
    localparam STATE_DEVADDR = 2'h1;

    // Read in memory address that we want to write to.
    // Once we've read 2 bytes, ack and goto STATE_FILL
    // If a start condition is detected, reset state and goto STATE_DEVADDR.
    // If a stop condition is detected, goto STATE_IDLE.
    localparam STATE_EBRADDR = 2'h2;

    // Read in bytes.
    // If a start condition is detected, goto STATE_DEVADDR
    // If a stop condition is detected, goto STATE_IDLE
    localparam STATE_FILL = 2'h3;

    assign cipo_scl = 1'b1;
    reg cipo_sda_next;
    reg ebr_select_next;
    reg ebr_wren_next;
    reg [7:0] ebr_data_out_next;
    reg [7:0] devaddr, devaddr_next;
    reg [7:0] ebr_addr_out_next;

    reg [1:0] state;
    reg [1:0] state_next;
    reg [3:0] counter;
    reg [3:0] counter_next;
    reg sda; //sample copi_sda
    reg sda_next;
    reg scl; //sample copi_scl
    reg scl_next;

    always @(posedge clock) begin
        cipo_sda <= cipo_sda_next;
        ebr_select <= ebr_select_next;
        ebr_wren <= ebr_wren_next;
        devaddr <= devaddr_next;
        ebr_addr_out <= ebr_addr_out_next;
        ebr_data_out <= ebr_data_out_next;

        state <= state_next;
        counter <= counter_next;

        sda <= sda_next;
        scl <= scl_next;
    end


    always @* begin
        //defaults:
        cipo_sda_next = cipo_sda;
        ebr_select_next = ebr_select;
        ebr_wren_next = 1'b0;
        devaddr_next = 8'hxx;
        ebr_addr_out_next = ebr_addr_out;
        ebr_data_out_next = ebr_data_out;

        state_next = state;
        counter_next = counter;

        sda_next = copi_sda;
        scl_next = copi_scl;

        if (reset) begin
            cipo_sda_next = 1'b1;
            ebr_select_next = 1'bx;
            devaddr_next = 8'hxx;
            ebr_addr_out_next = 8'hxx;
            ebr_data_out_next = 8'hxx;

            state_next = STATE_IDLE;
            counter_next = 4'h0;
        end else if (scl_next == 1'b1 && scl == 1'b1 && sda_next == 1'b0 && sda == 1'b1) begin
            // sda falling edge while scl high: start condition detected
            cipo_sda_next = 1'b1;
            ebr_select_next = 1'bx;
            ebr_data_out_next = 8'h00; //00 bc < | data_out> used

            state_next = STATE_DEVADDR;
            counter_next = 4'h0;
        end else if (scl_next == 1'b1 && scl == 1'b1 && sda_next == 1'b1 && sda == 1'b0) begin
            // sda rising edge while scl high: stop condition detected
            cipo_sda_next = 1'b1;
            ebr_select_next = 1'bx;
            ebr_data_out_next = 8'hxx;

            state_next = STATE_IDLE;
            counter_next = 4'h0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    //wait for start condition
                    cipo_sda_next = 1'b1;
                end

                STATE_DEVADDR: begin
                    devaddr_next = devaddr;
                    if (scl_next == 1'b1 && scl == 1'b0) begin
                        // on posedge scl, clock into deviceaddr
                        if (counter <= 4'h7) begin
                            devaddr_next = {sda_next, devaddr[7:1]};
                        end
                        counter_next = counter + 4'h1;
                    end else if (scl_next == 1'b0 && scl == 1'b1) begin
                        // on negedege scl, start or stop ack.
                        if (counter == 4'h8) begin
                            if (devaddr == device_address) begin
                                // address matches, ack.
                                cipo_sda_next = 1'b0;
                                devaddr_next = devaddr;
                            end else begin
                                // address doesn't match, just go back to idle.
                                state_next = STATE_IDLE;
                                devaddr_next = 8'hxx;
                                counter_next = 4'h0;
                            end
                        //end ack
                        end else if (counter == 4'h9) begin
                            cipo_sda_next = 1'b1;
                            state_next = STATE_EBRADDR;
                            devaddr_next = 8'hxx;
                            counter_next = 4'h0;
                        end else if (counter >= 4'hA) begin //this shouldn't happen
                            cipo_sda_next = 1'b1;
                            state_next = STATE_IDLE;
                            devaddr_next = 8'hxx;
                            counter_next = 4'h0;
                        end
                    end
                end

                STATE_EBRADDR: begin
                    if (scl_next == 1'b1 && scl == 1'b0) begin
                        // on posedge scl, clock sda bit into ebr addr
                        if (counter <= 4'h7) begin
                            ebr_addr_out_next = {sda_next, ebr_addr_out[7:1]};
                        end
                        counter_next = counter + 4'h1;
                    end else if (scl_next == 1'b0 && scl == 1'b1) begin
                        //on negedge scl, do nothing or start / stop ACK
                        if (counter == 4'h8) begin
                            //begin ack
                            cipo_sda_next = 1'b0;
                        end else if (counter == 4'h9) begin
                            // end ack
                            cipo_sda_next = 1'b1;
                            state_next = STATE_FILL;
                            counter_next = 4'h0;
                        end else if (counter >= 4'hA) begin //this shouldn't happen
                            state_next = STATE_IDLE;
                            ebr_addr_out_next = 8'hxx;
                            counter_next = 4'h0;
                        end
                    end
                end

                STATE_FILL: begin
                    if (scl_next == 1'b1 && scl == 1'b0) begin
                        // on posedge scl, clock sda bit into ebr_data_out
                        if (counter <= 4'h7) begin
                            ebr_data_out_next = {sda_next, ebr_data_out[7:1]};
                        end
                        counter_next = counter + 4'h1;
                    end else if (scl_next == 1'b0 && scl == 1'b1) begin
                        // on negedge scl, ack and present byte on output
                        if (counter == 4'h8) begin
                            cipo_sda_next = 1'b0;
                            ebr_wren_next = 1'b1;
                        end else if (counter == 4'h9) begin
                            //end ack
                            cipo_sda_next = 1'b1;
                            ebr_data_out_next = 8'hxx;
                            counter_next = 4'h0;
                        end else if (counter >= 4'hA) begin //this shouldn't happen
                            state_next = STATE_IDLE;
                            ebr_data_out_next = 8'hxx;
                            counter_next = 4'h0;
                        end
                    end
                end
            endcase
        end
    end
endmodule
