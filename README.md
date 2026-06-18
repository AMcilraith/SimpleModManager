**Simple SN2 Modloader**
------------------------

A streamlined, console-based terminal mod manager and launcher for **Subnautica 2**. Simple and efficient. No I will not be adding a GUI, it's terminal only for now. Originally made this for me and my friends but thought I'd post it here.

## First-time setup

UE4SS and user mods are **not** stored in this repository. After cloning:

1. Run `powershell -File Helpers\Windows\Install-Ue4ssRelease.ps1` (or use **Updater → Update UE4SS**). This pulls the latest stable zip from [RE-UE4SS GitHub releases](https://github.com/UE4SS-RE/RE-UE4SS/releases) (e.g. `UE4SS_v3.0.1.zip`).
2. Install your mods via **Mod Manager → Install Mod from Zip**.
3. **Deploy Mods to Game** before launching.

Features
--------

1\. Game Launcher

*   **Launch Standard:** Start Subnautica 2 from steam without any console stuff. Just normally play the game.
    
*   **Launch with Debug Console:** Run the game alongside a live diagnostic/debug window to trace active errors, monitor asset loading, or work on mod development.
    

2\. Mod Management 

*   **Toggle UE4SS Mods:** Toggle or Remove your UE4SS mods and a mod load order to boot.
    
*   **Toggle BP Patch Mods (~mods):** Toggle or Remove your pak patch mods and a mod load order to boot.
    
*   **Toggle BP Logic Mods:**  Toggle or Remove your LogicMods and a mod load order to boot.
    
*   **Engine Tweaks:** Adjust your game engine to optimise performance.
    
*   **Install Mod from Zip:** Directly install newly downloaded packages into your directories without requiring external extraction or manual file movement.

*   **Export Collection:** Save your current enabled mods and active PlayerTweaks config files into a reusable collection file you can share.

*   **Import Collection:** Load a saved collection file to switch the modloader to that exact saved setup.
    

3\. UE4SS Updater

*   **Update UE4SS:** Queries [RE-UE4SS GitHub releases](https://github.com/UE4SS-RE/RE-UE4SS/releases) and installs the latest stable `UE4SS_v*.zip` (no API key required).
    

4\. Deployment & Safety Guards

*   **Deploy Mods to Game:** Deploys the modpack to the game automagically.
    
*   **Purge Mods and Revert to Vanilla:** Un-Deploys mods and removes UE4SS so you can play mod-free.
    

Credits & Acknowledgments
-------------------------

This modloader leverages and supports incredible work across the Subnautica 2 modding community. Special credits to:

*   **Vercadi:** [Quality Engine.ini presets](https://www.nexusmods.com/subnautica2/mods/37) (High-Quality, Balanced-Quality).

*   **Ghostiexd:** [Performance Engine.ini presets](https://www.nexusmods.com/subnautica2/mods/51) (Balanced/High/Ultra/Potato).
    
*   **Caites:** For creating the PlayerTweaks system I used and packaged in this mod.
    
*   **The UE4SS Team:** [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases)