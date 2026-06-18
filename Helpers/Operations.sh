#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/.env"
    set +a
fi

require_linux_tools() {
    local tool missing=()
    for tool in bash curl jq unzip; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing[*]}. Install them with your package manager."
    fi
}

require_linux_tools

TARGET_GAME_ROOT="${TARGET_GAME_ROOT:-}"
STEAM_ROOT="${STEAM_ROOT:-}"
STEAM_APP_ID="${STEAM_APP_ID:-}"

on_error() {
    local line="$1"
    printf 'Error: Script failed at line %s.\n' "$line" >&2
    if [[ -t 0 ]]; then
        printf 'Press Enter to exit...' >&2
        read -r
    fi
}

trap 'on_error $LINENO' ERR

safe_source() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        printf 'Error: Required helper script not found: %s\n' "$path" >&2
        if [[ -t 0 ]]; then
            printf 'Press Enter to exit...' >&2
            read -r
        fi
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$path"
}

safe_source "$SCRIPT_DIR/Linux/Common.sh"
safe_source "$SCRIPT_DIR/Linux/Deploy.sh"
safe_source "$SCRIPT_DIR/Linux/Purge.sh"
safe_source "$SCRIPT_DIR/Linux/Launch.sh"
safe_source "$SCRIPT_DIR/Linux/EngineTweaks.sh"
safe_source "$SCRIPT_DIR/Linux/Install-Ue4ssRelease.sh"
safe_source "$SCRIPT_DIR/Linux/ModManager.sh"

show_play_menu() {
    local cursor=0
    while true; do
        local options=(
            "[1] Launch Standard"
            "[2] Launch with Debug Console"
        )
        local -a MENU_COLORS=()
        local -a MENU_DESCRIPTIONS=(
            "Launches Subnautica 2 normally via Steam with your active mods enabled."
            "Launches the game and opens the UE4SS debug console window for troubleshooting and viewing logs."
        )
        get_menu_selection "PLAY GAME" "${options[@]}"
        local choice=$?
        
        mapfile -t context < <(resolve_context)
        local app_id="${context[1]}"
        local game_root="${context[2]}"
        
        case "$choice" in
            0)
                launch_game "$app_id"
                return
                ;;
            1)
                enable_ue4ss_debug_console "$game_root"
                launch_game "$app_id" 1
                return
                ;;
            255)
                return
                ;;
        esac
    done
}

show_updater_menu() {
    mapfile -t context < <(resolve_context)
    export UE4SS_ROOT="${context[7]}"
    invoke_update_ue4ss
}

clear_terminal() {
    if command -v clear >/dev/null 2>&1; then
        clear
    else
        printf '\033c'
    fi
}

return_to_menu() {
    clear_terminal
}

return_invalid_input_to_menu() {
    local input_value="$1"
    if [[ -z "$input_value" ]]; then
        log "No selection entered."
    else
        log "Invalid selection: $input_value"
    fi
    return_to_menu
}

run_action() {
    local action="$1"
    mapfile -t context < <(resolve_context)
    local app_id="${context[1]}"
    local game_root="${context[2]}"
    local local_appdata_root="${context[3]}"
    
    export ENABLED_MODS="${context[5]}"
    export DISABLED_MODS="${context[6]}"
    export UE4SS_ROOT="${context[7]}"
    export DISABLED_UE4SS="${context[8]}"
    export ENGINE_TWEAKS="${context[9]}"
    export PLAYER_TWEAKS="${context[10]}"
    export MOD_UPDATES="${context[11]}"

    case "$action" in
        launch)
            launch_game "$app_id"
            ;;
        debug)
            enable_ue4ss_debug_console "$game_root"
            launch_game "$app_id" 1
            ;;
        deploy)
            deploy_mods "$game_root" "$app_id" "$local_appdata_root"
            ;;
        purge)
            purge_mods "$game_root" "$local_appdata_root"
            ;;
        modmanager)
            start_mod_manager
            ;;
        updateue4ss)
            invoke_update_ue4ss
            ;;
        *)
            die "Unknown action: $action"
            ;;
    esac
}

interactive_menu() {
    local cursor=0
    while true; do
        local options=(
            "[1] Play Game"
            "-"
            "[2] Mod Manager"
            "[3] Deploy Mods to Game"
            "[4] Purge Mods and Revert to Vanilla"
            "[5] Updater"
        )
        local -a MENU_COLORS=()
        local -a MENU_DESCRIPTIONS=(
            "Opens the Play Game sub-menu, offering options to launch the game normally or with the debug console."
            ""
            "Opens the Mod Manager, where you can toggle individual mods, modpacks, and engine/player tweaks."
            "Deploys your configured mods, plugins, and tweaks to the game directories so they load when playing."
            "Removes all deployed mods, plugins, and configurations from the game directories, reverting to clean vanilla."
            "Queries https://github.com/UE4SS-RE/RE-UE4SS/releases for the latest stable UE4SS build."
        )
        get_menu_selection "SIMPLE SN2 MODLOADER" "${options[@]}"
        local choice=$?
        
        mapfile -t context < <(resolve_context)
        export ENABLED_MODS="${context[5]}"
        export DISABLED_MODS="${context[6]}"
        export UE4SS_ROOT="${context[7]}"
        export DISABLED_UE4SS="${context[8]}"
        export ENGINE_TWEAKS="${context[9]}"
        export PLAYER_TWEAKS="${context[10]}"
        export MOD_UPDATES="${context[11]}"
        
        case "$choice" in
            0)
                show_play_menu
                cursor=0
                ;;
            2)
                start_mod_manager
                cursor=2
                ;;
            3)
                run_action deploy
                return_to_menu
                cursor=3
                ;;
            4)
                run_action purge
                return_to_menu
                cursor=4
                ;;
            5)
                show_updater_menu
                return_to_menu
                cursor=5
                ;;
            255)
                exit 0
                ;;
        esac
    done
}

show_general_help() {
    local text
    text=$'USAGE\n  ./Operations.sh menu\n  ./Operations.sh deploy\n  ./Operations.sh purge\n  ./Operations.sh modmanager\n  ./Operations.sh updateue4ss\n\nMANAGING MODS\n  - Use Mod Manager to toggle mods and engine/player tweaks.\n  - After changes, run Deploy to sync files into the game directory.\n  - Use Purge to remove all deployed files and return to vanilla.\n\nTROUBLESHOOTING\n  - If Steam or the game root is not detected, set STEAM_ROOT or TARGET_GAME_ROOT.\n  - Missing helper scripts or mod folders will stop execution with an error.'
    show_help_popup "INFO / USAGE" "$text"
}

main() {
    local action="${1:-menu}"
    action="${action#"${action%%[![:space:]]*}"}"
    action="${action%"${action##*[![:space:]]}"}"

    case "$action" in
        menu)
            interactive_menu
            ;;
        launch)
            run_action launch
            return_to_menu
            interactive_menu
            ;;
        debug)
            run_action debug
            return_to_menu
            interactive_menu
            ;;
        deploy)
            run_action deploy
            return_to_menu
            interactive_menu
            ;;
        purge)
            run_action purge
            return_to_menu
            interactive_menu
            ;;
        help|-h|--help)
            cat <<'EOF'
Usage: ./Operations.sh [menu|launch|debug|deploy|purge|modmanager|updateue4ss|info|help]

Environment overrides:
  STEAM_ROOT        Override the detected Steam root.
  TARGET_GAME_ROOT  Override the detected Subnautica2 install root.
  STEAM_APP_ID      Override the detected Steam app ID.

Workflow tips:
    1) Use Mod Manager to toggle mods and presets first.
    2) Run Deploy to apply your selections to the game folder.
    3) Use Purge to cleanly return to vanilla.

First-time setup:
    Install UE4SS: ./Helpers/Operations.sh updateue4ss
    Or: bash Helpers/Linux/Install-Ue4ssRelease.sh

Engine.ini preset sources:
  Performance (Ghostiexd): https://www.nexusmods.com/subnautica2/mods/51
  Quality (Vercadi):       https://www.nexusmods.com/subnautica2/mods/37

Layout expectations:
    ModManager/EnabledMods/{Mods,~mods,LogicMods} must exist.
    ModManager/UE4SS is populated by the UE4SS installer (not stored in git).
EOF
            ;;
                info)
                        show_general_help
                        ;;
        *)
            log "Unknown command: ${1}"
            return_to_menu
            interactive_menu
            ;;
    esac
}

main "$@"
