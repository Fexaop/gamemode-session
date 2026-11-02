#!/bin/bash
# Install the user-level Game Mode pieces and then the privileged system
# pieces.  Run as your desktop user, not as root:
#
#   ./install.sh
#
# Existing user commands and audio configs are backed up with a timestamp
# suffix before they are replaced.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
game_user="${GAME_USER:-${SUDO_USER:-${USER:-}}}"

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your desktop user, not root. The script calls sudo itself." >&2
    exit 1
fi

if [ -z "$game_user" ] || ! id "$game_user" >/dev/null 2>&1; then
    echo "Could not determine the desktop user. Set GAME_USER=yourname." >&2
    exit 1
fi

game_home="$(getent passwd "$game_user" | cut -d: -f6)"
if [ -z "$game_home" ] || [ ! -d "$game_home" ]; then
    echo "Could not resolve the home directory for $game_user." >&2
    exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"

backup() {
    if [ -e "$1" ]; then
        cp -a "$1" "$1.bak.$stamp"
        echo "  backed up $(basename "$1") -> $(basename "$1").bak.$stamp"
    fi
}

install_user_file() {
    local src="$1" dest="$2" mode="$3"

    install -d "$(dirname "$dest")"
    backup "$dest"
    install -m"$mode" "$src" "$dest"
}

for file in \
    bin/game-mode \
    bin/game-mode-gui \
    bin/bloodborne-gamescope \
    bin/game-exec \
    bin/game-terminal \
    config/wireplumber/51-bluetooth-codec.conf \
    config/wireplumber/53-bluetooth-keep-on-vt-switch.conf \
    config/wireplumber/54-bluetooth-no-profile-persistence.conf \
    config/pipewire/force-192k.conf \
    config/pipewire/99-custom-rates.conf \
    config/bbport/settings.example.json \
    system/install.sh; do
    if [ ! -f "$repo_dir/$file" ]; then
        echo "Missing required file: $repo_dir/$file" >&2
        exit 1
    fi
done

echo "Installing user commands into $game_home/.local/bin"
install_user_file "$repo_dir/bin/game-mode" \
    "$game_home/.local/bin/game-mode" 755
install_user_file "$repo_dir/bin/game-mode-gui" \
    "$game_home/.local/bin/game-mode-gui" 755
install_user_file "$repo_dir/bin/bloodborne-gamescope" \
    "$game_home/.local/bin/bloodborne-gamescope" 755
install_user_file "$repo_dir/bin/game-exec" \
    "$game_home/.local/bin/game-exec" 755
install_user_file "$repo_dir/bin/game-terminal" \
    "$game_home/.local/bin/game-terminal" 755

echo "Installing audio configuration into $game_home/.config"
install_user_file "$repo_dir/config/wireplumber/51-bluetooth-codec.conf" \
    "$game_home/.config/wireplumber/wireplumber.conf.d/51-bluetooth-codec.conf" 644
install_user_file "$repo_dir/config/wireplumber/53-bluetooth-keep-on-vt-switch.conf" \
    "$game_home/.config/wireplumber/wireplumber.conf.d/53-bluetooth-keep-on-vt-switch.conf" 644
install_user_file "$repo_dir/config/wireplumber/54-bluetooth-no-profile-persistence.conf" \
    "$game_home/.config/wireplumber/wireplumber.conf.d/54-bluetooth-no-profile-persistence.conf" 644
install_user_file "$repo_dir/config/pipewire/force-192k.conf" \
    "$game_home/.config/pipewire/pipewire.conf.d/force-192k.conf" 644
install_user_file "$repo_dir/config/pipewire/99-custom-rates.conf" \
    "$game_home/.config/pipewire/pipewire.conf.d/99-custom-rates.conf" 644

# Keep existing bbport settings: they contain the user's game directory and
# online preferences.  Only seed the example on a fresh install.
bbport_settings="$game_home/.config/bbport-launcher/settings.json"
if [ ! -e "$bbport_settings" ]; then
    install -d "$(dirname "$bbport_settings")"
    install -m644 "$repo_dir/config/bbport/settings.example.json" "$bbport_settings"
    echo "Seeded $bbport_settings; edit game_dir before playing."
else
    echo "Keeping existing $bbport_settings"
fi

# Provide a ready-to-paste keybind for the user's niri config.  It is not
# included automatically because niri only reads config.kdl.
keybind_file="$game_home/.config/niri/game-mode-keybind.kdl"
install -d "$(dirname "$keybind_file")"
backup "$keybind_file"
cat > "$keybind_file" <<EOF
// Game Mode GUI: NVIDIA profiles, brightness, start/return/quit.
// Paste this inside the binds { ... } block of ~/.config/niri/config.kdl.
Mod+Shift+G { spawn "sh" "-c" "exec \\"$game_home/.local/bin/game-mode-gui\\""; }
EOF
echo "Wrote niri keybind snippet: $keybind_file"

echo
echo "Optional dependencies:"
missing=0
for cmd in niri gamescope steam nvidia-smi wireplumber kitty; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "  missing: $cmd"
        missing=1
    fi
done
if [ "$missing" -eq 0 ]; then
    echo "  all detected"
fi

echo
echo "Installing privileged system pieces (sudo required)"
if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo not found. Run this as root once:" >&2
    echo "  GAME_USER=$game_user $repo_dir/system/install.sh" >&2
    exit 1
fi
sudo GAME_USER="$game_user" "$repo_dir/system/install.sh"

cat <<EOF

Game Mode installed.

Next steps:
  1. Log out and back in, or restart PipeWire/WirePlumber.
  2. Paste the keybind from:
       $keybind_file
     into the binds block of ~/.config/niri/config.kdl.
  3. Close Steam, then add the terminal shortcut:
       python3 "$repo_dir/tools/add-steam-shortcut.py"
  4. Set the Bloodborne directory in:
       $bbport_settings
     or export BLOODBORNE_DIR to the bbport package directory.
  5. Start the session with:
       game-mode game
EOF
