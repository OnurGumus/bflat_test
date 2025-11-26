// Example: Smallest possible bflat binary
// Build: bflat build Tiny.cs --stdlib:zero -Os --no-pie -o Tiny && strip Tiny
// Size: ~16KB after stripping!

using System.Runtime.InteropServices;

unsafe class Program
{
    [DllImport("libc")]
    static extern int puts(byte* s);

    static int Main()
    {
        byte* msg = stackalloc byte[] { (byte)'H', (byte)'i', 0 };
        puts(msg);
        return 0;
    }
}
