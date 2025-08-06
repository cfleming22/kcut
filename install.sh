#!/usr/bin/env bash
# =============================================================================
# install.sh  bootstrap script for the keyboardshortcut collector
#
# What it does:
#   1. Creates a Python virtual environment in ./venv
#   2. Installs the Python packages psutil, pyobjc-framework-Quartz and
#      pyinstaller inside that environment
#   3. Copies the main Python source file (show_shortcuts_v2.py) into the
#      repository if it does not already exist
#   4. Copies a starter shortcuts.json file if it does not already exist
#   5. Builds a macOS arm64 singlefile binary with PyInstaller
#   6. Symlinks the binary to ~/bin/kcut (creates ~/bin if necessary)
#   7. Adds ~/bin to the users $PATH (adds a line to ~/.zshrc if needed)
#
# Prerequisite: the script must be run on macOS (Applesilicon or Intel).
# =============================================================================

set -euo pipefail

# ----------------------------------------------------------------------
# Helper functions for nice output
# ----------------------------------------------------------------------
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# ----------------------------------------------------------------------
# 0. Verify we are on macOS
# ----------------------------------------------------------------------
if [[ "$(uname)" != "Darwin" ]]; then
    error "This installer only runs on macOS."
fi

# ----------------------------------------------------------------------
# 1. Determine the directory that contains this script
# ----------------------------------------------------------------------
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${PROJECT_ROOT}"
info "Project root: ${PROJECT_ROOT}"

# ----------------------------------------------------------------------
# 2. Create (or reuse) a virtual environment in .venv
# ----------------------------------------------------------------------
if [[ -d ".venv" ]]; then
    info "Virtual environment already exists  reusing it."
else
    info "Creating a new virtual environment with the system Python."
    python3 -m venv .venv
fi
source .venv/bin/activate

# ----------------------------------------------------------------------
# 3. Upgrade pip and install required Python packages
# ----------------------------------------------------------------------
info "Upgrading pip."
pip install -U pip setuptools > /dev/null

info "Installing required packages (psutil, pyobjc-framework-Quartz, pyinstaller)."
pip install psutil pyobjc-framework-Quartz pyinstaller > /dev/null

# ----------------------------------------------------------------------
# 4. Deploy the main Python script (if it does not already exist)
# ----------------------------------------------------------------------
if [[ -f "show_shortcuts_v2.py" ]]; then
    info "show_shortcuts_v2.py already present  leaving unchanged."
else
    info "Writing the main script (show_shortcuts_v2.py)."
    cat > show_shortcuts_v2.py <<'PY'
#!/usr/bin/env python3
"""
show_shortcuts_v2.py

Collect all keyboard shortcuts on macOS (system + menu bar + known app files).
Features:
  * --gui   opens a small Tkinter GUI
  * --export-json <path> writes the full list to a JSON file
  * The GUI includes an Add Shortcut button that writes to shortcuts.json
  * Shortcuts belonging to the active window are shown first
"""

# ----------------------------------------------------------------------
# Imports
# ----------------------------------------------------------------------
import argparse, json, os, pathlib, sys
from collections import defaultdict
from typing import List, Dict

import psutil                         # process enumeration
import Quartz                         # macOS Accessibility API
import plistlib

# ----------------------------------------------------------------------
# Minimal set of static system shortcuts (always present)
# ----------------------------------------------------------------------
_SYSTEM_SHORTCUTS = [
    {"shortcut": "L", "description": "Lock screen", "context": "System"},
    {"shortcut": "Space", "description": "Spotlight", "context": "System"},
    {"shortcut": "Power", "description": "Force shutdown dialog", "context": "System"},
]

# ----------------------------------------------------------------------
# Helper parsers for known configuration formats
# ----------------------------------------------------------------------
def _read_json(path: pathlib.Path) -> List[Dict[str, str]]:
    """Parse a JSON file that contains a list of keybinding dictionaries."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"  JSON error {path}: {e}", file=sys.stderr)
        return []
    shortcuts = []
    if isinstance(data, list):
        for entry in data:
            if isinstance(entry, dict) and "key" in entry:
                shortcuts.append({
                    "shortcut": entry["key"],
                    "description": entry.get("command", "").replace(".", " ").title(),
                    "context": entry.get("when", "VS Code")
                })
    elif isinstance(data, dict) and "commands" in data:
        for cmd, info in data["commands"].items():
            if isinstance(info, dict) and "suggested_key" in info:
                shortcuts.append({
                    "shortcut": info["suggested_key"],
                    "description": f"Chrome command: {cmd}",
                    "context": "Chrome"
                })
    return shortcuts


def _read_plist(path: pathlib.Path) -> List[Dict[str, str]]:
    """Parse a macOS .plist that contains key equivalents."""
    try:
        data = plistlib.load(open(path, "rb"))
    except Exception as e:
        print(f"  Plist error {path}: {e}", file=sys.stderr)
        return []
    shortcuts = []
    for title, key in data.get("NSUserKeyEquivalents", {}).items():
        shortcuts.append({
            "shortcut": key,
            "description": title,
            "context": path.stem
        })
    for title, key in data.get("keyEquivalents", {}).items():
        shortcuts.append({
            "shortcut": key,
            "description": title,
            "context": path.stem
        })
    return shortcuts


def _read_sublime_keymap(path: pathlib.Path) -> List[Dict[str, str]]:
    """Parse a Sublime Text .sublime-keymap (JSONlike) file."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"  Sublime error {path}: {e}", file=sys.stderr)
        return []
    shortcuts = []
    for entry in data:
        if isinstance(entry, dict) and "keys" in entry:
            keys = entry["keys"]
            if isinstance(keys, list):
                keys = "+".join(keys)
            shortcuts.append({
                "shortcut": keys,
                "description": entry.get("command", "Sublime command"),
                "context": "Sublime"
            })
    return shortcuts


def _read_iterm2_plist(path: pathlib.Path) -> List[Dict[str, str]]:
    """Parse iTerm2's preferences plist."""
    try:
        data = plistlib.load(open(path, "rb"))
    except Exception as e:
        print(f"  iTerm2 error {path}: {e}", file=sys.stderr)
        return []
    shortcuts = []
    for name, info in data.items():
        if isinstance(info, dict) and "KeyCode" in info:
            mods = []
            if info.get("Command"): mods.append("Command")
            if info.get("Control"): mods.append("Control")
            if info.get("Option"):  mods.append("Option")
            if info.get("Shift"):   mods.append("Shift")
            shortcut = "+".join(mods + [info["KeyCode"]])
            shortcuts.append({
                "shortcut": shortcut,
                "description": f"iTerm2 {name}",
                "context": "iTerm2"
            })
    return shortcuts


# ----------------------------------------------------------------------
# Collectors
# ----------------------------------------------------------------------
def collect_system() -> List[Dict[str, str]]:
    """Static shortcuts defined in the script."""
    return _SYSTEM_SHORTCUTS


def _system_symbolic_hotkeys() -> List[Dict[str, str]]:
    """Read the system symbolic hotkeys plist."""
    plist = pathlib.Path.home() / "Library/Preferences/com.apple.symbolichotkeys.plist"
    if not plist.is_file():
        return []
    try:
        data = plistlib.load(open(plist, "rb"))
    except Exception as e:
        print(f"  Symbolic hotkeys error: {e}", file=sys.stderr)
        return []
    results = []
    for hk_id, hk in data.get("AppleSymbolicHotKeys", {}).items():
        if not hk.get("enabled"):
            continue
        params = hk.get("parameters", [])
        if len(params) < 2:
            continue
        keycode, mods = params[0], params[1]
        mod_names = []
        if mods & 0x10000: mod_names.append("Shift")
        if mods & 0x20000: mod_names.append("Control")
        if mods & 0x40000: mod_names.append("Option")
        if mods & 0x80000: mod_names.append("Command")
        shortcut = "+".join(mod_names + [f"VK_{keycode}"])
        results.append({
            "shortcut": shortcut,
            "description": f"System hotkey #{hk_id}",
            "context": "System"
        })
    return results


def _active_app_name() -> str | None:
    """Return the localized name of the frontmost application (or None)."""
    try:
        focused = Quartz.AXUIElementCopyAttributeValue(
            Quartz.AXUIElementCreateSystemWide(),
            Quartz.kAXFocusedUIElementAttribute,
            None
        )[1]
        pid = Quartz.AXUIElementGetPid(focused)
        ax_app = Quartz.AXUIElementCreateApplication(pid)
        name = Quartz.AXUIElementCopyAttributeValue(
            ax_app, Quartz.kAXTitleAttribute, None
        )[1]
        return name
    except Exception:
        return None


def _collect_menu_bar(active_app: str | None) -> List[Dict[str, str]]:
    """Walk every UI process that has a menu bar; give activeapp shortcuts higher priority."""
    shortcuts = []

    def _walk(element, priority):
        # Look for a menuitem accelerator (the text shown next to a menu entry)
        try:
            cmd_char = Quartz.AXUIElementCopyAttributeValue(
                element, Quartz.kAXMenuItemCmdCharAttribute, None
            )
            cmd_mod = Quartz.AXUIElementCopyAttributeValue(
                element, Quartz.kAXMenuItemCmdModifiersAttribute, None
            )
            if cmd_char[0] != 0 or cmd_mod[0] != 0:
                mods = []
                flag = cmd_mod[1]
                if flag & Quartz.kAXMenuItemCmdModifierShift:   mods.append("Shift")
                if flag & Quartz.kAXMenuItemCmdModifierControl:mods.append("Control")
                if flag & Quartz.kAXMenuItemCmdModifierOption: mods.append("Option")
                if flag & Quartz.kAXMenuItemCmdModifierCommand:mods.append("Command")
                key = cmd_char[1]
                # Map a few common unicode symbols to readable names
                special = {"\r": "Enter", "\t": "Tab", " ": "Space", "\x1b": "Esc"}
                key = special.get(key, key.upper())
                shortcut = "+".join(mods + [key])
                title = Quartz.AXUIElementCopyAttributeValue(
                    element, Quartz.kAXTitleAttribute, None
                )[1] or ""
                shortcuts.append({
                    "shortcut": shortcut,
                    "description": title,
                    "context": app_name,
                    "priority": priority
                })
        except Exception:
            pass

        # Recurse into children
        try:
            children = Quartz.AXUIElementCopyAttributeValue(
                element, Quartz.kAXChildrenAttribute, None
            )[1]
        except Exception:
            return
        for child in children:
            _walk(child, priority)

    for proc in psutil.process_iter(['pid', 'name']):
        try:
            ax_app = Quartz.AXUIElementCreateApplication(proc.info['pid'])
            app_name = Quartz.AXUIElementCopyAttributeValue(
                ax_app, Quartz.kAXTitleAttribute, None
            )[1] or proc.info['name']
            priority = 2 if (active_app and app_name == active_app) else 1
            menu_bar = Quartz.AXUIElementCopyAttributeValue(
                ax_app, Quartz.kAXMenuBarAttribute, None
            )[1]
            _walk(menu_bar, priority)
        except Exception:
            continue
    return shortcuts


def _collect_known_app_files() -> List[Dict[str, str]]:
    """Parse a handful of apps that ship shortcuts in plain files."""
    shortcuts = []

    # VS Code
    vc = pathlib.Path.home() / "Library/Application Support/Code/User/keybindings.json"
    if vc.is_file():
        shortcuts.extend(_read_json(vc))

    # Sublime Text
    sub = pathlib.Path.home() / "Library/Application Support/Sublime Text 3/Packages/User/Default (OSX).sublime-keymap"
    if sub.is_file():
        shortcuts.extend(_read_sublime_keymap(sub))

    # iTerm2
    iterm = pathlib.Path.home() / "Library/Preferences/com.googlecode.iterm2.plist"
    if iterm.is_file():
        shortcuts.extend(_read_iterm2_plist(iterm))

    # Finder (optional)
    finder = pathlib.Path.home() / "Library/Preferences/com.apple.finder.plist"
    if finder.is_file():
        shortcuts.extend(_read_plist(finder))

    # Chrome commands (extensions can define them)
    chrome = pathlib.Path.home() / "Library/Application Support/Google/Chrome/Default/Preferences"
    if chrome.is_file():
        shortcuts.extend(_read_json(chrome))

    return shortcuts


def _collect_user_json(json_path: pathlib.Path) -> List[Dict[str, str]]:
    """Read a usersupplied JSON file (custom shortcuts + apps map)."""
    if not json_path.is_file():
        return []
    try:
        data = json.loads(json_path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"  Could not read {json_path}: {e}", file=sys.stderr)
        return []

    # custom shortcuts
    custom = data.get("custom", [])
    for rec in custom:
        rec.setdefault("priority", 1)

    # apps map (e.g. {"vscode": ".../keybindings.json"})
    apps = data.get("apps", {})
    app_entries = []
    for _, fp in apps.items():
        p = pathlib.Path(os.path.expanduser(fp)).expanduser().resolve()
        if not p.is_file():
            continue
        if p.suffix.lower() == ".json":
            app_entries.extend(_read_json(p))
        elif p.suffix.lower() in {".plist", ".xml"}:
            app_entries.extend(_read_plist(p))
        elif p.suffix.lower() == ".sublime-keymap":
            app_entries.extend(_read_sublime_keymap(p))
    return custom + app_entries


def _merge_all(*lists: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """Deduplicate and sort  activewindow shortcuts first."""
    flat = []
    for lst in lists:
        flat.extend(lst)

    uniq: dict[tuple, Dict] = {}
    for rec in flat:
        key = (rec["shortcut"], rec.get("context", ""))
        # Keep the entry with the highest priority (2 = active window)
        if key not in uniq or rec.get("priority", 1) > uniq[key].get("priority", 1):
            uniq[key] = rec

    sorted_items = sorted(
        uniq.values(),
        key=lambda r: (-r.get("priority", 1), r.get("context", ""), r.get("shortcut", ""))
    )
    return sorted_items


# ----------------------------------------------------------------------
# CLI and GUI output helpers
# ----------------------------------------------------------------------
def _cli_print(shortcuts: List[Dict[str, str]]) -> None:

