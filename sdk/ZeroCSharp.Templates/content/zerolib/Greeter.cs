// A library for zero-mode programs. It allocates nothing of its own: memory
// that must outlive a call comes from the caller's arena, and errors are
// returned, not thrown (a throw would end the caller's program).
using System;

namespace ZeroLibrary1;

public static class Greeter
{
    /// <summary>Writes "Hello, name!" to standard output.</summary>
    public static void Greet(ReadOnlySpan<char> name)
    {
        Out.Write("Hello, ");
        Out.Write(name);
        Out.Line("!");
    }
}
