#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${KERNEL:-$(uname -r)}"
IPU6_DRIVERS="${IPU6_DRIVERS:-$ROOT/third_party/ipu6-drivers}"
DKMS_NAME="${DKMS_NAME:-ipu6-drivers}"
DKMS_VERSION="${DKMS_VERSION:-0.0.0}"
DKMS_SOURCE_DIR="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"

if [[ ! -f "$IPU6_DRIVERS/dkms.conf" ]]; then
    cat >&2 <<EOF
Missing ipu6-drivers DKMS source:
  $IPU6_DRIVERS/dkms.conf

Run "$ROOT/scripts/clone-sources.sh" first, or set IPU6_DRIVERS=/path/to/ipu6-drivers.
EOF
    exit 1
fi

if ! command -v dkms >/dev/null 2>&1; then
    echo "Missing dkms. Install DKMS with your distro package manager, then rerun this script." >&2
    exit 1
fi

stage_dkms_source() {
    sudo rm -rf "$DKMS_SOURCE_DIR"
    sudo install -d -m 0755 "$DKMS_SOURCE_DIR"

    if git -C "$IPU6_DRIVERS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$IPU6_DRIVERS" archive --format=tar HEAD \
            | sudo tar -xf - -C "$DKMS_SOURCE_DIR"
    else
        sudo cp -a "$IPU6_DRIVERS/." "$DKMS_SOURCE_DIR/"
    fi
}

# Keep a persistent DKMS source tree.  Registering a temporary archive can
# leave /var/lib/dkms/.../source pointing at an empty path after cleanup,
# breaking future kernel upgrades.
if [[ ! -f "$DKMS_SOURCE_DIR/dkms.conf" ]]; then
    sudo dkms remove "$DKMS_NAME/$DKMS_VERSION" --all 2>/dev/null || true
    stage_dkms_source
    sudo dkms add "$DKMS_SOURCE_DIR"
fi

sudo dkms build "$DKMS_NAME/$DKMS_VERSION" -k "$KERNEL"
sudo dkms install "$DKMS_NAME/$DKMS_VERSION" -k "$KERNEL"
sudo depmod -a "$KERNEL"

sudo install -D -m 0644 \
    "$ROOT/config/udev/rules.d/70-ipu6-psys.rules" \
    /etc/udev/rules.d/70-ipu6-psys.rules

sudo udevadm control --reload-rules

if [[ -e /dev/ipu-psys0 ]]; then
    sudo chgrp video /dev/ipu-psys0 || true
    sudo chmod 660 /dev/ipu-psys0 || true
fi

cat <<EOF
Installed $DKMS_NAME/$DKMS_VERSION for kernel $KERNEL.

The DKMS-managed PSYS module will be used after reboot, or after all camera users are
closed and the live module can be unloaded/reloaded.
EOF
