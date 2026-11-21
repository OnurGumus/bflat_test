#!/usr/bin/env bash
# Copies the part of a bflat layout that zero-mode builds use: about 80 of its
# files, 550 MB down to about 110 MB. The ZeroCSharp.Bflat packages carry the
# result.
#
# Which files: the ones bflat opens while it builds, found by tracing real
# builds (strace) in a container, for every target the SDK supports. Then
# bflat and its linker are stripped of debug information.
#
# Usage:  sdk/trim-layout.sh <layout> <out>
#         <layout>  a full layout, e.g. ../bflat/layouts/linux-glibc-x64
#         <out>     where to put the trimmed copy (replaced)
# Needs Docker, and the SDK payload (./build.sh --sdk-payload
# sdk/ZeroCSharp.Sdk/payload), whose libraries and objects the builds use.
set -euo pipefail
cd "$(dirname "$0")/.."

layout=$(cd "${1:?layout}" && pwd)
out=${2:?out}
payload=sdk/ZeroCSharp.Sdk/payload
if [ ! -f "$payload/ref/BflatLib.dll" ]; then
    echo "Error: no SDK payload in $payload. Run ./build.sh --sdk-payload $payload" >&2
    exit 1
fi
case "$(file -b "$layout/bflat")" in
    *x86-64*)  platform=linux/amd64 ;;
    *aarch64*) platform=linux/arm64 ;;
    *) echo "Error: $layout/bflat isn't a Linux x64 or arm64 program." >&2; exit 1 ;;
esac

rm -rf "$out"
mkdir -p "$out"
out=$(cd "$out" && pwd)

# The build image has libtinfo5 and binutils, which older layouts' tools need;
# strace is added for the trace.
source ./env.sh
ensure_image
docker run --rm --platform "$platform" -v "$PWD:/w" -v "$layout:/bflat:ro" -v "$out:/out" -w /w "$IMAGE" bash -c '
set -euo pipefail
(apt-get update -qq && apt-get install -y -qq strace) > /dev/null 2>&1
P='"$payload"'
F="--stdlib:none --langversion preview --compiler-feature updated-memory-safety-rules --no-reflection -i libc -i libm.so.6"
R="-r $P/ref/BflatLib.dll -r $P/ref/System.Private.CoreLib.dll"
WIN="--os windows --arch x64 --ldflags /entry:zero_start --ldflags $P/native/win-x64/runtime.obj --ldflags $P/native/win-x64/zerocore.obj"
n=0
trace() {
    n=$((n + 1))
    strace -f -qq -e trace=openat,execve -o /tmp/trace.$n /bflat/bflat build "$@" $R $F -o /tmp/out.$n > /tmp/log.$n 2>&1 \
        || { echo "A traced build failed: bflat build $*" >&2; cat /tmp/log.$n >&2; exit 1; }
}
for s in Minimal Strings Threads; do
    trace samples/$s.cs --arch arm64 --ldflags $P/native/linux-arm64/zerocore.o --ldflags "-z max-page-size=4096" --ldflags "-z nostart-stop-gc"
    trace samples/$s.cs --arch x64 --ldflags $P/native/linux-x64/zerocore.o --ldflags "-z nostart-stop-gc"
    trace samples/$s.cs $WIN
done
trace samples/Minimal.cs --arch arm64 -m dotprod --ldflags $P/native/linux-arm64/zerocore.o --ldflags "-z nostart-stop-gc"
trace samples/Minimal.cs --arch x64 -m x86-64-v3 --ldflags $P/native/linux-x64/zerocore.o --ldflags "-z nostart-stop-gc"
trace samples/Minimal.cs --arch x64 -Os --ldflags $P/native/linux-x64/zerocore.o --ldflags "-z nostart-stop-gc"
# Every layout file opened, plus the license notices.
cat /tmp/trace.* | grep -v ENOENT | grep -o "\"/bflat/[^\"]*\"" | tr -d "\"" | sed "s|^/bflat/||" | sort -u > /tmp/opened
cd /bflat
{ cat /tmp/opened; ls | grep -iE "license|notice"; } | sort -u | while read -r f; do
    [ -f "$f" ] && echo "$f"
done > /tmp/files
tar cf - -T /tmp/files | tar xf - -C /out
# No debug information: bflat and lld are most of the size.
for f in bflat bin/lld; do
    [ -f "/out/$f" ] && /bflat/bin/llvm-objcopy --strip-all "/out/$f"
done
echo "$(wc -l < /tmp/files) files, $(du -sh /out | cut -f1)"
'
