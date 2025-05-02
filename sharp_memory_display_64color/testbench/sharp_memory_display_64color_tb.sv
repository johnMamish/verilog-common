`timescale 1ns/100ps

module sharp_memory_display_64color_tb;
    logic clk;
    logic reset;

    // generate 12MHz clock
    initial clk = 0;
    always begin
        repeat (6) begin #41.6; clk <= ~clk; end
        #(250 - (41.6 * 6));
    end

    ////////////////////////////////////////////////////////////////
    // connections going to DUT
    logic vsync;
    logic [15:0] addr, pixel_data;
    logic read_valid;

    logic intb, bsp, bck, gsp, gck, gen, vcom, vb, va;
    logic [1:0] r, g, b;

    ////////////////////////////////////////////////////////////////
    // dut
    color_sharp_memory_display_driver dut (
        .clk_i(clk), .reset_i(reset),
        .vsync_o(vsync), .addr_o(addr), .read_valid_o(read_valid), .pixel_data_i(pixel_data),
        .intb_o(intb), .bsp_o(bsp), .bck_o(bck),
        .gsp_o(gsp), .gck_o(gck), .gen_o(gen),
        .vcom_o(vcom), .vb_o(vb), .va_o(va),
        .r_o(r), .g_o(g), .b_o(b)
    );

    always_ff @(posedge clk) begin
        if (read_valid) begin
            pixel_data[12 +: 2] <= addr[12:11];
            pixel_data[10 +: 2] <= addr[12:11];
            pixel_data[8 +: 2] <= addr[12:11];
            pixel_data[4 +: 2] <= addr[12:11];
            pixel_data[2 +: 2] <= addr[12:11];
            pixel_data[0 +: 2] <= addr[12:11];
        end
    end

    initial begin
        $dumpfile("sharp_memory_display_64color_tb.vcd");
        $dumpvars(0, sharp_memory_display_64color_tb);

        reset <= 0;
        repeat(2) @(posedge clk);
        reset <= 1;
        repeat(20) @(posedge clk);
        reset <= 0;
        repeat(5_000_000) begin
            @(posedge clk);
        end

        $finish;
    end
endmodule
