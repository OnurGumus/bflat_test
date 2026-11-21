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
