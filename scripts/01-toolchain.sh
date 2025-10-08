#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${BASE_DIR}/scripts/00-bootstrap.sh" >/dev/null 2>&1 || true

echo "=== Stage 01: Toolchain (musl) ==="
SRCDIR="${SRCDIR}"
CHROOT="${MUREX_CHROOT_DIR}"
TOOLS="${TOOLS_DIR}"

# Ensure chroot mounts
mount_chroot

# Build musl on the host and install into ${TOOLS}
pushd "${SRCDIR}" >/dev/null

if [ ! -d "musl-${MUSL_VERSION}" ]; then
  tar -xf "${MUSL_TARBALL}"
fi

pushd "musl-${MUSL_VERSION}" >/dev/null
make clean || true
# Configure a musl installation under /tools inside the chroot target
CC=gcc ./configure --prefix="${TOOLS}" --disable-shared
make -j"$(nproc)"
make install
popd >/dev/null

# Create musl-gcc wrapper in tools/bin
mkdir -p "${TOOLS}/bin"
cat > "${TOOLS}/bin/musl-gcc" <<'EOF'
#!/usr/bin/env bash
# musl-gcc wrapper for building with musl (static)
MUSL_PREFIX="@TOOLS@"
exec gcc -static -nostdinc -I${MUSL_PREFIX}/include -L${MUSL_PREFIX}/lib "$@"
EOF
sed -i "s|@TOOLS@|${TOOLS}|g" "${TOOLS}/bin/musl-gcc"
chmod +x "${TOOLS}/bin/musl-gcc"

# Add tools to chroot
rsync -a "${TOOLS}/" "${CHROOT}/tools/"   # copy musl into chroot /tools
popd >/dev/null

# Create a minimal /etc/ld-musl.conf or wrapper; since we build static we should be fine.
# Create /tools/bin in PATH via /etc/profile and put musl wrapper as default CC
cat > "${CHROOT}/etc/profile" <<'EOF'
export PATH="/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export CC="/tools/bin/musl-gcc"
EOF

echo "Toolchain bootstrapped. musl installed to ${TOOLS} and copied into chroot."
