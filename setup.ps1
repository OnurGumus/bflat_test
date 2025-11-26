# Setup script for bflat on Windows
# Downloads and extracts bflat to ./bflat directory

$ErrorActionPreference = "Stop"

$BFLAT_VERSION = "9.0.0"
$BFLAT_URL = "https://github.com/AustinWise/NativeAOT-LLVM/releases/download/v${BFLAT_VERSION}/bflat-${BFLAT_VERSION}-windows-x64.zip"

Write-Host "=== bflat Setup ===" -ForegroundColor Cyan
Write-Host "Downloading bflat ${BFLAT_VERSION}..."

# Download
Invoke-WebRequest -Uri $BFLAT_URL -OutFile "bflat.zip"

# Extract
Write-Host "Extracting..."
Expand-Archive -Path "bflat.zip" -DestinationPath "." -Force
Remove-Item "bflat.zip"

# Find the extracted directory
$BFLAT_DIR = Get-ChildItem -Directory -Filter "bflat-*" | Select-Object -First 1

if (-not $BFLAT_DIR) {
    Write-Host "Error: Could not find extracted bflat directory" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host "bflat installed to: .\$($BFLAT_DIR.Name)"
Write-Host ""
Write-Host "Add to PATH:"
Write-Host "  `$env:PATH = `"`$PWD\$($BFLAT_DIR.Name);`$env:PATH`""
Write-Host ""
Write-Host "Or run directly:"
Write-Host "  .\$($BFLAT_DIR.Name)\bflat.exe build Minimal.cs --stdlib:zero -o Minimal.exe"
