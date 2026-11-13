#!/usr/bin/env bash
# Installer for winforensics. Fully automated on Arch-based distros (incl. Omarchy);
# on other distros it checks requirements and tells you what is missing.
#   ./install.sh          interactive
#   ./install.sh --yes    accept all defaults (random password, 8G RAM, 4 cores, 64G disk)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/winforensics"
APP_DIR="$HOME/.local/share/applications"
ASSUME_YES=0
NEED_RELOGIN=0

case "${1:-}" in
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}"; exit 0 ;;
    "") ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
esac

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
fail() { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }
ask() {   # ask "prompt" "default"
    local reply
    if [ "$ASSUME_YES" -eq 1 ]; then printf '%s' "$2"; return; fi
    read -r -p "$1${2:+ [$2]}: " reply
    printf '%s' "${reply:-$2}"
}

[ "$(id -u)" -ne 0 ] || fail "run as your normal user, not root (sudo is used where needed)"

# 1. Hardware --------------------------------------------------------------
info "Checking virtualization"
[ -e /dev/kvm ] || fail "/dev/kvm not found. Enable VT-x / AMD-V in your BIOS/UEFI."
{ [ -r /dev/kvm ] && [ -w /dev/kvm ]; } || warn "/dev/kvm is not accessible to you; you may need to join the 'kvm' group."

# 2. Packages --------------------------------------------------------------
if command -v pacman >/dev/null 2>&1; then
    info "Installing packages with pacman"
    pac=(sudo pacman -S --needed)
    [ "$ASSUME_YES" -eq 1 ] && pac+=(--noconfirm)
    "${pac[@]}" docker docker-compose freerdp libnotify
else
    warn "Not an Arch-based system. Install these yourself, then run this script again:"
    warn "  Docker + the compose plugin, FreeRDP 3 (provides xfreerdp3), libnotify (optional)"
fi
command -v docker >/dev/null 2>&1 || fail "docker not found"
docker compose version >/dev/null 2>&1 || fail "the 'docker compose' plugin was not found"
if ! command -v xfreerdp3 >/dev/null 2>&1 && ! command -v sdl-freerdp3 >/dev/null 2>&1; then
    fail "FreeRDP 3 not found (need xfreerdp3 or sdl-freerdp3; FreeRDP 2 is too old)"
fi

info "Enabling Docker"
sudo systemctl enable --now docker 2>/dev/null || warn "could not enable docker via systemd; start it yourself"
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    sudo usermod -aG docker "$USER"
    NEED_RELOGIN=1
fi

# 3. Config ----------------------------------------------------------------
info "Writing configuration to $CONF_DIR"
mkdir -p "$CONF_DIR" "$BIN_DIR" "$APP_DIR"
cp "$REPO_DIR/config/compose.yaml" "$CONF_DIR/compose.yaml"

if [ -f "$CONF_DIR/config.env" ]; then
    warn "config.env already exists, keeping it"
    SHARE_DIR="$(sed -n 's/^WF_SHARE=//p' "$CONF_DIR/config.env" | head -n1)"
    SHARE_DIR="${SHARE_DIR:-$HOME/WinForensics-Share}"
else
    WF_USERNAME="$(ask 'Windows username' 'forensics')"
    GEN_PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true)"
    if [ "$ASSUME_YES" -eq 1 ]; then
        WF_PASSWORD="$GEN_PASS"
    else
        read -r -s -p 'Windows password (empty = generate one): ' WF_PASSWORD; echo
        WF_PASSWORD="${WF_PASSWORD:-$GEN_PASS}"
    fi
    case "$WF_PASSWORD" in
        *[!A-Za-z0-9_.@%+=-]*) fail "password may only contain letters, digits and _ . @ % + = -" ;;
    esac
    case "$WF_USERNAME" in
        ""|*[!A-Za-z0-9_-]*) fail "username may only contain letters, digits, _ and -" ;;
    esac
    WF_RAM="$(ask 'RAM for the VM' '8G')"
    WF_CPUS="$(ask 'CPU cores for the VM' '4')"
    WF_DISK="$(ask 'Disk size (grows as needed)' '64G')"
    SHARE_DIR="$(ask 'Folder shared with Windows' "$HOME/WinForensics-Share")"
    ISO_PATH="$(ask 'Path to your Windows ISO (empty = container downloads one)' '')"

    umask 077
    cat > "$CONF_DIR/config.env" <<ENV
WF_USERNAME=$WF_USERNAME
WF_PASSWORD=$WF_PASSWORD
WF_VERSION=11
WF_RAM=$WF_RAM
WF_CPUS=$WF_CPUS
WF_DISK=$WF_DISK
WF_SHARE=$SHARE_DIR
WF_STOP_ON_EXIT=true
WF_BOOT_DELAY=20
WF_RDP_FLAGS=-gfx /gdi:sw
ENV
    chmod 600 "$CONF_DIR/config.env"
    umask 022

    if [ -n "$ISO_PATH" ]; then
        [ -f "$ISO_PATH" ] || fail "ISO not found: $ISO_PATH"
        case "$ISO_PATH" in *\"*|*:*) fail "ISO path must not contain quotes or colons" ;; esac
        cat > "$CONF_DIR/compose.iso.yaml" <<YAML
services:
  windows:
    volumes:
      - "$ISO_PATH:/boot.iso"
YAML
    fi
    if [ "$ASSUME_YES" -eq 1 ]; then
        info "Generated Windows password is stored in $CONF_DIR/config.env"
    fi
fi

mkdir -p "$SHARE_DIR"

# 4. Launcher and menu entry -----------------------------------------------
info "Installing launcher"
install -m 755 "$REPO_DIR/bin/winforensics" "$BIN_DIR/winforensics"
cat > "$APP_DIR/winforensics.desktop" <<DESKTOP
[Desktop Entry]
Name=Windows Forensics
Comment=Windows VM over RDP; stops when you close the window
Exec=$BIN_DIR/winforensics
Type=Application
Terminal=false
Categories=Utility;
DESKTOP

case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "$BIN_DIR is not in your PATH; add it to your shell profile." ;; esac

echo
info "Done. Next steps:"
[ "$NEED_RELOGIN" -eq 1 ] && echo "  0. Log out and back in (you were added to the docker group)."
echo "  1. winforensics doctor     # verify the setup"
echo "  2. winforensics            # first run installs Windows (20-40 min), watch http://127.0.0.1:8006"
echo "  3. Inside Windows, install the .NET Desktop Runtime and your tools (see README)"
