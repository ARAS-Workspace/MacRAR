#!/usr/bin/env bash
# Trigger the mac-staging workflow.
# The version is read from project.yml (single source of truth):
# MARKETING_VERSION + DISTRIBUTION_PATCH → <original release>+ARAS.Patch.<n>.
# Creates the staging-v<version> tag and pushes it.
# Produces signed and notarized DMG artifacts without creating a GitHub Release.
# Usage: .github/scripts/staging.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECT_YML="${REPO_ROOT}/project.yml"

read_setting() {
    grep -m1 -E "^ +$1:" "$PROJECT_YML" | sed -E 's/^ +[A-Z_]+: *"?([^"]*)"? *$/\1/'
}

BASE="$(read_setting MARKETING_VERSION)"
ROUND="$(read_setting DISTRIBUTION_PATCH)"

if [[ ! "$BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$ROUND" =~ ^[0-9]+$ ]]; then
    echo "ERROR: could not read MARKETING_VERSION / DISTRIBUTION_PATCH from project.yml" >&2
    exit 1
fi

# Round 0 is the original release itself, which is not ours to ship.
if [[ "$ROUND" -eq 0 ]]; then
    echo "ERROR: DISTRIBUTION_PATCH is 0 — run .github/scripts/bump.sh first" >&2
    exit 1
fi

VERSION="${BASE}+ARAS.Patch.${ROUND}"
TAG="staging-v${VERSION}"

echo "Version : ${VERSION}"
echo "Tag     : ${TAG}"
echo ""

# Check if tag already exists
if git -C "${REPO_ROOT}" rev-parse "${TAG}" &>/dev/null 2>&1; then
    echo "Tag ${TAG} already exists locally."
    printf "Delete and recreate? [y/N]: "
    read -r confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Aborted."
        exit 1
    fi
    git -C "${REPO_ROOT}" tag -d "${TAG}"
    git -C "${REPO_ROOT}" push origin ":refs/tags/${TAG}" 2>/dev/null || true
fi

git -C "${REPO_ROOT}" tag "${TAG}"
git -C "${REPO_ROOT}" push origin "${TAG}"

echo ""
echo "Staging triggered: ${TAG}"
echo "Watch: gh run list --workflow mac-staging.yml"
