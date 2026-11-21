#!/usr/bin/env bash
# Packs the Zero C# packages into sdk/feed/:
#   ZeroCSharp.Sdk               the MSBuild SDK and its payload (./build.sh --sdk-payload)
#   ZeroCSharp.Bflat.<rid>       bflat for each Linux host, trimmed (sdk/trim-layout.sh)
#   ZeroCSharp.Templates         dotnet new zero and zerolib (when it exists)
#
# Usage:  sdk/pack.sh
# Env:    ZERO_HOSTS     the hosts to pack bflat for (default "linux-x64 linux-arm64")
#         ZERO_LAYOUTS   where the full layouts are (default ../bflat/layouts):
#                        linux-glibc-x64, linux-glibc-arm64
#         BFLAT_FORK, BFLAT_COMMIT   where the fork is checked out, or its commit
#                        (the bflat packages name it; see build.sh --sdk-payload)
#         ZERO_PAYLOAD_PREBUILT=1   use sdk/ZeroCSharp.Sdk/payload as it is (CI builds it
#                        in another job, like sdk/trimmed/)
# Trimmed layouts are kept in sdk/trimmed/<rid> and redone only when the
# layout or the trimming script is newer.
set -euo pipefail
cd "$(dirname "$0")/.."
hosts=${ZERO_HOSTS:-linux-x64 linux-arm64}
layouts=${ZERO_LAYOUTS:-../bflat/layouts}
payload=sdk/ZeroCSharp.Sdk/payload

mkdir -p sdk/feed
rm -f sdk/feed/ZeroCSharp.*.nupkg
[ -n "${ZERO_PAYLOAD_PREBUILT:-}" ] || ./build.sh --sdk-payload "$payload"
bflat_commit=$(sed -n 's/^bflat //p' "$payload/VERSIONS.txt")
# The bflat packages are AGPL: they must name the exact source they were built from.
if ! [[ "$bflat_commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Error: the bflat fork's commit is '$bflat_commit'. Set BFLAT_FORK to its checkout, or BFLAT_COMMIT." >&2
    exit 1
fi

for rid in $hosts; do
    layout=$layouts/linux-glibc-${rid#linux-}
    trimmed=sdk/trimmed/$rid
    if [ ! -f "$trimmed/bflat" ] || [ "$layout/bflat" -nt "$trimmed/bflat" ] || [ "$layout/bin/lld" -nt "$trimmed/bflat" ] \
            || [ sdk/trim-layout.sh -nt "$trimmed/bflat" ]; then
        echo "[trim]  $layout -> $trimmed"
        sdk/trim-layout.sh "$layout" "$trimmed"
    fi
    dotnet pack sdk/ZeroCSharp.Bflat/ZeroCSharp.Bflat.csproj -o sdk/feed -v:q -nologo \
        -p:HostRid="$rid" -p:LayoutDir="$PWD/$trimmed" -p:BflatCommit="$bflat_commit"
done

dotnet pack sdk/ZeroCSharp.Sdk/ZeroCSharp.Sdk.csproj -o sdk/feed -v:q -nologo
if [ -f sdk/ZeroCSharp.Templates/ZeroCSharp.Templates.csproj ]; then
    dotnet pack sdk/ZeroCSharp.Templates/ZeroCSharp.Templates.csproj -o sdk/feed -v:q -nologo
fi
ls -la sdk/feed
