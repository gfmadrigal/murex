#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${BASE_DIR}/scripts/00-bootstrap.sh" >/dev/null 2>&1 || true

CHROOT="${MUREX_CHROOT_DIR}"
CHROOT_RUN="${MUREX_BUILD_DIR}/chroot-run.sh"

mount_chroot

echo "=== Stage 05: Configuration ==="

# Basic /etc skeleton inside chroot
cat > "${CHROOT}/etc/rc.conf" <<'EOF'
# Murex rc.conf
HOSTNAME="murex"
HUSHLOGIN=1
EOF

cat > "${CHROOT}/etc/profile" <<'EOF'
# /etc/profile - Murex
export PATH="/usr/local/bin:/usr/bin:/bin"
export PS1='%n@%m:%~%# '
EOF

# Setup runit directories
mkdir -p "${CHROOT}/etc/runit"
# create getty service for tty1
mkdir -p "${CHROOT}/etc/runit/getty"
cat > "${CHROOT}/etc/runit/getty/run" <<'EOF'
#!/bin/sh
exec /usr/bin/s6-svscan /etc/sv
EOF
chmod +x "${CHROOT}/etc/runit/getty/run" || true

# Create startx wrapper in /usr/local/bin to ensure GUI PATH isolation
cat > "${CHROOT}/usr/local/bin/startx" <<'EOF'
#!/usr/bin/env bash
# startx wrapper for Murex: add /usr/xbin to PATH only for X session
export PATH="/usr/xbin:/usr/local/bin:/usr/bin:/bin"
exec /usr/bin/xinit "$@"
EOF
chmod +x "${CHROOT}/usr/local/bin/startx"

# Ensure /usr/xbin exists and is not in default PATH
mkdir -p "${CHROOT}/usr/xbin"
echo "/usr/xbin is reserved for optional X apps. Use startx to enter graphical session."

# Sys users: create a minimal passwd and group
cat > "${CHROOT}/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
demo:x:1000:1000:Demo User:/home/demo:/usr/bin/zsh
EOF
cat > "${CHROOT}/etc/group" <<'EOF'
root:x:0:
users:x:1000:
EOF

# Create skeleton home for demo
mkdir -p "${CHROOT}/home/demo"
chown 1000:1000 "${CHROOT}/home/demo"

# set up murex-info script
cat > "${CHROOT}/usr/bin/murex-info" <<'EOF'
#!/usr/bin/env sh
echo "Murex Linux - terminal-first minimal OS"
echo "musl-based, runit init, sbase/ubase coreutils, zsh & rc shells available"
EOF
chmod +x "${CHROOT}/usr/bin/murex-info"

echo "Configuration installed. Edit ${CHROOT}/etc/rc.conf, /etc/profile, and create runit service directories for your services (sshd, syslog, cron)."
