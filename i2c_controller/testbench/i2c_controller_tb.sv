`timescale 1ns/100ps


module i2c_initializer_tb;
    logic clk_i;
    logic reset_i;
    always begin #10; clk_i = ~clk_i; end

    //
    wire sda;
    wire scl;

    pullup sda_pullup (sda);
    pullup scl_pullup (scl);

    // wires to output results from dut
    logic [11:0] read_tag_o;
    logic [7:0] read_data_o;
    logic nak_o;
    logic read_data_valid_o;

    logic [5:0] trigger_o, trigger_i;

    i2c_controller dut (
        .clk_i, .reset_i,
        .sda_io(sda), .scl_io(scl),
        .read_tag_o, .read_data_o, .nak_o, .read_data_valid_o,
        .trigger_o, .trigger_i
    );
    defparam dut.INIT_FILE = "i2c_initializer.hex";

    // trigger
    initial begin
        trigger_i <= 0;
        repeat (100000) @(posedge clk_i);
        while (1) begin
            repeat (100 * 60) @(posedge clk_i);
            trigger_i <= '1;
            @(posedge clk_i);
            trigger_i <= '0;
        end
    end

    // process for emulating i2c device
    logic sda_dev;
    logic eof;
    logic [7:0] i2c_device_data;
    initial begin: device
        localparam STATE_IDLE = 0;
        localparam STATE_ACTIVE = 1;
        localparam ADDR = 7'h30;

        logic [7:0] latched_addr;
        logic [7:0] data_to_write;

        forever begin
            logic start_cond, stop_cond, xfer, first_bit;
            sda_dev <= 1'bz;
            eof <= 1;
            fork
                // detect start condition
                begin
                    start_cond = 0;
                    forever begin
                        @(negedge sda);
                        if (scl) begin
                            start_cond = 1;
                            break;
                        end
                    end
                end

                // detect stop condition
                begin
                    stop_cond = 0;
                    forever begin
                        @(posedge sda);
                        if (scl) begin
                            stop_cond = 1;
                            break;
                        end
                    end
                end

                // detect 'regular' frame
                begin
                    xfer = 0;
                    forever begin
                        @(posedge scl);
                        first_bit <= sda;
                        fork
                            begin @(posedge sda or negedge sda); end
                            begin @(negedge scl); xfer = 1; end
                        join_any
                        if (xfer) break;
                    end
                end
            join_any
            disable fork;
            #1;
            eof <= 0;
            if (start_cond) begin
                // we had a start condition, read in device id address
                repeat (8) begin
                    @(posedge scl);
                    latched_addr <= {latched_addr[6:0], sda};
                end

                @(negedge scl);
                if (latched_addr[1 +: 7] == ADDR) sda_dev <= 0;
                else sda_dev <= 1'bz;
                @(negedge scl);
                sda_dev <= 1'bz;

                $display("dummy i2c device: rx'd address %02x with r/!w bit = %01b",  latched_addr[1 +: 7], latched_addr[0]);
            end else if (xfer) begin
                // just a regular frame. Ignore if the address doesn't match.
                if (latched_addr[1 +: 7] == ADDR) begin
                    if (latched_addr[0] == 0) begin
                        // write operation
                        repeat (7) begin
                            i2c_device_data <= {i2c_device_data[6:0], sda};
                            @(posedge scl);
                        end
                        i2c_device_data <= {i2c_device_data[6:0], sda};

                        // ack
                        @(negedge scl); sda_dev <= 0;
                        @(negedge scl); sda_dev <= 1'bz;
                        data_to_write <= i2c_device_data; #1;

                        $display("dummy i2c device: read frame with data %02x", data_to_write);
                    end else begin
                        // read operation
                        for (int signed i = 7; i > 0; i--) begin
                            sda_dev <= data_to_write[i];
                            @(posedge scl);
                        end
                        sda_dev <= data_to_write[0];

                        // let controller ack
                        @(negedge scl); sda_dev <= 1'bz;
                        @(negedge scl); sda_dev <= 1'bz;
                        data_to_write <= data_to_write + 1; #1;

                        $display("dummy i2c device: write frame with data %02x", data_to_write);
                    end
                end else begin
                    $display("dummy i2c device: frame not sent to my address");
                    sda_dev <= 1'bz;
                end
            end
        end
    end

    assign sda = sda_dev;

    initial begin
        $dumpfile("i2c_controller_tb.vcd");
        $dumpvars(0, i2c_initializer_tb);

        clk_i <= 0;
        reset_i <= 1;

        @(posedge clk_i); @(posedge clk_i);

        reset_i <= 0;

        repeat (300000) @(posedge clk_i);
        $finish;
    end

endmodule
