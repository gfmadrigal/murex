#!/usr/bin/env bash
set -euo pipefail

: "${MUREX_BUILD_DIR:=/mnt/murex_build}"
: "${MUREX_CHROOT_DIR:=${MUREX_BUILD_DIR}/murex-root}"
: "${SRCDIR:=${MUREX_BUILD_DIR}/sources}"
: "${TOOLS_DIR:=${MUREX_CHROOT_DIR}/tools}"

MUSL_VERSION="1.2.5"               # change if you want newer
MUSL_TARBALL="musl-${MUSL_VERSION}.tar.gz"
MUSL_URL="https://musl.libc.org/releases/${MUSL_TARBALL}"

# Kernel (optional)
LINUX_VERSION="6.6.10"
# ... add more version variables as needed for other packages

# Suckless / small-tools (git clones used)
# sbase/ubase we will clone from suckless/git or alternative repos
SBASE_GIT="https://git.suckless.org/sbase"
UBASE_GIT="https://git.suckless.org/ubase"
RC_GIT="https://git.suckless.org/rc"

# other projects
DWGIT="https://git.suckless.org/dwm"
DMMGIT="https://git.suckless.org/dmenu"
STGIT="https://git.suckless.org/st"
SURFGIT="https://git.suckless.org/surf"
TABBEDGIT="https://git.suckless.org/tabbed"
# zathura, nsxiv, sc-im, calcurse, lf will be built from their git tarballs or repos

# Tools needed on the host (non-exhaustive)
HOST_PKGS=(build-essential gcc make git curl wget xz-utils bzip2 pkg-config python3)

### Derived vars
mkdir -p "${MUREX_BUILD_DIR}" "${SRCDIR}" "${MUREX_CHROOT_DIR}"

echo "Build dir: ${MUREX_BUILD_DIR}"
echo "Chroot root will be: ${MUREX_CHROOT_DIR}"
echo "Sources dir: ${SRCDIR}"
echo "Tools dir: ${TOOLS_DIR}"

## Basic checks
if [ "$(uname -m)" != "x86_64" ]; then
  echo "Warning: This build was configured for x86_64. Host arch is $(uname -m). Aborting."
  exit 1
fi

## Download helper
download() {
  local url="$1"
  local out="$2"
  if [ -f "${out}" ]; then
    echo "Already have ${out}"
    return 0
  fi
  echo "Downloading ${url} -> ${out}"
  curl -L --retry 5 -o "${out}" "${url}"
}

## Fetch musl
pushd "${SRCDIR}" >/dev/null
if [ ! -f "${MUSL_TARBALL}" ]; then
  download "${MUSL_URL}" "${MUSL_TARBALL}"
fi
popd >/dev/null

## Prepare chroot skeleton
echo "Preparing chroot layout..."
for d in bin dev etc proc sys tmp run var var/log usr/bin usr/xbin usr/lib usr/sbin sbin lib mnt root home tools; do
  mkdir -p "${MUREX_CHROOT_DIR}/${d}"
done
chmod 1777 "${MUREX_CHROOT_DIR}/tmp"

## Mount helper for chroot usage
mount_chroot() {
  echo "Mounting /proc /sys /dev and /dev/pts into chroot..."
  mount --bind /dev "${MUREX_CHROOT_DIR}/dev"
  mount --bind /dev/pts "${MUREX_CHROOT_DIR}/dev/pts"
  mount -t proc proc "${MUREX_CHROOT_DIR}/proc"
  mount -t sysfs sys "${MUREX_CHROOT_DIR}/sys"
  cp -L /etc/resolv.conf "${MUREX_CHROOT_DIR}/etc/resolv.conf"
}

umount_chroot() {
  echo "Unmounting chroot"
  for p in dev/pts dev proc sys; do
    if mountpoint -q "${MUREX_CHROOT_DIR}/${p}"; then
      umount -lf "${MUREX_CHROOT_DIR}/${p}" || true
    fi
  done
}

# Provide simple chroot helper for later scripts
cat > "${MUREX_BUILD_DIR}/chroot-run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CHROOT="$1"
shift
# preserve some env
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/tools/bin"
exec chroot "$CHROOT" /usr/bin/env -i HOME=/root TERM="$TERM" PATH="$PATH" /bin/sh -c "$*"
EOF
chmod +x "${MUREX_BUILD_DIR}/chroot-run.sh"

echo "Bootstrap step done. Next: run 01-toolchain.sh"