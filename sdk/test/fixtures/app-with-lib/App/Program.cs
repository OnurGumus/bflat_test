// Uses the Geometry library (libs/Geometry) through a reference.
using System;
using Geometry;

public static class Program
{
    public static int Main()
    {
        Span<Rect> rooms = stackalloc Rect[] { new Rect(4, 3), new Rect(2.5, 2), new Rect(5, 4) };
        Out.Line($"Floor area: {Measure.TotalArea<Rect>(rooms):F2}");
        return 0;
    }
}
