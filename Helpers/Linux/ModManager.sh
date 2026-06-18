#!/usr/bin/env bash

# Colors
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[1;33m'
C_GRAY='\033[1;30m'
C_NC='\033[0m'

show_toggle_menu() {
    local title="$1"
    local enabled_path="$2"
    local disabled_path="$3"
    
    local cursor=0
    
    local is_ue4ss=0
    if [[ "$title" == *"UE4SS"* ]]; then
        is_ue4ss=1
    fi
    local load_order_file=""
    if [[ $is_ue4ss -eq 1 ]]; then
        load_order_file="$enabled_path/mods.txt"
    else
        load_order_file="$enabled_path/loadorder.txt"
    fi
    
    while true; do
        local enabled_mods=()
        if [[ -d "$enabled_path" ]]; then
            for dir in "$enabled_path"/*/; do
                [[ -d "$dir" ]] && enabled_mods+=("$(basename "$dir")")
            done
        fi
        
        local disabled_mods=()
        if [[ -d "$disabled_path" ]]; then
            for dir in "$disabled_path"/*/; do
                [[ -d "$dir" ]] && disabled_mods+=("$(basename "$dir")")
            done
        fi
        
        # Load load order
        local all_names=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && all_names+=("$line")
        done < <(get_current_load_order "$enabled_path" "$disabled_path" "$load_order_file" "$is_ue4ss")
        
        if [[ $is_ue4ss -eq 1 && ! -f "$load_order_file" ]]; then
            save_current_load_order "$load_order_file" "$enabled_path" "$is_ue4ss" "${all_names[@]}"
        fi
        
        local mods=()
        local sources=()
        local targets=()
        local states=()
        local options=()
        local -a MENU_COLORS=()
        local -a MENU_DESCRIPTIONS=()
        local idx=1
        
        for name in ${all_names[@]+"${all_names[@]}"}; do
            [[ -n "$name" ]] || continue
            # Check if enabled
            local is_enabled=0
            for m in ${enabled_mods[@]+"${enabled_mods[@]}"}; do
                if [[ "$m" == "$name" ]]; then
                    is_enabled=1
                    break
                fi
            done
            
            local source=""
            local target=""
            local state=""
            local color=""
            if [[ $is_enabled -eq 1 ]]; then
                source="$enabled_path/$name"
                target="$disabled_path/$name"
                state="Enabled"
                color="Green"
            else
                source="$disabled_path/$name"
                target="$enabled_path/$name"
                state="Disabled"
                color="Red"
            fi
            
            options+=("[$idx] $name")
            mods+=("$name")
            sources+=("$source")
            targets+=("$target")
            states+=("$state")
            MENU_COLORS+=("$color")
            MENU_DESCRIPTIONS+=("Mod: $name (Currently $state). Press [Enter]/[T] to toggle or [D] to delete.")
            ((idx++))
        done
        
        get_menu_selection "$title" "${options[@]}"
        local choice=$?
        local action="${MENU_ACTION:-Select}"
        
        if [[ $choice -eq 255 ]]; then
            return 0
        fi
        
        local mods_count=${#mods[@]}
        if [[ $choice -lt $mods_count ]]; then
            local selected_name="${mods[$choice]}"
            local selected_source="${sources[$choice]}"
            local selected_target="${targets[$choice]}"
            local selected_state="${states[$choice]}"
            
            if [[ "$action" == "CtrlUp" || "$action" == "CtrlDown" ]]; then
                log "Load order editing is disabled."
                sleep 0.25
                continue
            fi
            
            if [[ "$action" == "Delete" ]]; then
                clear_terminal
                printf '\n%bWARNING: You are about to permanently delete mod: %s%b\n' "${C_YELLOW}" "$selected_name" "${C_NC}"
                read -r -p "Are you sure you want to proceed? (y/N): " confirm
                if [[ "$confirm" =~ ^[yY]$ ]]; then
                    rm -rf "$selected_source"
                    local new_order=()
                    for item in "${all_names[@]}"; do
                        if [[ "$item" != "$selected_name" ]]; then
                            new_order+=("$item")
                        fi
                    done
                    save_current_load_order "$load_order_file" "$enabled_path" "$is_ue4ss" "${new_order[@]}"
                    log "Deleted mod $selected_name."
                    sleep 0.5
                fi
            else
                # Toggle
                local target_dir
                target_dir="$(dirname "$selected_target")"
                mkdir -p "$target_dir"
                mv "$selected_source" "$selected_target"
                if [[ $is_ue4ss -eq 1 ]]; then
                    save_current_load_order "$load_order_file" "$enabled_path" "$is_ue4ss" "${all_names[@]}"
                fi
                local new_state="Enabled"
                if [[ "$selected_state" == "Enabled" ]]; then
                    new_state="Disabled"
                fi
                log "Toggled $selected_name to $new_state"
                sleep 0.25
            fi
            cursor=$choice
        fi
    done
}

show_engine_tweak_menu() {
    local cursor=0
    while true; do
        local active_ini="$PLAYER_TWEAKS/engine.ini"
        local status_str="Status: Default (No Tweak)"
        if [[ -f "$active_ini" ]]; then
            status_str="Status: Active Custom Tweak"
        fi
        
        local tweaks=()
        local sources=()
        local options=()
        local -a MENU_COLORS=()
        local -a MENU_DESCRIPTIONS=()
        local idx=1
        
        if [[ -d "$ENGINE_TWEAKS" ]]; then
            local quality_order=("High-Quality" "Balanced-Quality" "Balanced-Performance" "High-Performance" "Ultra-Performance" "Potato-PC")
            for name in "${quality_order[@]}"; do
                local dir="$ENGINE_TWEAKS/$name"
                if [[ -d "$dir" ]]; then
                    local ini_file
                    ini_file="$(find "$dir" -iname 'Engine.ini' -type f -print -quit)"
                    if [[ -n "$ini_file" ]]; then
                        options+=("[$idx] Apply $name Preset")
                        local desc=""
                        case "$name" in
                            # "Ultra-Quality" entry and description fully removed (fix syntax)
                            "High-Quality")
                                desc=$'High Quality Preset\n\nWhat this config focuses on:\n- Texture streaming behavior\n- Async loading and IO behavior\n- Shader pipeline cache / PSO behavior\n- Garbage collection tuning\n- General frame-time stability\n\nWhat this config does NOT try to do:\n- No intentional visual downgrade\n- No forced low LOD look\n- No color or tonemapper overhaul\n- No aggressive shadow or lighting cuts\n- No Lumen disable\n- No Nanite disable\n- No Virtual Shadow Map disable\n- No \'potato mode\' changes\n\nNote: Removes post-process clutter like motion blur, lens flares, film grain, and chromatic aberration.'
                                ;;
                            "Balanced-Quality")
                                desc=$'Balanced Quality Preset\n\nWhat this config focuses on:\n- Texture streaming behavior\n- Async loading and IO behavior\n- Shader pipeline cache / PSO behavior\n- Garbage collection tuning\n- General frame-time stability\n\nWhat this config does NOT try to do:\n- No intentional visual downgrade\n- No forced low LOD look\n- No color or tonemapper overhaul\n- No aggressive shadow or lighting cuts\n- No Lumen disable\n- No Nanite disable\n- No Virtual Shadow Map disable\n- No \'potato mode\' changes\n\nNote: Purely lossless performance/streaming optimization with no visual changes.'
                                ;;
                            "Balanced-Performance")
                                desc=$'Balanced Performance Preset\n\nThis preset keeps most visuals intact while disabling expensive shadow features such as Dynamic Global Illumination for better performance without heavily changing the game\'s appearance.\n\n(Disables Lumen, so interior lights may be less effective at illuminating your base. Just put some extra lights, and it should be fine.)'
                                ;;
                            "High-Performance")
                                desc=$'High Performance Preset\n\nThis preset fully disables shadows and some other visual effects to provide the highest possible FPS boost without hurting graphics too much.\n\n(Disables Lumen, so interior lights may be less effective at illuminating your base. Just put some extra lights, and it should be fine.)'
                                ;;
                            "Ultra-Performance")
                                desc=$'Ultra Performance Preset\n\nThis preset removes almost all visual effects for the maximum possible FPS increase, significantly reducing graphical quality in exchange for the highest performance gains.\n\n(Disables Lumen, so interior lights may be less effective at illuminating your base. Just put some extra lights, and it should be fine.)'
                                ;;
                            "Potato-PC")
                                desc=$'Potato PC Preset\n\nThis preset removes basically all visual effects from the game. It is not recommended, but if you really want to play, this may be your last option.\n\n(Disables Lumen, so interior lights may be less effective at illuminating your base. Just put some extra lights, and it should be fine.)'
                                ;;
                            *)
                                desc="Applies the custom engine.ini preset from $name to optimize game graphics/performance."
                                ;;
                        esac
                        MENU_DESCRIPTIONS+=("$desc")
                        tweaks+=("$name")
                        sources+=("$ini_file")
                        ((idx++))
                    fi
                fi
            done
        fi
        
        local fetch_idx=${#options[@]}
        options+=("-")
        MENU_DESCRIPTIONS+=("")
        options+=("[F] Fetch presets from Nexus")
        MENU_DESCRIPTIONS+=("Downloads Engine.ini presets from Nexus Mods 51 (performance) and 37 (quality). Requires NEXUS_API_KEY in Helpers/.env.

$(get_engine_tweak_nexus_links_text)")
        local perf_link_idx=${#options[@]}
        options+=("[P] Open Performance presets (Nexus mod 51)")
        MENU_DESCRIPTIONS+=("Opens Ghostiexd's Subnautica 2 Performance Mod in your browser:
https://www.nexusmods.com/subnautica2/mods/51")
        local qual_link_idx=${#options[@]}
        options+=("[Q] Open Quality presets (Nexus mod 37)")
        MENU_DESCRIPTIONS+=("Opens Vercadi's quality Engine.ini tweaks in your browser:
https://www.nexusmods.com/subnautica2/mods/37")
        options+=("-")
        MENU_DESCRIPTIONS+=("")
        options+=("[D] Disable current Engine Tweak")
        MENU_DESCRIPTIONS+=("Disables the current active custom engine.ini tweak preset, reverting back to game defaults.")
        local disable_idx=$((${#options[@]} - 1))
        
        get_menu_selection "ENGINE TWEAKS ($status_str)" "${options[@]}"
        local choice=$?
        
        if [[ $choice -eq 255 ]]; then
            return 0
        fi
        
        if [[ $choice -eq $fetch_idx ]]; then
            invoke_fetch_engine_tweaks
            sleep 0.6
            continue
        fi
        if [[ $choice -eq $perf_link_idx ]]; then
            open_engine_tweak_nexus_url 'https://www.nexusmods.com/subnautica2/mods/51'
            continue
        fi
        if [[ $choice -eq $qual_link_idx ]]; then
            open_engine_tweak_nexus_url 'https://www.nexusmods.com/subnautica2/mods/37'
            continue
        fi
        
        if [[ $choice -eq $disable_idx ]]; then
            if [[ -f "$active_ini" ]]; then
                rm -f "$active_ini"
                log "Engine Tweak disabled."
            else
                log "Engine Tweak already disabled."
            fi
            sleep 0.35
            continue
        fi
        
        local tweaks_count=${#tweaks[@]}
        if [[ $choice -lt $tweaks_count ]]; then
            mkdir -p "$PLAYER_TWEAKS"
            cp -f "${sources[$choice]}" "$active_ini"
            log "Applied ${tweaks[$choice]} preset!"
            sleep 0.35
            cursor=$choice
        fi
    done
}

install_mod_from_zip() {
    printf '\n'
    read -r -p "Enter path to the mod/modpack .zip file: " zip_path
    zip_path="${zip_path#"${zip_path%%[![:space:]]*}"}"
    zip_path="${zip_path%"${zip_path##*[![:space:]]}"}"
    
    if [[ -z "$zip_path" ]]; then return 0; fi
    
    if [[ ! -f "$zip_path" ]]; then
        log "Error: File not found at $zip_path"
        sleep 2
        return 0
    fi
    
    local resolved_zip
    resolved_zip="$(realpath "$zip_path")"
    log "Extracting $resolved_zip to temporary folder..."
    
    local temp_dir="/tmp/sn2_install_$$"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    if ! unzip -q "$resolved_zip" -d "$temp_dir"; then
        log "Error: Failed to extract zip."
        rm -rf "$temp_dir"
        sleep 3
        return 0
    fi
    
    local found_structured=0
    
    local search_dirs=("$temp_dir")
    while IFS= read -r -d '' d; do
        search_dirs+=("$d")
    done < <(find "$temp_dir" -maxdepth 2 -type d -print0)
    
    for dir in "${search_dirs[@]}"; do
        local has_mods=0
        local has_paks=0
        local has_logic=0
        
        [[ -d "$dir/Mods" ]] && has_mods=1
        [[ -d "$dir/~mods" ]] && has_paks=1
        [[ -d "$dir/LogicMods" ]] && has_logic=1
        
        if [[ $has_mods -eq 1 || $has_paks -eq 1 || $has_logic -eq 1 ]]; then
            log "Found structured modpack layout at: $(basename "$dir")"
            if [[ $has_mods -eq 1 ]]; then
                log "  Copying UE4SS Mods..."
                copy_merge_dir_contents "$dir/Mods" "$ENABLED_MODS/Mods"
            fi
            if [[ $has_paks -eq 1 ]]; then
                log "  Copying BP Patch Pak Mods..."
                copy_merge_dir_contents "$dir/~mods" "$ENABLED_MODS/~mods"
            fi
            if [[ $has_logic -eq 1 ]]; then
                log "  Copying BP Logic Pak Mods..."
                copy_merge_dir_contents "$dir/LogicMods" "$ENABLED_MODS/LogicMods"
            fi
            found_structured=1
            break
        fi
    done
    
    if [[ $found_structured -eq 0 ]]; then
        log "Analyzing individual mod files..."
        
        local main_lua
        main_lua="$(find "$temp_dir" -type f -name "main.lua" | grep -i "/Scripts/main.lua" | head -n 1)"
        
        if [[ -n "$main_lua" ]]; then
            local scripts_dir
            scripts_dir="$(dirname "$main_lua")"
            local mod_folder
            mod_folder="$(dirname "$scripts_dir")"
            local mod_name
            mod_name="$(basename "$mod_folder")"
            
            log "Detected UE4SS Mod: $mod_name"
            copy_merge_dir_contents "$mod_folder" "$ENABLED_MODS/Mods/$mod_name"
        else
            local pak_files=()
            while IFS= read -r -d '' f; do
                pak_files+=("$f")
            done < <(find "$temp_dir" -type f -name "*.pak" -print0)
            
            if [[ ${#pak_files[@]} -gt 0 ]]; then
                for pak in "${pak_files[@]}"; do
                    if echo "$pak" | grep -qi "LogicMods"; then
                        log "Detected BP Logic Pak Mod: $(basename "$pak")"
                        mkdir -p "$ENABLED_MODS/LogicMods"
                        cp -f "$pak" "$ENABLED_MODS/LogicMods/"
                    else
                        log "Detected BP Patch Pak Mod: $(basename "$pak")"
                        mkdir -p "$ENABLED_MODS/~mods"
                        cp -f "$pak" "$ENABLED_MODS/~mods/"
                    fi
                done
            else
                log "Warning: No recognizable .pak files or UE4SS scripts found in the zip."
            fi
        fi
    fi
    
    rm -rf "$temp_dir"
    log "Success: Mod files successfully extracted and categorized."
    sleep 2
    return 0
}

get_ordered_enabled_mods() {
    local enabled_path="$1"
    local disabled_path="$2"
    local is_ue4ss="${3:-0}"
    local load_order_file=""
    if [[ "$is_ue4ss" -eq 1 ]]; then
        load_order_file="$enabled_path/mods.txt"
    else
        load_order_file="$enabled_path/loadorder.txt"
    fi

    local enabled_dirs=()
    if [[ -d "$enabled_path" ]]; then
        for dir in "$enabled_path"/*/; do
            [[ -d "$dir" ]] && enabled_dirs+=("$(basename "$dir")")
        done
    fi

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        for enabled_name in "${enabled_dirs[@]:-}"; do
            if [[ "$enabled_name" == "$name" ]]; then
                printf '%s\n' "$name"
                break
            fi
        done
    done < <(get_current_load_order "$enabled_path" "$disabled_path" "$load_order_file" "$is_ue4ss")
}

apply_collection_mod_state() {
    local title="$1"
    local enabled_path="$2"
    local disabled_path="$3"
    local is_ue4ss="$4"
    shift 4
    local desired_enabled=("$@")

    local load_order_file=""
    if [[ "$is_ue4ss" -eq 1 ]]; then
        load_order_file="$enabled_path/mods.txt"
    else
        load_order_file="$enabled_path/loadorder.txt"
    fi

    local all_names=()
    while IFS= read -r name; do
        [[ -n "$name" ]] && all_names+=("$name")
    done < <(get_current_load_order "$enabled_path" "$disabled_path" "$load_order_file" "$is_ue4ss")

    local ordered_desired=()
    local missing=()
    for desired_name in "${desired_enabled[@]:-}"; do
        [[ -n "$desired_name" ]] || continue
        local already_seen=0
        for existing_desired in "${ordered_desired[@]:-}"; do
            if [[ "$existing_desired" == "$desired_name" ]]; then
                already_seen=1
                break
            fi
        done
        if [[ $already_seen -eq 1 ]]; then
            continue
        fi

        local exists_locally=0
        for known_name in "${all_names[@]:-}"; do
            if [[ "$known_name" == "$desired_name" ]]; then
                exists_locally=1
                break
            fi
        done

        if [[ $exists_locally -eq 1 ]]; then
            ordered_desired+=("$desired_name")
        else
            missing+=("$desired_name")
        fi
    done

    for name in "${all_names[@]:-}"; do
        local should_enable=0
        for desired_name in "${ordered_desired[@]:-}"; do
            if [[ "$desired_name" == "$name" ]]; then
                should_enable=1
                break
            fi
        done

        local enabled_item="$enabled_path/$name"
        local disabled_item="$disabled_path/$name"
        if [[ $should_enable -eq 1 && ! -d "$enabled_item" && -d "$disabled_item" ]]; then
            mkdir -p "$enabled_path"
            mv "$disabled_item" "$enabled_item"
        elif [[ $should_enable -eq 0 && -d "$enabled_item" ]]; then
            mkdir -p "$disabled_path"
            mv "$enabled_item" "$disabled_item"
        fi
    done

    local new_order=("${ordered_desired[@]:-}")
    for name in "${all_names[@]:-}"; do
        local keep_existing=1
        for desired_name in "${ordered_desired[@]:-}"; do
            if [[ "$desired_name" == "$name" ]]; then
                keep_existing=0
                break
            fi
        done
        if [[ $keep_existing -eq 1 ]]; then
            new_order+=("$name")
        fi
    done
    save_current_load_order "$load_order_file" "$enabled_path" "$is_ue4ss" "${new_order[@]}"

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "$title collection entries not found locally: ${missing[*]}"
    fi
}

reset_player_tweaks_directory() {
    mkdir -p "$PLAYER_TWEAKS"
    find "$PLAYER_TWEAKS" -mindepth 1 -exec rm -rf -- {} +
}

get_collection_manifest_lines() {
    printf '# Addi-Pack Collection Zip v2\n'
    printf '[UE4SS Mods]\n'
    get_ordered_enabled_mods "$ENABLED_MODS/Mods" "$DISABLED_MODS/Mods" 1
    printf '\n[BP Patch Mods]\n'
    get_ordered_enabled_mods "$ENABLED_MODS/~mods" "$DISABLED_MODS/~mods" 0
    printf '\n[BP Logic Mods]\n'
    get_ordered_enabled_mods "$ENABLED_MODS/LogicMods" "$DISABLED_MODS/LogicMods" 0
}

copy_collection_directory() {
    local source_path="$1"
    local destination_path="$2"

    [[ -d "$source_path" ]] || return 0

    mkdir -p "$(dirname -- "$destination_path")"
    rm -rf -- "$destination_path"
    cp -R -- "$source_path" "$destination_path"
}

export_collection_category() {
    local enabled_path="$1"
    local disabled_path="$2"
    local export_path="$3"
    local is_ue4ss="${4:-0}"

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        copy_collection_directory "$enabled_path/$name" "$export_path/$name"
    done < <(get_ordered_enabled_mods "$enabled_path" "$disabled_path" "$is_ue4ss")
}

read_collection_manifest() {
    local manifest_path="$1"
    local section=""

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line="${raw_line%$'\r'}"
        [[ -n "$line" ]] || continue
        [[ "$line" == \#* ]] && continue
        case "$line" in
            "[UE4SS Mods]")
                section="ue4ss"
                continue
                ;;
            "[BP Patch Mods]")
                section="bp_patch"
                continue
                ;;
            "[BP Logic Mods]")
                section="bp_logic"
                continue
                ;;
        esac

        case "$section" in
            ue4ss)
                printf 'ue4ss|%s\n' "$line"
                ;;
            bp_patch)
                printf 'bp_patch|%s\n' "$line"
                ;;
            bp_logic)
                printf 'bp_logic|%s\n' "$line"
                ;;
        esac
    done < "$manifest_path"
}

import_collection_category() {
    local title="$1"
    local enabled_path="$2"
    local disabled_path="$3"
    local import_path="$4"
    local is_ue4ss="$5"
    shift 5
    local desired_enabled=("$@")

    local load_order_file=""
    if [[ "$is_ue4ss" -eq 1 ]]; then
        load_order_file="$enabled_path/mods.txt"
    else
        load_order_file="$enabled_path/loadorder.txt"
    fi

    local all_names=()
    while IFS= read -r name; do
        [[ -n "$name" ]] && all_names+=("$name")
    done < <(get_current_load_order "$enabled_path" "$disabled_path" "$load_order_file" "$is_ue4ss")

    local ordered_desired=()
    local missing=()
    for desired_name in "${desired_enabled[@]:-}"; do
        [[ -n "$desired_name" ]] || continue

        local already_seen=0
        for existing_desired in "${ordered_desired[@]:-}"; do
            if [[ "$existing_desired" == "$desired_name" ]]; then
                already_seen=1
                break
            fi
        done
        if [[ $already_seen -eq 1 ]]; then
            continue
        fi

        local enabled_item="$enabled_path/$desired_name"
        local disabled_item="$disabled_path/$desired_name"
        local source_item="$import_path/$desired_name"

        if [[ -d "$source_item" ]]; then
            copy_collection_directory "$source_item" "$enabled_item"
            rm -rf -- "$disabled_item"

            local known_name=0
            for existing_name in "${all_names[@]:-}"; do
                if [[ "$existing_name" == "$desired_name" ]]; then
                    known_name=1
                    break
                fi
            done
            if [[ $known_name -eq 0 ]]; then
                all_names+=("$desired_name")
            fi

            ordered_desired+=("$desired_name")
            continue
        fi

        if [[ -d "$disabled_item" ]]; then
            mkdir -p "$enabled_path"
            mv "$disabled_item" "$enabled_item"
            ordered_desired+=("$desired_name")
            continue
        fi

        if [[ -d "$enabled_item" ]]; then
            ordered_desired+=("$desired_name")
            continue
        fi

        missing+=("$desired_name")
    done

    for name in "${all_names[@]:-}"; do
        local should_enable=0
        for desired_name in "${ordered_desired[@]:-}"; do
            if [[ "$desired_name" == "$name" ]]; then
                should_enable=1
                break
            fi
        done
        if [[ $should_enable -eq 1 ]]; then
            continue
        fi

        local enabled_item="$enabled_path/$name"
        local disabled_item="$disabled_path/$name"
        if [[ -d "$enabled_item" ]]; then
            mkdir -p "$disabled_path"
            rm -rf -- "$disabled_item"
            mv "$enabled_item" "$disabled_item"
        fi
    done

    local new_order=()
    for name in "${ordered_desired[@]:-}"; do
        new_order+=("$name")
    done
    for name in "${all_names[@]:-}"; do
        local keep_existing=1
        for desired_name in "${ordered_desired[@]:-}"; do
            if [[ "$desired_name" == "$name" ]]; then
                keep_existing=0
                break
            fi
        done
        if [[ $keep_existing -eq 1 ]]; then
            new_order+=("$name")
        fi
    done
    save_current_load_order "$load_order_file" "$enabled_path" "$is_ue4ss" "${new_order[@]}"

    if [[ ${#missing[@]} -gt 0 ]]; then
        log "$title collection entries not found in the zip or local mod library: ${missing[*]}"
    fi
}

export_mod_collection() {
    printf '\n'
    read -r -p "Enter the path for the collection zip file (.zip suggested): " file_path
    file_path="${file_path#"${file_path%%[![:space:]]*}"}"
    file_path="${file_path%"${file_path##*[![:space:]]}"}"
    if [[ -z "$file_path" ]]; then
        return 0
    fi

    local resolved_path
    resolved_path="$(realpath -m "$file_path")"
    if [[ "$resolved_path" != *.zip ]]; then
        resolved_path="$resolved_path.zip"
    fi
    mkdir -p "$(dirname -- "$resolved_path")"

    local temp_dir="/tmp/sn2_collection_export_$$"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    export_collection_category "$ENABLED_MODS/Mods" "$DISABLED_MODS/Mods" "$temp_dir/Mods" 1
    export_collection_category "$ENABLED_MODS/~mods" "$DISABLED_MODS/~mods" "$temp_dir/~mods" 0
    export_collection_category "$ENABLED_MODS/LogicMods" "$DISABLED_MODS/LogicMods" "$temp_dir/LogicMods" 0

    if [[ -d "$PLAYER_TWEAKS" ]]; then
        copy_merge_dir_contents "$PLAYER_TWEAKS" "$temp_dir/PlayerTweaks"
    fi

    get_collection_manifest_lines > "$temp_dir/collection_manifest.txt"
    rm -f -- "$resolved_path"
    (
        cd "$temp_dir"
        zip -qr "$resolved_path" .
    )
    rm -rf "$temp_dir"

    log "Collection exported to $resolved_path"
    sleep 0.9
    return 0
}

import_mod_collection() {
    printf '\n'
    read -r -p "Enter the path to the collection zip file: " file_path
    file_path="${file_path#"${file_path%%[![:space:]]*}"}"
    file_path="${file_path%"${file_path##*[![:space:]]}"}"
    if [[ -z "$file_path" ]]; then
        return 0
    fi

    local resolved_path
    resolved_path="$(realpath -m "$file_path")"
    if [[ ! -f "$resolved_path" ]]; then
        log "Collection file not found: $resolved_path"
        sleep 2
        return 0
    fi

    local ue4ss_mods=()
    local bp_patch_mods=()
    local bp_logic_mods=()
    local temp_dir="/tmp/sn2_collection_import_$$"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    unzip -q "$resolved_path" -d "$temp_dir"

    local manifest_path="$temp_dir/collection_manifest.txt"
    if [[ ! -f "$manifest_path" ]]; then
        rm -rf "$temp_dir"
        log "Collection zip is missing collection_manifest.txt"
        sleep 2
        return 0
    fi

    while IFS= read -r entry; do
        local section_name="${entry%%|*}"
        local mod_name="${entry#*|}"
        case "$section_name" in
            ue4ss)
                ue4ss_mods+=("$mod_name")
                ;;
            bp_patch)
                bp_patch_mods+=("$mod_name")
                ;;
            bp_logic)
                bp_logic_mods+=("$mod_name")
                ;;
        esac
    done < <(read_collection_manifest "$manifest_path")

    import_collection_category "UE4SS Mods" "$ENABLED_MODS/Mods" "$DISABLED_MODS/Mods" "$temp_dir/Mods" 1 "${ue4ss_mods[@]}"
    import_collection_category "BP Patch Mods" "$ENABLED_MODS/~mods" "$DISABLED_MODS/~mods" "$temp_dir/~mods" 0 "${bp_patch_mods[@]}"
    import_collection_category "BP Logic Mods" "$ENABLED_MODS/LogicMods" "$DISABLED_MODS/LogicMods" "$temp_dir/LogicMods" 0 "${bp_logic_mods[@]}"

    reset_player_tweaks_directory
    if [[ -d "$temp_dir/PlayerTweaks" ]]; then
        copy_merge_dir_contents "$temp_dir/PlayerTweaks" "$PLAYER_TWEAKS"
    fi

    rm -rf "$temp_dir"

    log "Collection imported from $resolved_path"
    sleep 0.9
    return 0
}

start_mod_manager() {
    local cursor=0
    while true; do
        local options=(
            "[1] Toggle UE4SS Mods"
            "[2] Toggle BP Patch Mods"
            "[3] Toggle BP Logic Mods"
            "[4] Engine Tweaks"
            "[5] Install Mod from Zip"
            "[6] Export Collection"
            "[7] Import Collection"
        )
        local -a MENU_COLORS=()
        local -a MENU_DESCRIPTIONS=(
            "View and toggle Lua-based scripting mods that run via the UE4SS framework."
            "View and toggle BP patch (.pak) mods located in the ~mods folder."
            "View and toggle BP logic (.pak) mods located in the LogicMods folder."
            "Choose, apply, or disable custom engine configuration presets to tweak game graphics and performance."
            "Import and automatically install new mods or modpacks directly from a downloaded .zip file."
            "Save the current enabled mods and PlayerTweaks config files into a reusable collection file."
            "Load a collection file to restore a saved set of enabled mods and PlayerTweaks config files."
        )
        get_menu_selection "MOD MANAGER" "${options[@]}"
        local choice=$?
        
        case "$choice" in
            0)
                show_toggle_menu "UE4SS Mods" "$ENABLED_MODS/Mods" "$DISABLED_MODS/Mods"
                cursor=0
                ;;
            1)
                show_toggle_menu "BP Patch Mods (~mods)" "$ENABLED_MODS/~mods" "$DISABLED_MODS/~mods"
                cursor=1
                ;;
            2)
                show_toggle_menu "BP Logic Mods" "$ENABLED_MODS/LogicMods" "$DISABLED_MODS/LogicMods"
                cursor=2
                ;;
            3)
                show_engine_tweak_menu
                cursor=3
                ;;
            4)
                install_mod_from_zip
                cursor=4
                ;;
            5)
                export_mod_collection
                cursor=5
                ;;
            6)
                import_mod_collection
                cursor=6
                ;;
            255)
                return 0
                ;;
        esac
    done
}
