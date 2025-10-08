#!/bin/bash
set -e
source "$(dirname "$0")/../build.conf"

log() { echo -e "\033[1;32m==>\033[0m $*"; }
err() { echo -e "\033[1;31m!!\033[0m $*" >&2; exit 1; }

ensure_dir() {
  [ -d "$1" ] || mkdir -pv "$1"
}

download() {
  url=$1
  file=$2
  [ -f "$file" ] || wget -q --show-progress "$url" -O "$file"
}