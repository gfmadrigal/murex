#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${BASE_DIR}/scripts/00-bootstrap.sh" >/dev/null 2>&1 || true

CHROOT="${MUREX_CHROOT_DIR}"

echo "=== Stage 06: Cleanup and package rootfs ==="
mount_chroot

# Strip binaries to reduce size (careful)
echo "Stripping binaries (may break debugging)."
find "${CHROOT}/usr/bin" -type f -executable -exec file {} \; | grep 'ELF' | cut -d: -f1 | while read -r bin; do
  strip --strip-all "${bin}" || true
done

# Create a compressed tarball of the root filesystem
OUT_TARBALL="${MUREX_BUILD_DIR}/murex-rootfs.tar.xz"
echo "Creating rootfs tarball at ${OUT_TARBALL} ..."
tar --numeric-owner -C "${CHROOT}" -cJf "${OUT_TARBALL}" ./

echo "Rootfs tarball created. You can extract to a block device or prepare an ISO later."
