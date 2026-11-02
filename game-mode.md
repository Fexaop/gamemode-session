# Game Mode / tty2 HDR — Arch changes

Last updated: 2026-11-03  
Host: `gunit`  
Scope: local user-level and system-level changes for the niri + tty2 gamescope setup.

This document is a record of the current setup, not an installer. No VT switch was performed while writing it.

---

## 1. What the setup does

- **tty4**: normal niri desktop, Discord, EasyEffects, browsers, etc.
- **tty2**: strict Steam Big Picture session in gamescope, using the NVIDIA RTX 3050 for rendering and the AMD Cezanne iGPU for scanout.
- **Display**: eDP-1, 1920×1080 @ 60 Hz, 10-bit BT.2020 HDR when HDR content is present.
- **HDR mode**: gamescope runs with `--hdr-enabled`; a one-shot helper enables content-driven HDR so SDR content is not forced into HDR.
- **Power**: the game session uses NVIDIA-only profiles. CPU governor/EPP, ASUS platform profile, power-profiles-daemon, and AMD DPM are not modified by the game-mode scripts.
- **Brightness**: manual only, 5% steps, via the GUI buttons. No automatic dimming and no slider.

---

## 2. Main commands

```bash
game-mode-gui                 # GTK4 GUI (also Super+Shift+G in niri)
game-mode game                # start/focus the tty2 game session
game-mode desktop             # return to niri, keep gamescope/Steam alive
game-mode pause               # alias for desktop
game-mode return              # alias for desktop
game-mode quit                # stop the session and release NVIDIA
game-mode stop                # alias for quit
game-mode toggle              # toggle game/desktop
game-mode status              # human-readable status
game-mode status --json       # machine-readable status
game-mode power balanced      # NVIDIA auto clocks/default power
game-mode power boost         # NVIDIA max clocks/default power
game-mode power burn          # NVIDIA max clocks/persistence/max power
game-mode power status
game-mode brightness up       # +5%
game-mode brightness down     # -5%
game-mode brightness status
game-mode verify-hdr          # HDR/connector/gamescope diagnostics
game-mode autostart           # used by the GDM game session
```

`game-mode game` switches to tty2. `game-mode desktop` switches back to the niri VT and releases the NVIDIA clock locks without stopping gamescope/Steam.

---

## 3. tty2 gamescope session

### Service

`/etc/systemd/system/gamescope-tty2.service`

- `User=gunit`
- `PAMName=login`
- `TTYPath=/dev/tty2`
- `Conflicts=getty@tty2.service autovt@tty2.service`
- `Slice=game.slice`
- `ExecStart=/usr/local/bin/gamescope-tty2`
- `ExecStopPost=/usr/local/bin/game-mode-cleanup`
- `KillMode=mixed`, `TimeoutStopSec=30`

`getty@tty2.service` and `autovt@tty2.service` are masked so tty2 belongs to gamescope.

### Launcher

`/usr/local/bin/gamescope-tty2` runs:

```text
gamescope
  --backend drm
  --generate-drm-mode fixed
  --xwayland-count 2
  --expose-wayland
  --default-touch-mode 4
  --hide-cursor-delay 3000
  --fade-out-duration 200
  --hdr-enabled
  --hdr-sdr-content-nits 400
  --prefer-vk-device 1002:1638
  -W 1920 -H 1080
  -O eDP-1
  -e
  -- <Steam launcher with NVIDIA/HDR environment>
```

- `WLR_DRM_DEVICES` points gamescope at the AMD iGPU card (`pci-0000:04:00.0-card`); the NVIDIA card has no display outputs.
- The Steam/child environment uses the NVIDIA Vulkan ICD, `DXVK_HDR=1`, `PROTON_ENABLE_HDR=1`, `ENABLE_GAMESCOPE_WSI=1`, and `STEAM_GAMESCOPE_HDR_SUPPORTED=1`.
- The HDR tuning helper runs as a child of the gamescope launcher inside its own PAM session. It is not an `ExecStartPost`, which previously raced and stole tty2 from gamescope.
- HDR tuning command: `gamescopectl hdr_content_driven 1`.

### Startup/stop behavior

- Start order is VT-first: switch to tty2, wait for it to become active, then start the service.
- The backend verifies the service stays running after a short settle period; on failure it stops the service, stops the power profile, returns to the niri VT, and reports the journal tail.
- `game-mode desktop` stops `game-mode-perf.service` and switches to the remembered niri VT. It does **not** stop gamescope/Steam.
- `game-mode quit` stops `gamescope-tty2.service`, stops the power profile, and returns to the niri VT.
- The niri VT is remembered in `/run/user/1000/game-mode.niri-vt`; fallback is tty4.

---

## 4. NVIDIA power profiles

Script: `/usr/local/bin/game-mode-perf`  
State: `/run/game-mode/`  
Selected profile: `~/.config/game-mode/power-profile`

| Profile | NVIDIA behavior |
|---|---|
| `balanced` | Reset graphics/memory clocks, persistence off, default power limit |
| `boost` | Lock graphics and memory to maximum clocks, default power limit |
| `burn` | Lock max clocks, enable persistence, attempt maximum power limit |

Important:

- These scripts touch **NVIDIA only**.
- CPU governor/EPP, ASUS platform profile, power-profiles-daemon, and AMD DPM are left alone.
- `nvidia-smi -pl` is not supported by this vBIOS. The default is 35 W, the reported maximum is 50 W, but changing the limit returns “Changing power management limit is not supported.”
- Burn still locks maximum clocks and persistence; it cannot raise the wattage.
- On quit, clocks/persistence/power limit are restored.

---

## 5. Brightness

Backend writes directly to:

```text
/sys/class/backlight/amdgpu_bl1/brightness
```

- Step: 5% per button press.
- Clamped to 1–100%.
- No automatic dimming.
- No slider; the GUI has `−` and `+` buttons and a percentage label.
- Tested: 100% → 95% → 100%.

---

## 6. GUI

`~/.local/bin/game-mode-gui` — GTK4/libadwaita front end.

- NVIDIA profile buttons: Balanced, Boost, Burn PC.
- Burn PC requires confirmation.
- Brightness buttons `−` / `+` in 5% steps, percentage label, no slider.
- Start / Return / Quit actions.
- Polling only while the window is visible and the niri VT is foreground; no background daemon and no polling while tty2 is foreground.

niri keybind:

```kdl
Mod+Shift+G { spawn "/home/gunit/.local/bin/game-mode-gui"; }
```

---

## 7. VT switching, pause, and Bluetooth behavior

- Returning to niri no longer tears down the tty2 session or reconnects Bluetooth audio.
- `game-mode desktop` releases NVIDIA clock locks and switches to niri; gamescope/Steam remain running for a fast resume.
- The Bluetooth monitor stays alive across VT switches because WirePlumber's logind seat monitoring is disabled.
- The session is stopped only with `game-mode quit`/`stop`.

Known quirk: `game-mode quit` has been observed to return exit code 1 while still stopping gamescope and the power profile correctly. Check `game-mode status` if in doubt.

---

## 8. Bluetooth and audio

### 8.1 Bluetooth codecs and profiles

File: `~/.config/wireplumber/wireplumber.conf.d/51-bluetooth-codec.conf`

- `bluetooth.autoswitch-to-headset-profile = false`
- `bluetooth.profile-preference = quality`
- All codecs kept available:

```text
ldac aac sbc_xq sbc msbc cvsd
```

- HFP/mSBC is still available and can be selected manually. No codec or profile was removed.
- The temporary `52-bluetooth-a2dp-only.conf` restriction was removed; it is not part of the current setup.
- `bluez5.enable-sbc-xq = true`
- `bluez5.enable-msbc = true`
- `bluez5.enable-hw-volume = true`

### 8.2 No profile switching on VT changes

File: `~/.config/wireplumber/wireplumber.conf.d/53-bluetooth-keep-on-vt-switch.conf`

```text
wireplumber.profiles = {
  main = {
    monitor.bluez.seat-monitoring = disabled
  }
}
```

This stops WirePlumber from deactivating the BlueZ monitor when tty2 takes the seat. Previously that unregistered the A2DP endpoints, disconnected the headset, and caused the reconnect/HFP/mSBC behavior.

### 8.3 No profile persistence

File: `~/.config/wireplumber/wireplumber.conf.d/54-bluetooth-no-profile-persistence.conf`

```text
wireplumber.settings = {
  bluetooth.use-persistent-storage = false
}
```

WirePlumber no longer restores an old HFP/mSBC profile. A headset connects with the normal A2DP-first order. HFP remains manually selectable.

### 8.4 Default microphone

The default source is the laptop microphone:

```text
alsa_input.pci-0000_04_00.6.analog-stereo
```

This prevents Steam/gamescope from opening the headset microphone and forcing HFP.

### 8.5 Current Bluetooth state

- ULT WEAR `88:92:CC:19:E9:42`
- A2DP / LDAC at 96 kHz
- All A2DP and HFP/mSBC profiles available
- No automatic profile/codec switch on VT changes

Note: restarting WirePlumber can leave a headset in HFP until it is disconnected/reconnected. Avoid unnecessary WirePlumber restarts.

---

## 9. 192 kHz audio

Files:

- `~/.config/pipewire/pipewire.conf.d/force-192k.conf`
- `~/.config/pipewire/pipewire.conf.d/99-custom-rates.conf`

`force-192k.conf`:

```text
context.properties = {
    default.clock.rate          = 192000
    default.clock.allowed-rates = [ 192000 ]
    default.clock.min-quantum   = 128
    default.clock.max-quantum   = 4096
}
```

The analog sink is currently:

```text
alsa_output.pci-0000_04_00.6.analog-stereo
s32le 2ch 192000Hz
```

- ALC294 supports 44100, 48000, 96000, and 192000 Hz.
- The aux/headphone output supports 192 kHz.
- Current active port is Speakers because no headphones are plugged in.
- This is upsampling for 44.1/48 kHz sources; it does not add detail. It is a 192 kHz output pipeline.

---

## 10. Bloodborne

Launcher: `~/.local/bin/bloodborne-gamescope`  
Settings: `~/.config/bbport-launcher/settings.json`

The wrapper:

- Requires the tty2 `gamescope-0` Wayland socket.
- Sets `SDL_VIDEODRIVER=wayland`.
- Sets `VK_DRIVER_FILES` / `VK_ICD_FILENAMES` to the NVIDIA ICD.
- Sets `__NV_PRIME_RENDER_OFFLOAD=1`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`.
- Sets `BB_DLSS=0`.
- Sets `ENABLE_GAMESCOPE_WSI=1`, `DXVK_HDR=1`, `PROTON_ENABLE_HDR=1`, `STEAM_GAMESCOPE_HDR_SUPPORTED=1`.

Saved Bloodborne settings include:

- Fullscreen: on
- HDR: on
- FPS limit: 60
- Present mode: Fifo
- MangoHud: off

Launch:

```bash
# Inside the tty2 terminal
bloodborne-gamescope --play

# From niri, into the existing tty2 gamescope
game-exec bloodborne-gamescope --play
```

Without `--play`, the bbport launcher opens instead.

---

## 11. Terminal helpers and Steam shortcut

### `game-exec`

`~/.local/bin/game-exec` runs any command inside the existing tty2 gamescope session.

It supplies:

- `XDG_RUNTIME_DIR`
- `WAYLAND_DISPLAY=gamescope-0`
- gamescope's Xwayland `DISPLAY` (discovered from the Steam process)
- NVIDIA Vulkan ICD
- HDR environment variables

Examples:

```bash
game-exec kitty
game-exec bloodborne-gamescope --play
game-exec steam -gamepadui
```

If gamescope is not running, it exits with an error instead of switching VTs.

### `game-terminal`

`~/.local/bin/game-terminal` opens a kitty terminal inside the tty2 gamescope session.

- Run it from niri, or launch the **Game Terminal** shortcut in Steam Big Picture.
- Uses kitty because gamescope does not expose `wl_subcompositor`, which makes `foot` fail.
- The shell inherits the tty2 gamescope environment, so games launched from it appear in tty2.

A shared shell can be created with tmux:

```bash
# Inside the tty2 Game Terminal
tmux new -s game

# From niri
tmux attach -t game
```

Commands run in the attached tmux pane keep the gamescope environment.

### Steam shortcut

Added to `~/.local/share/Steam/userdata/1128085718/config/shortcuts.vdf`:

- Name: `Game Terminal`
- Target: `"/home/gunit/.local/bin/game-terminal"`
- Start directory: `/home/gunit`
- Steam overlay disabled for this shortcut
- Backup of `shortcuts.vdf` was made before editing

Steam must be restarted for the shortcut to appear.

---

## 12. Cheat Engine under tty2 gamescope HDR

Run it inside the existing tty2 gamescope session; do not start a second gamescope.

### Corrected environment

The original command had an empty `STEAM_COMPAT_CLIENT_INSTALL_PATH` and a mismatch between `STEAM_COMPAT_DATA_PATH` (`2156822488`) and the exe path (`2974274959/pfx`).

For the exe path shown, use:

```bash
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/2974274959/"
```

If the game uses `2156822488`, use `2156822488` for both the compatdata path and the Cheat Engine install path. Cheat Engine must be installed in the same prefix as the game.

### From a tty2 Game Terminal

```bash
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/2974274959/"

"$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton" run \
  "$HOME/.local/share/Steam/steamapps/compatdata/2974274959/pfx/drive_c/Program Files/Cheat Engine/cheatengine-x86_64.exe"
```

### From niri

```bash
game-exec env \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
  STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/2974274959/" \
  "$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton" run \
  "$HOME/.local/share/Steam/steamapps/compatdata/2974274959/pfx/drive_c/Program Files/Cheat Engine/cheatengine-x86_64.exe"
```

Cheat Engine is an SDR Win32 app; it runs inside the HDR session but does not itself make the panel HDR. HDR engages when the game presents HDR content.

A standalone copy of these instructions is at `~/cheat-engine-gamescope-hdr.md`.

---

## 13. Files changed

### User files

| Path | Purpose |
|---|---|
| `~/.local/bin/game-mode` | Backend: start/return/quit, power, brightness, status |
| `~/.local/bin/game-mode-gui` | GTK4 GUI |
| `~/.local/bin/bloodborne-gamescope` | Bloodborne tty2 wrapper |
| `~/.local/bin/game-exec` | Run commands inside tty2 gamescope |
| `~/.local/bin/game-terminal` | Terminal inside tty2 gamescope |
| `~/.local/share/game-mode/system/` | Privileged installer and system source files |
| `~/.config/niri/config.kdl` | `Mod+Shift+G` GUI keybind |
| `~/.config/game-mode/power-profile` | Saved NVIDIA profile |
| `~/.config/game-mode/gui.json` | GUI config |
| `~/.config/wireplumber/wireplumber.conf.d/51-bluetooth-codec.conf` | Codec whitelist, autoswitch off |
| `~/.config/wireplumber/wireplumber.conf.d/53-bluetooth-keep-on-vt-switch.conf` | Disable BlueZ seat monitoring |
| `~/.config/wireplumber/wireplumber.conf.d/54-bluetooth-no-profile-persistence.conf` | No HFP profile restore |
| `~/.config/pipewire/pipewire.conf.d/force-192k.conf` | 192 kHz graph |
| `~/.config/pipewire/pipewire.conf.d/99-custom-rates.conf` | Allowed-rate list |
| `~/.config/bbport-launcher/settings.json` | Bloodborne 1080p/HDR/60 settings |
| `~/.local/share/Steam/userdata/1128085718/config/shortcuts.vdf` | `Game Terminal` shortcut |

### System files

| Path | Purpose |
|---|---|
| `/usr/local/bin/gamescope-tty2` | tty2 gamescope/Steam launcher |
| `/usr/local/bin/game-mode-perf` | NVIDIA-only power profile |
| `/usr/local/bin/game-mode-return` | Return to niri, release clocks |
| `/usr/local/bin/game-mode-stop` | Stop session, release NVIDIA |
| `/usr/local/bin/game-mode-cleanup` | `ExecStopPost` cleanup |
| `/usr/local/bin/game-mode-gamescope-tune` | One-shot content-driven HDR |
| `/usr/local/bin/niri-gamemode-session` | GDM Game Mode session wrapper |
| `/etc/systemd/system/gamescope-tty2.service` | tty2 session unit |
| `/etc/systemd/system/game-mode-perf.service` | Power profile unit |
| `/etc/systemd/system/game-mode-return.service` | Return-to-desktop unit |
| `/etc/systemd/system/game-mode-stop.service` | Quit unit |
| `/etc/systemd/system/game-mode-focus@.service` | `chvt` helper |
| `/etc/systemd/system/game.slice` | Game session slice |
| `/etc/polkit-1/rules.d/49-game-mode.rules` | Passwordless control of game-mode units |
| `/usr/share/wayland-sessions/niri-gamemode.desktop` | GDM “Niri + Steam Big Picture (HDR)” entry |

Also:

- `getty@tty2.service` masked.
- `autovt@tty2.service` masked.
- No background daemon; only systemd oneshot units and the foreground sessions.

---

## 14. Install/update

The privileged source tree is:

```text
~/.local/share/game-mode/system/
```

To reinstall system pieces:

```bash
sudo ~/.local/share/game-mode/system/install.sh
```

The installer:

- Installs the `/usr/local/bin` helpers.
- Installs the systemd units and `game.slice`.
- Installs the polkit rule and GDM session file.
- Runs `systemctl daemon-reload`.
- Stops and masks `getty@tty2.service`.
- Resets failed game-mode units.

After editing a unit manually:

```bash
sudo systemctl daemon-reload
```

User-level scripts (`game-mode`, `game-mode-gui`, `bloodborne-gamescope`, `game-exec`, `game-terminal`) are edited directly.

---

## 15. Current state at time of writing

- Active VT: `tty4` (niri)
- `gamescope-tty2.service`: inactive
- `game-mode-perf.service`: inactive
- Brightness: 100%
- NVIDIA: RTX 3050 Laptop, 13 MiB used, 275 MiB reserved, 4096 MiB total
- NVIDIA persistence: disabled
- NVIDIA default power limit: 35 W; reported max: 50 W (setting unsupported)
- Bluetooth: ULT WEAR, A2DP/LDAC, 96 kHz
- PipeWire graph: 192 kHz
- Analog sink: `s32le 2ch 192000Hz`
- CPU governor/EPP: `performance` / `performance` (set manually)
- ASUS platform profile: `performance`
- AMD DPM: `high`
- The game-mode scripts did not modify CPU governor/EPP, ASUS platform profile, power-profiles-daemon, or AMD DPM.

---

## 16. Known limitations / notes

- `nvidia-smi -pl` cannot change the power limit on this vBIOS. Burn PC locks clocks and persistence but cannot exceed the default wattage.
- The `287/4 GB` VRAM display is `13 MiB used + 275 MiB reserved`; the reserved block belongs to the NVIDIA driver and cannot be reduced to zero while the driver is loaded.
- gamescope does not expose `wl_subcompositor`; `foot` fails inside it. Use kitty (`game-terminal` does this).
- The Bluetooth headset microphone is available only when manually selecting an HFP profile; the default microphone is the laptop mic.
- Restarting WirePlumber can temporarily leave a headset in HFP until a Bluetooth reconnect.
- `game-mode quit` may return exit code 1 while still stopping the session correctly.
- Verify Bloodborne launch, HDR state, and the Steam `Game Terminal` shortcut in the next tty2 session.
