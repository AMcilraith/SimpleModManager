purge_mods() {
    local game_root="$1"
    local local_appdata_root="$2"

    local win64_root="$game_root/Binaries/Win64"
    local ue4ss_root="$win64_root/ue4ss"
    local dwmapi_path="$win64_root/dwmapi.dll"
    local game_ini_path="$local_appdata_root/Subnautica2/Saved/Config/Windows/game.ini"
    local engine_ini_path="$local_appdata_root/Subnautica2/Saved/Config/Windows/engine.ini"
    local extra_mod_roots=(
        "$game_root/Content/Paks/~mods"
        "$game_root/Content/Paks/LogicMods"
    )

    if [[ -d "$ue4ss_root" ]]; then
        log "Removing $ue4ss_root"
        rm -rf -- "$ue4ss_root"
    else
        log "UE4SS root not found: $ue4ss_root"
    fi

    if [[ -f "$dwmapi_path" ]]; then
        log "Removing $dwmapi_path"
        rm -f -- "$dwmapi_path"
    else
        log "dwmapi.dll not present: $dwmapi_path"
    fi

    if [[ -f "$game_ini_path" ]]; then
        log "Removing $game_ini_path"
        rm -f -- "$game_ini_path"
    else
        log "game.ini not present: $game_ini_path"
    fi

    if [[ -f "$engine_ini_path" ]]; then
        log "Removing $engine_ini_path"
        rm -f -- "$engine_ini_path"
    else
        log "engine.ini not present: $engine_ini_path"
    fi

    local extra_mod_root
    for extra_mod_root in "${extra_mod_roots[@]}"; do
        if [[ -d "$extra_mod_root" ]]; then
            log "Removing $extra_mod_root"
            rm -rf -- "$extra_mod_root"
        fi
    done

    log "All UE4SS mods, game.ini, and engine.ini removed."
}
