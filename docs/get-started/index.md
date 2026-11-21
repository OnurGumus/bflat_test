---
title: Get started
index: 0
---

# Get started

This site documents zero-mode C#: C# compiled by a fork of [bflat](https://flattened.net/) into small
native programs that carry no .NET runtime and no garbage collector. A program here is C#'s syntax,
type checking and generics, compiled to something the size of a C program: the hello-world sample is
about 39 KB, the smallest one 16 KB.

The same source builds for five targets:

- **Native Linux**, x64 or arm64. On macOS the compiler runs in a Linux container.
- **macOS on Apple Silicon**, programs that run on the Mac directly.
- **Windows x64**, built from Linux or macOS and tested under Wine.
- **WebAssembly** (WASI), run with wasmtime.
- **DOS on a 386**, run under FreeDOS in an emulator, or on old hardware.

Without a runtime, some of C# is missing, and memory works differently: `new` allocates and nothing
ever frees it, so programs allocate from arenas that they free all at once. The repository's core
library (`zerocore/`) and library (`lib/`) give you strings, collections, input and output on those
terms.

## Where to go

1. [Install with dotnet](install-with-dotnet.html): on Linux, `dotnet new zero` and `dotnet build`
   make a native program, with nothing to clone. Or [install from the repository](install.html), the
   bflat fork and its prerequisites, which also builds for macOS, WebAssembly and DOS.
2. [Build your first program](first-program.html) and run it.
3. Run the same program [on WebAssembly](webassembly.html) and [on DOS](dos.html).

Or skip the installing: [run the samples in your browser](browser.html), compiled to WebAssembly from
this site's version of the code.

Then the [tutorial](../tutorial/index.html) builds a small interactive program step by step, the
[concepts](../concepts/index.html) explain how zero mode works and why, and the
[task guides](../how-to/index.html) answer specific questions.
