// A C# 15 union and a switch over it (as in samples/Core.cs).
public struct Parsed { public int Value; }
public struct BadChar { public int Position; }

public union ParseResult(Parsed, BadChar);

public static class Parse
{
    public static int ValueOrMinusOne(ParseResult r) => r switch
    {
        Parsed p => p.Value,
        BadChar => -1,
    };
}
