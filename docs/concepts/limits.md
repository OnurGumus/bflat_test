---
title: Limits
index: 6
---

# Limits

Zero mode has no garbage collector, no exceptions you can catch, no async/await, no .NET LINQ, and almost no base class
library. A good deal of ordinary C# still works, because zerocore provides the parts the compiler
needs. This page lists both sides and the known issues, so you can tell early whether a design fits.

## What works

With zerocore, as `build.sh` builds it:

- **Classes, structs and generics**, virtual methods, and interfaces, including default interface
  methods. Every `new` calls `calloc` and is never freed (see [Memory without a GC](memory.html)).
- **Static abstract interface members** and constrained generic calls.
- **Casts**: `(T)x`, `is`, `as` and type patterns, to classes and interfaces. **Boxing**: a struct
  converted to `object` or to an interface it implements.
- **Arrays**: `new T[n]`, including arrays of strings, objects and interfaces, array initializers, and
  `Span<T>`.
- **Static fields of every type**, including strings, objects and arrays, and static constructors.
- **Strings**: `==`, `+` (with numbers too: `"n=" + 5`), `switch`, `ToString()` and `string.Format`,
  plus `lib/` for the rest (see [Strings without a GC](strings.html)).
- **Records and anonymous types**: value equality, `with`, deconstruction and the generated `ToString`;
  `typeof` and `GetType()` for comparing types. With no reflection, a `Type` has no name, and a class
  without its own `ToString` prints `object`.
- **Delegates and lambdas** (they allocate), `try`/`finally` and `using`.
- **Function pointers, P/Invoke and `[UnmanagedCallersOnly]` callbacks.**
- **Threads**: [`Parallel.For`](../how-to/run-in-parallel.html) runs a loop on every processor, with
  `Interlocked` and `Volatile` for shared state. There is no `Thread` class or `lock`.
- **`Math` and `MathF`**, and `Main(string[] args)` and top-level statements.
- **Extension methods**, and C# 14 **extension members**: properties, static members and
  `ref` receivers in `extension(...)` blocks.

Records work as in .NET, including the generated `ToString`:

<!-- sample: samples/Records.cs records -->
```csharp
public record struct Point(int X, int Y);

public record Person(string Name, int Age);

public record Employee(string Name, int Age, string Team) : Person(Name, Age);
```

<!-- sample: samples/Records.cs record-use -->
```csharp
var a = new Point(1, 2);
var b = new Point(Opaque(1), 2);
Point moved = a with { Y = 5 };
Out.Line(a.ToString());     // Point { X = 1, Y = 2 }
Out.Line(moved.ToString()); // Point { X = 1, Y = 5 }
```

Extension members compile to ordinary static methods, so they cost nothing at run time:

<!-- sample: samples/Core.cs extension-members -->
```csharp
public struct Vec
{
    public int X, Y;
}

public static class VecExtensions
{
    // Classic extension method: `this` on the first parameter.
    public static int Dot(this Vec a, Vec b) => a.X * b.X + a.Y * b.Y;

    // C# 14 extension block: properties and methods on a Vec value.
    extension(Vec v)
    {
        public int LengthSquared => v.Dot(v);
        public bool IsZero => v.X == 0 && v.Y == 0;
        public Vec Scale(int k) => new Vec { X = v.X * k, Y = v.Y * k };
    }

    // Static members, called as Vec.Zero and Vec.Of(1, 2).
    extension(Vec)
    {
        public static Vec Zero => default;
        public static Vec Of(int x, int y) => new Vec { X = x, Y = y };
    }

    // By reference: changes the caller's variable.
    extension(ref Vec v)
    {
        public void Translate(int dx, int dy)
        {
            v.X += dx;
            v.Y += dy;
        }
    }
}
```

<!-- sample: samples/Core.cs extension-calls -->
```csharp
Vec v = Vec.Of(Opaque(3), Opaque(4));
Check("extension method", v.Dot(Vec.Of(1, 1)) == 7);
Check("extension property", v.LengthSquared == 25);
Check("extension method in a block", v.Scale(2).LengthSquared == 100);
Check("static extension members", Vec.Zero.IsZero && !v.IsZero);
v.Translate(-3, -4);
Check("by-reference extension", v.IsZero);
```

C# 15 **unions** work too. A union holds a value of one of the types it lists, and a `switch` on it
must handle each of them, which makes it the natural way to return an error:

<!-- sample: samples/Core.cs union-declaration -->
```csharp
public struct Parsed { public int Value; }
public struct BadChar { public int Position; }

// A ParseResult holds either a Parsed or a BadChar, and a switch on it must
// handle both.
public union ParseResult(Parsed, BadChar);
```

<!-- sample: samples/Core.cs union-function -->
```csharp
static ParseResult ParseNumber(string text)
{
    int value = 0;
    for (int i = 0; i < text.Length; i++)
    {
        char c = text[i];
        if (c < '0' || c > '9')
            return new BadChar { Position = i };
        value = value * 10 + (c - '0');
    }
    return new Parsed { Value = value };
}

static int ValueOrMinusOne(string text) => ParseNumber(text) switch
{
    Parsed p => p.Value,
    BadChar => -1,
};
```

A union keeps its value in a field of type `object`, so a struct value is boxed: each `Parsed` or
`BadChar` returned above is a heap allocation that is never freed. That is fine for an error that
happens once, but not for a function called in a hot loop. There, return a struct with a tag field,
or allocate in an [arena](memory.html).

Casts to interfaces work as in .NET, except that a failed `(T)x` ends the program instead of throwing:

<!-- sample: samples/Casts.cs interface-checks -->
```csharp
object circle = Opaque(new Circle { Radius = 2 });
object rect = Opaque(new Rect { W = 3, H = 4 });
object square = Opaque(new Square { W = 5, H = 5 });
object plain = Opaque(new Plain());
object nothing = Opaque(null);

Check("class implementing it directly", circle is IShape);
Check("second interface of a class", rect is IScalable);
Check("not implemented", !(circle is IScalable));
Check("unrelated class", !(plain is IShape));
Check("unrelated interface", !(rect is IUnrelated));
Check("null is never an instance", !(nothing is IShape));
Check("through the base class", square is IShape && square is IScalable);
Check("through another interface", circle is INamed && square is INamed);
```

## Choosing how to dispatch

Interfaces and virtual methods both work, but they don't cost the same. An interface call the compiler
can't resolve at build time goes through a small cache per call site: a little slower than a virtual
call, and slower again at a site that sees more than four classes.

Generics with static abstract members avoid the question. They are resolved at compile time, one
specialized copy per struct type, with no allocation and no indirect call. That suits hot loops such as
per-format compute kernels:

<!-- sample: samples/VirtualTest.cs static-abstract -->
```csharp
public interface IArea<TSelf> where TSelf : struct, IArea<TSelf>
{
    static abstract string Name { get; }
    static abstract int Area(in TSelf shape);
}

public struct Rect : IArea<Rect>
{
    public int W, H;
    public static string Name => "Rect";
    public static int Area(in Rect r) => r.W * r.H;
}
```

<!-- sample: samples/VirtualTest.cs generic-call -->
```csharp
static void PrintArea<T>(in T shape) where T : struct, IArea<T>
{
    Out.Write(T.Name);
    Out.Line(" area: ", T.Area(in shape));
}
```

## What doesn't work

- **Freeing memory.** Nothing allocated with `new`, boxing or `+` is ever freed. Use
  [arenas](memory.html) for anything short-lived.
- **Catching exceptions.** `throw` is a panic, like Rust's `panic!` built with `panic = "abort"`:
  it prints the exception's message and ends the program. Nothing unwinds, so no `catch` block runs,
  and neither do the `finally` blocks and `using` disposals between the `throw` and `Main`. A failure
  that would throw in .NET, such as a failed cast, an index out of range or an overflow in `checked`
  code, ends the program the same way. A null dereference is a plain segmentation fault. `lib/`
  follows the same rule: when it catches a mistake, it can only end the program with a message.
  Return errors as values instead, for example with a union (see above).
- **Variance.** Casting or dispatching through it (`IEnumerable<string>` as `IEnumerable<object>`,
  `string[]` as `object[]`) aborts with a message saying so, instead of answering wrongly.
- **Most of the base class library.** No `Console` (use `Out` and `In`), no .NET collections (use
  [`lib/`'s](../how-to/choose-a-collection.html)), no LINQ (use [`lib/Seq.cs`](../how-to/query-data.html)),
  no reflection (a `Type` only compares), async, `Thread`, `Half`, or boxing of `Nullable<T>`.
- **A struct's default `Equals` compares bytes.** A reference field compares by reference, where .NET
  would call its `Equals`. Records and `IEquatable<T>` compare field by field.
- **Reflection.** Builds need `--no-reflection`.
- **Run-time CPU detection.** Instruction sets beyond the baseline are available only when the build
  names them with `-m`.
- **Some platforms.** zerocore runs on Linux (x64, arm64), macOS on Apple Silicon, Windows x64,
  WebAssembly and DOS. Not on Windows on arm64 or Intel Macs. And Windows programs are built from
  Linux or macOS: building *on* Windows (`build.ps1`) is untested and uses bflat's zerolib. The .NET
  SDK packages ([Install with dotnet](../get-started/install-with-dotnet.html)) build on Linux only,
  for Linux x64, Linux arm64 and Windows x64; macOS, WebAssembly and DOS need the repository.

`zerocore/README.md` has the full list.

## Known issues and workarounds

These are the issues you may hit with zerocore, as `build.sh` builds:

| Issue | Workaround |
|---|---|
| `[DllImport]` of a library not passed with `-i` fails to compile ("Expected type 'Internal.Runtime.CompilerHelpers.InteropHelpers' not found") | Pass `-i <library>`; `build.sh` passes `-i libc -i libm.so.6` |
| Building without `--no-reflection` fails ("Failed to load type 'Internal.Metadata.NativeFormat.TypeDefinition'") | Pass `--no-reflection`; `build.sh` does |
| Non-baseline instruction sets (AVX2, FMA, dotprod) report `IsSupported == false` | Build with `-m x86-64-v3` or `-m dotprod`; `build.sh` does this for Simd and Kernels |
| No `Console`, `Half`, `Thread` | `lib/Out.cs` for output, `lib/In.cs` for input; `Parallel.For` (`lib/Threads.cs`) for threads |
| `"n=" + 5`, `ToString()` and `string.Format` allocate a string that's never freed | Fine once; in a loop, `Str.Format(arena, $"n={5}")` |
| Casts and interface calls that need variance abort at run time | Not supported |
| Windows: x64 only, built from Linux or macOS | `./build.sh --win`; building on Windows (`build.ps1`) is untested |
| macOS: Apple Silicon only, built on a Mac | `./build.sh --mac` |

Two of these come from the core library having to be named `System.Private.CoreLib`. bflat assumes a
library with that name is .NET's and looks for its reflection support, hence `--no-reflection`. And
without `-i`, bflat binds a `[DllImport]` function when it is first called, which needs runtime support
zerocore doesn't have; with `-i`, it is bound at link time.

The other targets add limits of their own: no SIMD and no callbacks from native code on WebAssembly,
one thread and a 387 for floating point on DOS. [Targets](targets.html) covers them.

## Errors from the compiler

Most of zerocore is a contract with the compiler, which looks types, methods and fields up by name
(`System.Runtime.TypeCast.CheckCastClass`, `String._stringLength`, ...). When one it needs is missing,
the build fails with "Expected type ... not found" or "Failed to load type ...", not with a C# error.
Those names can't be changed. If you see such a message, check the first two rows of the table above
before anything else.
