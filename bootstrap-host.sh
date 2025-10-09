#!/bin/bash
#
# Murex Host Bootstrap Script
# ---------------------------
# Ensures your host system has all necessary dependencies to build Murex (LFS-style).
# Automatically installs any missing packages using apt.
#
# Run as root or with sudo:
#   sudo ./bootstrap-host.sh
#
# Tested on: Debian, Ubuntu, Devuan, MX Linux
#

set -e

echo "Murex Build Environment Bootstrap"
echo "===================================="

#-------------------------------------------------------------
# 1. Required packages
#-------------------------------------------------------------
REQUIRED_PACKAGES=(
  bash
  binutils
  bison
  bzip2
  coreutils
  dialog
  diffutils
  findutils
  gawk
  gcc
  g++
  git
  grep
  gzip
  make
  patch
  perl
  python3
  sed
  tar
  texinfo
  xz-utils
  curl
  git
  rsync
  sudo
  time
  dialog
)

#-------------------------------------------------------------
# 2. Check for apt
#-------------------------------------------------------------
if ! command -v apt >/dev/null 2>&1; then
  echo "Error: apt not found. Please run this on a Debian-based system."
  exit 1
fi

#-------------------------------------------------------------
# 3. Update apt and install missing packages
#-------------------------------------------------------------
echo "🔍 Checking for missing packages..."
MISSING=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING+=("$pkg")
  fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
  echo "All required packages are already installed."
else
  echo "Installing missing packages: ${MISSING[*]}"
  apt update -y
  apt install -y "${MISSING[@]}"
fi

#-------------------------------------------------------------
# 4. Verify core tool versions
#-------------------------------------------------------------
echo
echo "Verifying toolchain versions..."

check_version() {
  prog="$1"
  minver="$2"
  current="$($prog --version 2>/dev/null | head -n1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -n1)"
  if [ -z "$current" ]; then
    echo "⚠️  $prog version could not be determined"
    return
  fi
  if dpkg --compare-versions "$current" "lt" "$minver"; then
    echo "$prog version $current < required $minver"
  else
    echo "$prog version $current (OK)"
  fi
}

check_version bash 3.2
check_version gcc 6.2
check_version binutils 2.25
check_version make 4.0
check_version perl 5.8
check_version python3 3.4
check_version tar 1.28
check_version xz 5.0

#-------------------------------------------------------------
# 5. Environment check
#-------------------------------------------------------------
echo
echo "Checking environment variables..."

if [ -z "$LFS" ]; then
  echo "⚠️  LFS variable not set. Set it before running the build script:"
  echo "   export LFS=/mnt/lfs"
else
  echo "LFS is set to $LFS"
fi

if [ ! -d "$LFS" ]; then
  echo "⚠️  Directory $LFS does not exist. Creating..."
  mkdir -pv "$LFS"
fi

echo
echo "Host bootstrap complete. You're ready to build Murex!"
