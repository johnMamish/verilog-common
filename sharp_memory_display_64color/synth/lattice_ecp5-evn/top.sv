// diamond 3.7 accepts this PLL
// diamond 3.8-3.9 is untested
// diamond 3.10 or higher is likely to abort with error about unable to use feedback signal
// cause of this could be from wrong CPHASE/FPHASE parameters
module pll
(
    input clkin, // 12 MHz, 0 deg
    output clkout0, // 57.6 MHz, 0 deg
    output locked
);
(* FREQUENCY_PIN_CLKI="12" *)
(* FREQUENCY_PIN_CLKOP="60" *)
(* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(5),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(5),
        .CLKOP_CPHASE(2),
        .CLKOP_FPHASE(0),
        .FEEDBK_PATH("CLKOP"),
        .CLKFB_DIV(25)
    ) pll_i (
        .RST(1'b0),
        .STDBY(1'b0),
        .CLKI(clkin),
        .CLKOP(clkout0),
        .CLKFB(clkout0),
        .CLKINTFB(),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b1),
        .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .LOCK(locked)
);
endmodule

module top (
    // FTDI pins
    input ftdi_clk_12m,

    output logic sda_0_uart_tx,
    input scl_0_uart_rx,

    // LEDs and random GPIOs
    output logic [7:0] led,
    input btn,

    // sharp LS021B7DD02 screen input
    output logic [1:0] sharp_b,
    output logic [1:0] sharp_g,
    output logic [1:0] sharp_r,

    output logic sharp_intb,
    output logic sharp_bck, sharp_bsp,
    output logic sharp_gsp, sharp_gck, sharp_gen,
    output logic sharp_vb_vcom, sharp_va
);
    logic sys_reset;

    assign sda_0_uart_tx = 1;

    ////////////////////////////////////////////////////////////////
    // PLL
    // from an input clock of 12MHz, the PLL generates 60MHz
    logic clk_pll;
    logic pll_locked;
    pll _pll (
        .clkin(ftdi_clk_12m), .clkout0(clk_pll), .locked(pll_locked)
    );

    logic [7:0] pll_sta_duty;
    always_ff @(posedge ftdi_clk_12m) begin
        if (pll_locked) led[7] <= (pll_sta_duty > 3);
        else led[7] <= 1;
        pll_sta_duty <= pll_sta_duty + 1;
    end

    ////////////////////////////////////////////////////////////////
    // reset logic
    always_comb sys_reset = (!pll_locked || (btn == 1'b0));

    ////////////////////////////////////////////////////////////////
    // ft232 output
    logic [15:0] smd_addr;
    logic smd_do_read;
    logic [15:0] pixel_data;
    logic scrn_vsync;
    color_sharp_memory_display_driver dut (
        .clk_i(clk_pll), .reset_i(sys_reset),
        .vsync_o(scrn_vsync),
        .addr_o(smd_addr), .read_valid_o(smd_do_read), .pixel_data_i(pixel_data),
        .intb_o(sharp_intb), .bsp_o(sharp_bsp), .bck_o(sharp_bck),
        .gsp_o(sharp_gsp), .gck_o(sharp_gck), .gen_o(sharp_gen),
        .vcom_o(sharp_vb_vcom), .va_o(sharp_va),
        .r_o(sharp_r), .g_o(sharp_g), .b_o(sharp_b)
    );
    assign vb_o = vcom_o;

    assign led[6] = ~scrn_vsync;

    ////////////////////////////////////////////////////////////////
    // memory for display
    always_ff @(posedge clk) begin
        if (read_valid) begin
            pixel_data[12 +: 2] <= addr[13 +: 2];      // r1
            pixel_data[10 +: 2] <= addr[11 +: 2];        // g1
            pixel_data[8 +: 2] <= addr[9 +: 2];         // b1
            pixel_data[4 +: 2] <= addr[13 +: 2];         // r0
            pixel_data[2 +: 2] <= addr[11 +: 2];         // g0
            pixel_data[0 +: 2] <= addr[9 +: 2];         // b0
        end
    end
endmodule
