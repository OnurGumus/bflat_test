// Example: Minimal zero-mode "Hello World"
// Build: bflat build Minimal.cs --stdlib:zero -o Minimal
// Size: ~45KB - no .NET runtime, just native code!

using System.Runtime.InteropServices;

unsafe class Program
{
    [DllImport("libc")]
    static extern int puts(byte* s);

    static int Main()
    {
        byte* msg = stackalloc byte[] {
            (byte)'H', (byte)'e', (byte)'l', (byte)'l', (byte)'o',
            (byte)' ', (byte)'f', (byte)'r', (byte)'o', (byte)'m',
            (byte)' ', (byte)'z', (byte)'e', (byte)'r', (byte)'o',
            (byte)'-', (byte)'m', (byte)'o', (byte)'d', (byte)'e', (byte)'!', 0
        };
        puts(msg);
        return 0;
    }
}
