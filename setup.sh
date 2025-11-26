#!/bin/bash
# Setup script for bflat on Linux
# Downloads and extracts bflat to ./bflat directory

set -e

BFLAT_VERSION="9.0.0"
BFLAT_URL="https://github.com/AustinWise/NativeAOT-LLVM/releases/download/v${BFLAT_VERSION}/bflat-${BFLAT_VERSION}-linux-glibc-x64.tar.gz"

echo "=== bflat Setup ==="
echo "Downloading bflat ${BFLAT_VERSION}..."

# Download
curl -L -o bflat.tar.gz "${BFLAT_URL}" || wget -O bflat.tar.gz "${BFLAT_URL}"

# Extract
echo "Extracting..."
tar -xzf bflat.tar.gz
rm bflat.tar.gz

# Find the extracted directory
BFLAT_DIR=$(ls -d bflat-* 2>/dev/null | head -1)

if [ -z "$BFLAT_DIR" ]; then
    echo "Error: Could not find extracted bflat directory"
    exit 1
fi

echo ""
echo "=== Setup Complete ==="
echo "bflat installed to: ./${BFLAT_DIR}"
echo ""
echo "Add to PATH:"
echo "  export PATH=\"\$PWD/${BFLAT_DIR}:\$PATH\""
echo ""
echo "Or run directly:"
echo "  ./${BFLAT_DIR}/bflat build Minimal.cs --stdlib:zero -o Minimal"
