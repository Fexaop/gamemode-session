# Game Mode — niri + tty2 Steam Big Picture HDR

A two-seat Linux game-mode setup: keep the normal niri desktop on one VT, and
run a dedicated Steam Big Picture session with gamescope HDR on another VT.
The NVIDIA GPU renders; the AMD iGPU scans out the laptop panel.

## TLDR

- **tty4** stays the normal niri desktop (Discord, browser, EasyEffects).
- **tty2** runs gamescope + Steam Big Picture at 1920×1080 @ 60 Hz, 10-bit
  BT.2020 HDR, with Steam and games rendered on NVIDIA.
- `game-mode game` starts or focuses tty2. `game-mode desktop` returns to niri
  and releases the NVIDIA clock locks **without stopping the session**.
  `game-mode quit` stops the session.
- Bluetooth audio survives VT switches. All codecs, including HFP/mSBC, remain
  available; profile/codec autoswitching is disabled.
- Brightness is manual only: `−` / `+` buttons in the GUI, 5% per press.
- Power profiles change the **NVIDIA GPU only**. CPU governor/EPP, ASUS
  platform profile, power-profiles-daemon, and AMD DPM are never modified.
- No background daemon and no GUI polling while tty2 is foreground.

## What it installs

| Area | Files |
|---|---|
| User commands | `game-mode`, `game-mode-gui`, `bloodborne-gamescope`, `game-exec`, `game-terminal` in `~/.local/bin` |
| Audio | WirePlumber Bluetooth fixes and PipeWire 192 kHz configs |
| System | `/usr/local/bin` helpers, systemd units, `game.slice`, polkit rule, GDM session entry |
| Optional | niri keybind snippet, Steam **Game Terminal** shortcut helper, bbport settings example |

`getty@tty2.service` and `autovt@tty2.service` are masked so tty2 belongs to
gamescope.

## Requirements

- Arch Linux (or a close derivative) with systemd.
- niri on one VT; this repo assumes **tty4** as the desktop fallback and
  **tty2** for games.
- GDM or another display manager that reads `wayland-sessions`.
- Hybrid graphics: AMD iGPU for scanout + NVIDIA proprietary driver for
  rendering. The included launcher assumes the panel is on `eDP-1`, the AMD
  GPU is at PCI `04:00.0`, and the backlight is `amdgpu_bl1`.
- gamescope with HDR support, Steam, PipeWire, WirePlumber, Python 3,
  GTK4/libadwaita, and kitty.
- `nvidia-smi` from the NVIDIA proprietary driver.
- Optional: `python-vdf` for the Steam shortcut helper.

This repo was written for one specific ASUS laptop. Check the hard-coded device
paths (`eDP-1`, `pci-0000:04:00.0-card`, `amdgpu_bl1`, `1920x1080`) before
installing on different hardware.

## Install

```bash
git clone git@github.com:Fexaop/gamemode-session.git
cd gamemode-session
./install.sh
```

The top-level installer:

1. Copies the user commands to `~/.local/bin`.
2. Backs up and installs the WirePlumber/PipeWire configs.
3. Writes the niri keybind snippet and (if missing) the bbport settings example.
4. Runs `system/install.sh` through `sudo` to install the system helpers, units,
   polkit rule, and GDM session entry.

It does **not** edit your niri config, add Steam shortcuts, or restart your
audio session. Do those steps below.

### After installing

1. **Reload the audio user services** (or simply log out and back in):

   ```bash
   systemctl --user restart pipewire wireplumber
   ```

   Restarting WirePlumber can leave a Bluetooth headset in HFP until it is
   disconnected and reconnected. A full re-login is gentler.

2. **Add the niri keybind.** Paste the line from
   `config/niri/game-mode-keybind.kdl` inside the `binds { ... }` block of
   `~/.config/niri/config.kdl`:

   ```kdl
   Mod+Shift+G { spawn "sh" "-c" "exec \"$HOME/.local/bin/game-mode-gui\""; }
   ```

3. **Add the Steam terminal shortcut.** Close Steam, then:

   ```bash
   python3 tools/add-steam-shortcut.py
   ```

   On Arch, install `python-vdf` first if needed:

   ```bash
   sudo pacman -S python-vdf
   ```

4. **Configure Bloodborne paths** if they differ from the defaults:

   ```bash
   mkdir -p ~/.config/bbport-launcher
   cp config/bbport/settings.example.json ~/.config/bbport-launcher/settings.json
   $EDITOR ~/.config/bbport-launcher/settings.json
   ```

   Set `game_dir` to your `CUSA03173` directory. The wrapper also accepts
   `BLOODBORNE_DIR` for the bbport package directory.

## Everyday use

```bash
game-mode game          # start/focus tty2, or switch to it if already running
game-mode desktop       # return to niri, keep gamescope/Steam alive
game-mode quit          # stop the session and release NVIDIA
game-mode status        # human-readable state
game-mode status --json # machine-readable state

game-mode-gui           # GTK4 GUI (niri: Mod+Shift+G)
```

In the GUI:

- **Balanced** — NVIDIA auto clocks, default power limit.
- **Boost** — NVIDIA maximum graphics/memory clocks, default power limit.
- **Burn PC** — maximum clocks, persistence on, attempt maximum power limit.
  It asks for confirmation first.
- Brightness `−` / `+` — 5% per press, with a percentage label. No slider and
  no automatic dimming.

CLI equivalents:

```bash
game-mode power balanced|boost|burn|status
game-mode brightness up|down|status
game-mode verify-hdr
```

`Burn PC` cannot raise the wattage on vBIOSes that reject `nvidia-smi -pl`.
It still locks the maximum clocks and enables persistence.

## Running commands inside tty2

`game-exec` runs a command in the existing tty2 gamescope session from niri:

```bash
game-exec steam -gamepadui
game-exec bloodborne-gamescope --play
game-exec kitty
```

It supplies the gamescope Wayland socket, gamescope's Xwayland `DISPLAY`, the
NVIDIA Vulkan ICD, and the HDR environment. It exits with an error instead of
switching VTs when tty2 is not running.

`game-terminal` opens a kitty shell inside tty2. kitty is used because
gamescope does not expose `wl_subcompositor`, which makes `foot` fail.

To share one shell between tty2 and niri:

```bash
# Inside the tty2 Game Terminal
tmux new -s game

# From niri
tmux attach -t game
```

Commands run in the attached pane keep the tty2 environment, so games still
launch into gamescope.

## Bloodborne on tty2

1. **Start tty2 if it is not running.** From niri:

   ```bash
   game-mode game
   ```

2. **On tty2**, open the **Game Terminal** shortcut in Steam Big Picture.

3. **In that terminal**, launch Bloodborne:

   ```bash
   "$HOME/.local/bin/bloodborne-gamescope" --play
   ```

   Without `--play`, the bbport launcher opens instead:

   ```bash
   "$HOME/.local/bin/bloodborne-gamescope"
   ```

4. The saved settings are fullscreen, HDR on, 60 FPS, FIFO present mode.
   HDR engages when the game presents HDR content.

5. **Leave the game but keep tty2 running:**

   ```bash
   game-mode desktop
   ```

   **Stop the session and release NVIDIA:**

   ```bash
   game-mode quit
   ```

### Alternative from niri

If tty2 is already running or paused:

```bash
game-exec bloodborne-gamescope --play
game-mode game
```

If **Game Terminal** is not in Big Picture yet, switch to niri with
`Ctrl+Alt+F4`, run the two commands above, then use `game-mode game`.

### Bloodborne paths

The wrapper defaults to:

```text
~/Downloads/Bloodborne-bbport-0.7-linux-x86_64/Bloodborne.sh
```

Override the package directory with `BLOODBORNE_DIR`. The bbport settings file
controls the game data directory (`game_dir`), HDR, fullscreen, and FPS limit.

## Cheat Engine inside tty2 HDR

Cheat Engine must be installed in the **same Proton prefix as the game**.
Cheat Engine is an SDR Win32 application: it runs inside the HDR session, but
it does not make the panel HDR by itself. HDR engages when the game presents HDR
content.

Two common mistakes in the original command:

- `STEAM_COMPAT_CLIENT_INSTALL_PATH` was empty.
- `STEAM_COMPAT_DATA_PATH` pointed at `2156822488`, while the exe was inside
  the `2974274959` prefix. These must match.

### From a tty2 Game Terminal

1. Start tty2 with `game-mode game` if needed.
2. Open **Game Terminal** in Steam Big Picture.
3. Run:

```bash
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/2974274959/"

"$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton" run \
  "$HOME/.local/share/Steam/steamapps/compatdata/2974274959/pfx/drive_c/Program Files/Cheat Engine/cheatengine-x86_64.exe"
```

If your game uses `2156822488`, use `2156822488` for both the compatdata path
and the Cheat Engine install path.

### From niri

This enters the existing tty2 gamescope session without opening a terminal
there first:

```bash
game-exec env \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
  STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/2974274959/" \
  "$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton" run \
  "$HOME/.local/share/Steam/steamapps/compatdata/2974274959/pfx/drive_c/Program Files/Cheat Engine/cheatengine-x86_64.exe"
```

`game-exec` provides the tty2 Wayland socket, Xwayland `DISPLAY`, NVIDIA ICD,
`DXVK_HDR=1`, `PROTON_ENABLE_HDR=1`, `ENABLE_GAMESCOPE_WSI=1`, and
`STEAM_GAMESCOPE_HDR_SUPPORTED=1`.

See [`docs/cheat-engine-gamescope-hdr.md`](docs/cheat-engine-gamescope-hdr.md)
for the standalone version.

## HDR, audio, and Bluetooth details

- gamescope runs with `--hdr-enabled`, `--hdr-sdr-content-nits 400`, and
  content-driven HDR. SDR content stays SDR; HDR turns on only for HDR content.
- The panel is driven at 1920×1080 @ 60 Hz, 10-bit BT.2020.
- Bluetooth config keeps every A2DP and HFP codec, including mSBC. It disables
  autoswitching to the headset profile, disables WirePlumber seat monitoring so
  the headset stays connected across VT switches, and disables profile
  persistence so a reconnect does not restore HFP.
- The default microphone is the laptop microphone, which prevents Steam from
  opening the headset mic and forcing HFP.
- PipeWire configs enable 192 kHz on the analog/aux output. The ALC294 codec
  supports 44.1, 48, 96, and 192 kHz.
- Restarting WirePlumber can temporarily leave a headset in HFP until it is
  disconnected and reconnected.

## Troubleshooting

```bash
game-mode status
game-mode verify-hdr
systemctl status gamescope-tty2.service
journalctl -u gamescope-tty2.service -b --no-pager
```

- **`game-exec` says tty2 is not running** — start it with `game-mode game`.
  It intentionally does not switch VTs for you.
- **`foot` fails with “no sub compositor”** — use `game-terminal` (kitty) or
  `game-exec kitty`.
- **`game-mode quit` returns 1** — this has been observed while the session
  still stops correctly. Check `game-mode status`.
- **Power limit does not change** — some vBIOSes reject `nvidia-smi -pl`.
  Burn PC still locks clocks and persistence.
- **No HDR** — run `game-mode verify-hdr`; confirm the game is presenting HDR
  and the panel is on `eDP-1`.
- **Different GPU/panel names** — update `gamescope-tty2`, `game-mode`, and the
  backlight path in `bin/game-mode` before installing.

## Repo layout

```text
bin/                    user commands
config/bbport/          bbport settings example
config/niri/            niri keybind snippet
config/pipewire/        192 kHz PipeWire configs
config/wireplumber/     Bluetooth codec/VT/profile fixes
docs/                   standalone guides
system/etc/             systemd units and polkit rule
system/usr/             privileged helpers and GDM session entry
system/install.sh       system installer (run through sudo)
tools/                  Steam shortcut helper
game-mode.md            full change log and current-state notes
install.sh              top-level installer
```

The full change log, file inventory, and current-state notes are in
[`game-mode.md`](game-mode.md).
