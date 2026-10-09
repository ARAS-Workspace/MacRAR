#!/usr/bin/env bash
# Bump the ARAS distribution version.
# The version is <original release>+ARAS.Patch.<n>. MARKETING_VERSION in
# project.yml is the original developer's release this build is based on
# (it is also CFBundleShortVersionString, so it stays MAJOR.MINOR.PATCH);
# DISTRIBUTION_PATCH counts the ARAS patch rounds on top of it. Info.plist
# joins the two as ARASDistributionVersion, and the release scripts tag
# mac-v<version> / staging-v<version> from them.
# Rewrites project.yml and commits it as `Bump v<new>`, leaving only the
# push to the operator.
# Usage:
#   .github/scripts/bump.sh          1.4.2+ARAS.Patch.1 → 1.4.2+ARAS.Patch.2
#   .github/scripts/bump.sh 1.4.3    new original release → 1.4.3+ARAS.Patch.1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECT_YML="${REPO_ROOT}/project.yml"

# The commit below stages one explicit path, but a dirty tree still means
# the operator has work in flight that a version commit would sit on top of
# unreviewed.
if ! git -C "${REPO_ROOT}" diff --quiet || ! git -C "${REPO_ROOT}" diff --cached --quiet; then
    echo "ERROR: working tree has uncommitted changes — commit or stash them first" >&2
    git -C "${REPO_ROOT}" status --short >&2
    exit 1
fi

read_setting() {
    grep -m1 -E "^ +$1:" "$PROJECT_YML" | sed -E 's/^ +[A-Z_]+: *"?([^"]*)"? *$/\1/'
}

BASE="$(read_setting MARKETING_VERSION)"
ROUND="$(read_setting DISTRIBUTION_PATCH)"
if [[ ! "$BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: MARKETING_VERSION in project.yml is '${BASE}', expected MAJOR.MINOR.PATCH" >&2
    exit 1
fi
if [[ ! "$ROUND" =~ ^[0-9]+$ ]]; then
    echo "ERROR: DISTRIBUTION_PATCH in project.yml is '${ROUND}', expected a number" >&2
    exit 1
fi

if [[ $# -ge 1 ]]; then
    NEW_BASE="$1"
    if [[ ! "$NEW_BASE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: '${NEW_BASE}' is not an original release (MAJOR.MINOR.PATCH)" >&2
        exit 1
    fi
    # Only a newer original release moves the base; the patch round restarts on it.
    if [[ "$NEW_BASE" == "$BASE" || "$(printf '%s\n%s\n' "$BASE" "$NEW_BASE" | sort -V | tail -1)" != "$NEW_BASE" ]]; then
        echo "ERROR: '${NEW_BASE}' is not newer than the current base ${BASE}" >&2
        exit 1
    fi
    NEW_ROUND=1
else
    NEW_BASE="$BASE"
    NEW_ROUND=$(( ROUND + 1 ))
fi

CURRENT="${BASE}+ARAS.Patch.${ROUND}"
NEW="${NEW_BASE}+ARAS.Patch.${NEW_ROUND}"

BASES=$(grep -c -E '^ +MARKETING_VERSION:' "$PROJECT_YML")
ROUNDS=$(grep -c -E '^ +DISTRIBUTION_PATCH:' "$PROJECT_YML")
sed -i '' -E \
    -e "s/^( +MARKETING_VERSION: )\"${BASE}\"/\1\"${NEW_BASE}\"/" \
    -e "s/^( +DISTRIBUTION_PATCH: )${ROUND}\$/\1${NEW_ROUND}/" \
    "$PROJECT_YML"

# Every target that carries the pair must move together; a partial rewrite
# would ship a bundle that lies about its own version.
if [[ "$(grep -c -E "^ +MARKETING_VERSION: \"${NEW_BASE}\"" "$PROJECT_YML")" -ne "$BASES" ]] \
    || [[ "$(grep -c -E "^ +DISTRIBUTION_PATCH: ${NEW_ROUND}\$" "$PROJECT_YML")" -ne "$ROUNDS" ]]; then
    echo "ERROR: project.yml was only partly rewritten — check MARKETING_VERSION and DISTRIBUTION_PATCH" >&2
    exit 1
fi

git -C "${REPO_ROOT}" commit --quiet --only -m "Bump v${NEW}" -- "${PROJECT_YML}"

echo "${CURRENT} → ${NEW}"
git -C "${REPO_ROOT}" log -1 --format="committed %h %s"
echo ""
echo "Push, wait for CI, then run: .github/scripts/release.sh"
