enable_ue4ss_debug_console() {
    local game_root="$1"
    local settings_path="$game_root/Binaries/Win64/ue4ss/UE4SS-settings.ini"

    require_file "$settings_path"
    set_ini_value "$settings_path" "GuiConsoleEnabled" "1"
    set_ini_value "$settings_path" "GuiConsoleVisible" "1"
    log "Enabled UE4SS GUI console in $settings_path"
}

launch_game() {
    local app_id="$1"
    local debug_log="${2:-0}"
    
    export WINEDLLOVERRIDES="dwmapi=n,b"

    # Automatically ensure launch options are injected
    local steam_root="${STEAM_ROOT:-}"
    if [[ -z "$steam_root" ]]; then
        if declare -f detect_steam_root >/dev/null; then
            steam_root="$(detect_steam_root || true)"
        fi
    fi
    if [[ -n "$steam_root" ]]; then
        local script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
        if command -v python3 >/dev/null 2>&1; then
            python3 "$script_dir/InjectLaunchOptions.py" "$steam_root" "$app_id" >/dev/null 2>&1 || true
        fi
    fi

    if command -v steam >/dev/null 2>&1; then
        if [[ "$debug_log" == "1" ]]; then
            log "Launching Subnautica 2 via Steam app ID $app_id with -log"
            steam -applaunch "$app_id" -log >/dev/null 2>&1 &
        else
            log "Launching Subnautica 2 via Steam app ID $app_id"
            steam -applaunch "$app_id" >/dev/null 2>&1 &
        fi
        disown || true
        return 0
    fi

    if command -v xdg-open >/dev/null 2>&1; then
        if [[ "$debug_log" == "1" ]]; then
            log "Launching Subnautica 2 via steam://run/$app_id//-log"
            xdg-open "steam://run/$app_id//-log" >/dev/null 2>&1 &
        else
            log "Launching Subnautica 2 via steam://rungameid/$app_id"
            xdg-open "steam://rungameid/$app_id" >/dev/null 2>&1 &
        fi
        disown || true
        return 0
    fi

    die "Neither steam nor xdg-open is available to launch the game."
}
