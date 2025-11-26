# Build all examples for Windows
# Assumes bflat is in PATH or in .\bflat-* directory

$ErrorActionPreference = "Stop"

# Find bflat
$BFLAT = Get-Command bflat -ErrorAction SilentlyContinue
if (-not $BFLAT) {
    $BFLAT_DIR = Get-ChildItem -Directory -Filter "bflat-*" | Select-Object -First 1
    if ($BFLAT_DIR) {
        $BFLAT = Join-Path $BFLAT_DIR.FullName "bflat.exe"
    } else {
        Write-Host "Error: bflat not found. Run .\setup.ps1 first or add bflat to PATH" -ForegroundColor Red
        exit 1
    }
} else {
    $BFLAT = $BFLAT.Source
}

Write-Host "Using: $BFLAT"
Write-Host ""

# Create output directory
New-Item -ItemType Directory -Force -Path "bin" | Out-Null

Write-Host "=== Building Zero Mode Examples ===" -ForegroundColor Cyan

Write-Host "[1/5] Building Tiny (smallest binary)..."
& $BFLAT build Tiny.cs --stdlib:zero -Os -o bin\Tiny.exe

Write-Host "[2/5] Building Minimal..."
& $BFLAT build Minimal.cs --stdlib:zero -o bin\Minimal.exe

Write-Host "[3/5] Building Arena (memory allocator)..."
& $BFLAT build Arena.cs --stdlib:zero -o bin\Arena.exe

Write-Host "[4/5] Building Collections (List, Dict)..."
& $BFLAT build Collections.cs --stdlib:zero -o bin\Collections.exe

Write-Host "[5/5] Building VirtualTest (polymorphism)..."
& $BFLAT build VirtualTest.cs --stdlib:zero -o bin\VirtualTest.exe

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Get-ChildItem bin\*.exe | Format-Table Name, @{N='Size (KB)';E={[math]::Round($_.Length/1KB,1)}}
Write-Host ""
Write-Host "Run examples:"
Write-Host "  .\bin\Minimal.exe"
Write-Host "  .\bin\Arena.exe"
Write-Host "  .\bin\Collections.exe"
Write-Host "  .\bin\VirtualTest.exe"
