## I2C Controller

This module contains a simple i2c controller that can write, read, and poll i2c devices without any extra controller - everything is self-contained, no axi master is needed.

Even though no axi master is needed, this controller is still very programmable. It can read an i2c device over and over until a register's bit value changes. It can wait for an external trigger OR can send an external trigger to indicate that initialization of some i2c device is finished or indicate error conditions.

## Programming

The `i2c_controller` module's actions are specified through a simple machine language. Programs for the i2c controller should be specified via a hex file which is loaded via the `INIT_FILE` parameter.

The contents of the program file can be written manually or generated by the included assembler - more info is below in the "Assembly Language" section.

## Interface

### Reading data
As the `i2c_controller` runs, data that is read from the i2c device is presented over the `read_data_o` and `read_tag_o` ports. Whenever the

The `read_tag_o` port can be used to let the downstream hardware know what the corresponding data is. The 12-bit `tag` can be specified in the control program for each write. If the `tag` isn't specified, then the `tag` is automatically incremented after each read.

For instance, the following sequence of operations:

```
set_read_tag 0x100
read_i2c 2Bytes
set_read_tag 0x200
read_i2c 1Byte
```

will produce 3 strobes on the `read_data_o` port. They will be tagged with `0x100`, `0x101`, and `0x200` respectively.

### Input and output triggers
The i2c controller has 6 1-bit input triggers. The controller can be programmed to wait until any one of the 6 triggers has a high or low value before proceeding.

The i2c controller has 6 1-bit output triggers. The controller can be programmed to set these triggers to any value.

This is useful for coordinating the i2c controller with other modules.

### SCL division

The parameter `SCL_DIV` can be used to specify a relationship between the input clock and the output scl clock. The nominal speed for scl should be 100kHz - `SCL_DIV` should be selected according to 0.5 * (input_clk_freq) / (desired_output_freq).

E.g. if the i2c controller is clocked by a 100MHz clock, `SCL_DIV` should be set to 0.5 * 100MHz / 100Khz = 500.

## Assembly langauge

This directory also contains an assembler that assembles simple programs for the i2c controller. It can be invoked with

```
./assemble.py -i input_filename.asm -o output_file.hex
```

It uses the domain-specific assembly language specific to this controller (described below). The resulting `hex` file should be fed into the i2c controller via its `INIT_FILE` param at synthesis time.

#### `i2c_write`
This instruction writes up to 255 bytes to the specified device address, ending in a stop condition.

Usage: `i2c_write <device_addr> <byte0> <byte1> ... <byten>`

Example:
```assembly
# This command writes bytes 01 02 03 04 to i2c device with 7-bit address 0x20.
    i2c_write 0x20 0x01 0x02 0x03 0x04
```

#### `i2c_writeread`
This instruction writes up to 255 bytes to the specified device address, sends a repeated start, and then reads up to 255 bytes.

Usage: `i2c_writeread <n_bytes>Bytes <device_addr> <byte0> <byte1> ... <byten>`

Example:
```assembly
# write bytes 0x10 0x00 to i2c device with 7-bit address 0x20
# and then read 2 bytes from 7-bit address 0x20.
i2c_writeread 2Bytes 0x20 0x10 0x00
```

#### `set_read_tag`
Sets the next value for the read tag - this value will be used to denote the subsequent read.

Usage: `set_read_tag <12b read_tag>`

Example:
```assembly
    set_read_tag 0x100   # The following read will have a tag of 0x100
    i2c_writeread 2Bytes 0x20 0x10 0x10  # The yielded reads will have tags 0x100 and 0x101
    i2c_writeread 2Bytes 0x20 0x10 0x40  # The yielded reads will have tags 0x102 and 0x103
    set_read_tag 0x018
    i2c_writeread 2Bytes 0x20 0x08 0x00  # The yielded reads will have tags 0x018 and 0x019
```

#### `delay`
Delays for a given number of clock cycles up to (2^15) * 255 = 8,355,840 cycles

Note that internally the requested amount is represented with a floating-point number, so not all requested delay values above 256 are possible.

Example:
```assembly
    delay 5000
```

#### `wait_trigger`
Waits until any of the input triggers matches the low and high masks.

Example
```assembly
    wait_trigger 0b00_0001 0b00_0000   # wait until trigger bit 0 is low
    wait_trigger 0b00_0000 0b00_0001   # wait until trigger bit 0 is high
```

#### `write_trigger`
Sets the output triggers to the immediate binary value.

Example
```assembly
    write_trigger 0b00_1011
```

#### `jmp`
Jumps control flow directly to a label.

Example:

```assembly
_loop:
    i2c_write 0x20 0x01
    jmp _loop
```

#### `jmp_mask_unsatisfied`
This instruction is given 2 masks: a low mask and a high mask. If the most-recently read byte does not match the low and high masks then the given label is jumped to.

A byte x 'matches' the low mask if x is '0' wherever the low mask is '1'. It matches a high mask if
x is '1' wherever the mask is '1'. For example:

```
      0100 0011       0100 0011       0100 0111
  low:0001 0100  high:0000 0001   low:0001 0100
   -------------    -----------   -------------
      xxx1 x1xx       xxxx xxx1       xxx1 x0xx
      matches         matches         doesn't match because of bit 2.
```

Example:

```assembly
_loop:
    i2c_writeread 1Byte 0x20 0x01 0x01
    jmp_mask_unsatisfied _loop 0b0000_1000 0b0000_0001
```

The low mask comes first and the high mask comes second in the arg list.
