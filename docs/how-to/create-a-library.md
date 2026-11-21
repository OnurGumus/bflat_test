---
title: Create a reusable library
index: 14
---

# Create a reusable library

Code that several programs need goes in a library: a project of its own that builds to an IL `.dll`.
Programs use it through `<ProjectReference>`, or, once you've packed it with `dotnet pack`, through
`<PackageReference>` like any NuGet package. Each program's build compiles the parts of the library it
uses into its own binary, so there's nothing to ship next to the program. This guide uses the .NET SDK
packages ([Install with dotnet](../get-started/install-with-dotnet.html)); the
[last section](#in-this-repository) shows the same thing inside this repository.

## Make the library

```bash
dotnet new zerolib -o Geometry
```

The project file names the SDK and says it's a library:

```xml
<Project Sdk="ZeroCSharp.Sdk/0.1.0">
  <PropertyGroup>
    <OutputType>Library</OutputType>
    <Version>1.0.0</Version>
  </PropertyGroup>
</Project>
```

A library has no `Main`. Give it a namespace of its own, so its names don't collide with a program's.
These are the types of the example library, `libs/Geometry` in the repository:

<!-- sample: libs/Geometry/Shapes.cs types -->
```csharp
public interface IShape
{
    double Area { get; }
    double Perimeter { get; }
}

public record struct Point(double X, double Y);

public record struct Circle(double Radius) : IShape
{
    public double Area => Math.PI * Radius * Radius;
    public double Perimeter => 2 * Math.PI * Radius;
}

public record struct Rect(double Width, double Height) : IShape
{
    public double Area => Width * Height;
    public double Perimeter => 2 * (Width + Height);
}
```

A library can use everything a program can: zerocore, `lib/` (`Arena`, `List`, `Out` and the rest),
and other zero libraries it references. `dotnet build` checks it and makes `Geometry.dll`, optimized:
programs compile from its IL, so the SDK always optimizes a library, in Debug too.

## Use it from a program

Reference the library's project:

```xml
<Project Sdk="ZeroCSharp.Sdk/0.1.0">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="../Geometry/Geometry.csproj" />
  </ItemGroup>
</Project>
```

Then a `using` is all the code needs:

<!-- sample: samples/Shapes.cs use -->
```csharp
Span<Rect> rooms = stackalloc Rect[]
{
    new Rect(4, 3), new Rect(2.5, 2), new Rect(5, 4),
};
Out.Line($"Floor area: {Measure.TotalArea<Rect>(rooms):F2}");

var table = new Circle(0.5);
Out.Line($"Table: area {table.Area:F2}, perimeter {table.Perimeter:F2}");

Arena arena = Arena.Create(1024, "shapes");
List<Point> corners = Measure.Corners(rooms[0], arena);
for (int i = 0; i < corners.Count; i++)
    Out.Line(corners.Get(i).ToString());
unsafe { arena.Destroy(); } // SAFETY: corners isn't used after this.
```

`dotnet build` builds the library first, then the program:

```text
Floor area: 37.00
Table: area 0.79, perimeter 3.14
Point { X = 0, Y = 0 }
Point { X = 4, Y = 0 }
Point { X = 4, Y = 3 }
Point { X = 0, Y = 3 }
```

Change the library and build the program again: bflat runs again, because the library's `.dll` is one
of the program's inputs. A library is compiled for no target in particular, so the same `.dll` serves
every `ZeroTarget`.

## Share it as a package

`dotnet pack` puts the `.dll` in a NuGet package. Package ids are shared by everyone on nuget.org
(there is already an unrelated `Geometry`), so give yours a prefix of your own in the project file,
`<PackageId>Acme.Geometry</PackageId>`, then:

```bash
dotnet pack Geometry -o feed
```

The package holds `lib/zero01/Geometry.dll`. Publish it to nuget.org, or to a folder that a
`nuget.config` lists, and programs reference it like any package:

```xml
<ItemGroup>
  <PackageReference Include="Acme.Geometry" Version="1.0.0" />
</ItemGroup>
```

`zero01` is the target framework of every project made with version 0.1 of the SDK. It does two
things. NuGet won't add an ordinary .NET package to a zero project, because such a package is built for
.NET's libraries, which a zero program doesn't have:

```text
error NU1202: Package Newtonsoft.Json 13.0.3 is not compatible with zero01 (zero01,Version=v0.0).
```

And a zero library built with another version of the SDK (whose zerocore may differ) is refused the
same way, naming both versions:

```text
error NU1202: Package Acme.Geometry 1.0.0 is not compatible with zero01 (zero01,Version=v0.0).
Package Acme.Geometry 1.0.0 supports: zero02 (zero02,Version=v0.0)
```

Rebuild the library with your SDK version, or build the program with the library's.

## How it's built

The library's build is the C# compiler's, against zerocore and `lib/` instead of .NET's libraries; its
output is IL, not machine code, and its metadata takes the place of a C header. The program's build
gives that `.dll` to bflat with `-r`. bflat compiles the library's code together with the program's
own, for the program's target and `-m` flags, and leaves out whatever the program doesn't call: a
program that uses one function of a large library gets that function and what it calls.

## Design the library for zero mode

A library runs inside programs with no garbage collector and no exceptions you can catch, so a few
habits make it easier to use.

**Make generic code take structs.** A generic method with a `struct` constraint is compiled again
for each type a program calls it with, so calls to the interface's members are direct calls, and
nothing is boxed:

<!-- sample: libs/Geometry/Measure.cs generic -->
```csharp
// Compiled again, for each T, into the program that calls it: no boxing,
// no interface calls.
public static double TotalArea<T>(ReadOnlySpan<T> shapes)
    where T : struct, IShape
{
    double total = 0;
    foreach (T shape in shapes)
        total += shape.Area;
    return total;
}
```

**Let the caller say where memory comes from.** Nothing is freed unless an arena frees it, and only
the caller knows how long a result must live. So a function whose result outlives the call takes an
`Arena` and allocates there, instead of calling `new` or keeping an arena of its own:

<!-- sample: libs/Geometry/Measure.cs arena -->
```csharp
// The corners of a rectangle with its lower left corner at the origin,
// counter-clockwise, in a list that lives in the caller's arena.
public static List<Point> Corners(Rect rect, Arena arena)
{
    List<Point> corners = List<Point>.Create(arena, 4);
    corners.Add(new Point(0, 0));
    corners.Add(new Point(rect.Width, 0));
    corners.Add(new Point(rect.Width, rect.Height));
    corners.Add(new Point(0, rect.Height));
    return corners;
}
```

**Return errors, don't throw them.** A `throw` in a library ends the program that called it, which
can't catch it. Return a `bool` with an `out` value, or a [union](../concepts/limits.html) of a result
and an error, and let the program decide.

**Keep helpers `internal`.** Programs can't see `internal` members, so the library can change them
without breaking anyone:

<!-- sample: libs/Geometry/Measure.cs internal -->
```csharp
// Whether two areas are equal to within rounding. internal: programs
// can't call it, so the library can change it freely.
internal static bool Near(double a, double b)
    => Math.Abs(a - b) < 1e-9 * (1 + Math.Abs(a));

public static bool SameArea<A, B>(in A a, in B b)
    where A : struct, IShape
    where B : struct, IShape
    => Near(a.Area, b.Area);
```

A library's static fields work as in a program: one copy per program, set up by static constructors
as usual. A program has no other copy of the library to share them with.

## Use one library from another

A library references another the same way a program does, with `<ProjectReference>` or
`<PackageReference>`. References can't go in a circle: if two libraries need each other, they are one
library.

## In this repository

Working in a clone of this repository, without the SDK, `build.sh` has its own convention: each folder
in `libs/` is a library. `build.sh` compiles each into `bin/libs/<folder>.dll`, in name order (so each
can use the ones before it), and every sample references all of them:

```bash
bflat build-il libs/Geometry/*.cs -O --target Shared --stdlib:none \
    -r bin/System.Private.CoreLib.dll -r bin/BflatLib.dll \
    --langversion preview --compiler-feature updated-memory-safety-rules \
    -o bin/libs/Geometry.dll
```

`-O` matters there: `build-il` doesn't optimize unless asked. `samples/Shapes.cs` uses
`libs/Geometry` this way, on every target `build.sh` knows, macOS, WebAssembly and DOS included:

```bash
./build.sh Shapes
./run.sh Shapes
```

## What a library isn't

A library is compiled into each program that uses it. It isn't loaded at run time: there's no runtime
to load it into, and neither the SDK nor `build.sh` builds native shared libraries (`.so`, `.dylib`,
`.dll`) for C programs to call.
