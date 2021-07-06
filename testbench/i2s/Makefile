HDL_DIR:=../../hdl

all: i2s_controller_tb.vvp

i2s_controller_tb.vvp: i2s_controller_tb.v $(HDL_DIR)/i2s.v
	iverilog -I$(HDL_DIR) -Wall -o $@ $^
