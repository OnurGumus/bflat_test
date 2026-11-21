#!/usr/bin/env bash
# Runs sdk/test/run.sh on Linux from a Mac: packs here (sdk/pack.sh), then
# runs the tests in a container with only the .NET 10 SDK (Debian 12), which
# is where native programs can be built.
#
# Usage:  sdk/test/linux.sh [test ...]      (same names as run.sh)
# Env:    ZERO_HOSTS, ZERO_LAYOUTS (see sdk/pack.sh); ZERO_NO_PACK=1 to skip packing
set -euo pipefail
cd "$(dirname "$0")/../.."
if [ -z "${ZERO_NO_PACK:-}" ]; then
    sdk/pack.sh > sdk/test/work.pack.log 2>&1 || { tail -30 sdk/test/work.pack.log; exit 1; }
fi
case "$(uname -m)" in x86_64 | amd64) platform=linux/amd64 ;; *) platform=linux/arm64 ;; esac
# file, strings and unzip for the tests; nothing else is installed.
docker run --rm --platform "$platform" -v "$PWD:/w" -v zero-csharp-nuget:/root/.nuget -w /w \
    -e ZERO_NO_PACK=1 -e ZERO_HOSTS="${ZERO_HOSTS:-}" mcr.microsoft.com/dotnet/sdk:10.0 bash -c '
    (apt-get update -qq && apt-get install -y -qq file binutils unzip zip) > /dev/null 2>&1
    sdk/test/run.sh "$@"' bash "$@"
