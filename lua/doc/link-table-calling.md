# Link Table Function Calling Guide

## Overview

This document describes how to call Limbo functions from Lua using the Loader module's link table.

## Background

The DIS parser can extract:
- Function names from link table
- Entry points (PC values)
- Type signatures

But actually **calling** those functions requires understanding the Limbo execution model.

## Loader Module API

From `/module/loader.m`:

```limbo
Loader: module {
    # Get link table from module
    link: fn(mp: Nilmod): array of Link;

    # Get instruction fetch
    ifetch: fn(mp: Nilmod): array of Inst;

    # Get type descriptors
    tdesc: fn(mp: Nilmod): array of Typedesc;

    # Create new module
    newmod: fn(name: string, ss, nlink: int,
              inst: array of Inst, data: ref Niladt): Nilmod;

    # Allocate data
    tnew: fn(mp: Nilmod, size: int, map: array of byte): int;

    # External function call
    ext: fn(mp: Nilmod, idx, pc: int, tdesc: int): int;

    # Compile module
    compile: fn(mp: Nilmod, flag: int): int;

    # Create data
    dnew: fn(size: int, map: array of byte): ref Niladt;
};
```

## Key Insight

The `Loader->link()` function returns the link table, but **Loader doesn't provide a direct "call function" API**.

### Why?

Because in Limbo/Inferno, modules are meant to be loaded and linked at **load time**, not called dynamically at runtime.

### The Solution

We need to use **Limbo's own execution mechanisms**:

## Approach 1: Use the dis Module (RECOMMENDED)

The `dis` module has `Dis->loadobj()` which returns a complete `Dis->Mod` structure.

Looking at the Dis->Mod structure:
```limbo
Mod: adt {
    inst: array of ref Inst;      # Instructions!
    links: array of ref Link;    # Link table
    ...
};
```

The `inst` array contains the actual instructions. We can execute them!

### How Execution Works

In Limbo, the VM executes instructions sequentially:
1. Start at PC (program counter)
2. Fetch instruction at `inst[pc]`
3. Decode and execute
4. Move to next PC
5. Repeat until `IRET` (return) instruction

### The Calling Convention

When calling a Limbo function:

1. **Set up frame**:
   - Allocate stack frame
   - Save return address
   - Set up frame pointer

2. **Pass arguments**:
   - Push arguments onto stack (in reverse order)
   - Set argument count

3. **Jump to PC**:
   - Set PC = function entry point
   - Start execution

4. **Handle return**:
   - Function executes `IRET`
   - Return value on stack
   - Restore frame

## Implementation Strategy

### Option 1: Direct Instruction Execution (Simplest)

```limbo
# Pseudo-code
callfunction(mod: ref Dis->Mod, link: ref Link, args: array of ref Value): ref Value
{
    # 1. Create execution context
    ctx := ref ExecutionContext;
    ctx.mod = mod;
    ctx.pc = link.pc;
    ctx.stack = newstack();

    # 2. Push arguments
    for(i := len args - 1; i >= 0; i--) {
        push(ctx.stack, args[i]);
    }

    # 3. Execute until return
    while(ctx.pc >= 0) {
        inst := mod.inst[ctx.pc];
        result := execute(ctx, inst);
        if(result == RETURNED)
            break;
        ctx.pc++;
    }

    # 4. Get return value
    return pop(ctx.stack);
}
```

### Option 2: Use Existing VM (If Available)

Check if there's a Limbo VM module we can use:
```limbo
# Look for VM module
vm := load VM VM->PATH;
if(vm != nil) {
    # Use VM to execute
    result = vm->call(mod, link.pc, args);
}
```

### Option 3: Compile as Native (Best Performance)

Use `Loader->compile()` to compile to native, then call:
```limbo
# Compile module
status := loader->compile(modinst, 0);
if(status >= 0) {
    # Now we can call functions directly
    # (This is platform-dependent)
}
```

## The Challenge

**The real challenge**: Limbo doesn't expose a "call function by PC" API in its standard modules.

### Why?

Because Limbo is designed as a **compiled** language. Functions are meant to be:
1. Linked at compile/load time
2. Called directly via normal Limbo syntax
3. Not invoked dynamically

## Workable Solutions

### Solution A: Shell Out to limbo(1)

```limbo
# Write a small Limbo program that calls the function
# Compile and execute it
cmd := sprint("echo 'impl \"%s\" %s' | limbo", modname, funcname);
sys->pipeline(cmd);
```

**Pros:** Simple, works
**Cons:** Slow, new process each call

### Solution B: Inline Interpreter (RECOMMENDED)

Implement a small Limbo interpreter for our use case:
- Only handle common instructions
- Simplified execution model
- Fast enough for most uses

**Instructions to implement** (~30 out of 311):
- IRET, ICALL, IFRAME
- IMOVP, IMOVM, IMOVB, IMOVW, IMOVF
- IADDB, IADDW, IADDF
- ISUBB, ISUBW, ISUBF
- IBEQB, IBEQW, IBEQF
- IEXIT, INEW, ISEND, IRECV

### Solution C: Module Compilation (Best for Production)

1. Generate a small Limbo wrapper
2. Compile it with the module
3. Load and call normally

Example wrapper:
```limbo
Wrapper: module {
    init: fn(fnname: string, args: list of ref Value->Value);
};

init(fnname, args) {
    # Call the function
    return mod->fnname(hd args, hd tl args);
}
```

## Recommendation

**Use Solution B (Inline Interpreter)** because:
1. No external processes
2. Fast enough
3. Controllable
4. Can handle most cases

**Fallback to Solution A (limbo(1))** for complex cases.

## Data Structures

```limbo
ExecutionContext: adt {
    mod: ref Dis->Mod;
    pc: int;
    fp: int;          # Frame pointer
    sp: int;          # Stack pointer
    inst: array of ref Inst;
    stack: array of ref Value;
    status: int;      # Running, Returned, Error
};

Value: adt {
    pick {
    Nil =>
        (void);
    Int =>
        v: int;
    Real =>
        v: real;
    String =>
        v: string;
    Array =>
        v: array of ref Value;
    }
};
```

## Execution Loop

```limbo
execute(ctx: ref ExecutionContext): int
{
    while(ctx.status == Running) {
        if(ctx.pc < 0 || ctx.pc >= len ctx.inst) {
            ctx.status = Error;
            break;
        }

        inst := ctx.inst[ctx.pc];

        case inst.op {
        IRET =>
            # Return from function
            ctx.status = Returned;
            return ctx.stack[ctx.sp];

        IMOVP =>
            # Move pointer
            ctx.stack[inst.dst] = ctx.stack[inst.src];

        IADDW =>
            # Add words
            a := ctx.stack[inst.src];
            b := ctx.stack[inst.mid];
            ctx.stack[inst.dst] = ref Value.Int(a.v + b.v);

        # ... other instructions

        * =>
            # Unimplemented
            ctx.status = Error;
        }

        ctx.pc++;
    }

    return 0;
}
```

## Next Steps

1. ✅ Document calling approach
2. ⏳ Design ExecutionContext
3. ⏳ Implement core instructions
4. ⏳ Test with simple functions
5. ⏳ Handle complex cases
6. ⏳ Optimize performance

## References

- `/module/dis.m` - Dis module definition
- `/module/loader.m` - Loader module
- Inferno source code - Limbo VM implementation
- Limbo language specification

---

**Conclusion:** While Limbo doesn't provide a direct "call by PC" API, we can implement a simplified interpreter or use shell-based execution. The inline interpreter approach gives us the best balance of performance and control.
