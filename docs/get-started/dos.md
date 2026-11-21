---
title: Run it on DOS
index: 5
---

# Run it on DOS

The same program also builds as a 32-bit DOS program that runs on a 386. The DOS build starts from the
same LLVM bitcode as the WebAssembly build, compiles it for a 386 with clang, and links a program the
HX DOS extender runs under DOS.

## Get the tools

```bash
./setup.sh --dos
```

This downloads FreeDOS, the HX DOS extender and NativeAOT-LLVM (shared with `--wasm`): about 75 MB
in all. You also need a clang with the x86 target and an emulator: Bochs, or QEMU. `setup.sh` checks
for both and says what's missing.

## Build and run

```bash
./build.sh --dos Minimal
./run.sh --dos Minimal
```

```text
Hello from zero-mode!
```

`run.sh --dos` boots FreeDOS in the emulator, runs `bin/dos/Minimal.exe` with its output redirected to
a file, powers the machine off and prints that file. It takes a few seconds. The program is about
16 KB.

To see the DOS screen, and to type at a program that reads input, open a window instead:

```bash
./run.sh --dos --window Minimal
```

The window stays at the DOS prompt; type `PROGRAM` to run the program again.

## Try the game

`samples/Vga.cs` is a small game for DOS only, in the VGA's 320x200 mode with 256 colors. Arrow keys
or the mouse steer, Esc quits:

```bash
./build.sh --dos Vga
./run.sh --dos --window Vga
```

## Use Bochs to test

Bochs's `i386` processor model refuses any instruction a 386 doesn't have, so a program that passes
there runs on a 386. QEMU's `486` model can't tell the difference. `run.sh` uses Bochs when it's
installed. `build.sh` also checks every DOS program after linking, when it finds an `llvm-objdump`, and fails if
it finds an instruction newer than the 386 and 387.

For memory needs, real hardware and what else differs, see [Build for DOS](../how-to/build-for-dos.html).

Next: the [tutorial](../tutorial/index.html).
