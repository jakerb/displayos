#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:?usage: build-receiver-release.sh VERSION}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
bundle="$stage/receiver-service"
mkdir -p "$bundle" "$root/dist"
cp "$root/apps/receiver/announce.py" "$root/apps/receiver/receiver-ui" "$bundle/"
chmod 755 "$bundle/announce.py" "$bundle/receiver-ui"
printf '{"version":"%s"}\n' "$version" > "$bundle/manifest.json"
archive="$root/dist/displayos-receiver-service.tar.gz"
tar -C "$stage" -czf "$archive" receiver-service
shasum -a 256 "$archive" > "$archive.sha256"
echo "Built $archive for release tag v$version"
