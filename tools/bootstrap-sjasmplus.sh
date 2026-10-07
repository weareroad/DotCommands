#!/usr/bin/env bash
set -euo pipefail

SJASMPLUS_VERSION=1.24.0
SJASMPLUS_SHA256=0b5013f07e8d8505f9e296529655668b6fdf0268625c19e883b0fff484e209f1

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
tools_dir="$project_dir/.tools"
archive_dir="$tools_dir/downloads"
source_dir="$tools_dir/sjasmplus-$SJASMPLUS_VERSION"
binary_dir="$tools_dir/bin"
archive="$archive_dir/sjasmplus-$SJASMPLUS_VERSION-src.tar.xz"
binary="$binary_dir/sjasmplus"
download_url="https://github.com/z00m128/sjasmplus/releases/download/v$SJASMPLUS_VERSION/sjasmplus-$SJASMPLUS_VERSION-src.tar.xz"

if [[ -x "$binary" ]]; then
    installed_version=$("$binary" --nologo --version 2>&1)
    if [[ "$installed_version" == "$SJASMPLUS_VERSION" ]]; then
        exit 0
    fi
fi

mkdir -p "$archive_dir" "$binary_dir"

if [[ ! -f "$archive" ]]; then
    curl --fail --location --output "$archive.part" "$download_url"
    mv "$archive.part" "$archive"
fi

printf '%s  %s\n' "$SJASMPLUS_SHA256" "$archive" | sha256sum --check --status

if [[ ! -f "$source_dir/Makefile" ]]; then
    tar --extract --xz --file "$archive" --directory "$tools_dir"
fi

make --directory "$source_dir" USE_LUA=0
install -m 0755 "$source_dir/build/release/sjasmplus" "$binary"

printf 'Installed SJAsmPlus %s at %s\n' "$SJASMPLUS_VERSION" "$binary"
