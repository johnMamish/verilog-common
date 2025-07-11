#!/usr/bin/python3

# Copyright 2025 John Mamish
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

helpstr = \
""" This utility program makes it easy to generate verilog .hex files that can be read by the i2c
controller.

Check the readme for valid assembly syntax.
"""

# This utility program makes it easy to generate hex files that can be read by the i2c controller.

# The following instructions and pseudo-instructions are supported:

# i2c_write <device_addr> <byte0> <byte1> ... <byten>
#     writes bytes 0 - n to device_addr
#
# i2c_writeread n_readBytes <device_addr> <byte0> ... <byten>
#     writes bytes 0 - n to device_addr, then generates a repeated start, then reads n_read bytes
#
# i2c_read n_readBytes <device_addr>
#
# set_read_tag 0x100
#
# delay <cycles>
#     Delays for <cycles> cycles. The number of cycles is represented by a floating point immediate,
#     so not all values will be possible. If an unrepresentable value is requested, then we round
#     up to the closest value.
#
# wait_trigger llllll hhhhhh
#     Waits until the trigger bits match the bitmask.
#     Check the README for more details
#
# write_trigger tttttt
#     Writes the output trigger register to the given binary value
#
# jmp <label>
#     Jumps directly to a label.
#
# jmp_mask_unsatisfied <label> <mask_low> <mask_high>
#     Jumps to a label if the most recently read byte does NOT satisfy the mask.
#     Good for repeatedly checking a status bit.
#     See the README for more details.

# This language also allows for comments (prefixed by a '#') and labels (postfixed with a ':')

# An example program might look something like this:
#
#     # Initialize device 1 (address 0x20)
#     i2c_write 0x20 0x12 0x34 0x56
#     i2c_write 0x20 0xab 0xcd 0xef
#
#     # Initialize device 2 (address 0x30)
#     i2c_write 0x30 0x12 0x34 0x56
#     i2c_write 0x30 0xab 0xcd 0xef
#
# _read_loop:
#     wait_trigger 0b000010 0b000000
#
#     # Read from device 1 (address 0x20)
#     i2c_writeread 1Bytes 0x20 0x10 0x23
#     jmp_mask_unsatisfied _read_loop
#
# _done:
#     write_trigger 0b00_0001
#     jmp _done

import re
import sys
import os
sys.path.append(os.path.dirname(__file__) + "/../tools/simpleasmparser/")
from simpleasmparser import *
import math

LJUSTLEN = 40

def justify_comments(s):
    r = []
    for l in s.split("\n"):
        chunks = l.split("//")
        if (len(chunks[0]) > 0):
            chunks[0] = chunks[0].ljust(LJUSTLEN)
        r.append("//".join(chunks))
    return "\n".join(r)


def convert_literal_bounded(line_number, arg, minimum, maximum, base=0):
    retval = None
    try:
        retval = int(arg, base)
    except ValueError as e:
        errstr = f"line {line_number}: couldn't parse {arg}. Must be numerical literal "
        errstr += f"" if (base == 0) else f" of base {base}."
        raise ValueError(errstr)

    if ((retval < minimum) or (retval > maximum)):
        raise ValueError(f"line {line_number}: bad value {arg}. Must be in range {minimum} - {maximum}.")

    return retval

class I2CWriteInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "i2c_write"

    def parse(self):
        self.dev_addr: int = 0
        self.write_bytes: [] = []

        args = self.argtext.split()

        # dev_addr should be in [0, 127]
        self.dev_addr = convert_literal_bounded(self.line_number, args[0], 0, 127)

        # Parse all other args
        for arg in args[1:]:
            b = convert_literal_bounded(self.line_number, arg, 0, 255)
            self.write_bytes.append(b)

        if (len(self.write_bytes) >= 255):
            raise ValueError(f"line {self.line_number}: max of 255 bytes supported for {self.MNEMONIC}")

        # Figure out how many words our instruction will take up
        self.size_words = int(math.ceil(1 + ((len(self.write_bytes) + 1) / 2)))

    def emit(self, parent: SimpleAsmParser) -> str:
        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"

        # encode a write with a stop condition
        opcode = 0x00 | (0 << 2) | (2 << 0)
        bytes_to_send = len(self.write_bytes) + 1
        retval += f"{opcode:02x}{bytes_to_send:02x} "

        # Encode bytes to send
        w = [self.dev_addr << 1] + self.write_bytes
        for a, b in zip(w[0::2], w[1::2]):
            retval += f"{a:02x}{b:02x} "

        # Check for leftover byte
        if ((len(w) % 2) != 0):
            retval += f"{w[-1]:02x}00"

        retval += f"    // write to device address 0x{self.dev_addr} \n\n"

        return justify_comments(retval)

class I2CWriteRawInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "i2c_write_raw"

    def parse(self):
        self.dev_addr: int = 0
        self.write_bytes: [] = []

        args = self.argtext.split()

        self.end_condition="stop"

        # Parse all args
        for arg in args:
            strarg = re.fullmatch(r"end_condition=((none)|(stop)|(repeated_start))", arg)
            if (strarg is not None):
                self.end_condition = strarg.group(1)
            else:
                b = convert_literal_bounded(self.line_number, arg, 0, 255)
                self.write_bytes.append(b)

        if (len(self.write_bytes) >= 255):
            raise ValueError(f"line {self.line_number}: max of 255 bytes supported for {self.MNEMONIC}")

        # Figure out how many words our instruction will take up
        self.size_words = int(1) + int(math.ceil(len(self.write_bytes) / 2))

    def emit(self, parent: SimpleAsmParser) -> str:
        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"

        # encode a write with a stop condition
        stopcond = None
        if (self.end_condition == "none"): stopcond = 0
        if (self.end_condition == "repeated_start"): stopcond = 1
        if (self.end_condition == "stop"): stopcond = 2
        opcode = 0x00 | (0 << 2) | (stopcond << 0)
        bytes_to_send = len(self.write_bytes)
        retval += f"{opcode:02x}{bytes_to_send:02x} "

        # Encode bytes to send
        for a, b in zip(self.write_bytes[0::2], self.write_bytes[1::2]):
            retval += f"{a:02x}{b:02x} "

        # Check for leftover byte
        if ((len(self.write_bytes) % 2) != 0):
            retval += f"{self.write_bytes[-1]:02x}00"

        retval += f"   // {self.MNEMONIC} {len(self.write_bytes)} on bus with no device address. "
        retval += f"requres {self.size_words} words in memory.\n\n"

        return justify_comments(retval)

class I2CWriteReadInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "i2c_writeread"

    def parse(self):
        self.dev_addr: int = 0
        self.write_bytes: [] = []

        args = self.argtext.split()

        l = args[0].lower()
        if (not (l.endswith("bytes") or l.endswith("byte") or l.endswith("b"))):
            raise ValueError(f"line {self.line_number}: For clarity, {self.MNEMONIC} read length {args[0]} " \
                             "must end with \'b\' or \'bytes\'.")
        l = l.replace("bytes", "").replace("byte", "").replace("b", "")
        self.read_length = convert_literal_bounded(self.line_number, l, 0, 255)

        # dev_addr should be in [0, 127]
        self.dev_addr = convert_literal_bounded(self.line_number, args[1], 0, 127)

        # Parse all other args
        for arg in args[2:]:
            b = convert_literal_bounded(self.line_number, arg, 0, 255)
            self.write_bytes.append(b)

        if (len(self.write_bytes) >= 255):
            raise ValueError(f"line {self.line_number}: max of 255 bytes supported for {self.MNEMONIC}")

        # Figure out how many words our instruction will take up
        # for the write portion
        self.size_words = int(math.ceil(1 + ((len(self.write_bytes) + 1) / 2)))

        # for the read portion
        self.size_words += int(1) + int(2)

    def emit(self, parent: SimpleAsmParser) -> str:
        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"

        # encode a write with a repeated start condition
        bytes_to_send = len(self.write_bytes) + 1
        retval += f"01_{bytes_to_send:02x} "

        # Encode bytes to send
        w = [self.dev_addr << 1] + self.write_bytes
        for a, b in zip(w[0::2], w[1::2]):
            retval += f"{a:02x}{b:02x} "

        # Check for leftover byte
        if ((len(w) % 2) != 0):
            retval += f"{w[-1]:02x}00"

        retval += "   // i2c write with repeated start\n"

        # encode a device address write then read with a stop condition
        dev_read_addr = (self.dev_addr << 1) | 1
        retval += f"00_01 {dev_read_addr:02x}_00       // i2c send device address\n"
        retval += f"0e_{self.read_length:02x}          // i2c read ({self.size_words} words) \n\n"

        return justify_comments(retval)

class I2CReadInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "i2c_read"

    def parse(self):
        self.dev_addr: int = 0

        args = self.argtext.split()

        l = args[0].lower()
        if (not (l.endswith("bytes") or l.endswidth("byte") or l.endswith("b"))):
            raise ValueError(f"line {self.line_number}: For clarity, {self.MNEMONIC} read length {args[0]} " \
                             "must end with \'b\' or \'bytes\'.")
        l = l.replace("bytes", "").replace("b", "")
        self.read_length = convert_literal_bounded(self.line_number, l, 0, 255)

        # dev_addr should be in [0, 127]
        self.dev_addr = convert_literal_bounded(self.line_number, args[1], 0, 127)

        # Need 2 words to write the device address and 1 word to read
        self.size_words = int(2) + int(1)

    def emit(self, parent: SimpleAsmParser) -> str:
        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"

        # encode a write with a repeated start condition to send the device address
        dev_read_addr = (self.dev_addr << 1) | 1
        retval += f"00_01 {dev_read_addr:02x}_00       // send device address for read\n"
        retval += f"0e_{self.read_length:02x}          // i2c read ({self.size_words} words)\n\n"

        return justify_comments(retval)

class I2CReadRawInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "i2c_read_raw"

    def parse(self):
        args = self.argtext.split()

        self.end_condition = "none"

        l = args[0].lower()
        if (not (l.endswith("bytes") or l.endswidth("byte") or l.endswith("b"))):
            raise ValueError(f"line {self.line_number}: For clarity, {self.MNEMONIC} read length {args[0]} " \
                             "must end with \'b\' or \'bytes\'.")
        l = l.replace("bytes", "").replace("b", "")
        self.read_length = convert_literal_bounded(self.line_number, l, 0, 255)

        # parse other arguments
        args.pop(0)
        for arg in args:
            strarg = re.fullmatch(r"end_condition=((none)|(stop)|(repeated_start))", arg)
            if (strarg is not None):
                self.end_condition = strarg.group(1)
            else:
                raise ValueError(f"line {self.line_number}: bad arg {arg} for {self.MNEMONIC}")

        self.size_words = int(1)

    def emit(self, parent: SimpleAsmParser) -> str:
        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"
        if (self.end_condition == "none"): retval += "0c_"
        if (self.end_condition == "stop"): retval += "0e_"
        if (self.end_condition == "repeated_start"): retval += "0d_"
        retval += f"{self.read_length:02x}          // i2c raw_read ({self.size_words} words)\n\n"
        return justify_comments(retval)


class SetReadTagInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "set_read_tag"

    def parse(self):
        self.tag: int = None

        args = self.argtext.split()
        if (len(args) != 1):
            raise ValueError(f"line {self.line_number}: {MNEMONIC} expected 1 argument, got {len(args)}")
        self.tag = convert_literal_bounded(self.line_number, args[0], 0, 0xfff)
        self.size_words = 1

    def emit(self, parent: SimpleAsmParser) -> str:
        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"
        retval += f"1_{self.tag:03x}             // set read tag ({self.size_words} words)\n\n"
        return justify_comments(retval)

class DelayInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "delay"

    def parse(self):
        self.delay_amount: int = None

        args = self.argtext.split()
        if (len(args) != 1):
            raise ValueError("line {self.line_number}: {MNEMONIC} expected 1 argument, got {len(args)}")
        self.arg = int(args[0], 0)
        self.size_words = 1

    def emit(self, parent):
        exponent = max(0, math.ceil(math.log2(self.arg)) - 8)
        mantissa = int(((self.arg + (2**exponent) - 1) / (2**exponent)))    # ceiling integer division
        max_delay = (0x100 << 0xf)
        if (self.arg > max_delay):
            print(f"Line {self.line_number}: Warning: specified delay {self.arg} "
                  f"exceeds max delay {max_delay}")

        actual_delay = (mantissa << exponent)
        if (self.arg != actual_delay):
            print(f"Line {self.line_number}: Warning: specified delay {self.arg} not "
                  f"exactly representable. Using delay {actual_delay}")

        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"
        retval += f"4_{exponent:01x}_{mantissa:02x}     // const delay {self.arg} clock cycles ({self.size_words} words)\n\n"
        return justify_comments(retval)

class WaitTriggerInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "wait_trigger"

    def parse(self):
        args = self.argtext.split()
        if (len(args) != 2):
            raise ValueError(f"line {self.line_number}: {self.MNEMONIC} expected 2 argument, got {len(args)}")
        self.arglow = convert_literal_bounded(self.line_number, args[0], 0, 0b11_1111, base=2)
        self.arghigh = convert_literal_bounded(self.line_number, args[1], 0, 0b11_1111, base=2)
        self.size_words = 1

    def emit(self, parent):
        arg = (self.arglow << 6) | self.arghigh
        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"
        retval += f"5_{arg:03x}        // wait til trigger bits {self.arglow:06b} is low or {self.arghigh:06b} is high\n\n"
        return justify_comments(retval)

class WriteTriggerInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "write_trigger"

    def parse(self):
        args = self.argtext.split()
        if (len(args) != 1):
            raise ValueError(f"line {self.line_number}: {self.MNEMONIC} expected 1 argument, got {len(args)}")
        self.arg = convert_literal_bounded(self.line_number, args[0], 0, 0b11_1111, base=2)
        self.size_words = 1

    def emit(self, parent):
        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"
        retval += f"6_{self.arg:03x}             // write trigger \n\n"
        return justify_comments(retval)

class JmpInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "jmp"

    def parse(self):
        args = self.argtext.split()
        if (len(args) != 1):
            raise ValueError(f"line {self.line_number}: {self.MNEMONIC} expected 1 argument, got {len(args)}")
        self.jump_target = args[0]
        self.size_words = 1

    def emit(self, parent):
        # resolve label
        try:
            target = parent.label_positions[self.jump_target]
        except KeyError as e:
            raise ValueError(f"line {self.line_number}: unknown label {self.jump_target}")

        # emit
        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"
        retval += f"8_{target.address:03x} \n\n"
        return justify_comments(retval)

class JmpMaskUnsatisfiedInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "jmp_mask_unsatisfied"

    def parse(self):
        args = self.argtext.split()
        if (len(args) != 3):
            raise ValueError(f"line {self.line_number}: {self.MNEMONIC} expected 3 arguments, got {len(args)}")
        self.jump_target = args[0]
        self.lowmask = convert_literal_bounded(self.line_number, args[1], 0, 255)
        self.highmask = convert_literal_bounded(self.line_number, args[2], 0, 255)
        self.size_words = 2

    def emit(self, parent):
        # resolve label
        try:
            target = parent.label_positions[self.jump_target]
        except KeyError as e:
            raise ValueError(f"line {self.line_number}: unknown label {self.jump_target}")

        retval = f"// {self.MNEMONIC:16} (instruction takes {self.size_words} words at addr {self.offset})\n"
        retval += f"a_{target.address:03x} {self.lowmask:02x}_{self.highmask:02x}\n\n"
        return justify_comments(retval)

import argparse

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=helpstr)
    parser.add_argument("-i", "--input-file", type=str,
                        help="assembly-style file to parse")
    parser.add_argument("-o", "--output-file", type=str,
                        help="output .hex file to write to")
    args = parser.parse_args()

    # Make new parser and register our assembly instructions with it
    p = SimpleAsmParser()
    p.register_instruction(I2CWriteInstruction.MNEMONIC, I2CWriteInstruction)
    p.register_instruction(I2CReadInstruction.MNEMONIC, I2CReadInstruction)
    p.register_instruction(I2CReadRawInstruction.MNEMONIC, I2CReadRawInstruction)
    p.register_instruction(I2CWriteRawInstruction.MNEMONIC, I2CWriteRawInstruction)
    p.register_instruction(I2CWriteReadInstruction.MNEMONIC, I2CWriteReadInstruction)
    p.register_instruction(SetReadTagInstruction.MNEMONIC, SetReadTagInstruction)
    p.register_instruction(DelayInstruction.MNEMONIC, DelayInstruction)
    p.register_instruction(WaitTriggerInstruction.MNEMONIC, WaitTriggerInstruction)
    p.register_instruction(WriteTriggerInstruction.MNEMONIC, WriteTriggerInstruction)
    p.register_instruction(JmpInstruction.MNEMONIC, JmpInstruction)
    p.register_instruction(JmpMaskUnsatisfiedInstruction.MNEMONIC, JmpMaskUnsatisfiedInstruction)

    with open(args.input_file, 'r') as infile:
        p.parse_file(infile)

    with open(args.output_file, 'w') as outfile:
        outfile.write(p.emit())
