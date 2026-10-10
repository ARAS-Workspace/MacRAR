#!/usr/bin/env bash
# Generate the large files the tests pack to check long-running operations.
# Each one is incompressible, like the media archives people pack, and the same on every
# machine: the AES-256-CTR keystream of openssl for key <n> over zeros, cut to size and
# pinned by its SHA-256. They are written next to this script into test-large-files/,
# which External/.gitignore keeps out of git. CI runs it before the tests; on a Mac, run it
# once. A file already there is checked by its SHA-256 and kept; a missing or different one
# is made again.
# Usage: External/generate-large-files.sh
set -euo pipefail

SIZE_MIB=256
# key | name | SHA-256; one name has a space and Turkish letters, as people's files do
FILES=(
    "1|large-1.bin|4a17dfe26a6ee22c0919c227a4e8b460b11ec24926bd107a8f1360362a538141"
    "2|large-2.bin|d24ca9f51b679dbeaeef2c0846263b19ae2d0b15623d1b1980d1a9aaa27cdcac"
    "3|büyük dosya 3.bin|536f7d2a09e2ced012b81ae23eb5e4297d937738dd1842856af5d211b3c47beb"
)

EXTERNAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${EXTERNAL_DIR}/test-large-files"
mkdir -p "$TARGET"

for entry in "${FILES[@]}"; do
    IFS="|" read -r key name sha256 <<< "$entry"
    file="${TARGET}/${name}"
    if [[ -f "$file" ]] && echo "${sha256}  ${file}" | shasum -a 256 -c -s -; then
        echo "${name}: already generated"
        continue
    fi
    partial="${file}.partial"
    # head closes the pipe once it has the size; openssl's broken pipe is expected
    { /usr/bin/openssl enc -aes-256-ctr -nosalt -K "$(printf '%064x' "$key")" -iv "$(printf '%032x' 0)" \
        < /dev/zero 2> /dev/null || true; } | head -c $((SIZE_MIB << 20)) > "$partial"
    if ! echo "${sha256}  ${partial}" | shasum -a 256 -c -s -; then
        rm -f "$partial"
        echo "ERROR: ${name} did not come out as pinned" >&2
        exit 1
    fi
    mv "$partial" "$file"
    echo "${name}: ${SIZE_MIB} MiB"
done
