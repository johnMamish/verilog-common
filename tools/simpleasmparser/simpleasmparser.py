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


# This library contains a few utiity classes that make it easy to parse simple assembly languages
# of the form:
#
# # This is a comment
# _label:
#     instr1 a b c       # do instruction 1 with args a, b, and c.
#     instr2
#     instr1 c b d
#     instr3 _label
#
# and then emit hex files.
#
# assembly languages are specified by:
#   1. Declaring instructions by inheriting from the Instruction class
#   2. Registering those instructions with a Parser using the 'register_instruction' method

from typing import Type
from types import SimpleNamespace

class SimpleAsmInstruction:
    # Takes an array of args and constructs a new instruction.
    # Should always succeed - should never do any parsing.
    # All text on the line following the instruction name will be passed into "text", excluding any
    # comments which the parser strips.
    def __init__(self, argtext: str, line_number: int, offset: int):
        # Which line number does this instruction appear on?
        self.line_number = line_number

        # What is the length of this instruction and its associated arguments in 16b words?
        self.size_words: int = None

        # The raw string text of all the arguments
        self.argtext = argtext

        # What position does this instruction have in the program in 16b words?
        self.offset = offset

    # This function should parse the arguments and validate them.
    # It must also set self.size_words to the final size of the instruction in 16b words.
    # it can raise an error if there was an issue parsing the instruction's argument test.
    def parse(self) -> None:
        self.size_words = 0
        raise ValueError("This class shouldn't be instantiated.")

    def get_size_words(self) -> int:
        return self.size_words

    # Returns a string containing hex to append to an output file.
    # the string may contain verilog-style '//' comments or vhdl-style '#' comments
    # (e.g. "// my_instr \n01_02")
    def emit(self, parent) -> str:
        pass

# Example instruction declaration
class __AddInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "add"

    # We recommend not declaring an init. The super().init should handle most things.
    #def __init__(self, argtext: str, line_number: int, offset: int):
        #super().__init__(argtext, line_number, offset)

    def parse(self):
        self.dest_register: int
        self.op1: int
        self.op2: int

        args = self.argtext.split()

        if (len(args) != 3):
            raise ValueError(f"line {self.line_number}: instruction expects 3 args but got {len(args)}.")

        self.dest_register = args[0]
        self.op1 = args[1]
        self.op2 = args[2]

        self.size_words = 1

    def emit(self, parent) -> str:
        args = ((op2 & 0xf) << 8) | ((op1 & 0xf) << 4) | (dest_register & 0xf)
        return f"87_{args:04x}"

# super basic template instruction declaration
class __NopInstruction(SimpleAsmInstruction):
    MNEMONIC: str = "nop"
    arg: int = None

    def parse(self):
        args = self.argtext.split()
        self.arg = args[0]
        self.size_words = 1

    def emit(self, parent):
        return f"00_{self.arg:02x}"

class SimpleAsmLabel:
    # What's the text of the label?
    name: str = None

    # Which line number does this label appear at?
    line_number: int = None

    # What is the address in 16b words?
    address: int = None

    # Takes a string containing the label and a line number and strips it to
    def __init__(self, s, line_number):
        self.name = s.split(":", maxsplit=1)[0]
        self.line_number = line_number


# This class iterates over
# You should provide it with an instruction factory that maps instruction names to instruction
# classes
class SimpleAsmParser:
    def __init__(self):
        # This dict maps instruction names to instruction generator classes
        self.known_instructions: dict = {}

        # This list contains labels and instructions interleaved.
        self.firstpass: list = []

        # This dict maps label names to SimpleAsmLabel objects
        self.label_positions: dict = {}

    # This method should be called to register new instructions. Example usage:
    #     .register_instruction("add", AddInstruction)
    # Any instruction added should inherit from Instruction.
    # def register_instruction(self, keyword: str, instr: Type[SimpleAsmInstruction]) -> None:
    def register_instruction(self, keyword: str, instr) -> None:
        self.known_instructions[keyword] = instr

    # This method performs a first pass on assembly file parsing (reads all instructions and
    # arguments in and constructs a list of instructions)
    # You should pass in an opened file object
    def parse_file(self, f) -> None:
        address = 0
        for line_number, line in enumerate(f):
            # Trim comment from end and whitespace
            line = line.split("#", maxsplit=1)[0]
            line = line.strip()

            # If the line was just a comment, then split and strip should reduce it to ""
            if (line == ""): continue

            # Check if it's a label, otherwise try to make it an instruction
            if (line.endswith(":")):
                label = SimpleAsmLabel(line, line_number+1)
                label.address = address
                self.label_positions[label.name] = label
            else:
                try:
                    spl = line.split(maxsplit=1)
                    mnem = spl[0]
                    argtext = "" if (len(spl) <= 1) else spl[1]
                    instr = self.known_instructions[mnem](argtext, line_number+1, address)
                except KeyError as e:
                    raise ValueError(f"Line {line_number + 1}: Unknown instruction {mnem}")

                instr.parse()
                self.firstpass.append(instr)
                address += instr.get_size_words()

    # This method takes the fully parsed instructions and fully resolved label positions and emits
    # everything that is to be written to the output file as a string
    def emit(self) -> str:
        outputstr = ""
        for instr in self.firstpass:
            outputstr += instr.emit(self)
        return outputstr
