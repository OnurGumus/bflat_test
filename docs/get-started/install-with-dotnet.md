---
title: Install with dotnet
index: 1
---

# Install with dotnet

With the .NET SDK, you can build zero-mode programs without cloning this repository. Three NuGet
packages do it: a project SDK (`ZeroCSharp.Sdk`), the bflat compiler for your machine
(`ZeroCSharp.Bflat.linux-x64` or `linux-arm64`, downloaded by the SDK), and the project templates
(`ZeroCSharp.Templates`). `dotnet build` then makes a native program, and your editor understands
the code.

## What you need

- **The .NET 10 SDK.** Nothing else: the packages bring the compiler and the linker.
- **Linux, x64 or arm64, to build programs.** The packages are tested on Ubuntu 22.04 and 24.04,
  Debian 12 and Fedora 41, each with nothing but the .NET SDK installed.
- **On macOS,** everything except the last step works: the editor, compiling, libraries and
  `dotnet pack`. Building a program stops with an error that says so. Build programs on a Linux
  machine or in a container, or [install from the repository](install.html), which also covers macOS,
  WebAssembly and DOS. Windows as a build machine comes in the next version.

## Make a program

```bash
dotnet new install ZeroCSharp.Templates
dotnet new zero -o Hello
cd Hello
dotnet build
```

`dotnet new zero` makes a project and this program, which reads a name into a buffer on the stack
and greets it:

<!-- sample: sdk/ZeroCSharp.Templates/content/zero/Program.cs file -->
```csharp
// A zero-mode program: no .NET runtime and no garbage collector. Out and In
// write and read without allocating; the name is read into a stack buffer.
using System;

Out.Write("What's your name? ");
Span<char> buffer = stackalloc char[64];
int length = In.ReadLine(buffer);
// length is -1 at the end of input, and more than the buffer holds when
// the line didn't fit: then keep what did.
ReadOnlySpan<char> name = length switch
{
    <= 0 => "world",
    _ when length > buffer.Length => buffer,
    _ => buffer.Slice(0, length),
};
Out.Write("Hello, ");
Out.Write(name);
Out.Line("!");
```

`dotnet build` puts the native program in `bin/Debug/zero01/`; `dotnet run` builds and runs it:

```bash
echo Ann | bin/Debug/zero01/Hello
echo Ann | dotnet run
```

```text
What's your name? Hello, Ann!
```

`zero01` is the project's target framework: zero mode, version 0.1 of the SDK. It keeps ordinary .NET
packages out, because they need .NET's libraries, which a zero program doesn't have.

## Build for another target

The `ZeroTarget` property picks what to build for; by default it's the machine you build on:

```bash
dotnet build -p:ZeroTarget=win-x64        # bin/Debug/zero01/Hello.exe
dotnet build -p:ZeroTarget=linux-arm64
```

| Property | Values | Default |
|---|---|---|
| `ZeroTarget` | `linux-x64`, `linux-arm64`, `win-x64` | the build machine's |
| `ZeroOptimizeFor` | `Speed`, or `Size` (bflat's `-Os`) | `Speed` |
| `ZeroInstructionSet` | passed to bflat as `-m`, e.g. `x86-64-v3` or `dotprod` (see [Use SIMD](../how-to/use-simd.html)) | none |
| `ZeroDllImports` | more libraries whose `[DllImport]`s are bound when linking, besides `libc` and `libm.so.6`, which always are | none |

Set them on the command line with `-p:`, or in the project file. The native program is optimized in
Debug and Release alike. `dotnet publish` copies it, and only it, to the publish folder: it needs
nothing next to it.

## What dotnet build does

It compiles your code twice. First the C# compiler compiles it against zerocore and `lib/`, the way
your editor sees it, into an IL `.dll`: this is where C# errors come from, and `Console` or any other
.NET API that zero mode doesn't have is an error here. Then bflat compiles the same sources into the
native program, with zerocore, `lib/` and any [zero libraries](../how-to/create-a-library.html) the
project references. bflat runs again only when a source, a referenced library or a property changed.

The compiler is pinned to the one bflat uses (Roslyn 5.12), so C# 15's unions and the
[memory safety rules](../concepts/safety-rules.html) work in `dotnet build` whatever your SDK's own
compiler is.

## Editors

Editors check code with the compiler they bundle, not the pinned one, so an editor whose compiler is
older than Roslyn 5.12 can mark C# 15 features as errors that `dotnet build` accepts, and a newer one
may treat preview features a little differently. For example, the C# extension for VS Code, version
11.9.41, bundles Roslyn 5.14. How editors handle these projects hasn't been checked yet: if yours
disagrees with `dotnet build`, `dotnet build` is right.

## Next

- [Your first program](first-program.html) goes through what a zero-mode program can and can't do,
  with the repository's build.
- [Create a reusable library](../how-to/create-a-library.html): `dotnet new zerolib`, references and
  packages.
