#!/usr/bin/env bash
# The tests of the Zero C# SDK packages (sdk/). Each test copies a project
# from sdk/test/fixtures into sdk/test/work, builds it with the dotnet CLI
# against the packages in sdk/feed, and checks the result.
#
# Usage:  sdk/test/run.sh                 pack (sdk/pack.sh), then run every test
#         sdk/test/run.sh name...         only these tests (names as in the list below)
# Env:    ZERO_NO_PACK=1                  use sdk/feed as it is (CI downloads it)
#         ZERO_HOSTS                      the host packages to expect (default: both,
#                                         "linux-x64 linux-arm64"); also passed to pack.sh
#
# Exit code: the number of failed tests.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$PWD
WORK=$ROOT/sdk/test/work
FEED=$ROOT/sdk/feed
VERSION=$(sed -n 's|.*<ZeroSdkVersion>\(.*\)</ZeroSdkVersion>.*|\1|p' sdk/version.props)
# The target framework: zero + major and minor, without the dot (0.1 -> zero01).
TFM=zero$(echo "$VERSION" | cut -d. -f1,2 | tr -d .)
HOST_OS=$(uname -s)
export ZERO_HOSTS=${ZERO_HOSTS:-linux-x64 linux-arm64}
case "$(uname -m)" in
    x86_64 | amd64)  HOST_ARCH_NAME=x64;   DOCKER_ARCH=amd64; HOST_ELF_ARCH=x86-64 ;;
    *)               HOST_ARCH_NAME=arm64; DOCKER_ARCH=arm64; HOST_ELF_ARCH=aarch64 ;;
esac

passed=0
failed=0
skipped=0
LOG=
pass() { echo "ok   $1"; passed=$((passed + 1)); }
fail() {
    echo "FAIL $1: $2"
    [ -n "$LOG" ] && [ -f "$LOG" ] && tail -20 "$LOG" | sed 's/^/     | /'
    failed=$((failed + 1))
}

skip() { echo "skip $1: $2"; skipped=$((skipped + 1)); }
# linux_only <test name>: true on Linux; on other hosts, records a skip.
linux_only() {
    [ "$HOST_OS" = Linux ] && return 0
    skip "$1" "builds native programs, which needs a Linux host"
    return 1
}

# fixture <fixture> [<dir under work>]: a fresh copy of a fixture, with the
# SDK version filled in and a nuget.config that finds the local feed.
fixture() {
    local from=$ROOT/sdk/test/fixtures/$1 to=$WORK/${2:-$1}
    rm -rf "$to"
    mkdir -p "$(dirname "$to")"
    cp -R "$from" "$to"
    find "$to" -name '*.csproj' -exec sed -i.bak "s|@ZERO_SDK_VERSION@|$VERSION|g" {} \; -exec rm -f {}.bak \;
    cat > "$to/nuget.config" <<EOF
<configuration>
  <packageSources>
    <clear />
    <add key="zero" value="$FEED" />
    <add key="nuget" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
EOF
    echo "$to"
}

# run_in <dir> <log name> dotnet args...: runs dotnet in <dir>, output to a log.
run_in() {
    local dir=$1
    LOG=$WORK/$2.log
    shift 2
    (cd "$dir" && dotnet "$@") > "$LOG" 2>&1
}

# ---- Tests -------------------------------------------------------------------

test_hello_compiles() {
    local dir
    dir=$(fixture hello)
    if ! run_in "$dir" hello build; then fail "hello compiles" "dotnet build failed"; return; fi
    local dll=$dir/bin/Debug/$TFM/hello.dll
    if [ ! -f "$dll" ]; then fail "hello compiles" "no $dll"; return; fi
    if strings "$dll" | grep -qx 'System.Runtime'; then
        fail "hello compiles" "the output references System.Runtime"; return
    fi
    pass "hello compiles"
}

test_console_is_an_error() {
    local dir
    dir=$(fixture console)
    if run_in "$dir" console build; then fail "console is an error" "the build succeeded"; return; fi
    if ! grep -qE 'CS0103|CS0234' "$LOG"; then fail "console is an error" "no CS0103/CS0234"; return; fi
    pass "console is an error"
}

test_unions_compile() {
    local dir
    dir=$(fixture union)
    if ! run_in "$dir" union build; then fail "unions compile" "dotnet build failed"; return; fi
    pass "unions compile"
}

test_plain_packages_refused() {
    local dir
    dir=$(fixture plainpkg)
    if run_in "$dir" plainpkg restore; then fail "plain packages refused" "restore succeeded"; return; fi
    if ! grep -q 'NU1202' "$LOG"; then fail "plain packages refused" "no NU1202"; return; fi
    pass "plain packages refused"
}

test_payload_complete() {
    local payload=$ROOT/sdk/ZeroCSharp.Sdk/payload f
    LOG=
    for f in ref/System.Private.CoreLib.dll ref/BflatLib.dll native/linux-x64/zerocore.o \
             native/linux-arm64/zerocore.o native/win-x64/runtime.obj native/win-x64/zerocore.obj VERSIONS.txt; do
        if [ ! -s "$payload/$f" ]; then fail "payload complete" "missing $f"; return; fi
    done
    if ! file "$payload/native/linux-x64/zerocore.o" | grep -q 'x86-64'; then fail "payload complete" "linux-x64 object isn't x86-64"; return; fi
    if ! file "$payload/native/linux-arm64/zerocore.o" | grep -q 'aarch64'; then fail "payload complete" "linux-arm64 object isn't aarch64"; return; fi
    if ! file "$payload/native/win-x64/runtime.obj" | grep -qiE 'COFF|x86-64'; then fail "payload complete" "win-x64 object isn't COFF"; return; fi
    pass "payload complete"
}

# Trims the host's layout (sdk/trim-layout.sh) and builds with the result in a
# clean Ubuntu 24.04: nothing installed, so it must need nothing the layout or
# a stock system lacks. Slow (it traces builds in a container): run it by name.
test_trimmed_layout_builds() {
    local layout=${BFLAT_DIR:-$ROOT/../bflat/layouts/linux-glibc-$HOST_ARCH_NAME} out=$WORK/trimmed size
    LOG=$WORK/trim.log
    if ! sdk/trim-layout.sh "$layout" "$out" > "$LOG" 2>&1; then fail "trimmed layout builds" "trim-layout.sh failed"; return; fi
    size=$(du -sm "$out" | cut -f1)
    if [ "$size" -ge 150 ]; then fail "trimmed layout builds" "$size MB, not under 150"; return; fi
    LOG=$WORK/trim-build.log
    if ! docker run --rm --platform "linux/$DOCKER_ARCH" -v "$ROOT:/w" -v "$out:/bflat:ro" -w /w ubuntu:24.04 bash -c '
            set -e
            P=sdk/ZeroCSharp.Sdk/payload
            F="--stdlib:none --langversion preview --compiler-feature updated-memory-safety-rules --no-reflection -i libc -i libm.so.6"
            B="/bflat/bflat build samples/Strings.cs -r $P/ref/BflatLib.dll -r $P/ref/System.Private.CoreLib.dll $F"
            $B --arch arm64 --ldflags $P/native/linux-arm64/zerocore.o --ldflags "-z nostart-stop-gc" -o /tmp/s-arm64
            $B --arch x64 --ldflags $P/native/linux-x64/zerocore.o --ldflags "-z nostart-stop-gc" -o /tmp/s-x64
            $B --os windows --arch x64 --ldflags "/entry:zero_start $P/native/win-x64/runtime.obj $P/native/win-x64/zerocore.obj" -o /tmp/s.exe
            /tmp/s-'"$HOST_ARCH_NAME"' > /dev/null' > "$LOG" 2>&1; then
        fail "trimmed layout builds" "building or running in ubuntu:24.04 failed"; return
    fi
    pass "trimmed layout builds ($size MB)"
}

test_host_packages() {
    local rid pkg size listing
    LOG=
    for rid in $ZERO_HOSTS; do
        pkg=$FEED/ZeroCSharp.Bflat.$rid.$VERSION.nupkg
        if [ ! -f "$pkg" ]; then fail "host packages" "no $(basename "$pkg")"; return; fi
        size=$(( $(wc -c < "$pkg") / 1000000 ))
        if [ "$size" -ge 100 ]; then fail "host packages" "$(basename "$pkg") is $size MB, not under 100"; return; fi
        # Listed once: grep -q stops reading early, which pipefail counts as a failure.
        listing=$(unzip -l "$pkg")
        if ! grep -q ' tools/bflat/bflat$' <<< "$listing"; then fail "host packages" "$rid: no tools/bflat/bflat"; return; fi
        if ! grep -q ' tools/bflat/bin/lld$' <<< "$listing"; then fail "host packages" "$rid: no tools/bflat/bin/lld"; return; fi
        # The AGPL package must point to its exact source.
        if ! unzip -p "$pkg" "ZeroCSharp.Bflat.$rid.nuspec" | grep -qE 'commit="[0-9a-f]{40}"'; then
            fail "host packages" "$rid: the nuspec doesn't name the fork's commit"; return
        fi
    done
    pass "host packages ($ZERO_HOSTS)"
}

# ---- The native step (Linux hosts) -----------------------------------------

test_native_hello_runs() {
    local name="native hello runs" dir exe out
    linux_only "$name" || return
    dir=$(fixture native)
    if ! run_in "$dir" native build; then fail "$name" "dotnet build failed"; return; fi
    exe=$dir/bin/Debug/$TFM/native
    if [ ! -x "$exe" ]; then fail "$name" "no $exe"; return; fi
    out=$("$exe"); if [ "$out" != hi ]; then fail "$name" "printed '$out'"; return; fi
    if ! file "$exe" | grep -q "ELF.*$HOST_ELF_ARCH"; then fail "$name" "not an ELF for $HOST_ELF_ARCH: $(file -b "$exe")"; return; fi
    pass "$name"
}

test_cross_targets() {
    local name="cross targets" dir other other_arch
    linux_only "$name" || return
    dir=$(fixture native cross)
    if ! run_in "$dir" cross-win build -p:ZeroTarget=win-x64; then fail "$name" "win-x64 build failed"; return; fi
    if [ "$(head -c 2 "$dir/bin/Debug/$TFM/native.exe" 2>/dev/null)" != MZ ]; then fail "$name" "native.exe isn't a Windows program"; return; fi
    if [ "$HOST_ARCH_NAME" = x64 ]; then other=linux-arm64; other_arch=aarch64; else other=linux-x64; other_arch=x86-64; fi
    if ! run_in "$dir" cross-linux build -p:ZeroTarget=$other; then fail "$name" "$other build failed"; return; fi
    if ! file "$dir/bin/Debug/$TFM/native" | grep -q "ELF.*$other_arch"; then fail "$name" "not an ELF for $other_arch"; return; fi
    pass "$name"
}

test_bad_target() {
    local name="bad target" dir
    linux_only "$name" || return
    dir=$(fixture native badtarget)
    if run_in "$dir" badtarget build -p:ZeroTarget=mac-arm64; then fail "$name" "the build succeeded"; return; fi
    if ! grep -q 'linux-x64, linux-arm64, win-x64' "$LOG"; then fail "$name" "the error doesn't list the targets"; return; fi
    pass "$name"
}

test_path_with_spaces() {
    local name="path with spaces" dir out
    linux_only "$name" || return
    dir=$(fixture native "spaces dir/native")
    if ! run_in "$dir" spaces build; then fail "$name" "dotnet build failed"; return; fi
    out=$("$dir/bin/Debug/$TFM/native"); if [ "$out" != hi ]; then fail "$name" "printed '$out'"; return; fi
    pass "$name"
}

test_compile_items() {
    local name="compile items" dir out
    linux_only "$name" || return
    dir=$(fixture subfolders)
    if ! run_in "$dir" subfolders build; then fail "$name" "dotnet build failed"; return; fi
    out=$("$dir/bin/Debug/$TFM/subfolders"); if [ "$out" != "from b" ]; then fail "$name" "printed '$out'"; return; fi
    pass "$name"
}

# Whether the last log shows bflat being run.
ran_bflat() { grep -q 'tools/bflat/bflat" build' "$LOG"; }

test_incremental() {
    local name="incremental" dir
    linux_only "$name" || return
    dir=$(fixture native incremental)
    if ! run_in "$dir" incremental-1 build -v:n || ! ran_bflat; then fail "$name" "the first build didn't run bflat"; return; fi
    if ! run_in "$dir" incremental-2 build -v:n || ran_bflat; then fail "$name" "an unchanged project ran bflat again"; return; fi
    sleep 1; touch "$dir/Program.cs"
    if ! run_in "$dir" incremental-3 build -v:n || ! ran_bflat; then fail "$name" "a changed source didn't run bflat"; return; fi
    pass "$name"
}

test_bflat_failure_fails_the_build() {
    local name="bflat failure fails the build" dir
    linux_only "$name" || return
    dir=$(fixture badimport)
    if run_in "$dir" badimport build; then fail "$name" "the build succeeded"; return; fi
    if ! ran_bflat; then fail "$name" "it failed before bflat ran"; return; fi
    if ! grep -qE 'error' "$LOG"; then fail "$name" "no error in the output"; return; fi
    pass "$name"
}

test_size() {
    local name="size" dir
    linux_only "$name" || return
    dir=$(fixture native size)
    if ! run_in "$dir" size build -v:n -p:ZeroOptimizeFor=Size; then fail "$name" "dotnet build failed"; return; fi
    if ! grep -q 'tools/bflat/bflat" build.* -Os' "$LOG"; then fail "$name" "bflat wasn't given -Os"; return; fi
    pass "$name"
}

test_macos_error() {
    local name="macos error" dir
    if [ "$HOST_OS" != Darwin ]; then skip "$name" "macOS only"; return; fi
    dir=$(fixture native macos)
    if run_in "$dir" macos build; then fail "$name" "the build succeeded"; return; fi
    if ! grep -qF "Zero C# can't make native programs on macOS yet; build on Linux or Windows, or use the repository's build.sh." "$LOG"; then
        fail "$name" "not the macOS message"; return
    fi
    dir=$(fixture hello macos-library)
    if ! run_in "$dir" macos-library build; then fail "$name" "a library didn't build on macOS"; return; fi
    pass "$name"
}

# ---- Libraries ----------------------------------------------------------------

# app_with_lib <work dir>: the program and the Geometry library (from libs/).
app_with_lib() {
    local dir
    dir=$(fixture app-with-lib "$1")
    cp "$ROOT"/libs/Geometry/*.cs "$dir/Geometry/"
    echo "$dir"
}

test_project_reference() {
    local name="project reference" dir out
    linux_only "$name" || return
    dir=$(app_with_lib projref)
    if ! run_in "$dir/App" projref build; then fail "$name" "dotnet build failed"; return; fi
    out=$("$dir/App/bin/Debug/$TFM/App"); if [ "$out" != "Floor area: 37.00" ]; then fail "$name" "printed '$out'"; return; fi
    pass "$name"
}

test_library_change_rebuilds() {
    local name="library change rebuilds" dir out
    linux_only "$name" || return
    dir=$(app_with_lib libchange)
    if ! run_in "$dir/App" libchange-1 build; then fail "$name" "the first build failed"; return; fi
    sleep 1
    sed -i.bak 's/double total = 0;/double total = 1;/' "$dir/Geometry/Measure.cs" && rm -f "$dir/Geometry/Measure.cs.bak"
    if ! run_in "$dir/App" libchange-2 build -v:n || ! ran_bflat; then fail "$name" "changing the library didn't run bflat"; return; fi
    out=$("$dir/App/bin/Debug/$TFM/App"); if [ "$out" != "Floor area: 38.00" ]; then fail "$name" "printed '$out'"; return; fi
    pass "$name"
}

# add_source <nuget.config> <name> <dir>: one more package source.
add_source() {
    sed -i.bak "s|<clear />|<clear />\n    <add key=\"$2\" value=\"$3\" />|" "$1" && rm -f "$1.bak"
}

test_pack_and_package_reference() {
    local name="pack and package reference" dir app out
    linux_only "$name" || return
    dir=$(app_with_lib pack)
    rm -rf "$WORK/libfeed" "${NUGET_PACKAGES:-$HOME/.nuget/packages}/zerotest.geometry"
    if ! run_in "$dir/Geometry" pack-lib pack -o "$WORK/libfeed"; then fail "$name" "dotnet pack failed"; return; fi
    unzip -l "$WORK/libfeed/ZeroTest.Geometry.1.0.0.nupkg" > "$WORK/pack-list.txt" 2>&1
    if ! grep -q " lib/$TFM/Geometry.dll$" "$WORK/pack-list.txt"; then fail "$name" "the package has no lib/$TFM/Geometry.dll"; return; fi
    app=$(fixture app-with-pkg)/App
    add_source "$app/../nuget.config" libs "$WORK/libfeed"
    if ! run_in "$app" pkgref build; then fail "$name" "the program didn't build"; return; fi
    out=$("$app/bin/Debug/$TFM/App"); if [ "$out" != "Floor area: 37.00" ]; then fail "$name" "printed '$out'"; return; fi
    pass "$name"
}

# A package made for another SDK version (lib/zero02/) must be refused.
test_version_mismatch() {
    local name="version mismatch" app pkg=$WORK/oldfeed
    rm -rf "$pkg" "${NUGET_PACKAGES:-$HOME/.nuget/packages}/zerotest.geometry"
    mkdir -p "$pkg/src/lib/zero02"
    cp "$ROOT/sdk/ZeroCSharp.Sdk/payload/ref/BflatLib.dll" "$pkg/src/lib/zero02/Geometry.dll"
    printf '%s\n' '<?xml version="1.0"?>' \
        '<package><metadata><id>ZeroTest.Geometry</id><version>1.0.0</version><authors>test</authors><description>A zero library built for SDK 0.2.</description></metadata></package>' \
        > "$pkg/src/ZeroTest.Geometry.nuspec"
    (cd "$pkg/src" && zip -qr ../ZeroTest.Geometry.1.0.0.nupkg .)
    app=$(fixture app-with-pkg oldpkg)/App
    add_source "$app/../nuget.config" old "$pkg"
    if run_in "$app" oldpkg restore; then fail "$name" "restore succeeded"; return; fi
    if ! grep -q "NU1202" "$LOG" || ! grep -q "zero02" "$LOG" || ! grep -q "$TFM" "$LOG"; then
        fail "$name" "no NU1202 naming zero02 and $TFM"; return
    fi
    pass "$name"
}

# ---- Templates ----------------------------------------------------------------

test_templates() {
    local name="templates" dir=$WORK/templates out
    linux_only "$name" || return
    rm -rf "$dir" && mkdir -p "$dir"
    fixture hello templates-config > /dev/null    # just for its nuget.config
    cp "$WORK/templates-config/nuget.config" "$dir/"
    dotnet new uninstall ZeroCSharp.Templates > /dev/null 2>&1 || true
    if ! run_in "$dir" templates-install new install "$FEED/ZeroCSharp.Templates.$VERSION.nupkg"; then fail "$name" "install failed"; return; fi
    if ! run_in "$dir" templates-new new zero -o Hello; then fail "$name" "dotnet new zero failed"; return; fi
    if ! run_in "$dir/Hello" templates-build build; then fail "$name" "the program didn't build"; return; fi
    out=$(echo Ann | "$dir/Hello/bin/Debug/$TFM/Hello")
    if [[ "$out" != *"Hello, Ann!"* ]]; then fail "$name" "printed '$out'"; return; fi
    if ! run_in "$dir" templates-newlib new zerolib -o Lib; then fail "$name" "dotnet new zerolib failed"; return; fi
    if ! run_in "$dir/Lib" templates-pack pack -o "$dir/feed"; then fail "$name" "the library didn't pack"; return; fi
    pass "$name"
}

# ---- From the final review -----------------------------------------------------

test_custom_packages_folder() {
    local name="custom packages folder" dir out
    linux_only "$name" || return
    dir=$(fixture native pkgfolder)
    rm -rf "$WORK/pkgfolder-packages"
    # No trailing slash, as CI setups often write it.
    if ! (export NUGET_PACKAGES=$WORK/pkgfolder-packages; run_in "$dir" pkgfolder build); then fail "$name" "dotnet build failed"; return; fi
    out=$("$dir/bin/Debug/$TFM/native"); if [ "$out" != hi ]; then fail "$name" "printed '$out'"; return; fi
    pass "$name"
}

test_dotnet_run() {
    local name="dotnet run" dir
    linux_only "$name" || return
    dir=$(fixture native run)
    if ! run_in "$dir" run run; then fail "$name" "dotnet run failed"; return; fi
    if [ "$(tail -1 "$LOG")" != hi ]; then fail "$name" "didn't print hi"; return; fi
    pass "$name"
}

test_publish() {
    local name="publish" dir out
    linux_only "$name" || return
    dir=$(fixture native publish)
    if ! run_in "$dir" publish publish -c Release -o "$dir/out"; then fail "$name" "dotnet publish failed"; return; fi
    if [ ! -x "$dir/out/native" ]; then fail "$name" "no native program in the publish folder"; return; fi
    if [ -e "$dir/out/native.dll" ]; then fail "$name" "the IL native.dll was published"; return; fi
    out=$("$dir/out/native"); if [ "$out" != hi ]; then fail "$name" "printed '$out'"; return; fi
    pass "$name"
}

test_extra_dll_imports() {
    local name="extra dll imports" dir
    linux_only "$name" || return
    dir=$(fixture native dllimports)
    if ! run_in "$dir" dllimports build -v:n "-p:ZeroDllImports=libdl.so.2;"; then fail "$name" "dotnet build failed"; return; fi
    if ! grep -q 'tools/bflat/bflat" build.* -i libc .*-i libdl.so.2' "$LOG" && ! grep -q 'tools/bflat/bflat" build.* -i libdl.so.2 .*-i libc ' "$LOG"; then
        fail "$name" "libc and libdl.so.2 weren't both passed"; return
    fi
    pass "$name"
}

test_inherited_settings() {
    local name="inherited settings" dir out
    linux_only "$name" || return
    dir=$(fixture inherited)
    if ! run_in "$dir" inherited build; then fail "$name" "dotnet build failed"; return; fi
    out=$("$dir/bin/Debug/$TFM/inherited"); if [ "$out" != hi ]; then fail "$name" "printed '$out'"; return; fi
    pass "$name"
}

test_clean_and_rebuild() {
    local name="clean and rebuild" dir
    linux_only "$name" || return
    dir=$(fixture native clean)
    if ! run_in "$dir" clean-1 build; then fail "$name" "dotnet build failed"; return; fi
    if ! run_in "$dir" clean-2 clean; then fail "$name" "dotnet clean failed"; return; fi
    if [ -e "$dir/bin/Debug/$TFM/native" ]; then fail "$name" "dotnet clean left the native program"; return; fi
    if ! run_in "$dir" clean-3 build -v:n || ! ran_bflat; then fail "$name" "building after clean didn't run bflat"; return; fi
    pass "$name"
}

ALL_TESTS=(host_packages payload_complete hello_compiles console_is_an_error unions_compile plain_packages_refused
    native_hello_runs cross_targets bad_target path_with_spaces compile_items incremental
    bflat_failure_fails_the_build size macos_error
    project_reference library_change_rebuilds pack_and_package_reference version_mismatch templates
    custom_packages_folder dotnet_run publish extra_dll_imports inherited_settings clean_and_rebuild)

# ---- Run ---------------------------------------------------------------------

if [ -z "${ZERO_NO_PACK:-}" ]; then
    if ! sdk/pack.sh > "$WORK.pack.log" 2>&1; then
        echo "sdk/pack.sh failed:"
        tail -30 "$WORK.pack.log"
        exit 1
    fi
fi
# The feed's packages keep their version between runs, so drop the cached
# copies: restore must take the ones just packed.
rm -rf "${NUGET_PACKAGES:-$HOME/.nuget/packages}"/zerocsharp.*
# MSBuild processes that stay alive between builds keep the SDK's files in
# memory; with the same version repacked, they'd build with the old ones.
export MSBUILDDISABLENODEREUSE=1
dotnet build-server shutdown > /dev/null 2>&1 || true
mkdir -p "$WORK"

tests=("$@")
[ ${#tests[@]} -eq 0 ] && tests=("${ALL_TESTS[@]}")
for name in "${tests[@]}"; do
    LOG=
    "test_${name//-/_}"
done
echo
echo "$passed passed, $failed failed, $skipped skipped"
exit "$failed"
