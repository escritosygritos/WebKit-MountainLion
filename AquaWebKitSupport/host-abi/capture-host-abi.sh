#!/bin/bash
# Read-only x86_64 Mach-O evidence for a host's Safari/WebKit ABI.
set -euo pipefail

usage() {
    echo "Usage: bash $0 OUTPUT_DIRECTORY MACH_O [MACH_O ...]"
    echo "Run on macOS with Command Line Tools; OUTPUT_DIRECTORY must not exist."
    echo "Supply Safari, Safari.framework, injected bundles, and stock WebKit images explicitly."
}

if [ "${1:-}" = --help ]; then
    usage
    exit 0
fi
if [ "$#" -lt 2 ]; then
    usage >&2
    exit 2
fi
if [ "$(uname -s)" != Darwin ]; then
    echo "ERROR: capture requires macOS Mach-O tools; no files written." >&2
    exit 2
fi
for tool in sw_vers otool dyldinfo nm lipo shasum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: $tool" >&2
        exit 2
    fi
done

case "$1" in
    /*) output=$1 ;;
    *) output="$PWD/$1" ;;
esac
shift
# Validate every input before creating the evidence directory.
for binary in "$@"; do
    if [ ! -f "$binary" ]; then
        echo "ERROR: not a file: $binary" >&2
        exit 2
    fi
    binary="$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")"
    lipo -verify_arch x86_64 "$binary"
done
mkdir "$output"
output=$(cd "$output" && pwd)
trap 'echo "ERROR: incomplete capture in $output; COMPLETE is absent." >&2' ERR
{
    sw_vers
    uname -a
    for tool in otool dyldinfo nm lipo shasum; do command -v "$tool"; done
} > "$output/host.txt"

index=0
for binary in "$@"; do
    binary="$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")"
    index=$((index + 1))
    prefix="$output/$index"
    printf '%s\n' "$binary" > "$prefix.path.txt"
    shasum -a 256 "$binary" > "$prefix.sha256.txt"
    otool -arch x86_64 -L "$binary" > "$prefix.libraries.txt"
    otool -arch x86_64 -l "$binary" > "$prefix.load-commands.txt"
    otool -arch x86_64 -ov "$binary" > "$prefix.objc.txt"
    dyldinfo -arch x86_64 -bind -lazy_bind -weak_bind "$binary" > "$prefix.bindings.txt"
    nm -arch x86_64 -um "$binary" > "$prefix.undefined.txt"
    nm -arch x86_64 -gU "$binary" > "$prefix.exports.txt"
done
printf '%s binaries captured; scope is the explicitly supplied images only.\n' "$index" > "$output/COMPLETE"
echo "Captured $index images in $output. This is evidence, not a compatibility verdict."
