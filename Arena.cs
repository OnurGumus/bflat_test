// Example: Growable Arena (bump) allocator for bflat --stdlib:zero
// Build: bflat build Arena.cs --stdlib:zero -o Arena
// Size: ~50KB
//
// Features:
// - Fibonacci growth strategy (128 -> 128 -> 256 -> 384 -> 640...)
// - Generic Alloc<T>() for type-safe allocations
// - Linked list of blocks - auto-grows when full
// - Reset() frees extra blocks, keeps first
// - No GC - you control memory lifetime

using System;
using System.Runtime.InteropServices;
using System.Runtime.CompilerServices;

unsafe static class Arena
{
    // Block header - linked list of arena chunks
    struct Block
    {
        public Block* Next;
        public byte* Start;
        public byte* End;
        public nuint Size;
    }

    static Block* _firstBlock;
    static Block* _currentBlock;
    static byte* _ptr;
    static nuint _initialBlockSize;
    static nuint _lastBlockSize;
    static nuint _currentBlockSize;
    static int _blockCount;
    static nuint _totalAllocated;

    [DllImport("libc")]
    static extern void* malloc(nuint size);

    [DllImport("libc")]
    static extern void free(void* ptr);

    [DllImport("libc")]
    static extern int puts(byte* s);

    public static void Init(nuint blockSize = 4096)
    {
        _initialBlockSize = blockSize;
        _lastBlockSize = 0;
        _currentBlockSize = blockSize;
        _blockCount = 0;
        _totalAllocated = 0;
        _firstBlock = null;
        _currentBlock = null;
        _ptr = null;

        // Allocate first block
        AddBlock(blockSize);
    }

    static void AddBlock(nuint size)
    {
        // Allocate block header + data together
        nuint totalSize = (nuint)sizeof(Block) + size;
        byte* mem = (byte*)malloc(totalSize);

        if (mem == null)
            return;

        Block* block = (Block*)mem;
        block->Start = mem + sizeof(Block);
        block->End = block->Start + size;
        block->Size = size;
        block->Next = null;

        if (_firstBlock == null)
        {
            _firstBlock = block;
            _currentBlock = block;
        }
        else
        {
            _currentBlock->Next = block;
            _currentBlock = block;
        }

        _ptr = block->Start;
        _blockCount++;
    }

    public static void Destroy()
    {
        Block* block = _firstBlock;
        while (block != null)
        {
            Block* next = block->Next;
            free(block);
            block = next;
        }
        _firstBlock = null;
        _currentBlock = null;
        _ptr = null;
        _blockCount = 0;
        _totalAllocated = 0;
    }

    public static T* Alloc<T>() where T : unmanaged
    {
        return (T*)Alloc((nuint)sizeof(T), (nuint)sizeof(nuint));
    }

    public static T* AllocArray<T>(int count) where T : unmanaged
    {
        return (T*)Alloc((nuint)(sizeof(T) * count), (nuint)sizeof(nuint));
    }

    public static void* Alloc(nuint size, nuint align = 8)
    {
        if (_currentBlock == null)
            return null;

        // Align pointer
        nuint p = (nuint)_ptr;
        nuint aligned = (p + (align - 1)) & ~(align - 1);
        byte* result = (byte*)aligned;
        byte* newPtr = result + size;

        // Check if fits in current block
        if (newPtr > _currentBlock->End)
        {
            // Fibonacci growth: next = current + last
            nuint nextSize = _currentBlockSize + _lastBlockSize;
            if (nextSize < _currentBlockSize) // overflow protection
                nextSize = _currentBlockSize;
            if (nextSize == 0)
                nextSize = _initialBlockSize;

            // Make sure block is big enough for this allocation
            if (size + align > nextSize)
                nextSize = size + align;

            _lastBlockSize = _currentBlockSize;
            _currentBlockSize = nextSize;

            AddBlock(nextSize);

            if (_currentBlock == null)
                return null;

            // Realign in new block
            p = (nuint)_ptr;
            aligned = (p + (align - 1)) & ~(align - 1);
            result = (byte*)aligned;
            newPtr = result + size;
        }

        _ptr = newPtr;
        _totalAllocated += size;

        // Zero memory
        for (nuint i = 0; i < size; i++)
            result[i] = 0;

        return result;
    }

    public static void Reset()
    {
        // Free all blocks except the first
        if (_firstBlock != null)
        {
            Block* block = _firstBlock->Next;
            while (block != null)
            {
                Block* next = block->Next;
                free(block);
                block = next;
            }
            _firstBlock->Next = null;
            _currentBlock = _firstBlock;
            _ptr = _firstBlock->Start;
            _blockCount = 1;
            _totalAllocated = 0;

            // Reset Fibonacci sequence
            _lastBlockSize = 0;
            _currentBlockSize = _initialBlockSize;
        }
    }

    public static nuint TotalAllocated => _totalAllocated;
    public static int BlockCount => _blockCount;
    public static nuint CurrentBlockFree => (_currentBlock != null) ? (nuint)(_currentBlock->End - _ptr) : 0;
    public static nuint LastBlockSize => (_currentBlock != null) ? _currentBlock->Size : 0;
}

// Demo structs (use struct, not class, to avoid 'new')
unsafe struct Point
{
    public int X;
    public int Y;
    public Point* Next;  // Reference to another point
}

struct Entity
{
    public int Id;
    public Point Position;
    public Point Velocity;
}

unsafe class Program
{
    [DllImport("libc")]
    static extern int puts(byte* s);

    static int Main()
    {
        Print("=== Growable Arena Demo ===");

        // Init arena with small block size to demonstrate growth
        Arena.Init(128);  // Start with only 128 bytes
        PrintNum("Initial block size: ", 128);
        PrintNum("Block count: ", Arena.BlockCount);

        // Allocate some points
        Point* p1 = Arena.Alloc<Point>();
        p1->X = 10;
        p1->Y = 20;

        Point* p2 = Arena.Alloc<Point>();
        p2->X = 30;
        p2->Y = 40;

        PrintNum("After 2 Points, allocated: ", (int)Arena.TotalAllocated);
        PrintNum("Block count: ", Arena.BlockCount);

        // Link points together: p1 -> p2 -> p3 -> null
        Point* p3 = Arena.Alloc<Point>();
        p3->X = 50;
        p3->Y = 60;
        p3->Next = null;

        p2->Next = p3;
        p1->Next = p2;

        Print("");
        Print("Linked list: p1 -> p2 -> p3");

        // Walk the linked list
        Print("Walking linked points:");
        Point* current = p1;
        int index = 1;
        while (current != null)
        {
            PrintPoint("  Point ", index, current);
            current = current->Next;
            index++;
        }

        Print("");

        // Allocate an entity
        Entity* e = Arena.Alloc<Entity>();
        e->Id = 1;
        e->Position.X = 100;
        e->Position.Y = 200;

        PrintNum("After linked points + Entity, allocated: ", (int)Arena.TotalAllocated);
        PrintNum("Block count: ", Arena.BlockCount);

        // Allocate array of 10 ints
        int* arr = Arena.AllocArray<int>(10);
        for (int i = 0; i < 10; i++)
            arr[i] = i * i;

        PrintNum("After int[10], allocated: ", (int)Arena.TotalAllocated);
        PrintNum("Block count: ", Arena.BlockCount);
        PrintNum("arr[5] = ", arr[5]);

        // Force multiple block allocations to show Fibonacci growth
        Print("");
        Print("Forcing Fibonacci growth (128 -> 128 -> 256 -> 384 -> 640...)");

        for (int i = 0; i < 6; i++)
        {
            // Allocate enough to fill current block
            byte* filler = Arena.AllocArray<byte>(150);
            Print2Num("Blocks: ", Arena.BlockCount, " | Last block size: ", (int)Arena.LastBlockSize);
        }

        // Reset arena - frees extra blocks, keeps first
        Print("");
        Print("Resetting arena...");
        Arena.Reset();
        PrintNum("After reset, allocated: ", (int)Arena.TotalAllocated);
        PrintNum("Block count: ", Arena.BlockCount);

        // Can reuse memory now
        Point* p4 = Arena.Alloc<Point>();
        p4->X = 999;
        PrintNum("New point X: ", p4->X);

        // Cleanup
        Arena.Destroy();
        Print("Arena destroyed.");

        return 0;
    }

    static void Print(string s)
    {
        fixed (char* c = s)
        {
            byte* buf = stackalloc byte[256];
            int i = 0;
            while (i < s.Length && i < 255)
            {
                buf[i] = (byte)c[i];
                i++;
            }
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
            while (i < prefix.Length && i < 200)
            {
                buf[i] = (byte)c[i];
                i++;
            }
            if (num < 0) { buf[i++] = (byte)'-'; num = -num; }
            if (num == 0) { buf[i++] = (byte)'0'; }
            else
            {
                int start = i;
                while (num > 0)
                {
                    buf[i++] = (byte)('0' + num % 10);
                    num /= 10;
                }
                for (int j = start, k = i - 1; j < k; j++, k--)
                {
                    byte tmp = buf[j]; buf[j] = buf[k]; buf[k] = tmp;
                }
            }
            buf[i] = 0;
            puts(buf);
        }
    }

    static void PrintPoint(string prefix, int index, Point* p)
    {
        byte* buf = stackalloc byte[256];
        int i = 0;

        // Copy prefix
        fixed (char* c = prefix)
        {
            while (i < prefix.Length && i < 50)
            {
                buf[i] = (byte)c[i];
                i++;
            }
        }

        // Add index
        buf[i++] = (byte)('0' + index);
        buf[i++] = (byte)':';
        buf[i++] = (byte)' ';
        buf[i++] = (byte)'(';

        // Add X
        i = AppendInt(buf, i, p->X);
        buf[i++] = (byte)',';
        buf[i++] = (byte)' ';

        // Add Y
        i = AppendInt(buf, i, p->Y);
        buf[i++] = (byte)')';
        buf[i] = 0;

        puts(buf);
    }

    static int AppendInt(byte* buf, int i, int num)
    {
        if (num < 0) { buf[i++] = (byte)'-'; num = -num; }
        if (num == 0) { buf[i++] = (byte)'0'; return i; }

        int start = i;
        while (num > 0)
        {
            buf[i++] = (byte)('0' + num % 10);
            num /= 10;
        }
        // Reverse
        for (int j = start, k = i - 1; j < k; j++, k--)
        {
            byte tmp = buf[j]; buf[j] = buf[k]; buf[k] = tmp;
        }
        return i;
    }

    static void Print2Num(string p1, int n1, string p2, int n2)
    {
        byte* buf = stackalloc byte[256];
        int i = 0;
        fixed (char* c = p1)
        {
            for (int j = 0; j < p1.Length && i < 100; j++)
                buf[i++] = (byte)c[j];
        }
        i = AppendInt(buf, i, n1);
        fixed (char* c = p2)
        {
            for (int j = 0; j < p2.Length && i < 200; j++)
                buf[i++] = (byte)c[j];
        }
        i = AppendInt(buf, i, n2);
        buf[i] = 0;
        puts(buf);
    }
}
