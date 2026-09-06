#!/usr/bin/env bash
# Builds an amd64 UEFI-hybrid Debian live ISO in Docker. Run from macOS/Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/image/out"
WORK="$ROOT/image/build/live-build"
mkdir -p "$OUT"
rm -rf "$WORK"
mkdir -p "$WORK"

# The container keeps Debian build dependencies out of the host.
docker rm -f displayos-iso-build >/dev/null 2>&1 || true
docker run --name displayos-iso-build --privileged --platform linux/amd64 \
  -v "$ROOT:/workspace" -w /workspace/image/build \
  debian:bookworm-slim bash -ec '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends live-build ca-certificates
    # Build inside the container filesystem: Docker bind mounts are nodev on
    # macOS, whereas debootstrap needs to create device nodes in its chroot.
    rm -rf /build
    mkdir -p /build
    cp -a /workspace/image/config/. /build/
    cd /build
    lb config --architectures amd64 --distribution bookworm --archive-areas "main contrib non-free-firmware" \
      --binary-images iso-hybrid --bootappend-live "boot=live components quiet splash"
    lb build
    cp live-image-amd64.hybrid.iso /workspace/image/out/displayos-poc-amd64.iso
  '

docker rm displayos-iso-build >/dev/null
shasum -a 256 "$OUT/displayos-poc-amd64.iso" > "$OUT/displayos-poc-amd64.iso.sha256"
echo "Built $OUT/displayos-poc-amd64.iso"
