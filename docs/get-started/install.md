---
title: Install
index: 2
---

# Install

You need two things: this repository, and the bflat fork it builds with. The fork is a compiler only;
the libraries your programs use are compiled from source in this repository.

## The repository

```bash
git clone https://github.com/OnurGumus/zero-csharp.git
cd zero-csharp
```

## The bflat fork

The programs need [OnurGumus/bflat](https://github.com/OnurGumus/bflat), branch `master`. It differs
from upstream bflat in the ways this repository depends on: it compiles C# 15 and can turn on the
updated memory safety rules, it binds SIMD intrinsics, and it treats instruction sets beyond the
baseline as available only when they're given with `-m`.

The fork has no release to download yet, so you build it. bflat's packages live on GitHub Packages,
which needs a GitHub token with **only** the `read:packages` scope. Save the token in
`~/.config/bflat/packages-token`, then build in an x64 .NET 10 container next to this repository:

```bash
git clone https://github.com/OnurGumus/bflat.git ../bflat
cd ../bflat
docker run --rm --platform linux/amd64 -v "$PWD:/src" -w /src \
  -v ~/.config/bflat/packages-token:/run/token:ro \
  mcr.microsoft.com/dotnet/sdk:10.0 bash -c \
  'BFLAT_PACKAGES_TOKEN=$(cat /run/token) dotnet build src/bflat/bflat.csproj -t:BuildLayouts -c Release'
```

The token file is mounted read-only, so the token never appears on a command line. The build produces
`layouts/linux-glibc-{x64,arm64}` and `layouts/windows-{x64,arm64}`, and takes about 15 minutes
under emulation.

`build.sh` looks for the compiler in `../bflat/layouts/linux-glibc-<arch>`. If you put the fork
elsewhere, set `BFLAT_DIR`.

## Prerequisites

- **macOS:** Docker. bflat is a Linux program, so it runs in a Linux container of your Mac's
  own architecture (native on Apple Silicon), and so do the programs it builds.
- **Linux:** an assembler (`as`, from binutils) for zerocore's assembly routines:
  `sudo apt install binutils`. bflat's linker needs nothing else. (Layouts built before the fork
  switched to LLVM 20's lld, on 2026-11-21, need `libtinfo.so.5`: rebuild them.)
- **Windows:** programs for Windows build from Linux or macOS with `./build.sh --win` (see
  [Targets](../concepts/targets.html)), which also needs clang (Xcode's on macOS). Building on a
  Windows machine isn't supported yet: `setup.ps1` and `build.ps1` exist but are untested.

Then let `setup.sh` check them. On macOS it also builds the container image:

```bash
./setup.sh
```

WebAssembly and DOS need more tools, which `./setup.sh --wasm` and `./setup.sh --dos` download. Their
pages say what: [WebAssembly](webassembly.html), [DOS](dos.html).

Next: [build your first program](first-program.html).
