// A [DllImport] of a library the build doesn't link: the C# compiler accepts
// it, but bflat can't bind it, so the native step must fail.
using System.Runtime.InteropServices;

public static class Program
{
    [DllImport("nosuchlib")]
    static unsafe extern int nosuchfunction();

    public static int Main()
    {
        unsafe { return nosuchfunction(); } // SAFETY: takes no arguments.
    }
}
