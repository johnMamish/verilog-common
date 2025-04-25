HDL_DIR:=../../hdl

all: word_concatenator_tb.vvp

word_concatenator_tb.vvp: word_concatenator_tb.v $(HDL_DIR)/word_concatenator.v
	iverilog -g2005-sv -I$(HDL_DIR) -Wall -o $@ $^
