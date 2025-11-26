// Example: Function pointer polymorphism in bflat --stdlib:zero
// Build: bflat build VirtualTest.cs --stdlib:zero -o VirtualTest
// Size: ~51KB
//
// Zero mode doesn't support interfaces/virtual methods.
// Instead, use function pointers for "manual vtables" -
// same pattern C uses for OOP, with C#'s type-safe syntax.
//
// This is how game engines and embedded systems do polymorphism.

using System;
using System.Runtime.InteropServices;

// Manual "vtable" using function pointers
unsafe struct Shape
{
    public delegate*<Shape*, int> GetArea;
    public delegate*<Shape*, void> Describe;
    public int Param1;
    public int Param2;
}

unsafe class Program
{
    [DllImport("libc")]
    static extern int puts(byte* s);

    // "Methods" for Rectangle
    static int RectangleArea(Shape* s) => s->Param1 * s->Param2;
    static void RectangleDescribe(Shape* s)
    {
        Print("Rectangle");
        PrintNum("  Width: ", s->Param1);
        PrintNum("  Height: ", s->Param2);
        PrintNum("  Area: ", s->GetArea(s));
    }

    // "Methods" for Circle
    static int CircleArea(Shape* s) => 3 * s->Param1 * s->Param1;
    static void CircleDescribe(Shape* s)
    {
        Print("Circle");
        PrintNum("  Radius: ", s->Param1);
        PrintNum("  Area: ", s->GetArea(s));
    }

    // "Methods" for Square
    static int SquareArea(Shape* s) => s->Param1 * s->Param1;
    static void SquareDescribe(Shape* s)
    {
        Print("Square");
        PrintNum("  Side: ", s->Param1);
        PrintNum("  Area: ", s->GetArea(s));
    }

    // Factory functions
    static Shape CreateRectangle(int w, int h)
    {
        return new Shape
        {
            GetArea = &RectangleArea,
            Describe = &RectangleDescribe,
            Param1 = w,
            Param2 = h
        };
    }

    static Shape CreateCircle(int radius)
    {
        return new Shape
        {
            GetArea = &CircleArea,
            Describe = &CircleDescribe,
            Param1 = radius,
            Param2 = 0
        };
    }

    static Shape CreateSquare(int side)
    {
        return new Shape
        {
            GetArea = &SquareArea,
            Describe = &SquareDescribe,
            Param1 = side,
            Param2 = 0
        };
    }

    static int Main()
    {
        Print("=== Function Pointer Polymorphism ===");
        Print("(Manual vtable in --stdlib:zero)");
        Print("");

        // Create different "types"
        Shape rect = CreateRectangle(10, 5);
        Shape circle = CreateCircle(7);
        Shape square = CreateSquare(6);

        // Polymorphic dispatch via function pointers
        Print("--- Polymorphic Calls ---");

        rect.Describe(&rect);
        Print("");

        circle.Describe(&circle);
        Print("");

        square.Describe(&square);
        Print("");

        // Direct call
        Print("--- Direct Area Calls ---");
        PrintNum("Rectangle area: ", rect.GetArea(&rect));
        PrintNum("Circle area: ", circle.GetArea(&circle));
        PrintNum("Square area: ", square.GetArea(&square));

        Print("");
        Print("Done!");
        return 0;
    }

    public static void Print(string s)
    {
        fixed (char* c = s)
        {
            byte* buf = stackalloc byte[256];
            int i = 0;
            while (i < s.Length && i < 255) { buf[i] = (byte)c[i]; i++; }
            buf[i] = 0;
            puts(buf);
        }
    }

    public static void PrintNum(string prefix, int num)
    {
        fixed (char* c = prefix)
        {
            byte* buf = stackalloc byte[256];
            int i = 0;
            while (i < prefix.Length && i < 200) { buf[i] = (byte)c[i]; i++; }
            if (num < 0) { buf[i++] = (byte)'-'; num = -num; }
            if (num == 0) { buf[i++] = (byte)'0'; }
            else
            {
                int start = i;
                while (num > 0) { buf[i++] = (byte)('0' + num % 10); num /= 10; }
                for (int j = start, k = i - 1; j < k; j++, k--)
                { byte t = buf[j]; buf[j] = buf[k]; buf[k] = t; }
            }
            buf[i] = 0;
            puts(buf);
        }
    }
}
