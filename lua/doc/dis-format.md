# DIS Binary File Format Specification

## Overview

DIS (Dis) is the bytecode format for Limbo programs in Inferno/TaijiOS. This document specifies the binary structure of DIS files.

## File Header

Every DIS file begins with a header containing metadata about the module.

### Header Structure

```limbo
Mod: adt {
    name: string;          # Module name
    srcpath: string;       # Source file path

    magic: int;            # Magic number (XMAGIC or SMAGIC)
    rt: int;              # Runtime flags
    ssize: int;           # Stack size
    isize: int;           # Instruction count
    dsize: int;           # Data size
    tsize: int;           # Type descriptor size
    lsize: int;           # Link table size
    entry: int;           # Entry point (PC)
    entryt: int;          # Entry point type descriptor

    inst: array of ref Inst;      # Instructions
    types: array of ref Type;     # Type descriptors
    data: list of ref Data;       # Data segment
    links: array of ref Link;     # Link table
    imports: array of array of ref Import;  # Imports
    handlers: array of ref Handler;  # Exception handlers

    sign: array of byte;          # Module signature
};
```

### Magic Numbers

```
XMAGIC: con 819248;   # 0xC8008 (executable)
SMAGIC: con 923426;   # 0xE1742 (shared library)
```

### Runtime Flags

```
MUSTCOMPILE: con 1<<0;   # Must compile before execution
DONTCOMPILE: con 1<<1;   # Don't compile (interpret)
SHAREMP:     con 1<<2;   # Share module pointer
DYNMOD:      con 1<<3;   # Dynamic module
HASLDT0:     con 1<<4;   # Has local descriptor table 0
HASEXCEPT:   con 1<<5;   # Has exception handlers
HASLDT:      con 1<<6;   # Has local descriptor tables
```

## Instruction Format

### Instruction Structure

```limbo
Inst: adt {
    op: int;    # Opcode (byte)
    addr: int;  # Addressing mode (byte)
    mid: int;   # Middle operand
    src: int;   # Source operand
    dst: int;   # Destination operand
};
```

### Instruction Encoding

Instructions are variable-length encoded:
- **Opcode**: 1 byte (0-309)
- **Addressing mode**: Encoded in operand fields
- **Operands**: Variable-length big-endian integers

### Addressing Modes

```
# Source/Destination addressing (lower 3 bits)
AMP:  con 16r00;   # Memory (direct)
AFP:  con 16r01;   # Frame pointer
AIMM: con 16r02;   # Immediate
AXXX: con 16r03;   # Reserved
AIND: con 16r04;   # Indirect
AMASK: con 16r07;   # Mask for addressing mode

# Middle operand addressing (bits 6-7)
AXNON: con 16r00;   # No middle operand
AXIMM: con 16r40;   # Immediate middle
AXINF: con 16r80;   # Indirect frame
AXINM: con 16rC0;   # Indirect module
```

### Opcode Reference

Major opcode categories:

**Control Flow:**
- `INOP` (0) - No operation
- `IGOTO` (3) - Unconditional jump
- `ICALL` (4) - Call function
- `IRET` (12) - Return
- `IJMP` (13) - Jump
- `IEXIT` (15) - Exit program

**Frame Management:**
- `IFRAME` (5) - Create frame
- `IMFRAME` (10) - Module frame
- `ISPAWN` (6) - Spawn thread
- `IRUNT` (7) - Run thread

**Memory Operations:**
- `INEW` (16) - Allocate memory
- `INEWA` (17) - Allocate array
- `ISEND` (24) - Send on channel
- `IRECV` (25) - Receive from channel

**Stack Operations:**
- `IMOVP` (33) - Move pointer
- `IMOVM` (34) - Move to module
- `IMOVMP` (35) - move module to pointer
- `IMOVB` (36) - Move byte
- `IMOVW` (37) - Move word
- `IMOVF` (38) - Move real

**Type Conversions:**
- `ICVTBW` (38) - Convert byte to word
- `ICVTWB` (39) - Convert word to byte
- `ICVTFW` (40) - Convert real to word
- `ICVTWF` (41) - Convert word to real
- And many more...

**Arithmetic:**
- `IADDB` (57) - Add bytes
- `IADDW` (58) - Add words
- `IADDF` (59) - Add reals
- `ISUBB` (60) - Subtract bytes
- `ISUBW` (61) - Subtract words
- And many more...

**Comparisons:**
- `IBEQB` (78) - Branch if equal byte
- `IBNEW` (79) - Branch if not equal word
- `IBLTW` (80) - Branch if less than word
- And many more...

**Total Opcodes:** MAXDIS (311)

## Data Segment

### Data Structure

```limbo
Data: adt {
    op: int;    # Data operation type
    n: int;     # Number of elements
    off: int;   # Byte offset in data space
    pick {
    Zero =>     # DEFZ (0) - Zero-initialized
        (void);
    Bytes =>    # DEFB (1) - Byte array
        bytes: array of byte;
    Words =>    # DEFW (2) - Word array
        words: array of int;
    String =>   # DEFS (3) - UTF-8 string
        str: string;
    Reals =>    # DEFF (4) - Real array
        reals: array of real;
    Array =>    # DEFA (5) - Array descriptor
        typex: int;     # Type index
        length: int;    # Array length
    Aindex =>   # DIND (6) - Set array index
        index: int;
    Arestore => # DAPOP (7) - Restore address register
        (void);
    Bigs =>     # DEFL (8) - Big integer array
        bigs: array of big;
    }
};
```

### Data Operations

```
DEFZ: con 0;   # Zero-initialized space
DEFB: con 1;   # Byte values
DEFW: con 2;   # Word values (32-bit)
DEFS: con 3;   # UTF-8 string
DEFF: con 4;   # Real values (64-bit float)
DEFA: con 5;   # Array descriptor
DIND: con 6;   # Set index register
DAPOP: con 7;  # Restore address register
DEFL: con 8;   # Big integer values
```

## Type Descriptors

### Type Structure

```limbo
Type: adt {
    size: int;              # Size in bytes
    np: int;                # Number of pointers
    map: array of byte;     # GC bitmap
};
```

### Type Map

The `map` field is a bitmap used by the garbage collector:
- Each bit indicates if a word at that offset is a pointer
- Required for accurate garbage collection
- Size = ceiling(size / 4) bytes (4 bytes per word, 1 bit per word)

## Link Table

### Link Structure

```limbo
Link: adt {
    name: string;   # Function/entry name
    sig: int;       # Signature index
    pc: int;        # Program counter (instruction offset)
    tdesc: int;     # Type descriptor index
};
```

### Purpose

The link table provides:
- Exported function entry points
- Function signatures for type checking
- Type information for return values
- Used for dynamic linking and calling

## Import Table

### Import Structure

```limbo
Import: adt {
    sig: int;       # Signature index
    name: string;   # Imported function name
};
```

### Import Table Structure

```limbo
imports: array of array of Import;
```

Array of import arrays:
- Each sub-array = imports from one module
- Index = module ID in instruction

## Exception Handling

### Exception Structure

```limbo
Except: adt {
    s: string;   # Exception string
    pc: int;     # Exception handler PC
};
```

### Handler Structure

```limbo
Handler: adt {
    pc1: int;                      # Start PC
    pc2: int;                      # End PC
    eoff: int;                     # Exception offset
    ne: int;                       # Number of exceptions
    t: ref Type;                   # Exception type
    etab: array of ref Except;     # Exception table
};
```

## Module Signature

```limbo
sign: array of byte;
```

Cryptographic signature of the module (if signed).

## Binary Layout

### File Organization

```
Offset  Description
------  -----------
0+      Header (variable length, encoded)
-       Instruction count
-       Instructions (array of Inst)
-       Data size
-       Data segment (list of Data)
-       Type descriptor count
-       Type descriptors (array of Type)
-       Link table size
-       Link table (array of Link)
-       Import table
-       Exception handlers (if present)
-       Signature (if present)
```

### Encoding

- **Integers**: Big-endian, variable length (similar to BER)
- **Strings**: Length-prefixed UTF-8
- **Arrays**: Count-prefixed
- **ADTs**: Tag-prefixed, then fields

## Variable-Length Integer Encoding

Limbo uses a variable-length encoding for integers in DIS files:

```
If byte & 0x80 == 0:
    Value = byte
Else:
    Value = (byte & 0x7F)
    While next_byte & 0x80:
        Value = (Value << 7) | (next_byte & 0x7F)
        Read next_byte
```

## Example: Parsing a Simple DIS File

```limbo
# Pseudo-code
disfile := open("module.dis")

# Read header
magic := read_int(disfile)
if(magic != XMAGIC && magic != SMAGIC)
    error("Invalid magic number")

rt := read_int(disfile)
ssize := read_int(disfile)
isize := read_int(disfile)

# Read instructions
inst := array[isize] of Inst
for(i := 0; i < isize; i++) {
    inst[i].op = read_byte(disfile)
    inst[i].addr = read_byte(disfile)
    inst[i].mid = read_int(disfile)
    inst[i].src = read_int(disfile)
    inst[i].dst = read_int(disfile)
}

# Read data segment
dsize := read_int(disfile)
data := read_data(disfile, dsize)

# Read type descriptors
tsize := read_int(disfile)
types := array[tsize] of Type
for(i := 0; i < tsize; i++) {
    types[i].size = read_int(disfile)
    types[i].np = read_int(disfile)
    types[i].map = read_bytes(disfile, ...)
}

# Read link table
lsize := read_int(disfile)
links := array[lsize] of Link
for(i := 0; i < lsize; i++) {
    links[i].name = read_string(disfile)
    links[i].sig = read_int(disfile)
    links[i].pc = read_int(disfile)
    links[i].tdesc = read_int(disfile)
}
```

## Related Files

- `/module/dis.m` - DIS module definition
- `/module/loader.m` - Loader module interface
- `/dis/lib/*.dis` - Example DIS files

## Tools

The `dis` module provides utilities:
- `Dis.loadobj(file)` - Load DIS file
- `Dis.op2s(op)` - Convert opcode to string
- `Dis.inst2s(ins)` - Disassemble instruction

## References

- Inferno DIS format documentation
- Limbo Virtual Machine specification
- Opcode reference in `/module/dis.m`
