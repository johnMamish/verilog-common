module color_sharp_memory_display_driver #(
    // width of the image
    parameter WIDTH = 240,

    // height of the image
    parameter HEIGHT = 320,

    // x-axis (horizontal) padding of the image in pixels
    parameter HPADDING = 8,

    // y-axis (vertical) padding of the image in pixels
    parameter VPADDING = 4,

    // How much should the input clock be divided by to generate bck?
    // The datasheet recommends a frequency of 746kHz
    // Should be an even number.
    parameter CLKDIV = 16,

    // VCOM_CLKDIV must be set to make VCom 60Hz.
    // e.g. if clk_i is 12MHz, VCOM_CLKDIV should be 12000000 / 60 = 200000
    parameter VCOM_CLKDIV = 200000,

    // how many clk cycles are there of latency from the time we ask for a pixel til the
    // time that we get it?
    parameter MEM_DELAY = 1
) (
    input clk_i,
    input reset_i,

    // Timing information for rest of system
    output logic vsync_o,

    // Memory interface.
    // Note that pixels must be presented 2 at a time with the following format:
    //     - msb   0 0 r1.1 r1.0 g1.1 g1.0 b1.1 b1.0 | 0 0 r0.1 r0.0 g0.1 g0.0 b0.1 b0.0   lsb
    output logic [15:0] addr_o,
    output logic read_valid_o,
    input [15:0] pixel_data_i,

    // outputs going to panel
    output logic intb_o,

    // per-line signals
    output logic bsp_o,
    output logic bck_o,

    // per-frame signals
    output logic gsp_o,
    output logic gck_o,
    output logic gen_o,

    output logic vcom_o,
    output logic vb_o,
    output logic va_o,

    output logic [1:0] r_o,
    output logic [1:0] g_o,
    output logic [1:0] b_o
);
    // After reset, we need to send a black frame with no vcom, no va, and no vb.
    // This state keeps track of that.
    logic sending_reset_frame, reset_frame_started;

    // padding around image
    localparam BCK_MAXVAL = ((WIDTH + HPADDING) >> 1) - 1;
    localparam GCK_MAXVAL = ((HEIGHT + VPADDING) << 1) - 1;

    // more detailed timing info for INTB offset
    localparam INTB_START_GCK_OFFSET = 397 / (BCK_MAXVAL + 1);
    localparam INTB_START_BCK_OFFSET = 397 % (BCK_MAXVAL + 1);
    localparam INTB_END_BCK_OFFSET = 30;
    localparam INTB_GCK_START = ((HEIGHT << 1) + 2 + INTB_START_GCK_OFFSET);
    localparam INTB_GCK_END = (GCK_MAXVAL);

    //
    localparam GEN_STARTING_BCK_IDX = 20;

    // latch for holding freshly fetched pixels
    logic [15:0] pixel_latch;

    logic next_pixel_is_in_active_region;

    // Track where we are in the image.
    logic pixel_fetch_pending;
    logic [$clog2(MEM_DELAY)+1:0] mem_dly_count;
    logic [15:0] bck_count, gck_count, bck_count_next;
    logic this_line_valid, prev_line_valid;
    logic sending_msb;
    logic [$clog2(CLKDIV)+1:0] clkcount;
    always_ff @(posedge clk_i) begin
        clkcount <= clkcount + 1;

        // read-from-memory strobe default low
        read_valid_o <= 0;

        if (clkcount == ((CLKDIV >> 1) - 1)) begin
            // we advance internal logic whenever clkcount rolls over
            clkcount <= 0;

            // Initiate a new fetch from memory if required
            if (!sending_reset_frame && next_pixel_is_in_active_region) begin
                read_valid_o <= 1;
                pixel_fetch_pending <= 1;
                mem_dly_count <= '0;

                addr_o <= bck_count_next + 256 * (gck_count - 1);
            end

            // Update bck
            // Note that gck update needs to happen a little out-of-phase with bck update so we
            // take care of it elsewhere.
            bck_o <= ~bck_count[0];
            bck_count <= bck_count_next;
        end

        // we only update pixel values one clock cycle after bck rises or falls because
        // the pixels need a hold time of 335ns
        if ((clkcount == 1) && this_line_valid) begin
            if (sending_msb) begin
                r_o <= {pixel_latch[13], pixel_latch[5]};
                g_o <= {pixel_latch[11], pixel_latch[3]};
                b_o <= {pixel_latch[9], pixel_latch[1]};
            end else begin
                r_o <= {pixel_latch[12], pixel_latch[4]};
                g_o <= {pixel_latch[10], pixel_latch[2]};
                b_o <= {pixel_latch[8], pixel_latch[0]};
            end
        end

        // fetch from memory
        if (pixel_fetch_pending) mem_dly_count <= mem_dly_count + 1;
        if (pixel_fetch_pending && (mem_dly_count == MEM_DELAY)) begin
            pixel_latch <= pixel_data_i;
            pixel_fetch_pending <= 0;
        end

        // detect when we're starting our first frame
        if (gck_count == 1) reset_frame_started <= 1;

        // send a vsync pulse at the end of the frame
        if (gck_count == (HEIGHT << 1)) vsync_o <= 1;
        else vsync_o <= 0;

        // Handle gck update when we're 1 cycle into BCK
        if ((clkcount == 1) && (bck_count == (BCK_MAXVAL))) begin
            gck_o <= gck_count[0];
            gck_count <= (gck_count == GCK_MAXVAL) ? 0 : gck_count + 1;

            // if we've rolled over into a new frame, cancel the 'sending_reset_frame' signal
            if ((gck_count == GCK_MAXVAL) && reset_frame_started) sending_reset_frame <= 0;

            sending_msb <= ~gck_count[0];

            // update whether the current line is valid or not
            this_line_valid <= ((gck_count >= 0) && (gck_count < (HEIGHT << 1)));
            prev_line_valid <= this_line_valid;
        end

        // strobe GSP at the start of each frame and de-assert halfway into the line
        if ((bck_count == (BCK_MAXVAL >> 1)) && (gck_count == GCK_MAXVAL)) gsp_o <= 1;
        if ((bck_count == (BCK_MAXVAL >> 1)) && (gck_count == 1)) gsp_o <= 0;

        // strobe INTB
        // INTB needs to go low 270us after start of line 642 and high 20.77us into line 646
        // (270us after start of line 642 is on bck)
        if ((bck_count == INTB_START_BCK_OFFSET) && (gck_count == INTB_GCK_START)) intb_o <= 0;
        if ((bck_count == INTB_END_BCK_OFFSET) && (gck_count == INTB_GCK_END)) intb_o <= 1;

        // strobe BSP at start of each line
        if ((clkcount == 2) && (bck_count == BCK_MAXVAL)) bsp_o <= 1;
        if ((clkcount == 2) && (bck_count == 1)) bsp_o <= 0;

        // Strobe GEN
        // GEN has to be high for at least 24.6 microseconds (18.1 bck cycles) in the middle
        // of each line
        if (bck_count == GEN_STARTING_BCK_IDX) gen_o <= prev_line_valid;
        if (bck_count == (GEN_STARTING_BCK_IDX + (30 * 2))) gen_o <= 0;

        if (reset_i) begin
            sending_msb <= 1;
            sending_reset_frame <= 1;
            reset_frame_started <= 0;
            bck_count <= BCK_MAXVAL - 2;
            gck_count <= GCK_MAXVAL - 4;
            clkcount <= 0;
            {this_line_valid, prev_line_valid} <= 0;
            mem_dly_count <= 0;
            pixel_fetch_pending <= 0;

            pixel_latch <= '0;

            // reset output signals
            vsync_o <= '0;
            {addr_o, read_valid_o} <= '0;
            {intb_o, bsp_o, bck_o, gsp_o, gck_o, gen_o, r_o, g_o, b_o} <= '0;
        end
    end

    always_comb begin
        /*
        if (clkcount == ((CLKDIV >> 1) - 1)) begin
            bck_count_next = (bck_count == BCK_MAXVAL) ? 0 : bck_count + 1;
        end else begin
            bck_count_next = bck_count;
        end
         */
        bck_count_next = (bck_count == BCK_MAXVAL) ? 0 : bck_count + 1;
        next_pixel_is_in_active_region = bck_count_next <= BCK_MAXVAL;
    end

    ////////////////////////////////////////////////////////////////
    // drive vcom, va, and vb.

    // need to wait a few cycles after the initial frame before we start driving vcom
    localparam VCOM_SUPPRESS_TIME = 1000;
    logic [15:0] vcom_suppress_counter;
    logic suppress_vcom;
    always_ff @(posedge clk_i) begin
        vcom_suppress_counter <= vcom_suppress_counter + 1;
        if (vcom_suppress_counter > VCOM_SUPPRESS_TIME) suppress_vcom <= 0;

        if (reset_i || sending_reset_frame) begin
            vcom_suppress_counter <= 0;
            suppress_vcom <= 1;
        end
    end

    // actually generate va, vb, and vcom
    logic [$clog2(VCOM_CLKDIV)+1:0] vcom_counter;
    always_ff @(posedge clk_i) begin
        logic va;

        vcom_counter <= vcom_counter + 1;
        if (vcom_counter == (VCOM_CLKDIV - 1)) begin
            vcom_counter <= 0;
        end

        va = (vcom_counter < (VCOM_CLKDIV >> 1)) ? 1 : 0;
        va_o <= va;
        vcom_o <= ~va;
        vb_o <= ~va;

        if (reset_i || suppress_vcom) begin
            vcom_counter <= 0;
            {va_o, vcom_o, vb_o} <= '0;
        end
    end
endmodule
