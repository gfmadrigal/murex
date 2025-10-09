#!/usr/bin/env bash
#
# murex-build.sh
#
# Single-file, non-interactive LFS-style build script for Murex Linux (x86_64, musl).
# Modular stages are implemented as functions. All variables are defined near the top.
#
# USAGE:
#   sudo ./murex-build.sh
#
# The script logs output for each stage under ./logs/
#
# WARNING:
#   - Run as root on a disposable build host or VM.
#   - This script will bind-mount /dev, /proc, /sys into the chroot.
#   - Building Xorg and some GUI apps is complex and may require additional dev libraries;
#     those sections are scaffolded and may need iteration.
#
set -euo pipefail
IFS=$'\n\t'

################################################################################
# CONFIGURATION (edit these variables before running)
################################################################################

# Build root and chroot layout
BUILD_ROOT="${PWD}/build"              # top-level working directory (default: ./build)
SRCDIR="${BUILD_ROOT}/sources"         # where tarballs and clones will live
CHROOT_DIR="${BUILD_ROOT}/rootfs"      # target rootfs/chroot
TOOLS_DIR="${CHROOT_DIR}/tools"        # musl and helpers will be installed here during bootstrap
LOGDIR="${BUILD_ROOT}/logs"            # logs for each stage go here
CACHE_DIR="${BUILD_ROOT}/cache"        # optional cache for built packages

# Architecture & targets
TARGET_ARCH="x86_64"

# Versions - change these to the exact versions you prefer
MUSL_VERSION="1.2.5"
MUSL_TARBALL="musl-${MUSL_VERSION}.tar.gz"
MUSL_URL="https://musl.libc.org/releases/${MUSL_TARBALL}"

# Suckless / small tools (we'll clone from upstream)
SBASE_GIT="https://git.suckless.org/sbase"
UBASE_GIT="https://git.suckless.org/ubase"
RC_GIT="https://git.suckless.org/rc"
DWGIT="https://git.suckless.org/dwm"
STGIT="https://git.suckless.org/st"
DMMGIT="https://git.suckless.org/dmenu"
SURFGIT="https://git.suckless.org/surf"
TABBEDGIT="https://git.suckless.org/tabbed"
SLOCKGIT="https://git.suckless.org/slock"

# Other repos (may be heavier)
LF_GIT="https://github.com/gokcehan/lf.git"
SCIM_GIT="https://github.com/andmarti1424/sc-im.git"
CALCURSE_GIT="https://github.com/lfos/calcurse.git"
NEWSBOAT_GIT="https://github.com/newsboat/newsboat.git"
DROPBEAR_GIT="https://github.com/openssh/openssh-portable.git"  # fallback if dropbear not used; heavy

# Build parallelism
JOBS="$(nproc || echo 1)"

# Default shell choices
DEFAULT_SHELL="rc"  # "rc" or "zsh"
INSTALL_ZSH=true    # set true to compile zsh into chroot (may be heavy)

# Misc flags
STRIP_BINARIES=true   # strip installed binaries to reduce size (careful while debugging)

################################################################################
# Derived paths - do not edit
################################################################################
mkdir -p "${BUILD_ROOT}" "${SRCDIR}" "${CHROOT_DIR}" "${LOGDIR}" "${CACHE_DIR}"
ABS_BUILD_ROOT="$(cd "${BUILD_ROOT}" && pwd)"
ABS_SRCDIR="$(cd "${SRCDIR}" && pwd)"
ABS_CHROOT_DIR="$(cd "${CHROOT_DIR}" && pwd)"
ABS_LOGDIR="$(cd "${LOGDIR}" && pwd)"
ABS_CACHE_DIR="$(cd "${CACHE_DIR}" && pwd)"

################################################################################
# Helper functions
################################################################################

log() {
  echo "[INFO] $*" | tee -a "${ABS_LOGDIR}/build.log"
}

err() {
  echo "[ERROR] $*" | tee -a "${ABS_LOGDIR}/build.log" >&2
  exit 1
}

run_log() {
  # Run a command and tee stdout/stderr to a stage-specific log
  local stage="$1"; shift
  local logf="${ABS_LOGDIR}/${stage}.log"
  log "Starting stage: ${stage}. Log: ${logf}"
  # shellcheck disable=SC2086
  ("$@") 2>&1 | tee "${logf}"
  log "Stage ${stage} finished (return $?)."
}

# download helper: idempotent
download() {
  local url="$1" out="$2"
  if [ -f "${out}" ]; then
    log "Already have ${out}"
    return 0
  fi
  log "Downloading ${url} -> ${out}"
  if command -v curl >/dev/null 2>&1; then
    curl -L --retry 5 -o "${out}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${out}" "${url}"
  else
    err "Neither curl nor wget available on host"
  fi
}

# chroot-run: run a command inside the fresh chroot with a sanitized environment
chroot_run() {
  local cmd="$*"
  # PATH inside chroot: /tools/bin first then normal places
  env -i HOME=/root TERM="${TERM:-xterm}" PATH="/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    chroot "${ABS_CHROOT_DIR}" /bin/sh -lc "${cmd}"
}

################################################################################
# Safety checks
################################################################################

if [ "$(id -u)" -ne 0 ]; then
  err "This script must be run as root. Exiting."
fi

if [ "$(uname -m)" != "x86_64" ]; then
  err "This script targets x86_64. Host arch is $(uname -m). Aborting."
fi

log "Murex build starting in ${ABS_BUILD_ROOT}"
log "Logs will be written to ${ABS_LOGDIR}"

################################################################################
# STAGE 0: Prepare chroot skeleton and download sources
################################################################################
stage_prepare() {
  local stage="00-prepare"
  run_log "${stage}" bash -lc "$(cat <<'SH'
set -eu
# Create chroot skeleton directories with proper modes
for d in bin dev etc proc sys tmp run var var/log usr/bin usr/sbin usr/xbin usr/lib usr/local bin sbin tools; do
  mkdir -p "${CHROOT_DIR}/${d}"
done
chmod 1777 "${CHROOT_DIR}/tmp"
# Note: populate /etc with base files later in config stage
SH
)" || true

  # Download musl tarball for musl bootstrap
  download "${MUSL_URL}" "${ABS_SRCDIR}/${MUSL_TARBALL}"

  # Create a simple chroot-run helper script in build dir
  cat > "${ABS_BUILD_ROOT}/chroot-run.sh" <<'SH'
#!/usr/bin/env bash
CHROOT_DIR="$1"; shift
env -i HOME=/root TERM="${TERM:-xterm}" PATH="/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  chroot "$CHROOT_DIR" /bin/sh -lc "$*"
SH
  chmod +x "${ABS_BUILD_ROOT}/chroot-run.sh"
}

################################################################################
# STAGE 1: Bootstrap toolchain (build musl and musl-gcc wrapper into /tools)
#  - Build musl on the host and install to $TOOLS_DIR, then copy into chroot.
#  - Create /tools/bin/musl-gcc wrapper to force static builds.
################################################################################
stage_toolchain() {
  local stage="01-toolchain"
  mkdir -p "${ABS_CACHE_DIR}"
  run_log "${stage}" bash -lc "$(cat <<'SH'
set -eu
# unpack musl
cd "${SRCDIR}"
if [ ! -d "musl-${MUSL_VERSION}" ]; then
  tar -xzf "${SRCDIR}/${MUSL_TARBALL}" -C "${SRCDIR}"
fi
cd "musl-${MUSL_VERSION}"

# configure musl to install into /tools inside the future chroot
# (we first build and install musl into a temporary host dir, then copy into chroot)
TMP_TOOLS="${BUILD_ROOT}/tmp-tools"
rm -rf "${TMP_TOOLS}"
mkdir -p "${TMP_TOOLS}"

# Configure, make, and install musl (static-only)
CC="${CC:-gcc}" ./configure --prefix="${TMP_TOOLS}"
make -j"${JOBS}"
make install

# Create a static musl-gcc wrapper that invokes host gcc but points includes/libs to musl
mkdir -p "${TMP_TOOLS}/bin"
cat > "${TMP_TOOLS}/bin/musl-gcc" <<'EOF'
#!/usr/bin/env bash
# musl-gcc wrapper - static by default
MUSL_PREFIX="@MUSL_PREFIX@"
exec gcc -static -nostdinc -I"${MUSL_PREFIX}/include" -L"${MUSL_PREFIX}/lib" "$@"
EOF
# replace placeholder with real path
sed -i "s|@MUSL_PREFIX@|${TMP_TOOLS}|g" "${TMP_TOOLS}/bin/musl-gcc"
chmod +x "${TMP_TOOLS}/bin/musl-gcc"

# copy the temporary tools into the chroot's /tools
rm -rf "${CHROOT_DIR}/tools"
mkdir -p "${CHROOT_DIR}/tools"
cp -a "${TMP_TOOLS}/." "${CHROOT_DIR}/tools/"

# Also copy musl source into chroot for reference
mkdir -p "${CHROOT_DIR}/usr/src"
cp -a "${SRCDIR}/musl-${MUSL_VERSION}" "${CHROOT_DIR}/usr/src/"

# create a minimal /etc/profile inside chroot to ensure PATH and CC are set
cat > "${CHROOT_DIR}/etc/profile" <<'EOF'
export PATH="/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export CC="/tools/bin/musl-gcc"
EOF
SH
)" || err "toolchain stage failed"
}

################################################################################
# STAGE 2: Mount /dev, /proc, /sys and prepare chroot for builds
################################################################################
stage_mounts() {
  local stage="02-mounts"
  run_log "${stage}" bash -lc "$(cat <<'SH'
set -eu
# Bind mount host devices into the chroot so builds can access /dev, /proc, /sys
mount --bind /dev "${CHROOT_DIR}/dev"
mount --bind /dev/pts "${CHROOT_DIR}/dev/pts" || true
mount -t proc proc "${CHROOT_DIR}/proc"
mount -t sysfs sys "${CHROOT_DIR}/sys"
# copy resolver so network works inside chroot
cp -L /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"
SH
)" || err "mounts stage failed"
}

################################################################################
# STAGE 3: Build and install basic system utilities inside chroot
#   - sbase and ubase (suckless)
#   - rc (shell)
#   - runit (service manager)
################################################################################
stage_system_core() {
  local stage="03-system-core"
  run_log "${stage}" bash -lc "$(cat <<'SH'
set -eu
# define a local helper to run commands inside chroot using musl-gcc
CHROOT_RUN='"${ABS_BUILD_ROOT}/chroot-run.sh"'
# Clone and build sbase inside chroot
cd /usr/src
if [ ! -d sbase ]; then git clone --depth 1 ${SBASE_GIT} sbase; fi
cd sbase
# build with musl wrapper and install to /usr
make clean || true
make CC=/tools/bin/musl-gcc PREFIX=/usr install

# Clone and build ubase inside chroot (admin utilities)
cd /usr/src
if [ ! -d ubase ]; then git clone --depth 1 ${UBASE_GIT} ubase; fi
cd ubase
make clean || true
make CC=/tools/bin/musl-gcc PREFIX=/usr install

# Clone and build rc if not included
cd /usr/src
if [ ! -d rc ]; then git clone --depth 1 ${RC_GIT} rc; fi
cd rc
make clean || true
make CC=/tools/bin/musl-gcc PREFIX=/usr install

# Install runit service manager
cd /usr/src
if [ ! -d runit ]; then git clone --depth 1 https://git.savannah.nongnu.org/git/runit.git runit; fi
cd runit/src
# runit build system uses simple Makefiles
make CC=/tools/bin/musl-gcc
make PREFIX=/usr install

# Symlink /bin/sh to rc for minimalism (can be changed later)
ln -sf /usr/bin/rc /bin/sh || true
SH
)" || err "system core build failed"
}

################################################################################
# STAGE 4: Userland - shells, editors, and terminal applications
#   - zsh (optional)
#   - vis / ed
#   - lf, sc-im, calcurse, newsboat, dropbear (or openssh)
################################################################################
stage_userland() {
  local stage="04-userland"
  run_log "${stage}" bash -lc "$(cat <<'SH'
set -eu
cd /usr/src

# Install vis (suckless editor)
if [ ! -d vis ]; then git clone --depth 1 https://github.com/martanne/vis.git vis; fi
cd vis
make CC=/tools/bin/musl-gcc
make PREFIX=/usr install || true

# Install lf (terminal file manager)
cd /usr/src
if [ ! -d lf ]; then git clone --depth 1 ${LF_GIT} lf; fi
cd lf
# lf is Go-based by default; if go isn't available, attempt 'make install' (may need host go)
if command -v go >/dev/null 2>&1; then
  GOFLAGS= make install PREFIX=/usr
else
  echo "lf build skipped: Go not available on host" >&2
fi

# Install sc-im (spreadsheet)
cd /usr/src
if [ ! -d sc-im ]; then git clone --depth 1 ${SCIM_GIT} sc-im; fi
cd sc-im
make CC=/tools/bin/musl-gcc
make PREFIX=/usr install || true

# Install calcurse - may require autotools on host; try best-effort
cd /usr/src
if [ ! -d calcurse ]; then git clone --depth 1 ${CALCURSE_GIT} calcurse; fi
cd calcurse
autoreconf -fi || true
./configure --prefix=/usr CC=/tools/bin/musl-gcc || true
make -j${JOBS} || true
make install || true

# Install newsboat (optional)
cd /usr/src
if [ ! -d newsboat ]; then git clone --depth 1 ${NEWSBOAT_GIT} newsboat; fi
cd newsboat
# newsboat uses autotools; build best-effort with musl
autoreconf -fi || true
./configure --prefix=/usr CC=/tools/bin/musl-gcc || true
make -j${JOBS} || true
make install || true

# Install SSH server: try dropbear (lightweight)
cd /usr/src
if [ ! -d dropbear ]; then git clone --depth 1 https://github.com/mkj/dropbear.git dropbear; fi
cd dropbear
./configure --prefix=/usr CC=/tools/bin/musl-gcc || true
make PROGRAMS="dropbear dbclient dropbearkey scp" -j${JOBS} || true
make PREFIX=/usr install || true

# Optionally compile zsh (heavy)
if [ "${INSTALL_ZSH}" = true ]; then
  cd /usr/src
  if [ ! -d zsh ]; then git clone --depth 1 https://github.com/zsh-users/zsh.git zsh; fi
  cd zsh
  # Prepare build
  ./Util/preconfig || true
  ./configure --prefix=/usr CC=/tools/bin/musl-gcc LDFLAGS=-static CFLAGS=-O2 || true
  make -j${JOBS} || true
  make install || true
fi

# ensure some base programs exist
for cmd in grep sed awk tar gzip bzip2 uname printf head tail; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "WARNING: ${cmd} not found; some scripts may rely on it"
  fi
done
SH
)" || err "userland stage failed"
}

################################################################################
# STAGE 5: Graphical scaffold (attempt to build minimal Xorg libs and suckless apps)
#   - NOTE: building Xorg is non-trivial; this stage scaffolds the steps and attempts
#     to build a small set of suckless GUI programs (st, dwm, dmenu, tabbed, slock).
################################################################################
stage_graphics() {
  local stage="05-graphics"
  run_log "${stage}" bash -lc "$(cat <<'SH'
set -eu
cd /usr/src

# Build libX11 minimally (may require many deps in practice)
if [ ! -d libX11 ]; then git clone --depth 1 https://gitlab.freedesktop.org/xorg/lib/libX11.git libX11; fi
cd libX11
autoreconf -fi || true
./configure --prefix=/usr CC=/tools/bin/musl-gcc || true
make -j${JOBS} || true
make install || true

# xorg-server is complicated; attempt a minimal build (likely to fail on missing deps)
cd /usr/src
if [ ! -d xorg-server ]; then git clone --depth 1 https://gitlab.freedesktop.org/xorg/xserver.git xorg-server; fi
cd xorg-server
autoreconf -fi || true
./configure --prefix=/usr CC=/tools/bin/musl-gcc || true
make -j${JOBS} || true
make install || true

# Build suckless st, dwm, dmenu, slock, tabbed, surf
for repo in "${STGIT}" "${DWGIT}" "${DMMGIT}" "${SLOCKGIT}" "${TABBEDGIT}" "${SURFGIT}"; do
  name="$(basename "${repo}")"
  cd /usr/src
  if [ ! -d "${name}" ]; then git clone --depth 1 "${repo}" "${name}"; fi
  cd "${name}"
  make CC=/tools/bin/musl-gcc || true
  make PREFIX=/usr install || true
done

# Note: Many GUI programs require libXft, fontconfig, freetype, pixman, libxcb, mesa etc.
# Those should be added if you want a functional X session. This scaffold aims to
# install the small suckless programs in /usr (it may be necessary to iterate).
SH
)" || err "graphics stage failed"
}

################################################################################
# STAGE 6: Install configuration files, runit services, and finalize rootfs layout
################################################################################
stage_config() {
  local stage="06-config"
  run_log "${stage}" bash -lc "$(cat <<'SH'
set -eu
# Basic /etc skeleton and users
mkdir -p /etc/runit
cat > /etc/rc.conf <<'EOF'
HOSTNAME="murex"
EOF

# Minimal /etc/passwd and /etc/group
cat > /etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/sh
demo:x:1000:1000:Demo User:/home/demo:/usr/bin/zsh
EOF

cat > /etc/group <<'EOF'
root:x:0:
users:x:1000:
EOF

# Create a demo user and home (password can be set later by admin)
mkdir -p /home/demo
chown 1000:1000 /home/demo || true

# Ensure /usr/xbin exists for GUI segregation
mkdir -p /usr/xbin
# by default, PATH in profile will not include /usr/xbin; startx should export it temporarily

# create a simple startx wrapper in /usr/local/bin/startx
mkdir -p /usr/local/bin
cat > /usr/local/bin/startx <<'EOF'
#!/bin/sh
export PATH="/usr/xbin:/usr/local/bin:/usr/bin:/bin"
exec /usr/bin/xinit "\$@"
EOF
chmod +x /usr/local/bin/startx

# create basic murex-info
cat > /usr/bin/murex-info <<'EOF'
#!/bin/sh
echo "Murex Linux - musl based, runit init, suckless utilities"
EOF
chmod +x /usr/bin/murex-info
SH
)" || err "config stage failed"
}

################################################################################
# STAGE 7: Cleanup, optional stripping, and produce rootfs tarball
################################################################################
stage_cleanup_and_package() {
  local stage="07-package"
  run_log "${stage}" bash -lc "$(cat <<'SH'
set -eu
# Optionally strip binaries to reduce size (will remove debugging info)
if [ "${STRIP_BINARIES}" = true ]; then
  find /usr/bin /usr/sbin /bin /sbin -type f -executable 2>/dev/null | while read -r b; do
    file "$b" | grep -q 'ELF' && strip --strip-all "$b" || true
  done
fi

# Clean package caches (best-effort)
rm -rf /var/cache/* || true

# Ensure ownership and permissions look reasonable
chmod 755 /root || true

# Create a compressed rootfs tarball (numeric owner to preserve uid/gid)
OUT_TAR="${BUILD_ROOT}/murex-rootfs-$(date +%Y%m%d).tar.xz"
log "Creating rootfs tarball: ${OUT_TAR}"
# Move out of chroot dir to create tar
cd "${CHROOT_DIR}"
tar --numeric-owner -cJf "${OUT_TAR}" ./
log "Rootfs tarball created at ${OUT_TAR}"
SH
)" || err "package stage failed"
}

################################################################################
# STAGE 8: Unmount chroot mounts (cleanup)
################################################################################
stage_unmount() {
  local stage="08-unmount"
  run_log "${stage}" bash -lc "$(cat <<'SH'
set -eu
# Unmount in reverse order to be safe
for p in dev/pts dev proc sys; do
  if mountpoint -q "${CHROOT_DIR}/$p"; then
    umount -lf "${CHROOT_DIR}/$p" || true
  fi
done
# Also unmount any other binds if present
if mountpoint -q "${CHROOT_DIR}/dev"; then
  umount -lf "${CHROOT_DIR}/dev" || true
fi
SH
)" || err "unmount stage failed"
}

################################################################################
# DRIVER: run stages in order
################################################################################
main() {
  stage_prepare
  stage_toolchain
  stage_mounts
  stage_system_core
  stage_userland
  stage_graphics
  stage_config
  stage_cleanup_and_package
  stage_unmount
  log "Murex build completed. Check ${ABS_LOGDIR} for per-stage logs."
}

# Execute main
main "$@"