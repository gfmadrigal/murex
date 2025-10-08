#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${BASE_DIR}/scripts/00-bootstrap.sh" >/dev/null 2>&1 || true

echo "=== Stage 02: System core (sbase/ubase, runit, util-linux-lite) ==="
CHROOT="${MUREX_CHROOT_DIR}"
SRCDIR="${SRCDIR}"

mount_chroot

# ensure tools and profile are visible in chroot
cp -a "${SRCDIR}/musl-${MUSL_VERSION}" "${CHROOT}/usr/src/musl" || true

# helper for building inside chroot using musl
CHROOT_RUN="${MUREX_BUILD_DIR}/chroot-run.sh"

# 1) Build sbase (suckless) inside chroot
echo "Cloning and building sbase in chroot..."
${CHROOT_RUN} "${CHROOT}" "bash -lc 'mkdir -p /usr/src && cd /usr/src && if [ ! -d sbase ]; then git clone ${SBASE_GIT}; fi; cd sbase; make clean || true; make CC=/tools/bin/musl-gcc PREFIX=/usr install'"

# 2) Build ubase (system admin tools) in chroot
echo "Cloning and building ubase in chroot..."
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d ubase ]; then git clone ${UBASE_GIT}; fi; cd ubase; make clean || true; make CC=/tools/bin/musl-gcc PREFIX=/usr install'"

# 3) Install runit (service manager)
echo "Installing runit into chroot..."
${CHROOT_RUN} "${CHROOT}" "bash -lc 'apk add --no-cache runit' 2>/dev/null || true"
# If apk isn't present (e.g., host is Debian), fall back to building runit from git
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d runit ]; then git clone https://git.savannah.nongnu.org/git/runit.git runit; fi; cd runit/src; make clean || true; CC=/tools/bin/musl-gcc PREFIX=/usr make install' || true"

# 4) util-linux-lite: for mount/umount, fdisk basics – optional minimal subset
echo "Installing util-linux minimal components (mount, umount) if available..."
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && mkdir -p util-linux || true; echo \"skipping heavy util-linux; using sbase/ubase for mount/umount\"'"

# 5) Create vital symlinks for /bin/sh -> rc (we will install rc later)
${CHROOT_RUN} "${CHROOT}" "bash -lc 'ln -sf /usr/bin/rc /bin/sh || true'"

echo "System core stage complete."
