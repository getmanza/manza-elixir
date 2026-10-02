#!/usr/bin/env bash
# Downloads the cassette tarball published by manza-ruby's release workflow.
# CI calls this before running tests so we don't have to commit cassettes
# into both repos.
#
#   scripts/fetch-cassettes.sh            # the pinned tag below
#   scripts/fetch-cassettes.sh v1.0.1     # specific tag
#
# Cassettes land under testdata/cassettes/.
set -euo pipefail

REPO="getmanza/manza-ruby"
# Pinned so a new manza-ruby release cannot break every SDK's CI at once; bump on purpose.
PINNED_TAG="v1.0.0"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/testdata/cassettes"

TAG="${1:-$PINNED_TAG}"
AUTH=()
if [[ -n "${GH_TOKEN:-}" ]]; then
  AUTH=(-H "Authorization: Bearer $GH_TOKEN")
fi

URL="https://github.com/$REPO/releases/download/$TAG/cassettes-$TAG.tar.gz"
echo "Fetching cassettes from $URL"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 8 --retry-all-errors --retry-delay 10 "${AUTH[@]}" -H "Accept: application/octet-stream" -o "$TMP/cassettes.tar.gz" "$URL"

mkdir -p "$DEST"
tar -xzf "$TMP/cassettes.tar.gz" -C "$(dirname "$DEST")"
echo "Cassettes extracted to $DEST"
