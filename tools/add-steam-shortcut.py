#!/usr/bin/env python3
"""Add or update the "Game Terminal" non-Steam shortcut in Steam.

Close Steam before running this.  Steam rewrites shortcuts.vdf on exit, so a
change made while it is running can be lost.

Examples:
    python3 tools/add-steam-shortcut.py --dry-run
    python3 tools/add-steam-shortcut.py
    python3 tools/add-steam-shortcut.py --user 1128085718
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
import zlib
from pathlib import Path

try:
    import vdf
except ImportError:
    sys.exit(
        "python-vdf is required.\n"
        "  Arch: sudo pacman -S python-vdf\n"
        "  pip:  python3 -m pip install --user vdf"
    )


def find_steam_root(explicit: str | None) -> Path:
    if explicit:
        root = Path(explicit).expanduser()
        if not (root / "userdata").is_dir():
            sys.exit(f"Not a Steam root (no userdata directory): {root}")
        return root

    candidates = [
        Path.home() / ".local/share/Steam",
        Path.home() / ".steam/steam",
        Path.home() / ".var/app/com.valvesoftware.Steam/.local/share/Steam",
    ]
    for root in candidates:
        if (root / "userdata").is_dir():
            return root
    sys.exit("Could not find a Steam installation. Pass --steam-root PATH.")


def select_userdata(root: Path, wanted: str | None) -> Path:
    accounts = sorted(
        path
        for path in (root / "userdata").iterdir()
        if path.is_dir() and path.name.isdigit() and (path / "config/shortcuts.vdf").is_file()
    )
    if not accounts:
        sys.exit(f"No Steam userdata with config/shortcuts.vdf under {root / 'userdata'}")

    if wanted:
        for account in accounts:
            if account.name == wanted:
                return account
        sys.exit(f"Steam user {wanted} not found under {root / 'userdata'}")

    if len(accounts) == 1:
        return accounts[0]

    listed = "\n".join(f"  {account.name}" for account in accounts)
    sys.exit(
        "Multiple Steam accounts found; choose one with --user:\n"
        f"{listed}"
    )


def steam_is_running() -> bool:
    for name in ("steam", "steamwebhelper"):
        result = subprocess.run(
            ["pgrep", "-x", name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode == 0:
            return True
    return False


def make_appid(exe: str, name: str, used: set[int]) -> int:
    payload = f"{exe}{name}".encode("utf-8")
    raw = zlib.crc32(payload) & 0xFFFFFFFF
    if raw < 0x80000000:
        raw |= 0x80000000
    appid = raw - 0x100000000
    while appid in used:
        raw = (raw + 1) & 0xFFFFFFFF
        if raw < 0x80000000:
            raw |= 0x80000000
        appid = raw - 0x100000000
    return appid


def default_exe() -> Path:
    installed = Path.home() / ".local/bin/game-terminal"
    if installed.is_file():
        return installed
    repo_copy = Path(__file__).resolve().parent.parent / "bin/game-terminal"
    if repo_copy.is_file():
        return repo_copy
    return installed


def backup_path(path: Path) -> Path:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = path.with_name(f"{path.name}.bak-{stamp}")
    counter = 1
    while backup.exists():
        backup = path.with_name(f"{path.name}.bak-{stamp}-{counter}")
        counter += 1
    return backup


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Add or update the Game Terminal shortcut in Steam."
    )
    parser.add_argument("--steam-root", help="Steam root containing userdata/")
    parser.add_argument("--user", help="Steam userdata account ID")
    parser.add_argument("--exe", help="Path to game-terminal (default: ~/.local/bin)")
    parser.add_argument("--name", default="Game Terminal", help="Shortcut name")
    parser.add_argument("--dry-run", action="store_true", help="Show changes only")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Write even if Steam is running (not recommended)",
    )
    args = parser.parse_args()

    if steam_is_running() and not args.force:
        sys.exit("Steam is running. Close it first, then run this again.")

    root = find_steam_root(args.steam_root)
    account = select_userdata(root, args.user)
    shortcuts_path = account / "config/shortcuts.vdf"

    exe = Path(args.exe).expanduser() if args.exe else default_exe()
    if not exe.is_file():
        sys.exit(f"game-terminal not found: {exe}\nRun ./install.sh first.")
    exe = exe.resolve()
    exe_field = f'"{exe}"'

    data = vdf.binary_loads(shortcuts_path.read_bytes())
    shortcuts = data.setdefault("shortcuts", {})

    existing_key = None
    used_appids: set[int] = set()
    for key, entry in shortcuts.items():
        appid = entry.get("appid")
        if isinstance(appid, int):
            used_appids.add(appid)
        if entry.get("AppName") == args.name:
            existing_key = key

    if existing_key is not None:
        entry = shortcuts[existing_key]
        entry["Exe"] = exe_field
        entry["StartDir"] = str(Path.home())
        entry["AllowOverlay"] = 0
        action = f"Updated existing shortcut {existing_key}"
    else:
        key = str(max((int(k) for k in shortcuts), default=-1) + 1)
        entry = {
            "appid": make_appid(exe_field, args.name, used_appids),
            "AppName": args.name,
            "Exe": exe_field,
            "StartDir": str(Path.home()),
            "icon": "",
            "ShortcutPath": "",
            "LaunchOptions": "",
            "IsHidden": 0,
            "AllowDesktopConfig": 1,
            "AllowOverlay": 0,
            "OpenVR": 0,
            "Devkit": 0,
            "DevkitGameID": "",
            "DevkitOverrideAppID": 0,
            "LastPlayTime": 0,
            "FlatpakAppID": "",
            "sortas": "",
            "tags": {},
        }
        shortcuts[key] = entry
        action = f"Added shortcut {key}"

    print(f"Steam:     {root}")
    print(f"Account:   {account.name}")
    print(f"Shortcuts: {shortcuts_path}")
    print(
        f"{action}: {entry['AppName']} -> {entry['Exe']} "
        f"(overlay={entry['AllowOverlay']}, appid={entry['appid']})"
    )

    if args.dry_run:
        print("Dry run; nothing written.")
        return 0

    backup = backup_path(shortcuts_path)
    shutil.copy2(shortcuts_path, backup)
    payload = vdf.binary_dumps(data)
    tmp = shortcuts_path.with_name(shortcuts_path.name + ".tmp")
    tmp.write_bytes(payload)
    with tmp.open("rb") as handle:
        os.fsync(handle.fileno())
    tmp.replace(shortcuts_path)

    print(f"Backup:    {backup}")
    print("Done. Start Steam and open Big Picture to find the shortcut.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
