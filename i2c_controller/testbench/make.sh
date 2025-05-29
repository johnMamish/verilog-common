#!/bin/bash

rm i2c_controller_tb

../assemble.py -i i2c_initializer.i2casm -o i2c_initializer.hex

iverilog -g2012 \
         ../i2c_controller.sv \
         i2c_controller_tb.sv \
         -o i2c_controller_tb

./i2c_controller_tb
