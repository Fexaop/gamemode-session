# Launch Cheat Engine inside tty2 gamescope with HDR

## Before you start

- The tty2 Game Mode session must already be running. Cheat Engine must use that
  existing gamescope session; do not launch a second gamescope.
- `game-exec` and `game-terminal` are available in `~/.local/bin`.
- Cheat Engine must be installed in the same Proton prefix as the game you want
  to attach to.

## 1. Fix the environment variables

Your original command had two problems:

- `STEAM_COMPAT_CLIENT_INSTALL_PATH` was empty.
- `STEAM_COMPAT_DATA_PATH` pointed at `2156822488`, while the Cheat Engine exe
  was inside the `2974274959` prefix. Those must match.

For the exe path you showed, use:

```bash
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/2974274959/"
```

If the game you want to attach to actually uses `2156822488`, change both the
`STEAM_COMPAT_DATA_PATH` and the Cheat Engine exe path to `2156822488`.
Cheat Engine must be installed in that prefix.

## 2. Open a terminal inside the tty2 gamescope session

From Steam Big Picture:

- Launch the **Game Terminal** shortcut.

Or from niri, while Game Mode is already running:

```bash
game-terminal
```

Then switch to tty2 and use the terminal there.

## 3. Run Cheat Engine from that terminal

```bash
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/2974274959/"

"$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton" run \
  "$HOME/.local/share/Steam/steamapps/compatdata/2974274959/pfx/drive_c/Program Files/Cheat Engine/cheatengine-x86_64.exe"
```

## 4. Alternative: launch from niri

This runs the command inside the existing tty2 gamescope session without
opening a terminal there first:

```bash
game-exec env \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
  STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/2974274959/" \
  "$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/proton" run \
  "$HOME/.local/share/Steam/steamapps/compatdata/2974274959/pfx/drive_c/Program Files/Cheat Engine/cheatengine-x86_64.exe"
```

`game-exec` supplies:

- the tty2 `gamescope-0` Wayland socket
- gamescope's Xwayland `DISPLAY`
- the NVIDIA Vulkan ICD
- `DXVK_HDR=1`
- `PROTON_ENABLE_HDR=1`
- `ENABLE_GAMESCOPE_WSI=1`
- `STEAM_GAMESCOPE_HDR_SUPPORTED=1`

## HDR notes

- The tty2 gamescope session is already launched with `--hdr-enabled`, and
  content-driven HDR is enabled by the one-shot helper.
- Cheat Engine is an SDR Win32 application. It will run inside the HDR-enabled
  session, but it will not make the panel HDR by itself.
- HDR engages when the game presents HDR content. Launch the HDR game from
  Steam/Proton as usual; Cheat Engine can stay open alongside it.

## Same-prefix requirement

Cheat Engine can only attach to a game running in the same Wine prefix. If the
game runs in a different `compatdata` prefix, Cheat Engine will not see it.
Use one `STEAM_COMPAT_DATA_PATH` for both the game and Cheat Engine.

## Original command, for reference

```bash
STEAM_COMPAT_CLIENT_INSTALL_PATH= STEAM_COMPAT_DATA_PATH=/home/gunit/.local/share/Steam/steamapps/compatdata/2156822488/ /home/gunit/.local/share/Steam/steamapps/common/Proton\ -\ Experimental/proton run /home/gunit/.local/share/Steam/steamapps/compatdata/2974274959/pfx/drive_c/Program\ Files/Cheat\ Engine/cheatengine-x86_64.exe
```

Do not run this unchanged: the empty client-install path and the mismatched
prefix IDs will prevent Cheat Engine from sharing the game's Wine prefix.
