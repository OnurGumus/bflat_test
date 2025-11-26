// Example: Generic collections for bflat --stdlib:zero
// Build: bflat build Collections.cs --stdlib:zero -o Collections
// Size: ~62KB
//
// Implements:
// - List<T>  - dynamic array with Add, Get, Set, RemoveAt
// - Dict<K,V> - hash map with Set, TryGet, ContainsKey
//
// All memory comes from a simple arena allocator.
// Works with any unmanaged type (int, structs, etc.)

using System;
using System.Runtime.InteropServices;
using System.Runtime.CompilerServices;

// ============================================
// Arena Allocator
// ============================================
unsafe static class Arena
{
    static byte* _start;
    static byte* _ptr;
    static byte* _end;

    [DllImport("libc")]
    static extern void* malloc(nuint size);

    [DllImport("libc")]
    static extern void free(void* ptr);

    public static void Init(nuint size)
    {
        _start = (byte*)malloc(size);
        _ptr = _start;
        _end = _start + size;
    }

    public static void Destroy()
    {
        if (_start != null) { free(_start); _start = null; }
    }

    public static void* Alloc(nuint size, nuint align = 8)
    {
        nuint p = (nuint)_ptr;
        nuint aligned = (p + (align - 1)) & ~(align - 1);
        byte* result = (byte*)aligned;
        _ptr = result + size;
        if (_ptr > _end) return null;
        for (nuint i = 0; i < size; i++) result[i] = 0;
        return result;
    }

    public static T* Alloc<T>() where T : unmanaged => (T*)Alloc((nuint)sizeof(T));
    public static T* AllocArray<T>(int count) where T : unmanaged => (T*)Alloc((nuint)(sizeof(T) * count));
    public static void Reset() => _ptr = _start;
    public static nuint Used => (nuint)(_ptr - _start);
}

// ============================================
// List<T> - dynamic array
// ============================================
unsafe struct List<T> where T : unmanaged
{
    T* _data;
    int _count;
    int _capacity;

    public int Count => _count;
    public int Capacity => _capacity;

    public static List<T> Create(int initialCapacity = 16)
    {
        var list = new List<T>();
        list._capacity = initialCapacity;
        list._data = Arena.AllocArray<T>(initialCapacity);
        list._count = 0;
        return list;
    }

    public void Add(T item)
    {
        if (_count >= _capacity)
            Grow();
        _data[_count++] = item;
    }

    public T Get(int index) => _data[index];
    public void Set(int index, T value) => _data[index] = value;
    public T* GetPtr(int index) => &_data[index];

    public bool RemoveAt(int index)
    {
        if (index < 0 || index >= _count) return false;
        for (int i = index; i < _count - 1; i++)
            _data[i] = _data[i + 1];
        _count--;
        return true;
    }

    public void Clear() => _count = 0;

    void Grow()
    {
        int newCap = _capacity * 2;
        T* newData = Arena.AllocArray<T>(newCap);
        for (int i = 0; i < _count; i++)
            newData[i] = _data[i];
        _data = newData;
        _capacity = newCap;
        // Old data stays in arena, freed on Reset()
    }
}

// ============================================
// Dictionary<TKey, TValue> - hash map
// ============================================
unsafe struct Dict<TKey, TValue>
    where TKey : unmanaged
    where TValue : unmanaged
{
    struct Entry
    {
        public TKey Key;
        public TValue Value;
        public bool Used;
        public int Hash;
    }

    Entry* _entries;
    int _capacity;
    int _count;

    public int Count => _count;

    public static Dict<TKey, TValue> Create(int capacity = 32)
    {
        var dict = new Dict<TKey, TValue>();
        dict._capacity = capacity;
        dict._entries = Arena.AllocArray<Entry>(capacity);
        dict._count = 0;
        return dict;
    }

    public void Set(TKey key, TValue value)
    {
        if (_count >= _capacity * 3 / 4)
            Grow();

        int hash = GetHash(key);
        int idx = (hash & 0x7FFFFFFF) % _capacity;

        // Linear probing
        while (_entries[idx].Used)
        {
            if (_entries[idx].Hash == hash && Equals(_entries[idx].Key, key))
            {
                _entries[idx].Value = value;
                return;
            }
            idx = (idx + 1) % _capacity;
        }

        _entries[idx].Key = key;
        _entries[idx].Value = value;
        _entries[idx].Hash = hash;
        _entries[idx].Used = true;
        _count++;
    }

    public bool TryGet(TKey key, out TValue value)
    {
        int hash = GetHash(key);
        int idx = (hash & 0x7FFFFFFF) % _capacity;
        int start = idx;

        while (_entries[idx].Used)
        {
            if (_entries[idx].Hash == hash && Equals(_entries[idx].Key, key))
            {
                value = _entries[idx].Value;
                return true;
            }
            idx = (idx + 1) % _capacity;
            if (idx == start) break;
        }

        value = default;
        return false;
    }

    public bool ContainsKey(TKey key)
    {
        TValue v;
        return TryGet(key, out v);
    }

    void Grow()
    {
        int oldCap = _capacity;
        Entry* oldEntries = _entries;

        _capacity *= 2;
        _entries = Arena.AllocArray<Entry>(_capacity);
        _count = 0;

        for (int i = 0; i < oldCap; i++)
        {
            if (oldEntries[i].Used)
                Set(oldEntries[i].Key, oldEntries[i].Value);
        }
    }

    static int GetHash(TKey key)
    {
        // Simple hash for unmanaged types - use bytes
        byte* p = (byte*)&key;
        int hash = 17;
        for (int i = 0; i < sizeof(TKey); i++)
            hash = hash * 31 + p[i];
        return hash;
    }

    static bool Equals(TKey a, TKey b)
    {
        byte* pa = (byte*)&a;
        byte* pb = (byte*)&b;
        for (int i = 0; i < sizeof(TKey); i++)
            if (pa[i] != pb[i]) return false;
        return true;
    }
}

// ============================================
// Demo
// ============================================
unsafe class Program
{
    [DllImport("libc")]
    static extern int puts(byte* s);

    static int Main()
    {
        Arena.Init(64 * 1024); // 64KB

        Print("=== Collections Demo ===");
        Print("");

        // List demo
        Print("--- List<int> ---");
        var numbers = List<int>.Create(4);
        for (int i = 1; i <= 10; i++)
            numbers.Add(i * 10);

        PrintNum("Count: ", numbers.Count);
        PrintNum("Capacity: ", numbers.Capacity);
        Print("Values:");
        PrintList(numbers);

        numbers.RemoveAt(5);
        Print("After RemoveAt(5):");
        PrintList(numbers);

        Print("");

        // List of structs
        Print("--- List<Point> ---");
        var points = List<Point>.Create();
        points.Add(new Point { X = 1, Y = 2 });
        points.Add(new Point { X = 10, Y = 20 });
        points.Add(new Point { X = 100, Y = 200 });

        for (int i = 0; i < points.Count; i++)
        {
            var p = points.Get(i);
            PrintPoint(i, &p);
        }

        Print("");

        // Dictionary demo
        Print("--- Dict<int, int> ---");
        var scores = Dict<int, int>.Create();
        scores.Set(1, 100);
        scores.Set(2, 250);
        scores.Set(3, 175);
        scores.Set(42, 999);

        PrintNum("Count: ", scores.Count);

        int val;
        if (scores.TryGet(2, out val))
            PrintNum("scores[2] = ", val);
        if (scores.TryGet(42, out val))
            PrintNum("scores[42] = ", val);
        if (!scores.TryGet(99, out val))
            Print("scores[99] not found");

        Print("");

        // Dictionary with struct keys
        Print("--- Dict<Point, int> ---");
        var pointIds = Dict<Point, int>.Create();
        pointIds.Set(new Point { X = 0, Y = 0 }, 1);
        pointIds.Set(new Point { X = 10, Y = 10 }, 2);
        pointIds.Set(new Point { X = 5, Y = 5 }, 3);

        Point lookup = new Point { X = 10, Y = 10 };
        if (pointIds.TryGet(lookup, out val))
            PrintNum("ID for (10,10): ", val);

        Print("");
        PrintNum("Arena used: ", (int)Arena.Used);

        Arena.Destroy();
        Print("Done!");

        return 0;
    }

    struct Point { public int X; public int Y; }

    static void PrintList(List<int> list)
    {
        byte* buf = stackalloc byte[256];
        int pos = 0;
        buf[pos++] = (byte)'[';
        for (int i = 0; i < list.Count; i++)
        {
            if (i > 0) { buf[pos++] = (byte)','; buf[pos++] = (byte)' '; }
            pos = AppendInt(buf, pos, list.Get(i));
        }
        buf[pos++] = (byte)']';
        buf[pos] = 0;
        puts(buf);
    }

    static void PrintPoint(int idx, Point* p)
    {
        byte* buf = stackalloc byte[64];
        int pos = 0;
        buf[pos++] = (byte)'[';
        pos = AppendInt(buf, pos, idx);
        buf[pos++] = (byte)']';
        buf[pos++] = (byte)' ';
        buf[pos++] = (byte)'(';
        pos = AppendInt(buf, pos, p->X);
        buf[pos++] = (byte)',';
        pos = AppendInt(buf, pos, p->Y);
        buf[pos++] = (byte)')';
        buf[pos] = 0;
        puts(buf);
    }

    static void Print(string s)
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

    static void PrintNum(string prefix, int num)
    {
        fixed (char* c = prefix)
        {
            byte* buf = stackalloc byte[256];
            int i = 0;
            while (i < prefix.Length && i < 200) { buf[i] = (byte)c[i]; i++; }
            i = AppendInt(buf, i, num);
            buf[i] = 0;
            puts(buf);
        }
    }

    static int AppendInt(byte* buf, int pos, int num)
    {
        if (num == 0) { buf[pos++] = (byte)'0'; return pos; }
        if (num < 0) { buf[pos++] = (byte)'-'; num = -num; }
        int start = pos;
        while (num > 0) { buf[pos++] = (byte)('0' + num % 10); num /= 10; }
        for (int j = start, k = pos - 1; j < k; j++, k--)
        { byte t = buf[j]; buf[j] = buf[k]; buf[k] = t; }
        return pos;
    }
}
