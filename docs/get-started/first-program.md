---
title: Your first program
index: 3
---

# Your first program

The repository's programs live in `samples/`, one file each. `Minimal` is the smallest one that prints
something. This is all of it:

<!-- sample: samples/Minimal.cs file -->
```csharp
// Example: Minimal zero-mode "Hello World" (~39 KB, no .NET runtime).
// Build: ./build.sh Minimal
//
// Under the updated memory safety rules, creating a pointer (stackalloc) is
// safe; only the call that reads through it needs an unsafe block.

using System.Runtime.InteropServices;

namespace MinimalSample;

public static class Program
{
    [DllImport("libc")]
    static unsafe extern int puts(byte* s);

    public static int Main()
    {
        byte* msg = stackalloc byte[] {
            (byte)'H', (byte)'e', (byte)'l', (byte)'l', (byte)'o',
            (byte)' ', (byte)'f', (byte)'r', (byte)'o', (byte)'m',
            (byte)' ', (byte)'z', (byte)'e', (byte)'r', (byte)'o',
            (byte)'-', (byte)'m', (byte)'o', (byte)'d', (byte)'e', (byte)'!', 0
        };
        unsafe { puts(msg); } // SAFETY: msg is NUL-terminated.
        return 0;
    }
}
```

It calls the C library's `puts` directly. That's possible because a zero-mode program is a native
program: `[DllImport("libc")]` binds to the C function when the program is linked, with no
marshalling layer in between. The message is a `stackalloc` byte array, which is safe to create; only
the call that reads through the pointer needs an `unsafe` block, with a comment saying why it's safe.
That is C# 15's [updated memory safety rules](../concepts/safety-rules.html) at work.

## Build and run it

```bash
./build.sh Minimal
./run.sh Minimal
```

```text
Hello from zero-mode!
```

`build.sh` first compiles the core library (`zerocore/`) and the library (`lib/`), then the program,
into `bin/Minimal`. On Linux, `bin/Minimal` is an ordinary executable. On macOS it is a Linux
executable, and `run.sh` runs it in the container. On a Mac with Apple Silicon,
`./build.sh --mac Minimal` builds `bin/mac/Minimal` instead, a macOS program you can run directly.

## What you built

```bash
ls -l bin/Minimal
```

About 39 KB, debug information included. It needs nothing installed to run: no .NET, no runtime,
only the C library every Linux system has. `./build.sh Tiny` builds the smallest sample, stripped and
optimized for size: 16 KB.

## Without puts

Most programs don't call `puts`. They use `lib/`, which gives zero mode the pieces it lacks: `Out` for
output, `In` for input, arenas, strings and collections. With it, the same program is one line:

```csharp no-sample
Out.Line("Hello from zero-mode!");
```

The [tutorial](../tutorial/index.html) starts from there.

## Adding a program of your own

`build.sh` builds the programs it knows by name. To add one:

1. Create `samples/Hello.cs`. Give it its own namespace (`namespace HelloSample;`): the editor
   project compiles all the samples together.
2. Add `Hello` to `ALL_SAMPLES` at the top of `build.sh`, and to `DOS_SAMPLES` if it should build
   for DOS.
3. `./build.sh Hello && ./run.sh Hello`.

Next: the same program [on WebAssembly](webassembly.html).
