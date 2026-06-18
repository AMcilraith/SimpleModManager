copy_merge_dir_contents() {
    local source="$1"
    local target="$2"
    require_dir "$source"
    mkdir -p "$target"
    cp -a "$source/." "$target/"
}

clear_directory_contents() {
    local target="$1"
    mkdir -p "$target"
    find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

reset_directory() {
    local target="$1"
    rm -rf -- "$target"
    mkdir -p "$target"
}

set_player_tweaks_readonly() {
    local target="$1"
    if find "$target" -type f -print -quit | grep -q .; then
        find "$target" -type f ! -iname 'GameUserSettings.ini' -exec chmod a-w {} +
        find "$target" -type f -iname 'GameUserSettings.ini' -exec chmod u+w {} +
    else
        log "No files found in $target"
    fi
}

prepare_player_tweaks_source() {
    local player_tweaks="$1"
    require_dir "$player_tweaks"
    if find "$player_tweaks" -type f -print -quit | grep -q .; then
        log "Setting PlayerTweaks source files read-only"
        find "$player_tweaks" -type f -exec chmod a-w {} +
    else
        log "No files found in $player_tweaks"
    fi
}

deploy_mods() {
    local game_root="$1"
    local app_id="$2"
    local local_appdata_root="$3"
    
    # These are passed or available from global env
    local enabled_mods="${4:-$ENABLED_MODS}"
    local ue4ss_root="${5:-$UE4SS_ROOT}"
    local player_tweaks="${6:-$PLAYER_TWEAKS}"

    prepare_player_tweaks_source "$player_tweaks"

    local target_player_tweaks="$local_appdata_root/Subnautica2/Saved/Config/Windows"
    local target_game_ini="$target_player_tweaks/game.ini"
    
    local target_ue4ss="$game_root/Binaries/Win64/ue4ss"
    local target_ue4ss_mods="$target_ue4ss/Mods"
    local target_mods="$game_root/Content/Paks/~mods"
    local target_logic_mods="$game_root/Content/Paks/LogicMods"
    local target_dwmapi="$game_root/Binaries/Win64/dwmapi.dll"

    local source_ue4ss_mods="$enabled_mods/Mods"
    local source_mods="$enabled_mods/~mods"
    local source_logic_mods="$enabled_mods/LogicMods"
    local source_dwmapi="$ue4ss_root/dwmapi.dll"
    local source_ue4ss="$ue4ss_root/ue4ss"

    require_dir "$source_ue4ss_mods"
    require_dir "$source_mods"
    require_dir "$source_logic_mods"

    if [[ -f "$target_game_ini" ]]; then
        log "Deleting existing game.ini at $target_game_ini"
        rm -f -- "$target_game_ini"
    fi

    log "Copying $player_tweaks -> $target_player_tweaks"
    copy_merge_dir_contents "$player_tweaks" "$target_player_tweaks"
    set_player_tweaks_readonly "$target_player_tweaks"

    if [[ ! -f "$source_dwmapi" ]]; then
        log "[WARN] UE4SS is not installed. Run the updater or install from GitHub releases first."
    fi

    log "Copying UE4SS Core -> $target_ue4ss"
    if [[ -d "$source_ue4ss" ]]; then
        copy_merge_dir_contents "$source_ue4ss" "$target_ue4ss"
    fi

    local source_builtin_mods="$source_ue4ss/Mods"
    log "Clearing $target_ue4ss_mods"
    clear_directory_contents "$target_ue4ss_mods"

    if [[ -d "$source_builtin_mods" ]]; then
        log "Copying UE4SS built-in mods -> $target_ue4ss_mods"
        copy_merge_dir_contents "$source_builtin_mods" "$target_ue4ss_mods"
    fi

    log "Merging enabled UE4SS mods -> $target_ue4ss_mods"
    copy_merge_dir_contents "$source_ue4ss_mods" "$target_ue4ss_mods"

    log "Resetting $target_mods"
    reset_directory "$target_mods"
    log "Copying $source_mods -> $target_mods"
    copy_mod_directories "$source_mods" "$target_mods"
 
    log "Resetting $target_logic_mods"
    reset_directory "$target_logic_mods"
    log "Copying $source_logic_mods -> $target_logic_mods"
    copy_mod_directories "$source_logic_mods" "$target_logic_mods"

    if [[ -f "$source_dwmapi" ]]; then
        mkdir -p "$(dirname -- "$target_dwmapi")"
        log "Copying dwmapi.dll -> $target_dwmapi"
        cp -f -- "$source_dwmapi" "$target_dwmapi"
    fi

    # Automatically inject Steam launch options for Steam Deck / Linux
    local steam_root="${STEAM_ROOT:-}"
    if [[ -z "$steam_root" ]]; then
        if declare -f detect_steam_root >/dev/null; then
            steam_root="$(detect_steam_root || true)"
        fi
    fi
    if [[ -n "$steam_root" ]]; then
        local script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
        if command -v python3 >/dev/null 2>&1; then
            log "Injecting Steam launch options for Subnautica 2 (App ID: $app_id)..."
            if python3 "$script_dir/InjectLaunchOptions.py" "$steam_root" "$app_id"; then
                log "Steam launch options verified/injected successfully. Please restart Steam if it is currently running."
            else
                log "Warning: Failed to inject Steam launch options automatically."
            fi
        else
            log "Warning: python3 is not available. Skipping automatic Steam launch options injection."
            log "Please manually configure Steam launch options for Subnautica 2 to:"
            log "  WINEDLLOVERRIDES=\"dwmapi=n,b\" %command%"
        fi
    fi

    log "Mods deployed for app $app_id"
}

copy_mod_directories() {
    local source_path="$1"
    local target_path="$2"
    
    mkdir -p "$target_path"

    local mod_dirs=()
    if [[ -d "$source_path" ]]; then
        while IFS= read -r dir; do
            [[ -n "$dir" ]] && mod_dirs+=("$dir")
        done < <(find "$source_path" -mindepth 1 -maxdepth 1 -type d | sort)
    fi

    for mod_dir in ${mod_dirs[@]+"${mod_dirs[@]}"}; do
        local mod_name
        mod_name="$(basename "$mod_dir")"
        local mod_dir="$source_path/$mod_name"
        
        if [[ -d "$mod_dir" ]]; then
            find "$mod_dir" -type f | while IFS= read -r file; do
                local rel_path="${file#"$mod_dir/"}"
                local base_file
                base_file="$(basename "$file")"
                local sub_dir
                sub_dir="$(dirname "$rel_path")"
                
                local dest_dir="$target_path"
                if [[ "$sub_dir" != "." ]]; then
                    dest_dir="$target_path/$sub_dir"
                fi
                mkdir -p "$dest_dir"
                cp -f "$file" "$dest_dir/$base_file"
            done
        fi
    done
}
