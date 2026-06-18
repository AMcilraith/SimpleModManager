# Simple SN2 Modloader Instructions

A terminal-based mod manager for **Subnautica 2**. It manages UE4SS Lua mods, BP patch mods (`~mods`), logic mods, and engine/player tweaks.

---

## Quick Start

### 1. Install UE4SS (first time only)

UE4SS is not bundled in this repository. Install it once before deploying:

```bat
powershell -ExecutionPolicy Bypass -File Helpers\Windows\Install-Ue4ssRelease.ps1
```

Linux / Steam Deck:

```bash
bash Helpers/Linux/Install-Ue4ssRelease.sh
```

Or open `RUNME.bat` / `RUNME.sh` and choose **Updater** (runs the UE4SS GitHub installer).

Downloads come from [RE-UE4SS GitHub releases](https://github.com/UE4SS-RE/RE-UE4SS/releases). The installer checks for newer stable tags automatically (e.g. `https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v3.0.1/UE4SS_v3.0.1.zip`).

### 2. Run the modloader

Double-click `RUNME.bat` (Windows) or `RUNME.sh` (Linux).

### 3. Add mods

Use **Mod Manager → Install Mod from Zip**, or copy mods into:

- `ModManager/EnabledMods/Mods` — UE4SS Lua/C++ mods
- `ModManager/EnabledMods/~mods` — BP patch mods
- `ModManager/EnabledMods/LogicMods` — BP logic mods

### 4. Deploy before playing

Choose **Deploy Mods to Game** after changing mods or tweaks.

### 5. Engine.ini presets

Performance presets: [Nexus mod 51](https://www.nexusmods.com/subnautica2/mods/51) (Ghostiexd)  
Quality presets: [Nexus mod 37](https://www.nexusmods.com/subnautica2/mods/37) (Vercadi)

Fetch them via **Mod Manager → Engine Tweaks** (requires optional `NEXUS_API_KEY` in `Helpers/.env`), or download manually into `ModManager/EngineTweaks/<preset-name>/Engine.ini`. See `ModManager/EngineTweaks/SOURCES.md`.

---

## Reverting to vanilla

Choose **Purge Mods and Revert to Vanilla** to remove deployed files from the game directory.
