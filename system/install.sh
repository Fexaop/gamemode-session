#!/bin/bash
# Install the privileged Game Mode pieces.
#
# Run through the top-level installer, or directly:
#   sudo GAME_USER="$USER" ./system/install.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo GAME_USER=\"$USER\" $0" >&2
    exit 1
fi

GAME_USER="${GAME_USER:-${SUDO_USER:-}}"
if [ -z "$GAME_USER" ] || [ "$GAME_USER" = "root" ]; then
    echo "Set GAME_USER to the desktop user: sudo GAME_USER=yourname $0" >&2
    exit 1
fi

GAME_HOME="$(getent passwd "$GAME_USER" | cut -d: -f6)"
GAME_UID="$(id -u "$GAME_USER")"
if [ -z "$GAME_HOME" ] || [ -z "$GAME_UID" ]; then
    echo "Could not resolve user $GAME_USER" >&2
    exit 1
fi

src="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Replace the development user/home/UID with the installing user.  The source
# tree uses /home/gunit, user "gunit", and UID 1000 as placeholders.
render() {
    sed \
        -e "s|/home/gunit|$GAME_HOME|g" \
        -e "s|/run/user/1000|/run/user/$GAME_UID|g" \
        -e "s|gunit|$GAME_USER|g" \
        "$1"
}

install_script() {
    render "$1" > "$tmp/file"
    install -Dm755 "$tmp/file" "$2"
}

install_unit() {
    render "$1" > "$tmp/file"
    install -Dm644 "$tmp/file" "$2"
}

install_script "$src/usr/local/bin/gamescope-tty2" /usr/local/bin/gamescope-tty2
install_script "$src/usr/local/bin/niri-gamemode-session" /usr/local/bin/niri-gamemode-session
install_script "$src/usr/local/bin/game-mode-perf" /usr/local/bin/game-mode-perf
install_script "$src/usr/local/bin/game-mode-return" /usr/local/bin/game-mode-return
install_script "$src/usr/local/bin/game-mode-stop" /usr/local/bin/game-mode-stop
install_script "$src/usr/local/bin/game-mode-cleanup" /usr/local/bin/game-mode-cleanup
install_script "$src/usr/local/bin/game-mode-gamescope-tune" /usr/local/bin/game-mode-gamescope-tune

install_unit "$src/etc/systemd/system/gamescope-tty2.service" /etc/systemd/system/gamescope-tty2.service
install_unit "$src/etc/systemd/system/game-mode-perf.service" /etc/systemd/system/game-mode-perf.service
install_unit "$src/etc/systemd/system/game-mode-return.service" /etc/systemd/system/game-mode-return.service
install_unit "$src/etc/systemd/system/game-mode-stop.service" /etc/systemd/system/game-mode-stop.service
install_unit "$src/etc/systemd/system/game-mode-focus@.service" /etc/systemd/system/game-mode-focus@.service
install_unit "$src/etc/systemd/system/game.slice" /etc/systemd/system/game.slice
install_unit "$src/etc/polkit-1/rules.d/49-game-mode.rules" /etc/polkit-1/rules.d/49-game-mode.rules
install_unit "$src/usr/share/wayland-sessions/niri-gamemode.desktop" /usr/share/wayland-sessions/niri-gamemode.desktop

systemctl daemon-reload

# tty2 belongs to gamescope, not a getty.
systemctl stop getty@tty2.service >/dev/null 2>&1 || true
systemctl stop autovt@tty2.service >/dev/null 2>&1 || true
systemctl mask getty@tty2.service >/dev/null 2>&1 || true
systemctl mask autovt@tty2.service >/dev/null 2>&1 || true

for unit in gamescope-tty2.service game-mode-perf.service game-mode-return.service game-mode-stop.service; do
    systemctl reset-failed "$unit" >/dev/null 2>&1 || true
done

echo
echo "Game Mode system pieces installed."
echo "GDM entry: Niri + Steam Big Picture (HDR)"
echo "Add the niri keybind from config/niri/game-mode-keybind.kdl manually."
