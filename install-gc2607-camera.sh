#!/usr/bin/env bash
set -Eeuo pipefail

# Standalone GitHub bootstrap installer for the Huawei MateBook X Pro 2024
# GC2607 camera stack. It may be run from a checkout or downloaded as a single
# release asset. It intentionally builds DKMS modules on the target machine.

REPO_URL="${GC2607_REPO_URL:-https://github.com/zylona/gc2607-camera-linux.git}"
DEFAULT_REF="main"
REF="${GC2607_REF:-$DEFAULT_REF}"
AUTO_CONFIRM=0
SKIP_HARDWARE_CHECK=0
SOURCE_ROOT=""
TEMP_ROOT=""

log() {
    printf '\n==> %s\n' "$*"
}

warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: install-gc2607-camera.sh [options]

Install the GC2607 camera stack on a supported Arch/Omarchy MateBook X Pro.
The script can run from a checkout or as a standalone downloaded file.

Options:
  --ref REF                 Git branch or tag to install (default: main)
  --yes                     do not ask pacman/makepkg/AUR confirmation
  --skip-hardware-check    allow the build on a non-matching host
  -h, --help               show this help

Environment:
  GC2607_REF               same as --ref
  GC2607_REPO_URL          override the source repository URL

The script does not reboot automatically. A reboot is recommended after the
DKMS modules have been installed.
EOF
}

cleanup() {
    if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
        rm -rf -- "$TEMP_ROOT"
    fi
}
trap cleanup EXIT

migrate_legacy_user_unit() {
    local user_config user_unit backup_unit

    user_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    user_unit="$user_config/systemd/user/gc2607-camera.service"

    [[ -f "$user_unit" ]] || return 0

    # A manually installed checkout-level unit takes precedence over the
    # packaged /usr/lib/systemd/user unit. Keep it only when it already points
    # at the stable packaged script; otherwise stop it and preserve a backup.
    if grep -Fq '/usr/lib/gc2607-camera/scripts/virtual-camera.sh' "$user_unit"; then
        return 0
    fi

    log "Migrating the legacy checkout-level user service"
    systemctl --user disable --now gc2607-camera.service 2>/dev/null || true
    backup_unit="${user_unit}.legacy.$(date +%Y%m%d-%H%M%S)"
    mv -- "$user_unit" "$backup_unit"
    systemctl --user daemon-reload
    printf '    preserved old unit as %s\n' "$backup_unit"
}

while (($#)); do
    case "$1" in
        --ref)
            (($# >= 2)) || die "--ref requires a branch or tag"
            REF="$2"
            shift 2
            ;;
        --yes|--noconfirm)
            AUTO_CONFIRM=1
            shift
            ;;
        --skip-hardware-check)
            SKIP_HARDWARE_CHECK=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1 (use --help)"
            ;;
    esac
done

[[ "${EUID}" -ne 0 ]] || die "run as a normal user; the script invokes sudo when needed"

for command in sudo pacman makepkg uname; do
    command -v "$command" >/dev/null 2>&1 || die "required command not found: $command"
done

if [[ "$SKIP_HARDWARE_CHECK" -eq 0 ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "$SCRIPT_DIR/scripts/check-gc2607-hardware.sh" ]]; then
        "$SCRIPT_DIR/scripts/check-gc2607-hardware.sh" || die "unsupported hardware; use --skip-hardware-check only for packaging tests"
    else
        vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
        product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
        [[ "${vendor,,}" == *huawei* && "${product^^}" == "VGHH-XX" ]] ||
            die "unsupported hardware: ${vendor:-unknown} ${product:-unknown}"
    fi
else
    warn "hardware check disabled"
fi

sudo -v
migrate_legacy_user_unit

PACMAN_FLAGS=(--needed)
# VCS pkgver() functions otherwise rewrite the local PKGBUILD after each
# install, leaving a checkout dirty and making the next `git pull` fail.
# Package versions are updated in the repository when releases are pushed.
MAKEPKG_FLAGS=(-C -s -i --holdver)
if [[ "$AUTO_CONFIRM" -eq 1 ]]; then
    PACMAN_FLAGS+=(--noconfirm)
    MAKEPKG_FLAGS+=(--noconfirm)
fi

log "Installing Arch/Omarchy build and runtime dependencies"
sudo pacman -S "${PACMAN_FLAGS[@]}" \
    base-devel git cmake ninja dkms v4l-utils \
    gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad \
    v4l2-relayd v4l2loopback-dkms

KERNEL="$(uname -r)"
[[ -e "/usr/lib/modules/${KERNEL}/build/Makefile" ]] ||
    die "matching kernel headers are missing: /usr/lib/modules/${KERNEL}/build"

find_aur_helper() {
    local helper
    for helper in paru yay; do
        if command -v "$helper" >/dev/null 2>&1; then
            command -v "$helper"
            return 0
        fi
    done
    return 1
}

bootstrap_yay() {
    local yay_root
    yay_root="$(mktemp -d -t gc2607-yay.XXXXXX)"
    git clone --depth 1 https://aur.archlinux.org/yay.git "$yay_root/yay"
    (
        cd "$yay_root/yay"
        makepkg "${MAKEPKG_FLAGS[@]}"
    )
    rm -rf -- "$yay_root"
}

AUR_HELPER="$(find_aur_helper || true)"
if [[ -z "$AUR_HELPER" ]]; then
    log "No yay/paru found; bootstrapping yay from the public AUR repository"
    command -v git >/dev/null 2>&1 || die "git is required to bootstrap yay"
    bootstrap_yay
    AUR_HELPER="$(find_aur_helper || true)"
fi
[[ -n "$AUR_HELPER" ]] || die "could not install or locate yay/paru"

log "Installing external Intel IPU6 userspace dependencies"
"$AUR_HELPER" -S "${PACMAN_FLAGS[@]}" \
    intel-ipu6-camera-bin icamerasrc-git intel-ipu6-dkms-git

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SCRIPT_DIR/packaging/aur" && -f "$SCRIPT_DIR/README.md" ]]; then
    SOURCE_ROOT="$SCRIPT_DIR"
else
    TEMP_ROOT="$(mktemp -d -t gc2607-camera.XXXXXX)"
    log "Downloading gc2607-camera-linux (${REF})"
    git clone --depth 1 --branch "$REF" --single-branch "$REPO_URL" \
        "$TEMP_ROOT/gc2607-camera-linux"
    SOURCE_ROOT="$TEMP_ROOT/gc2607-camera-linux"
fi

PACKAGING_ROOT="$SOURCE_ROOT/packaging/aur"
[[ -d "$PACKAGING_ROOT" ]] || die "packaging/aur not found in $SOURCE_ROOT"

build_package() {
    local directory="$1"
    [[ -f "$PACKAGING_ROOT/$directory/PKGBUILD" ]] ||
        die "missing PKGBUILD: $PACKAGING_ROOT/$directory"
    log "Building and installing $directory"
    (
        cd "$PACKAGING_ROOT/$directory"
        makepkg "${MAKEPKG_FLAGS[@]}"
    )
}

# Keep this order explicit: the HAL needs Intel userspace libraries at build
# time, and the virtual-camera package depends on all earlier local packages.
build_package gc2607-dkms
build_package gc2607-ipu-bridge-dkms
build_package gc2607-ipu6-camera-hal
build_package gc2607-virtual-camera
build_package gc2607-camera-git

log "Refreshing module metadata and the current user service"
sudo depmod -a "$KERNEL"
sudo udevadm control --reload-rules
sudo udevadm settle || true
systemctl --user daemon-reload
systemctl --user enable gc2607-camera.service 2>/dev/null || true

printf '\nInstallation completed.\n'
printf '  Source ref: %s\n' "$REF"
printf '  Kernel:     %s\n' "$KERNEL"
printf '  Next step:  reboot, then select "GC2607 Virtual Camera" in the application.\n'
printf '  Status:     systemctl --user status gc2607-camera.service\n'
printf '  Logs:       journalctl --user -u gc2607-camera.service -f\n'
