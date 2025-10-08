#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${BASE_DIR}/scripts/00-bootstrap.sh" >/dev/null 2>&1 || true

CHROOT="${MUREX_CHROOT_DIR}"
SRCDIR="${SRCDIR}"
CHROOT_RUN="${MUREX_BUILD_DIR}/chroot-run.sh"

mount_chroot

echo "=== Stage 04: Graphical stack (Xorg + suckless apps) ==="

# Build Xorg: This is a simplified flow. Building full Xorg requires many libs (libX11, libxcb, pixman, libdrm, libglvnd, mesa, etc.)
# You will likely need to add many more dependencies. The script below clones a minimal set and tries to build libX11 and xorg-server.
# It's provided as a scaffold rather than an exhaustive solution.

${CHROOT_RUN} "${CHROOT}" "bash -lc 'set -e; cd /usr/src; \
if [ ! -d libX11 ]; then git clone https://gitlab.freedesktop.org/xorg/lib/libX11.git libX11; fi; \
cd libX11; ./autogen.sh || true; ./configure --prefix=/usr CC=/tools/bin/musl-gcc || true; make -j$(nproc) || true; make install || true'"

# Build xorg-server (likely to require many deps)
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src; if [ ! -d xorg-server ]; then git clone https://gitlab.freedesktop.org/xorg/xserver.git xorg-server; fi; cd xorg-server; ./autogen.sh || true; ./configure --prefix=/usr CC=/tools/bin/musl-gcc || true; make -j$(nproc) || true; make install || true' || true"

echo "Note: Xorg build is complex. You will almost certainly need to add pixman, libxcb, libxrandr, libxinerama, libXft, fontconfig, freetype, mesa, libdrm, and device drivers. Use this stage as skeleton to iterate on."

# Build suckless st, dwm, dmenu, tabbed, surf, tabbed
for rep in "${STGIT}" "${DWGIT}" "${DMMGIT}" "${TABBEDGIT}" "${SURFGIT}"; do
  name="$(basename "${rep}")"
  echo "Cloning and building ${name}..."
  ${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d ${name} ]; then git clone ${rep} ${name}; fi; cd ${name}; make CC=/tools/bin/musl-gcc && make PREFIX=/usr install || true'"
done

# Build nsxiv (image viewer)
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d nsxiv ]; then git clone https://github.com/NationalSecurityAgency/NSXIV.git nsxiv || git clone https://github.com/hdv/nsxiv.git nsxiv; fi; cd nsxiv; make CC=/tools/bin/musl-gcc; make PREFIX=/usr install || true'"

# zathura (PDF viewer) - requires poppler, gir etc. May be heavy
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d zathura ]; then git clone https://gitlab.pwmt.org/pwmt/zathura.git zathura; fi; cd zathura; make CC=/tools/bin/musl-gcc || true; make PREFIX=/usr install || true' || true"

# slock (locker)
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d slock ]; then git clone https://git.suckless.org/slock slock; fi; cd slock; make CC=/tools/bin/musl-gcc; make PREFIX=/usr install || true'"

echo "Graphical stage done. Expect to iterate heavily. The point here is to include builds and install them under /usr/xbin (see config stage)."
