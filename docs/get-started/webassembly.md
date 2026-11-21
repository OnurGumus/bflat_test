---
title: Run it on WebAssembly
index: 4
---

# Run it on WebAssembly

The same program, unchanged, builds as a WebAssembly module for WASI. bflat itself can't target
WebAssembly, so this build takes a different compiler for the last step: NativeAOT-LLVM turns the IL
into LLVM bitcode, and the WASI SDK's clang links it with WASI's C library.

## Get the toolchain

```bash
./setup.sh --wasm
```

This downloads NativeAOT-LLVM, the WASI SDK and wasmtime into `tools/wasm`: about 900 MB unpacked, most of
it the WASI SDK. It only has to run once.

## Build and run

```bash
./build.sh --wasm Minimal
./run.sh --wasm Minimal
```

```text
Hello from zero-mode!
```

The module is `bin/wasm/Minimal.wasm`, about 16 KB stripped. `run.sh --wasm` runs it with wasmtime,
which is the runtime the repository tests; the module targets WASI 0.1.

`[DllImport("libc")]` still works: on WebAssembly, `libc` is WASI's C library, and `puts` is in it.
`lib/`'s `Out` and `In` use `write` and `read` the same way, so programs that use them run unchanged.

## What's different

Pointers are 32 bits, so anything that prints a size or an address prints a different number. There
is one thread, no SIMD, and native code can't call back into C#. The test suite compares each sample's
output with its native build's, except where it can't match: Arena and Collections print
pointer-sized byte counts, and Simd and Kernels print timings, so only their exit codes are checked.

The same modules also run [in your browser](browser.html), on this site.

For the details (what the toolchain does, the shadow stack, and what doesn't carry over), see
[Build for WebAssembly](../how-to/build-for-webassembly.html) and
[How the targets work](../concepts/targets.html).

Next: the same program [on DOS](dos.html).
