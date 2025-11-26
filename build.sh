#!/bin/bash
# Build all examples for Linux
# Assumes bflat is in PATH or in ./bflat-* directory

set -e

# Find bflat
if command -v bflat &> /dev/null; then
    BFLAT="bflat"
else
    BFLAT=$(ls -d bflat-*/bflat 2>/dev/null | head -1)
    if [ -z "$BFLAT" ]; then
        echo "Error: bflat not found. Run ./setup.sh first or add bflat to PATH"
        exit 1
    fi
fi

echo "Using: $BFLAT"
echo ""

# Create output directory
mkdir -p bin

echo "=== Building Zero Mode Examples ==="

echo "[1/5] Building Tiny (smallest binary)..."
$BFLAT build Tiny.cs --stdlib:zero -Os --no-pie -o bin/Tiny
strip bin/Tiny

echo "[2/5] Building Minimal..."
$BFLAT build Minimal.cs --stdlib:zero -o bin/Minimal

echo "[3/5] Building Arena (memory allocator)..."
$BFLAT build Arena.cs --stdlib:zero -o bin/Arena

echo "[4/5] Building Collections (List, Dict)..."
$BFLAT build Collections.cs --stdlib:zero -o bin/Collections

echo "[5/5] Building VirtualTest (polymorphism)..."
$BFLAT build VirtualTest.cs --stdlib:zero -o bin/VirtualTest

echo ""
echo "=== Build Complete ==="
ls -lh bin/
echo ""
echo "Run examples:"
echo "  ./bin/Minimal"
echo "  ./bin/Arena"
echo "  ./bin/Collections"
echo "  ./bin/VirtualTest"
