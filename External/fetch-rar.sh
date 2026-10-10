#!/usr/bin/env bash
# Fetch RARLAB's rar for the RAR tests (MacRARTests/RARTests.swift).
# Test use only: the app never bundles or downloads rar (RAR licence 3.2/3.3).
# Downloads the pinned "RAR for macOS ARM" release, checks its SHA-256 and
# unpacks it next to this script into a directory named after the archive:
# External/rarmacos-arm-723/rar/rar. External/.gitignore keeps it out of git.
# CI runs it before the tests, keeping the result in the Actions cache; on a
# Mac, run it once. A copy already there is checked by its SHA-256 before it
# is used, so a cached or local rar is the pinned one too.
# Usage: External/fetch-rar.sh
set -euo pipefail

RAR_VERSION="7.23"
RAR_ARCHIVE="rarmacos-arm-723"
RAR_URL="https://www.win-rar.com/fileadmin/winrar-versions/${RAR_ARCHIVE}.tar.gz"
RAR_SHA256="68b393c000758d477fde43c955ff7542f12f76f3f5e87cdda923152fc791bd4d"
RAR_BINARY_SHA256="fd6c7db73c659a28b50408354f4a4845c53a67f929f37fd99df92aa77b9f5153"

EXTERNAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${EXTERNAL_DIR}/${RAR_ARCHIVE}"
RAR="${TARGET}/rar/rar"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "ERROR: the pinned rar ${RAR_VERSION} is the Apple Silicon build" >&2
    exit 1
fi

if [[ -x "$RAR" ]] && echo "${RAR_BINARY_SHA256}  ${RAR}" | shasum -a 256 -c -s -; then
    echo "rar ${RAR_VERSION}: ${RAR} (already fetched)"
    exit 0
fi

# One rar at a time: the tests take the rarmacos-* directory they find
rm -rf "${EXTERNAL_DIR}"/rarmacos-*
mkdir -p "$TARGET"
ARCHIVE="${TARGET}.tar.gz"
curl -fsSL --retry 3 -o "$ARCHIVE" "$RAR_URL"
echo "${RAR_SHA256}  ${ARCHIVE}" | shasum -a 256 -c -
tar -xzf "$ARCHIVE" -C "$TARGET"
rm "$ARCHIVE"
echo "${RAR_BINARY_SHA256}  ${RAR}" | shasum -a 256 -c -

VERSION="$("$RAR" -iver)"
if [[ "$VERSION" != "$RAR_VERSION" ]]; then
    echo "ERROR: expected rar ${RAR_VERSION}, got ${VERSION}" >&2
    exit 1
fi
echo "rar ${VERSION}: ${RAR}"
