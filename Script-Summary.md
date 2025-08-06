| Section | Purpose |
|---|---|
| Shebang & safety flags | Guarantees the script stops on any error. |
| Helper output functions | Makes messages easy to read. |
| OS check | Prevents accidental execution on non‑macOS systems. |
| Virtual‑env creation | Isolates Python packages from the system. |
| Package installation | Installs the exact libraries the Python code needs. |
| Copy of source files | Guarantees the repository contains a working script and JSON. |
| PyInstaller build | Produces a single executable (`dist/show_shortcuts`). |
| Symlink to `~/bin/kcut` | Provides a one‑word command that works everywhere. |
| PATH adjustment | Ensures `~/bin` is searched by the shell. |
| Final instruction block | Tells the user how to start using the tool. |