/**
 * Module for image dithering.
 *
 * Default params give floyd-steinberg
 */

module image_dither
  #(
    parameter PIXWIDTH_IN = 8,
    parameter PIXWIDTH_OUT = 1,
    parameter INTERNAL_PRECISION = 8,
    parameter IMAGE_WIDTH = 320,
    parameter IMAGE_HEIGHT = 240,

    // These parameters define the dithering array.
    // The dithering array needs to be passed in as a packed, fixed-point vector.
    parameter DITHER_KERNEL_WIDTH = 3,
    parameter DITHER_KERNEL_HEIGHT = 2,
    parameter DITHER_KERNEL_LENGTH = (INTERNAL_PRECISION * DITHER_KERNEL_WIDTH * DITHER_KERNEL_HEIGHT),
    parameter logic [DITHER_KERNEL_LENGTH-1:0] DITHER_KERNEL = { 8'd000, 8'd000, 8'd112,
                                                                 8'd048, 8'd080, 8'd016 }
)  (
    input clk,
    input reset,

    input hsync_in,
    input vsync_in,
    input [PIXWIDTH_IN-1:0] pix_in,

    output logic hsync_out,
    output logic vsync_out,
    output logic [PIXWIDTH_OUT-1:0] pix_out
);
    logic [PIXWIDTH_IN:0] pix_quantized;
    logic [PIXWIDTH_IN-1:0] pix;
    logic pix_valid;

    always_ff @(posedge clk) begin


    end
endmodule
