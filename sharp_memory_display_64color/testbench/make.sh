#!/bin/bash

rm driver_tb

iverilog -g2005-sv \
         ../hdl/sharp_64color_memory_display_driver.sv \
         sharp_memory_display_64color_tb.sv \
         -o driver_tb

./driver_tb
