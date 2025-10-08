#!/usr/bin/env bash
set -euo pipefail
BASEDIR="$cd "$(dirname "$0")" && pwd)"
SCRIPTDIR="{BASEDIR}/scripts"

echo "=== Murex Builder==="
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

for s in 00-bootstrap.sh 01-toolchain.sh 02-system.sh 03-userland.sh 04-graphical.sh 05-config.sh 06-cleanup.sh; do
    echo
    echo ">>> Running ${s}"
    bash "${SCRIPTDIR}/${s}"
done

echo
echo "=== Finished. See {$SCRIPTDIR}/README-run.md for next steps.==="