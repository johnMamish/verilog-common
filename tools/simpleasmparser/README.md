## SimpleAsmParser

A lot of times when we develop a systemverilog module, it will be controlled by a very simple
machine code that's loaded via a hex file.

```
00_05
01_ff
```

Unfortunately, writing machine code - even for extremely simple one-off state machines - can be onerous. It would be better if we could write a domain-specific assembly language like this:

```assembly
# Keep on adding 5 to our accumulator
_loop:
    accumulate 0x05
    jmp _loop             # go back to the label '_loop'
```

`SimpleAsmParser` is a Python framework that makes it easy to write parsers for domain-specific assembly languages.

## Using SimpleAsmParser

To use `SimpleAsmParser`, you just have to do two things:

1. For each instruction in your instruction set, implement a class derived from `simpleasmparser.SimpleAsmInstruction`. In `simpleasmparser.py` we've provided a couple examples for you. Each class must do 3 things:

    a. Provide a `parse()` method. The `parse()` method should take `self.argtext` (a string containing everything after the instruction keyword) and evaluate it according to your instructions semantics. `self.argtext` is filled out by the superclass before the instruction is parsed.

    b. During the `parse()` method, fill out the `self.size_words` member variable. This must give the size that the instruction will take up in memory words. It's used by the parser for determining label position.

    c. Provide an `emit()` method. The `emit()` method should produce a string containing data appropriate for a systemverilog `.hex` file representing the instruction. The `emit()` method may emit comments (like `// ...`) to make the resulting hex file easier to understand.

2. All your newly defined instructions need to be registered with a parser object, like so:
```python
p = SimpleAsmParser()
p.register_instruction("accumulate", MyAccumulateInstruction)
p.register_instruction("jmp", MyBranchInstruction)
```
This provides a mapping between instruction mnemonics and instruction objects that emit binary.

Then, you can parse files like this:
```python
    with open(args.input_file, 'r') as infile:
        p.parse_file(infile)

    with open(args.output_file, 'w') as outfile:
        outfile.write(p.emit())
```
