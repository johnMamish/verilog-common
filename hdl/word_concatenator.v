/**
 * Given a number of fixed-width words serially, this module concatenates them and outputs them
 * once the appropriate number of words have been concatenated.
 *
 * For instance, if the words
 *     8'hf0 8'h0f 8'hba 8'h11
 * are provided, then the resulting concatenated word will be
 *     32'hf00fba11
 *
 * When a full output word has been accumulated, the 'output_valid' line will be strobed.
 */

`timescale 1ns/100ps

module word_concatenator #(
    parameter INPUT_WIDTH=8,
    parameter NUM_WORDS_TO_CONCAT=4,

    // Valid values: {"little", "big"}
    parameter string ENDIAN="little",

    localparam OUTPUT_WIDTH = (INPUT_WIDTH * NUM_WORDS_TO_CONCAT)
)  (
    input clk_i,
    input reset_i,

    // data input
    input [INPUT_WIDTH-1:0] data_i,
    input data_valid_i,

    // accumulated output
    output logic [OUTPUT_WIDTH-1:0] accumulated_data_o,
    output logic accumulated_data_valid_o
);
    localparam CONCAT_IDX_MIN = 0;
    localparam CONCAT_IDX_MAX = INPUT_WIDTH * (NUM_WORDS_TO_CONCAT - 1);
    localparam CONCAT_IDX_START = (ENDIAN == "little") ? CONCAT_IDX_MIN : CONCAT_IDX_MAX;
    localparam CONCAT_IDX_END = (ENDIAN == "little") ? CONCAT_IDX_MAX : CONCAT_IDX_MIN;
    logic [$clog2(OUTPUT_WIDTH)+1:0] concat_idx;
    always_ff @(posedge clk_i) begin
        accumulated_data_valid_o <= 0;
        if (data_valid_i) begin
            accumulated_data_o[concat_idx +: INPUT_WIDTH] <= data_i;

            if (concat_idx == CONCAT_IDX_END) begin
                concat_idx <= CONCAT_IDX_START;
                accumulated_data_valid_o <= 1;
            end else begin
                if (ENDIAN == "little") concat_idx <= concat_idx + INPUT_WIDTH;
                else concat_idx <= concat_idx - INPUT_WIDTH;
                accumulated_data_valid_o <= 0;
            end
        end

        if (reset_i) begin
            accumulated_data_o <= 'x;
            accumulated_data_valid_o <= '0;
            concat_idx <= '0;
        end
    end
endmodule
