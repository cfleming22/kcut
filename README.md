````markdown
# Keyboard‑Shortcut Collector

A small macOS‑only utility that gathers **all keyboard shortcuts** you can discover on your Mac:

System‑wide shortcuts (Spotlight, Lock screen, etc.)
Menu‑bar shortcuts of every visible application (active‑window shortcuts are shown first)
Shortcuts stored in common configuration files (VS Code, Sublime Text, iTerm2, Chrome, …)
Custom shortcuts you add yourself (via a JSON file or the built‑in GUI)

The tool can be used from the command line or through a tiny searchable Tkinter window. A **stand‑alone binary** (`kcut`) is built with PyInstaller, so it can be run on any Apple‑silicon Mac without installing Python.

---

## Table of Contents

[Features](#features)
[Prerequisites](#prerequisites)
[Installation](#installation)
[Usage](#usage)
[Adding Your Own Shortcuts](#adding-your-own-shortcuts)
[Exporting Shortcuts to JSON](#exporting-shortcuts-to-json)
[Contributing](#contributing)
[License](#license)

## Features

| Feature | Description |
|---|---|
| **System shortcut detection** | Reads `com.apple.symbolichotkeys.plist` and other system preference files. |
| **Menu‑bar scan** | Uses macOS Accessibility (AX) API to collect shortcuts from every visible app’s menu bar. |
| **App‑specific parsers** | Supports VS Code (`keybindings.json`), Sublime Text (`*.sublime-keymap`), iTerm2, Chrome, Finder, and more. |
| **Active‑window priority** | Shortcuts belonging to the currently focused application are shown first. |
| **GUI** | Searchable list with **Add Shortcut** and **Refresh** buttons. |
| **CLI** | Simple table output for quick terminal use. |
| **Export** | `kcut --export-json <path>` writes the complete shortcut list to a JSON file. |
| **Standalone binary** | Built with PyInstaller; `kcut` works on any macOS system without a Python interpreter. |

## Prerequisites

macOS 13 – 15 (Apple Silicon or Intel)
System‑provided Python 3 (which includes the necessary Tkinter library)

> **Note:** All other Python dependencies are installed into a local virtual environment by the installer script and will not affect your system.

## Installation

**Clone the repository:**
```bash
git clone [https://github.com/your-username/keyboard-shortcuts.git](https://github.com/your-username/keyboard-shortcuts.git)
cd keyboard-shortcuts
```

**Run the installer script:**
```bash
chmod +x install.sh
./install.sh
```
The script will perform the following actions:
Create a local Python virtual environment in `.venv/`.
Install required packages (`psutil`, `pyobjc-framework-Quartz`, `pyinstaller`).
Build a single‑file binary at `dist/show_shortcuts`.
Create a symbolic link at `~/bin/kcut` so the command is available everywhere.
Add `~/bin` to your shell's `$PATH` (by updating `~/.zshrc` if needed).

**Reload your shell:** For the `$PATH` change to take effect, open a new terminal window or run:
```bash
source ~/.zshrc
```
You can now use the `kcut` command from any directory.

## Usage

| Command | Description |
|---|---|
| `kcut` | Shows a plain‑text table of all discovered shortcuts in your terminal. |
| `kcut --gui` | Opens the searchable Tkinter GUI with "Add" and "Refresh" buttons. |
| `kcut --export-json <path>` | Writes the complete list of shortcuts to the specified JSON file. |

> **Permissions Note:** The first time you run the command, macOS will request **Accessibility** permissions. You must grant this for the tool to read menu bar shortcuts. Go to `System Settings → Privacy & Security → Accessibility` and enable the permission for your terminal application (e.g., Terminal, iTerm2).

## Adding Your Own Shortcuts

You can add custom shortcuts either through the GUI or by editing the JSON file directly.

### Through the GUI
Run `kcut --gui`.
Click the **Add Shortcut** button.
Fill in the fields: `Shortcut` (e.g., `⌘⇧N`), `Description`, and `Context` (the app name, or `User` for global).
Click **Save**. The new shortcut appears instantly and is saved to `shortcuts.json`.

### By Editing `shortcuts.json` Directly
Open the `shortcuts.json` file in the repository root and add your entry to the `custom` array:
```json
{
"custom": [
{
"shortcut": "⌘⇧N",
"description": "New window (Safari)",
"context": "Safari"
}
],
"apps": {}
}
````

After saving the file, run `kcut` again or click **Refresh** in the GUI to see your changes.

## Exporting Shortcuts to JSON

To get a complete snapshot of all discovered shortcuts (system, menu-bar, app files, and custom) in a single file, run:

```bash
kcut --export-json ~/Desktop/all_shortcuts.json
```

## Contributing

Contributions are welcome\!

Fork the repository.
Create a new branch for your feature or bug fix.
Make your changes.
Run `./install.sh` to test that the binary still builds correctly.
Commit and push your branch, then open a Pull Request.

Please keep the following in mind:

The project targets **macOS only**.
Try to preserve the existing JSON schema.

## License

This project is released under the **MIT License**. See the `LICENSE` file for details.

```

```
