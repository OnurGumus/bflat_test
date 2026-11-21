#!/usr/bin/env bash
# Builds the samples with the bflat fork, which compiles C# 15 with the updated
# memory safety rules in one step. They run without .NET's runtime: the core
# library is zerocore/ (see zerocore/README.md), compiled from source here.
#
# On macOS bflat runs in a Linux container (see docker/Dockerfile); the
# binaries in ./bin are Linux binaries, so use ./run.sh to run them.
#
# With --wasm, builds WebAssembly modules (bin/wasm/*.wasm, WASI) instead, with
# NativeAOT-LLVM and the WASI SDK (./setup.sh --wasm downloads them).
#
# With --dos, builds 32-bit DOS programs for a 386 and later (bin/dos/*.exe),
# with NativeAOT-LLVM and a clang that has the x86 target (./setup.sh --dos).
#
# With --win, builds 64-bit Windows programs (bin/win/*.exe), with bflat and
# a clang that has the x86 target for the small C and assembly part.
#
# With --mac (on a Mac with Apple Silicon), builds macOS programs (bin/mac/*)
# that run directly, without the container: bflat compiles, Xcode's clang links.
# With MAC_OBJECTS_PREBUILT=1 it only links, using the object files already in
# bin/mac/obj (from `./build.sh --native-mac-objects <samples>` on Linux), and
# needs neither bflat nor Docker: that is how CI's macOS job works.
#
# Usage:  ./build.sh [--wasm | --dos | --win | --mac] [Sample ...]     default: all samples
#         ./build.sh --sdk-payload <dir>     what the ZeroCSharp.Sdk package carries (sdk/)
# Env:    BFLAT_DIR, BFLAT_FORK, BFLAT_ARCH, WASM_TOOLS, DOS_CLANG (see env.sh)
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

ALL_SAMPLES=(Tiny Minimal Arena Collections VirtualTest Casts Core Simd Kernels Strings QuizStep1 QuizStep2 QuizStep3 Quiz Guards Queries Threads Records Shapes Refs Llama)
# Simd and Kernels benchmark SIMD instructions, which a 386 doesn't have.
# Vga is a game for DOS only (lib/Dos.cs: graphics mode, keyboard, clock).
DOS_SAMPLES=(Tiny Minimal Arena Collections VirtualTest Casts Core Strings QuizStep1 QuizStep2 QuizStep3 Quiz Guards Queries Threads Records Shapes Refs Llama Vga)

# Language version and memory safety rules for every sample.
CSHARP_FLAGS=(--langversion preview --compiler-feature updated-memory-safety-rules)

# zerocore/ is the core library: object, string, Span<T>, and the runtime code
# the compiler expects to find (allocation, casts, static fields). bflat only
# accepts a custom core library under the name System.Private.CoreLib.
# --stdlib:none means "no built-in library": every build references this one.
CORE=bin/System.Private.CoreLib.dll
CORE_FLAGS=(--stdlib:none --langversion preview)

# lib/ is compiled once into an IL assembly that the samples reference with -r,
# the way a C program links a library, except the assembly's metadata replaces
# the header files. It holds IL, not native code: each sample's bflat build
# compiles the parts it uses, for its own -m flags, into a single binary.
# -O matters: unlike bflat build, build-il doesn't optimize unless asked.
LIB=bin/BflatLib.dll

# What every native build needs besides the sources:
# --no-reflection   bflat assumes a library named System.Private.CoreLib is
#                   .NET's and would look for its reflection support
# -i libc ...       bind [DllImport("libc")] at link time; binding at run time
#                   needs runtime support zerocore doesn't have
NATIVE_FLAGS=(--no-reflection -i libc -i libm.so.6)

check_sample() {
    case " ${ALL_SAMPLES[*]} " in
        *" $1 "*) ;;
        *) echo "Unknown sample: $1 (known: ${ALL_SAMPLES[*]})" >&2; return 1 ;;
    esac
}

bflat_flags() {
    case "$1" in
        Tiny) echo -Os --no-pie ;;
        # Zero mode has no runtime CPU detection, so SIMD extensions must be part of
        # the baseline. x64: AVX2/FMA (Haswell, 2013, or newer). arm64 always has
        # NEON; dotprod (SDOT, for int8) needs ARMv8.2+, e.g. Apple M1 or Cortex-A76.
        Simd | Kernels | Llama)
            if [ "$BFLAT_ARCH" = x64 ]; then echo -m x86-64-v3; else echo -m dotprod; fi ;;
    esac
}

# arm64 links with 64 KB segment alignment by default, which pads even Tiny
# (~5 KB of code) to ~200 KB. 4 KB pages give the same sizes as x64, but the
# binaries then won't load on 16 KB/64 KB-page kernels (Asahi Linux, some
# servers); set ARM64_MAX_PAGE_SIZE=65536 for those.
ARM64_MAX_PAGE_SIZE=${ARM64_MAX_PAGE_SIZE:-4096}
# zerocore's few assembly routines (zerocore/native), linked into every binary.
CORE_NATIVE=bin/zerocore-$BFLAT_ARCH.o
LINK_FLAGS=(--ldflags "$CORE_NATIVE")
if [ "$BFLAT_ARCH" = arm64 ]; then
    LINK_FLAGS+=(--ldflags "-z max-page-size=$ARM64_MAX_PAGE_SIZE")
fi

# The sources of a sample: samples/<name>.cs, plus anything generated for it.
# Llama compiles its model and tokenizer in as byte literals, generated here
# from models/ into bin/gen/LlamaModel.cs (od is in coreutils, so this works
# in the build container too).
sample_sources() {
    echo "samples/$1.cs"
    if [ "$1" = Llama ]; then
        local out=bin/gen/LlamaModel.cs
        if [ ! -f "$out" ] || [ models/stories260K.bin -nt "$out" ] || [ models/tok512.bin -nt "$out" ]; then
            mkdir -p bin/gen
            {
                echo "// Generated by build.sh from models/: don't edit."
                echo "static class LlamaModel"
                echo "{"
                echo "    public static System.ReadOnlySpan<byte> Model => ["
                od -An -v -tu1 models/stories260K.bin | sed -E 's/^ +//; s/ +/, /g; s/$/,/'
                echo "    ];"
                echo "    public static System.ReadOnlySpan<byte> Tokenizer => ["
                od -An -v -tu1 models/tok512.bin | sed -E 's/^ +//; s/ +/, /g; s/$/,/'
                echo "    ];"
                echo "}"
            } > "$out.tmp"
            mv "$out.tmp" "$out"
        fi
        echo "$out"
    fi
}

check_bflat() {
    if [ ! -x "$BFLAT_DIR/bflat" ]; then
        echo "Error: no bflat at $BFLAT_DIR" >&2
        echo "       Build the fork's layouts (README, \"Getting bflat\") or set BFLAT_DIR." >&2
        exit 1
    fi
}

# $1: output assembly; the rest: extra flags (-d WASM for the WebAssembly build).
build_core() {
    local out=$1
    shift
    mkdir -p "$(dirname "$out")"
    echo "[bflat] zerocore/ -> $out"
    # shellcheck disable=SC2046
    "$BFLAT_DIR/bflat" build-il $(find zerocore -name '*.cs' | sort) -O "${CORE_FLAGS[@]}" "$@" -o "$out"
}

# Any assembler for the target will do: the cross one from the build image, or
# plain `as` when building on the target's own architecture.
build_core_native() {
    local triple as
    case "$BFLAT_ARCH" in
        x64)   triple=x86_64-linux-gnu ;;
        arm64) triple=aarch64-linux-gnu ;;
    esac
    if command -v "$triple-as" >/dev/null 2>&1; then
        as=$triple-as
    elif [ "$BFLAT_ARCH" = "$HOST_ARCH" ] && command -v as >/dev/null 2>&1; then
        as=as
    else
        echo "Error: no assembler for $BFLAT_ARCH. Install binutils (binutils-$triple to cross-compile)." >&2
        exit 1
    fi
    echo "[as]    zerocore/native/$BFLAT_ARCH.S -> $CORE_NATIVE"
    "$as" "zerocore/native/$BFLAT_ARCH.S" -o "$CORE_NATIVE"
}

# Your own libraries: each folder in libs/ is compiled, like lib/, into an IL
# assembly, bin/libs/<folder>.dll, and every program references all of them.
# A library can use zerocore, lib/ and the libraries before it in name order.
# LIB_REFS holds the -r flags for lib/ and these.
LIB_REFS=(-r "$LIB")

build_lib() {
    local dir name refs
    echo "[bflat] lib/*.cs -> $LIB"
    "$BFLAT_DIR/bflat" build-il lib/*.cs -O --stdlib:none -r "$CORE" "${CSHARP_FLAGS[@]}" --target Shared -o "$LIB"
    LIB_REFS=(-r "$LIB")
    for dir in libs/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        refs=("${LIB_REFS[@]}")
        mkdir -p bin/libs
        echo "[bflat] libs/$name/*.cs -> bin/libs/$name.dll"
        "$BFLAT_DIR/bflat" build-il "$dir"*.cs -O --stdlib:none -r "$CORE" "${refs[@]}" "${CSHARP_FLAGS[@]}" \
            --target Shared -o "bin/libs/$name.dll"
        LIB_REFS+=(-r "bin/libs/$name.dll")
    done
}

build_native() {
    local name
    check_bflat
    build_core "$CORE"
    build_core_native
    build_lib
    for name in "$@"; do
        echo "[bflat] $name -> bin/$name"
        # shellcheck disable=SC2046
        "$BFLAT_DIR/bflat" build $(sample_sources "$name") "${LIB_REFS[@]}" -r "$CORE" --stdlib:none "${CSHARP_FLAGS[@]}" \
            "${NATIVE_FLAGS[@]}" --arch "$BFLAT_ARCH" $(bflat_flags "$name") "${LINK_FLAGS[@]}" -o "bin/$name"
        if [ "$name" = Tiny ]; then
            if [ "$BFLAT_ARCH" = "$HOST_ARCH" ]; then
                strip "bin/$name"
            else
                echo "  (not stripped: strip can't handle $BFLAT_ARCH binaries on $HOST_ARCH)"
            fi
        fi
    done
}

# zerocore's WebAssembly build differs in how it finds static fields (-d WASM).
WASM_CORE=bin/wasm/System.Private.CoreLib.dll

check_wasm() {
    if [ ! -x "$WASM_ILC" ] || [ ! -x "$WASI_SDK/bin/clang" ]; then
        echo "Error: no WebAssembly toolchain in $WASM_TOOLS. Run ./setup.sh --wasm" >&2
        exit 1
    fi
}

# Source -> IL (bflat, as for the native build) -> LLVM bitcode (NativeAOT-LLVM).
# $1: sample; $2: directory for the output; $3: zerocore's WebAssembly build.
# Leaves $name.N.bc (bitcode: the code) and two WASM object files that need no
# compiling: $name.bc (the program's data) and $name.external.o.
compile_bitcode() {
    local name=$1 obj=$2 core=$3
    rm -rf "$obj"
    mkdir -p "$obj"

    "$BFLAT_DIR/bflat" build-il $(sample_sources "$name") "${LIB_REFS[@]}" -r "$CORE" -O --stdlib:none "${CSHARP_FLAGS[@]}" -o "$obj/$name.dll"

    # --directpinvoke binds [DllImport("libc")] and ("libm.so.6") at link time,
    # to the target's C library.
    if ! "$WASM_ILC" "$obj/$name.dll" "${LIB_REFS[@]}" -r "$core" --reflectiondata:none \
            --generateunmanagedentrypoints:System.Private.CoreLib \
            --targetos:wasi --targetarch:wasm -O --wasm-global-base:1024 \
            --codegenopt:Target=wasm32-unknown-wasip2 --codegenopt:LlvmExceptionHandlingModel=emulated \
            --directpinvoke:libc --directpinvoke:libm.so.6 -o:"$obj/$name.bc" > "$obj/ilc.log" 2>&1; then
        cat "$obj/ilc.log" >&2
        exit 1
    fi
}

# Bitcode (against zerocore's WebAssembly build) -> WASM objects (clang) -> one
# module, linked with wasm/runtime.c (zerocore's native half there) and WASI's
# C library.
build_wasm() {
    local name obj bc
    check_bflat
    check_wasm
    build_core "$CORE"
    build_core "$WASM_CORE" -d WASM
    build_lib
    for name in "$@"; do
        echo "[wasm]  $name -> bin/wasm/$name.wasm"
        obj=bin/wasm/obj/$name
        compile_bitcode "$name" "$obj" "$WASM_CORE"

        for bc in "$obj/$name".*.bc; do
            "$WASI_SDK/bin/clang" "$bc" -c -o "${bc%.bc}.o" -target wasm32-unknown-wasip2 -O2 \
                -mllvm -combiner-global-alias-analysis=false -mllvm -disable-lsr
        done
        cp "$obj/$name.bc" "$obj/$name.data.o"

        # wasip1, not wasip2: a WASI 0.2 exit only says success or failure, and the
        # samples report failures in their exit code. --no-stack-first: WASI SDK 34
        # puts the stack first by default, which clashes with the 1 KB global base.
        # --fatal-warnings: if wasm/runtime.c's signature for a function no longer
        # matches what NativeAOT-LLVM's code calls, wasm-ld only warns and links a
        # trap; this makes it a build error instead.
        "$WASI_SDK/bin/clang" -target wasm32-wasip1 -Os "$obj"/*.o wasm/runtime.c -lm -o "bin/wasm/$name.wasm" \
            -Wl,--no-stack-first -Wl,--global-base=1024 -Wl,-z,stack-size=1048576 \
            -Wl,--strip-all -Wl,--gc-sections -Wl,--fatal-warnings
    done
}

# ---- DOS ---------------------------------------------------------------------
#
# The same bitcode as for WebAssembly, compiled for a 386 instead. Three steps,
# because on macOS the first and last run in the build container (bflat,
# NativeAOT-LLVM and bflat's linker are Linux programs) and the middle one on
# the Mac (its clang has the x86 target; the WASI SDK's doesn't):
#
#   build_dos_bitcode   C# -> bitcode, against zerocore's single-threaded
#                       32-bit build (the WebAssembly one)
#   build_dos_objects   bitcode -> 386 object files; the program's data, which
#                       NativeAOT-LLVM writes as a WebAssembly object file, is
#                       rewritten as assembly by dos/wasm2i386.py
#   build_dos_link      -> a 32-bit Windows console program, which the HX DOS
#                       extender runs under DOS, with dos/runtime.c as its C
#                       library and zerocore's native half

DOS_CORE=bin/dos/System.Private.CoreLib.dll
# Windows object files (COFF), C calling convention, nothing newer than a 386.
DOS_TARGET=(-target i386-pc-windows-gnu -march=i386)

check_dos_ilc() {
    if [ ! -x "$WASM_ILC" ]; then
        echo "Error: no NativeAOT-LLVM in $WASM_TOOLS. Run ./setup.sh --dos" >&2
        exit 1
    fi
}

build_dos_bitcode() {
    local name
    check_bflat
    check_dos_ilc
    build_core "$CORE"
    build_core "$DOS_CORE" -d WASM
    build_lib
    for name in "$@"; do
        echo "[dos]   $name -> bitcode"
        compile_bitcode "$name" "bin/dos/obj/$name" "$DOS_CORE"
    done
}

# $1: clang; the rest: samples.
build_dos_objects() {
    local clang=$1 name obj out source bc
    shift
    "$clang" "${DOS_TARGET[@]}" -O2 -ffreestanding -fno-builtin -Wall -Wextra -c dos/runtime.c -o bin/dos/obj/runtime.o
    for name in "$@"; do
        echo "[dos]   $name -> 386 code"
        obj=bin/dos/obj/$name
        out=$obj/i386
        mkdir -p "$out"

        python3 dos/wasm2i386.py "$obj/$name.bc" "$out/data"
        if [ -f "$obj/$name.external.o" ]; then
            python3 dos/wasm2i386.py "$obj/$name.external.o" "$out/external"
        fi
        for source in "$out"/*.s; do
            "$clang" "${DOS_TARGET[@]}" -c "$source" -o "$source.o"
        done
        for source in "$out"/*.c; do
            [ -f "$source" ] || continue
            "$clang" "${DOS_TARGET[@]}" -O2 -ffreestanding -c "$source" -o "$source.o"
        done

        for bc in "$obj/$name".*.bc; do
            source=$out/$(basename "${bc%.bc}")
            # The flag compiled code checks after every call (RhpExceptionThrown)
            # is declared thread-local. These programs have one thread, and
            # Windows-style thread-local storage costs three more memory reads
            # per check, so make it an ordinary variable: bitcode -> text ->
            # edit -> object file.
            "$clang" "${DOS_TARGET[@]}" -Wno-override-module -S -emit-llvm "$bc" -o "$source.bc.ll"
            sed -E 's/^(@[A-Za-z0-9_.$]+ = external) thread_local /\1 /' "$source.bc.ll" > "$source.ll"
            rm "$source.bc.ll"
            if grep -q thread_local "$source.ll"; then
                echo "Error: thread-local variables left in $source.ll" >&2
                exit 1
            fi
            "$clang" "${DOS_TARGET[@]}" -O2 -c "$source.ll" -o "$source.o"
        done
    done
}

build_dos_link() {
    local name
    check_bflat
    for name in "$@"; do
        echo "[dos]   $name -> bin/dos/$name.exe"
        # /safeseh:no: no table of Windows exception handlers; there are none.
        "$BFLAT_DIR/bin/lld" -flavor link /nologo "/out:bin/dos/$name.exe" /subsystem:console \
            /entry:start /nodefaultlib /safeseh:no /stack:262144 /opt:ref \
            bin/dos/obj/runtime.o "bin/dos/obj/$name/i386"/*.o "$BFLAT_DIR/lib/windows/x86/kernel32.lib"
    done
}

# "Runs on a 386" is easy to break without noticing: one atomic operation or
# byte swap and the compiler emits a 486 instruction, and most emulators run it
# anyway. So disassemble each program and refuse anything newer than a 386 and
# its 387 coprocessor. $1: llvm-objdump; the rest: samples.
NEWER_THAN_386='^(cmov|fcmov|fu?comip? |fisttp|bswap|cmpxchg|xadd|cpuid|rdtsc|rdmsr|wrmsr|rdpmc|invd|wbinvd|invlpg|sysenter|sysexit|ud2|prefetch|cvt|nopw|nopl|[lms]fence|pause|emms|fxsave|fxrstor|popcnt|lzcnt|tzcnt|movbe|<unknown>)|xmm|ymm|%mm[0-7]'

check_386() {
    local objdump=$1 name bad
    shift
    for name in "$@"; do
        bad=$("$objdump" -d --no-show-raw-insn "bin/dos/$name.exe" \
            | awk '/^ *[0-9a-f]+:/ { print $2, $3, $4 }' | grep -E "$NEWER_THAN_386" | sort | uniq -c || true)
        if [ -n "$bad" ]; then
            echo "Error: bin/dos/$name.exe has instructions a 386 can't run:" >&2
            echo "$bad" >&2
            exit 1
        fi
    done
}

# Windows, x64 only. The same bflat compiles the samples, against the same
# zerocore, with two Windows object files linked in:
#   win/runtime.c               the entry point, and write/read/clock_gettime
#                               on top of kernel32 (the rest of the C library
#                               is Windows' own Universal CRT)
#   zerocore/native/win-x64.S   x64.S for the Windows calling convention
# clang compiles both on the host (Xcode's on macOS), like dos/runtime.c.
WIN_OBJ=bin/win/obj
WIN_TARGET=(-target x86_64-pc-windows-msvc)

# $1: clang
build_win_objects() {
    local clang=$1
    mkdir -p "$WIN_OBJ"
    echo "[clang] win/runtime.c, zerocore/native/win-x64.S -> $WIN_OBJ"
    "$clang" "${WIN_TARGET[@]}" -O2 -ffreestanding -fno-builtin -Wall -Wextra -c win/runtime.c -o "$WIN_OBJ/runtime.obj"
    "$clang" "${WIN_TARGET[@]}" -c zerocore/native/win-x64.S -o "$WIN_OBJ/zerocore.obj"
}

build_win() {
    local name
    check_bflat
    build_core "$CORE"
    build_lib
    for name in "$@"; do
        echo "[bflat] $name -> bin/win/$name.exe"
        # /entry: bflat names __managed__Main, which expects argc and argv;
        # zero_start (win/runtime.c) makes them first. The later /entry wins.
        # shellcheck disable=SC2046
        "$BFLAT_DIR/bflat" build $(sample_sources "$name") "${LIB_REFS[@]}" -r "$CORE" --stdlib:none \
            "${CSHARP_FLAGS[@]}" "${NATIVE_FLAGS[@]}" --os windows --arch x64 $(BFLAT_ARCH=x64 bflat_flags "$name") \
            --ldflags "/entry:zero_start $WIN_OBJ/runtime.obj $WIN_OBJ/zerocore.obj" -o "bin/win/$name.exe"
        rm -f "bin/win/$name.pdb"
    done
}

# macOS on Apple Silicon. bflat has no Mach-O linker, so it only compiles
# (--os macos -c, in the container), and the Mac's own clang and linker do
# the rest, with two macOS files:
#   mac/runtime.c               main, and clock_gettime for the samples' clock
#   zerocore/native/mac-arm64.S arm64.S, as a Mach-O object
MAC_OBJ=bin/mac/obj

build_mac_objects() {
    local name
    check_bflat
    build_core "$CORE"
    build_lib
    mkdir -p "$MAC_OBJ"
    for name in "$@"; do
        echo "[bflat] $name -> $MAC_OBJ/$name.o"
        # shellcheck disable=SC2046
        "$BFLAT_DIR/bflat" build $(sample_sources "$name") "${LIB_REFS[@]}" -r "$CORE" --stdlib:none \
            "${CSHARP_FLAGS[@]}" "${NATIVE_FLAGS[@]}" --os macos --arch arm64 -c \
            $(BFLAT_ARCH=arm64 bflat_flags "$name") -o "$MAC_OBJ/$name.o"
    done
}

# $1: clang; the rest: samples.
build_mac_link() {
    local clang=$1 name
    shift
    echo "[clang] mac/runtime.c, zerocore/native/mac-arm64.S -> $MAC_OBJ"
    "$clang" -arch arm64 -O2 -Wall -Wextra -c mac/runtime.c -o "$MAC_OBJ/runtime.o"
    "$clang" -arch arm64 -c zerocore/native/mac-arm64.S -o "$MAC_OBJ/zerocore.o"
    for name in "$@"; do
        echo "[ld]    $name -> bin/mac/$name"
        # zerocore finds the compiler's module list between __start___modules
        # and __stop___modules, which GNU ld defines on Linux. Apple's linker
        # has its own names for a section's bounds; -alias maps them.
        "$clang" -arch arm64 -o "bin/mac/$name" "$MAC_OBJ/$name.o" "$MAC_OBJ/runtime.o" "$MAC_OBJ/zerocore.o" \
            -Wl,-dead_strip \
            '-Wl,-alias,section$start$__DATA$__modules,___start___modules' \
            '-Wl,-alias,section$end$__DATA$__modules,___stop___modules'
        if [ "$name" = Tiny ]; then strip "bin/mac/$name"; fi
    done
}

# ---- The SDK's payload -------------------------------------------------------
#
# What the ZeroCSharp.Sdk package (sdk/) carries, so that users build without
# this repository: zerocore and lib/ as IL assemblies, zerocore's assembly
# routines for each Linux architecture, and win/runtime.c and the Windows
# routines as COFF objects. $1: the payload directory.
build_sdk_payload() {
    local dir=$1 arch
    check_bflat
    build_core "$CORE"
    build_lib
    mkdir -p "$dir/ref"
    cp "$CORE" "$LIB" "$dir/ref/"
    for arch in x64 arm64; do
        mkdir -p "$dir/native/linux-$arch"
        BFLAT_ARCH=$arch CORE_NATIVE=$dir/native/linux-$arch/zerocore.o build_core_native
    done
}

# Internal entry points used inside the container.
if [ "${1:-}" = "--native-dos-bitcode" ]; then
    shift
    build_dos_bitcode "$@"
    exit 0
fi
if [ "${1:-}" = "--native-dos-link" ]; then
    shift
    build_dos_link "$@"
    exit 0
fi
if [ "${1:-}" = "--native" ]; then
    shift
    build_native "$@"
    exit 0
fi
if [ "${1:-}" = "--native-mac-objects" ]; then
    shift
    build_mac_objects "$@"
    exit 0
fi
if [ "${1:-}" = "--native-win" ]; then
    shift
    build_win "$@"
    exit 0
fi
if [ "${1:-}" = "--native-sdk-payload" ]; then
    shift
    build_sdk_payload "$@"
    exit 0
fi
if [ "${1:-}" = "--native-wasm" ]; then
    shift
    build_wasm "$@"
    exit 0
fi

TARGET=native
case "${1:-}" in
    --wasm) TARGET=wasm; shift ;;
    --dos)  TARGET=dos; shift ;;
    --win)  TARGET=win; shift ;;
    --mac)  TARGET=mac; shift ;;
    --sdk-payload)
        TARGET=sdk-payload
        PAYLOAD_DIR=${2:?--sdk-payload needs a directory, inside this one}
        shift 2 ;;
esac

if [ $# -eq 0 ]; then
    if [ "$TARGET" = dos ]; then
        set -- "${DOS_SAMPLES[@]}"
    else
        set -- "${ALL_SAMPLES[@]}"
    fi
fi
for name in "$@"; do
    if [ "$TARGET" = dos ]; then
        if [[ " ${DOS_SAMPLES[*]} " != *" $name "* ]]; then
            check_sample "$name"
            echo "$name isn't built for DOS: it benchmarks SIMD instructions, which a 386 doesn't have." >&2
            exit 1
        fi
    elif [[ " ${DOS_SAMPLES[*]} " == *" $name "* ]] && [[ " ${ALL_SAMPLES[*]} " != *" $name "* ]]; then
        echo "$name is a DOS program: ./build.sh --dos $name" >&2
        exit 1
    else
        check_sample "$name"
    fi
done

case "$TARGET" in
    wasm)   output() { echo "bin/wasm/$1.wasm"; } ;;
    dos)    output() { echo "bin/dos/$1.exe"; } ;;
    win)    output() { echo "bin/win/$1.exe"; } ;;
    mac)    output() { echo "bin/mac/$1"; } ;;
    native) output() { echo "bin/$1"; } ;;
esac

# Runs ./build.sh with the given arguments in the build container (macOS).
in_container() {
    # WASM_TOOLS must be inside this directory to be visible in the container.
    docker run --rm --platform "$DOCKER_PLATFORM" \
        -v "$PWD:/w" -v "$(cd "$BFLAT_DIR" && pwd):/bflat:ro" -w /w \
        -e BFLAT_DIR=/bflat -e BFLAT_ARCH="$BFLAT_ARCH" -e ARM64_MAX_PAGE_SIZE="$ARM64_MAX_PAGE_SIZE" \
        -e WASM_TOOLS="$WASM_TOOLS" \
        "$IMAGE" ./build.sh "$@"
}

if [ "$TARGET" = mac ] && [ -n "${MAC_OBJECTS_PREBUILT:-}" ]; then
    run() { :; } # the objects are in bin/mac/obj already
elif [ "$(uname -s)" = Darwin ]; then
    check_bflat
    ensure_image
    run() { in_container "--native-$1" "${@:2}"; }
else
    run() { "build_${1//-/_}" "${@:2}"; }
fi

case "$TARGET" in
    sdk-payload)
        if ! WIN_CLANG=$(find_dos_clang); then
            echo "Error: no clang that can compile for x86 Windows. Install clang (Xcode's works)." >&2
            exit 1
        fi
        rm -rf "$PAYLOAD_DIR"
        mkdir -p "$PAYLOAD_DIR/native/win-x64"
        run sdk-payload "$PAYLOAD_DIR"
        build_win_objects "$WIN_CLANG"
        cp "$WIN_OBJ/runtime.obj" "$WIN_OBJ/zerocore.obj" "$PAYLOAD_DIR/native/win-x64/"
        {
            echo "zero-csharp $(git rev-parse HEAD)"
            # BFLAT_COMMIT when the layouts came without their checkout (CI's cache).
            echo "bflat ${BFLAT_COMMIT:-$(git -C "${BFLAT_FORK:-../bflat}" rev-parse HEAD 2>/dev/null || echo unknown)}"
        } > "$PAYLOAD_DIR/VERSIONS.txt"
        exit 0
        ;;
    wasm)   run wasm "$@" ;;
    native)
        if [ "$(uname -s)" = Darwin ]; then in_container --native "$@"; else build_native "$@"; fi ;;
    mac)
        if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
            echo "Error: --mac builds on a Mac with Apple Silicon: it links with Apple's linker." >&2
            exit 1
        fi
        run mac-objects "$@"
        build_mac_link "${MAC_CC:-clang}" "$@"
        ;;
    win)
        if ! WIN_CLANG=$(find_dos_clang); then
            echo "Error: no clang that can compile for x86 Windows. Install clang (Xcode's works)." >&2
            exit 1
        fi
        build_win_objects "$WIN_CLANG"
        run win "$@"
        ;;
    dos)
        if ! DOS_CLANG=$(find_dos_clang); then
            echo "Error: no clang that can compile for 32-bit x86. Run ./setup.sh --dos" >&2
            exit 1
        fi
        if ! command -v python3 >/dev/null 2>&1; then
            echo "Error: python3 is needed for the tools in dos/" >&2
            exit 1
        fi
        run dos-bitcode "$@"
        build_dos_objects "$DOS_CLANG" "$@"
        run dos-link "$@"
        objdump=$(dirname "$DOS_CLANG")/llvm-objdump
        [ -x "$objdump" ] || objdump=$(command -v llvm-objdump || true)
        if [ -n "$objdump" ]; then
            check_386 "$objdump" "$@"
            echo "[dos]   checked: no instruction newer than a 386/387"
        else
            echo "[dos]   (not checked for instructions newer than a 386: no llvm-objdump found)"
        fi
        ;;
esac

echo
for name in "$@"; do
    printf '%-12s %8d bytes\n' "$name" "$(wc -c < "$(output "$name")")"
done
