// Compiles against zerocore and lib/ only: Out, Arena and a record struct.
public record struct Point(int X, int Y);

public static class Hello
{
    public static void Run()
    {
        Arena arena = Arena.Create(256, "hello");
        Out.Line(new Point(1, 2).ToString());
        unsafe { arena.Destroy(); } // SAFETY: nothing from the arena is used after this.
    }
}
