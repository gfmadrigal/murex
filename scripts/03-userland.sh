#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${BASE_DIR}/scripts/00-bootstrap.sh" >/dev/null 2>&1 || true

CHROOT="${MUREX_CHROOT_DIR}"
SRCDIR="${SRCDIR}"
CHROOT_RUN="${MUREX_BUILD_DIR}/chroot-run.sh"

mount_chroot

echo "=== Stage 03: Userland tools (rc, zsh, editors, terminal apps) ==="

# rc (if not installed by sbase)
echo "Installing rc (if needed) ..."
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d rc ]; then git clone ${RC_GIT}; fi; cd rc; make CC=/tools/bin/musl-gcc PREFIX=/usr install || true'"

# zsh (optional) - build in chroot using musl
echo "Building zsh inside chroot..."
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d zsh ]; then git clone https://sourceforge.net/p/zsh/code/ci/master/tree zsh || git clone --depth 1 https://github.com/zsh-users/zsh.git zsh; fi; cd zsh; ./Util/preconfig || true; ./configure --prefix=/usr CC=/tools/bin/musl-gcc CFLAGS=-static LDFLAGS=-static || true; make -j$(nproc) || true; make install || true'"

# doas (privilege tool) - simple
echo "Installing doas (from OpenBSD doas clone)"
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d doas ]; then git clone https://github.com/slicer69/doas.git doas || true; fi; cd doas; make CC=/tools/bin/musl-gcc; make PREFIX=/usr install || true'"

# editors: vis or tiny vi
echo "Installing vis (suckless vis) and ed..."
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d vis ]; then git clone https://github.com/martanne/vis.git vis; fi; cd vis; make CC=/tools/bin/musl-gcc; make PREFIX=/usr install || true'"

# lf (terminal file manager)
echo "Installing lf"
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d lf ]; then git clone https://github.com/gokcehan/lf.git lf; fi; cd lf; make install PREFIX=/usr || true'"

# sc-im (spreadsheet)
echo "Installing sc-im"
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d sc-im ]; then git clone --recursive https://github.com/andmarti1424/sc-im.git sc-im; fi; cd sc-im; make CC=/tools/bin/musl-gcc; make PREFIX=/usr install || true'"

# calcurse
echo "Installing calcurse"
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d calcurse ]; then git clone https://github.com/lfos/calcurse.git calcurse; fi; cd calcurse; autoreconf -fi || true; ./configure --prefix=/usr CC=/tools/bin/musl-gcc LDFLAGS=-static CFLAGS=-static || true; make -j$(nproc) || true; make install || true'"

# newsboat (optional)
echo "Installing newsboat (optional)"
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d newsboat ]; then git clone https://github.com/newsboat/newsboat.git newsboat; fi; cd newsboat; ./autogen.sh || true; ./configure --prefix=/usr CC=/tools/bin/musl-gcc LDFLAGS=-static CFLAGS=-static || true; make -j$(nproc) || true; make install || true'"

# scp/ssh: dropbear as lightweight alternative
echo "Installing dropbear (lightweight ssh)"
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d dropbear ]; then git clone https://github.com/mkj/dropbear.git dropbear; fi; cd dropbear; ./configure --prefix=/usr CC=/tools/bin/musl-gcc CFLAGS=-static LDFLAGS=-static || true; make PROGRAMS=\"dropbear dbclient dropbearkey scp\" -j$(nproc) || true; make install || true'"

# basic networking clients: curl and wget
echo "Installing curl (may be dynamically linked) and wget"
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d curl ]; then git clone https://github.com/curl/curl.git curl; fi; cd curl; ./buildconf || true; ./configure --prefix=/usr CC=/tools/bin/musl-gcc --disable-shared --enable-static || true; make -j$(nproc) || true; make install || true'"

${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d wget ]; then git clone https://git.savannah.gnu.org/git/wget.git wget; fi; cd wget; ./bootstrap || true; ./configure --prefix=/usr CC=/tools/bin/musl-gcc --with-ssl=openssl || true; make -j$(nproc) || true; make install || true'"

# git and dev tools
echo "Installing git (optional, heavy)"
${CHROOT_RUN} "${CHROOT}" "bash -lc 'cd /usr/src && if [ ! -d git ]; then git clone https://github.com/git/git.git git; fi; cd git; make configure; ./configure --prefix=/usr CC=/tools/bin/musl-gcc || true; make -j$(nproc) || true; make install || true'"

echo "Userland stage complete. You may need to iterate on builds if static linking fails for particular apps."
