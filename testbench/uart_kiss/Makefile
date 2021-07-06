HDL_DIR:=../../hdl

all: uart_tx_kiss_tb.vvp

uart_tx_kiss_tb.vvp: uart_tx_kiss_tb.v $(HDL_DIR)/uart_kiss.v
	iverilog -I$(HDL_DIR) -Wall -o $@ $^
