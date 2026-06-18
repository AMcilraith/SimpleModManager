die() {
    printf 'Error: %s\n' "$*" >&2
    if [[ -t 0 ]]; then
        printf 'Press Enter to exit...' >&2
        read -r
    fi
    exit 1
}

log() {
    printf '%s\n' "$*"
}

require_dir() {
    local path="$1"
    [[ -d "$path" ]] || die "Required directory not found: $path"
}

require_file() {
    local path="$1"
    [[ -f "$path" ]] || die "Required file not found: $path"
}

detect_steam_root() {
    if [[ -n "$STEAM_ROOT" ]]; then
        printf '%s\n' "$STEAM_ROOT"
        return 0
    fi
    local candidates=(
        "$HOME/.steam/steam"
        "$HOME/.local/share/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate/steamapps" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    die "Unable to locate Steam root. Set STEAM_ROOT to override."
}

get_steam_libraries() {
    local steam_root="$1"
    local library_file="$steam_root/steamapps/libraryfolders.vdf"
    printf '%s\n' "$steam_root"
    if [[ ! -f "$library_file" ]]; then return 0; fi
    sed -n 's/.*"[Pp][Aa][Tt][Hh]"[[:space:]]*"\([^"]*\)".*/\1/p' "$library_file" \
        | sed -e 's#\\\\#/#g' -e 's#/\+$##' \
        | awk '!seen[$0]++'
}

resolve_app_manifest() {
    local steam_root="$1"
    local library
    while IFS= read -r library; do
        [[ -n "$library" ]] || continue
        local steamapps="$library/steamapps"
        [[ -d "$steamapps" ]] || continue
        local manifest
        shopt -s nullglob
        for manifest in "$steamapps"/appmanifest_*.acf; do
            if grep -Eq '"name"[[:space:]]+"Subnautica 2"|"name"[[:space:]]+"Subnautica2"' "$manifest"; then
                printf '%s\n' "$manifest"
                shopt -u nullglob
                return 0
            fi
        done
        shopt -u nullglob
    done < <(get_steam_libraries "$steam_root")
    return 1
}

extract_app_id() {
    local manifest="$1"
    local base_name
    base_name="$(basename -- "$manifest")"
    [[ "$base_name" =~ ^appmanifest_([0-9]+)\.acf$ ]] || return 1
    printf '%s\n' "${BASH_REMATCH[1]}"
}

resolve_game_root() {
    if [[ -n "$TARGET_GAME_ROOT" ]]; then
        printf '%s\n' "$TARGET_GAME_ROOT"
        return 0
    fi
    local steam_root="$1"
    local library
    while IFS= read -r library; do
        [[ -n "$library" ]] || continue
        local base="$library/steamapps/common/Subnautica2"
        local candidate
        for candidate in "$base/Subnautica2" "$base"; do
            if [[ -d "$candidate/Content/Paks" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    done < <(get_steam_libraries "$steam_root")
    die "Unable to locate Subnautica2 game root. Set TARGET_GAME_ROOT to override."
}

resolve_local_appdata_root() {
    local steam_root="$1"
    local app_id="$2"
    local game_root="$3"
    local compat_root
    compat_root="$(cd -- "$(dirname -- "$game_root")/../../compatdata/$app_id/pfx/drive_c/users/steamuser/AppData/Local" 2>/dev/null && pwd || true)"
    if [[ -n "$compat_root" && -d "$compat_root" ]]; then
        printf '%s\n' "$compat_root"
        return 0
    fi
    local library
    while IFS= read -r library; do
        [[ -n "$library" ]] || continue
        local candidate="$library/steamapps/compatdata/$app_id/pfx/drive_c/users/steamuser/AppData/Local"
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(get_steam_libraries "$steam_root")
    die "Unable to locate Proton compatdata for app $app_id. Launch the game once in Steam or set TARGET_GAME_ROOT/STEAM_APP_ID correctly."
}

set_ini_value() {
    local path="$1"
    local key="$2"
    local value="$3"
    require_file "$path"
    if grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$path"; then
        sed -i -E "s|^[[:space:]]*$key[[:space:]]*=.*|$key = $value|" "$path"
    else
        printf '%s = %s\n' "$key" "$value" >> "$path"
    fi
}

resolve_context() {
    local steam_root
    steam_root="$(detect_steam_root)"
    local manifest
    if ! manifest="$(resolve_app_manifest "$steam_root")"; then
        die "Unable to determine Steam app manifest for Subnautica 2."
    fi
    local app_id="$STEAM_APP_ID"
    if [[ -z "$app_id" ]]; then
        app_id="$(extract_app_id "$manifest")" || die "Failed to extract Steam app ID from $manifest"
    fi
    local game_root
    game_root="$(resolve_game_root "$steam_root")"
    local local_appdata_root
    local_appdata_root="$(resolve_local_appdata_root "$steam_root" "$app_id" "$game_root")"
    
    # Common.sh is in Helpers/Linux
    local script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    local source_root="$(cd -- "$script_dir/../.." && pwd)"
    
    local enabled_mods="$source_root/ModManager/EnabledMods"
    local disabled_mods="$source_root/ModManager/DisabledMods"
    local ue4ss_root="$source_root/ModManager/UE4SS"
    local disabled_ue4ss="$source_root/ModManager/DisabledUE4SS"
    local engine_tweaks="$source_root/ModManager/EngineTweaks"
    local player_tweaks="$source_root/ModManager/PlayerTweaks"
    local mod_updates="$source_root/Helpers/ModUpdates"
    
    printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
        "$steam_root" "$app_id" "$game_root" "$local_appdata_root" \
        "$source_root" "$enabled_mods" "$disabled_mods" "$ue4ss_root" \
        "$disabled_ue4ss" "$engine_tweaks" "$player_tweaks" "$mod_updates"
}

show_help_popup() {
    local raw_title="$1"
    local description="$2"
    
    local clean_title
    clean_title="$(echo "$raw_title" | sed -E 's/^\[[a-zA-Z0-9]\][[:space:]]+//')"
    
    clear_terminal
    
    printf '%b┌────────────────────────────────────────────────────────────┐%b\n' "${C_CYAN}" "${C_NC}"
    printf '%b│%b%b%-60s%b%b│%b\n' "${C_CYAN}" "${C_NC}" "${C_YELLOW}" " HELP: $clean_title" "${C_NC}" "${C_CYAN}" "${C_NC}"
    printf '%b├────────────────────────────────────────────────────────────┤%b\n' "${C_CYAN}" "${C_NC}"
    
    local old_ifs="$IFS"
    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line=""
        IFS="$old_ifs"
        for word in $raw_line; do
            if (( ${#line} + ${#word} + 1 > 56 )); then
                printf '%b│%b  %-58s%b│%b\n' "${C_CYAN}" "${C_NC}" "$line" "${C_CYAN}" "${C_NC}"
                line="$word"
            else
                if [[ -z "$line" ]]; then
                    line="$word"
                else
                    line="$line $word"
                fi
            fi
        done
        if [[ -n "$line" ]]; then
            printf '%b│%b  %-58s%b│%b\n' "${C_CYAN}" "${C_NC}" "$line" "${C_CYAN}" "${C_NC}"
        else
            printf '%b│%b  %-58s%b│%b\n' "${C_CYAN}" "${C_NC}" "" "${C_CYAN}" "${C_NC}"
        fi
    done <<< "$description"
    
    printf '%b├────────────────────────────────────────────────────────────┤%b\n' "${C_CYAN}" "${C_NC}"
    printf '%b│%b  %-58s%b│%b\n' "${C_CYAN}" "${C_NC}" "Press any key to return..." "${C_CYAN}" "${C_NC}"
    printf '%b└────────────────────────────────────────────────────────────┘%b\n' "${C_CYAN}" "${C_NC}"
    
    local old_stty
    old_stty="$(stty -g 2>/dev/null || true)"
    if [[ -n "$old_stty" ]]; then
        stty raw -echo min 1
    fi
    dd bs=1 count=1 2>/dev/null
    if [[ -n "$old_stty" ]]; then
        stty "$old_stty"
    fi
}

get_menu_selection() {
    local title="$1"
    shift
    local options=("$@")
    
    export MENU_ACTION="Select"
    declare -A hotkey_map
    for i in "${!options[@]}"; do
        if [[ "${options[i]}" == "-" ]]; then continue; fi
        if [[ "${options[i]}" =~ \[([a-zA-Z0-9])\] ]]; then
            local key="${BASH_REMATCH[1]}"
            key="${key^^}"
            hotkey_map[$key]=$i
        fi
    done
    
    local cursor=0
    local options_count=${#options[@]}
    
    while [[ $cursor -lt $options_count && "${options[cursor]}" == "-" ]]; do
        ((cursor++))
    done
    if [[ $cursor -ge $options_count ]]; then cursor=0; fi
    
    while true; do
        clear_terminal
        
        printf '%b┌────────────────────────────────────────────────────────────┐%b\n' "${C_CYAN}" "${C_NC}"
        local pad=$(( (60 - ${#title}) / 2 ))
        local pad_str=""
        if [ $pad -gt 0 ]; then
            pad_str="$(printf '%*s' "$pad" '')"
        fi
        local header_line="${pad_str}${title}"
        printf '%b│%b%-60s%b│%b\n' "${C_CYAN}" "${C_NC}" "$header_line" "${C_CYAN}" "${C_NC}"
        printf '%b├────────────────────────────────────────────────────────────┤%b\n' "${C_CYAN}" "${C_NC}"
        
        for i in "${!options[@]}"; do
            if [[ "${options[i]}" == "-" ]]; then
                printf '%b├────────────────────────────────────────────────────────────┤%b\n' "${C_CYAN}" "${C_NC}"
                continue
            fi
            
            local prefix="   "
            local prefix_color="${C_NC}"
            local fg="${C_NC}"
            if [[ -n "${MENU_COLORS[i]:-}" ]]; then
                case "${MENU_COLORS[i]}" in
                    Green) fg="${C_GREEN}" ;;
                    Red) fg="${C_RED}" ;;
                    Yellow) fg="${C_YELLOW}" ;;
                    Gray) fg="${C_GRAY}" ;;
                    Cyan) fg="${C_CYAN}" ;;
                esac
            fi
            if [ $i -eq $cursor ]; then
                prefix="-->"
                prefix_color="${C_CYAN}"
            fi
            
            local opt="${options[i]}"
            if [[ "$opt" =~ ^(\[[0-9a-zA-Z]+\])(.*)$ ]]; then
                local num="${BASH_REMATCH[1]}"
                local rest="${BASH_REMATCH[2]}"
                local pad_len=$(( 56 - ${#num} - ${#rest} ))
                local pad=""
                if [ $pad_len -gt 0 ]; then
                    pad="$(printf '%*s' "$pad_len" '')"
                fi
                printf '%b│%b%b%s %b%b%s%b%s%s%b│%b\n' "${C_CYAN}" "${C_NC}" "${prefix_color}" "${prefix}" "${C_NC}" "${fg}" "$num" "${C_NC}" "$rest" "$pad" "${C_CYAN}" "${C_NC}"
            else
                printf '%b│%b%b%s %b%b%-56s%b%b│%b\n' "${C_CYAN}" "${C_NC}" "${prefix_color}" "${prefix}" "${C_NC}" "${fg}" "$opt" "${C_NC}" "${C_CYAN}" "${C_NC}"
            fi
        done
        
        printf '%b└────────────────────────────────────────────────────────────┘%b\n' "${C_CYAN}" "${C_NC}"
        
        local char=""
        local old_stty
        old_stty="$(stty -g 2>/dev/null || true)"
        if [[ -n "$old_stty" ]]; then
            stty raw -echo min 1 time 0
        fi
        char="$(dd bs=1 count=1 2>/dev/null)"
        if [[ -n "$old_stty" ]]; then
            stty "$old_stty"
        fi
        
        if [[ "$char" == $'\x1b' ]]; then
            local next_chars=""
            if [[ -n "$old_stty" ]]; then
                stty raw -echo min 0 time 1
            fi
            next_chars="$(dd bs=1 count=5 2>/dev/null)"
            if [[ -n "$old_stty" ]]; then
                stty "$old_stty"
            fi
            
            if [[ "$next_chars" == "[A" ]]; then
                while true; do
                    ((cursor--))
                    if [ $cursor -lt 0 ]; then cursor=$((options_count - 1)); fi
                    if [[ "${options[cursor]}" != "-" ]]; then break; fi
                done
            elif [[ "$next_chars" == "[1;5A" ]]; then
                export MENU_ACTION="CtrlUp"
                return $cursor
            elif [[ "$next_chars" == "[B" ]]; then
                while true; do
                    ((cursor++))
                    if [ $cursor -ge $options_count ]; then cursor=0; fi
                    if [[ "${options[cursor]}" != "-" ]]; then break; fi
                done
            elif [[ "$next_chars" == "[1;5B" ]]; then
                export MENU_ACTION="CtrlDown"
                return $cursor
            elif [[ -z "$next_chars" ]]; then
                export MENU_ACTION="Select"
                if [[ -n "${hotkey_map[X]:-}" ]]; then
                    return "${hotkey_map[X]}"
                fi
                if [[ -n "${hotkey_map[B]:-}" ]]; then
                    return "${hotkey_map[B]}"
                fi
                return 255
            fi
        elif [[ "$char" == "" || "$char" == $'\n' || "$char" == $'\r' ]]; then
            export MENU_ACTION="Toggle"
            return $cursor
        elif [[ "$char" == "h" || "$char" == "H" ]]; then
            if [[ -n "${MENU_DESCRIPTIONS[cursor]:-}" ]]; then
                show_help_popup "${options[cursor]}" "${MENU_DESCRIPTIONS[cursor]}"
            fi
        else
            local upper_char
            upper_char="$(printf '%s' "$char" | tr '[:lower:]' '[:upper:]')"
            if [[ -n "${hotkey_map[$upper_char]:-}" ]]; then
                export MENU_ACTION="Select"
                return "${hotkey_map[$upper_char]}"
            elif [[ "$upper_char" == "T" ]]; then
                export MENU_ACTION="Toggle"
                return $cursor
            elif [[ "$upper_char" == "D" ]]; then
                export MENU_ACTION="Delete"
                return $cursor
            fi
        fi
    done
}

get_current_load_order() {
    local enabled_path="$1"
    local disabled_path="$2"
    local load_order_file="$3"
    local is_ue4ss="$4"
    
    local existing_names=()
    if [[ -d "$enabled_path" ]]; then
        for dir in "$enabled_path"/*/; do
            [[ -d "$dir" ]] && existing_names+=("$(basename "$dir")")
        done
    fi
    if [[ -d "$disabled_path" ]]; then
        for dir in "$disabled_path"/*/; do
            [[ -d "$dir" ]] && existing_names+=("$(basename "$dir")")
        done
    fi
    
    if [[ "$is_ue4ss" -ne 1 ]]; then
        printf '%s\n' "${existing_names[@]}" | sort -u
        return 0
    fi

    local order=()
    if [[ "$is_ue4ss" -eq 1 ]]; then
        if [[ -f "$load_order_file" ]]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ ^[[:space:]]*([^;:][^:]+?)[[:space:]]*:[[:space:]]*(0|1) ]]; then
                    local name="${BASH_REMATCH[1]}"
                    name="${name#"${name%%[![:space:]]*}"}"
                    name="${name%"${name##*[![:space:]]}"}"
                    for m in "${existing_names[@]:-}"; do
                        if [[ "$m" == "$name" ]]; then
                            order+=("$name")
                            break
                        fi
                    done
                fi
            done < "$load_order_file"
        fi
    fi
    
    local missing=()
    for name in "${existing_names[@]:-}"; do
        local found=0
        for o in "${order[@]:-}"; do
            if [[ "$o" == "$name" ]]; then
                found=1
                break
            fi
        done
        if [[ $found -eq 0 ]]; then
            missing+=("$name")
        fi
    done
    
    local sorted_missing=()
    if [[ ${#missing[@]} -gt 0 ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && sorted_missing+=("$line")
        done < <(printf '%s\n' "${missing[@]}" | sort)
    fi
    
    for o in "${order[@]:-}"; do
        printf '%s\n' "$o"
    done
    for m in "${sorted_missing[@]:-}"; do
        printf '%s\n' "$m"
    done
}

save_current_load_order() {
    local load_order_file="$1"
    local enabled_path="$2"
    local is_ue4ss="$3"
    shift 3
    local order=("$@")
    
    if [[ "$is_ue4ss" -ne 1 ]]; then
        rm -f -- "$load_order_file"
        return 0
    fi

    if [[ "$is_ue4ss" -eq 1 ]]; then
        local enabled_mods=()
        if [[ -d "$enabled_path" ]]; then
            for dir in "$enabled_path"/*/; do
                [[ -d "$dir" ]] && enabled_mods+=("$(basename "$dir")")
            done
        fi
        
        local temp_file
        temp_file="$(mktemp)"
        for name in "${order[@]:-}"; do
            [[ -n "$name" ]] || continue
            if [[ "$name" == "Keybinds" || "$name" == "UnlockAllConstructs" ]]; then continue; fi
            local state="0"
            for m in "${enabled_mods[@]:-}"; do
                if [[ "$m" == "$name" ]]; then
                    state="1"
                    break
                fi
            done
            printf '%s : %s\n' "$name" "$state" >> "$temp_file"
        done
        
        printf '\n; Built-in keybinds, do not move up!\n' >> "$temp_file"
        local keybind_state="0"
        for m in "${enabled_mods[@]:-}"; do
            if [[ "$m" == "Keybinds" ]]; then
                keybind_state="1"
                break
            fi
        done
        printf 'Keybinds : %s\n' "$keybind_state" >> "$temp_file"
        printf 'UnlockAllConstructs : 1\n' >> "$temp_file"
        
        mv -f "$temp_file" "$load_order_file"
    fi
}
