#!/usr/bin/env bash

ENGINE_TWEAK_NEXUS_SOURCES=(
    "51|Performance|Ghostiexd|https://www.nexusmods.com/subnautica2/mods/51|Balanced-Performance,High-Performance,Ultra-Performance,Potato-PC"
    "37|Quality|Vercadi|https://www.nexusmods.com/subnautica2/mods/37|High-Quality,Balanced-Quality"
)

get_engine_tweak_nexus_links_text() {
    local entry mod_id label credit url
    for entry in "${ENGINE_TWEAK_NEXUS_SOURCES[@]}"; do
        IFS='|' read -r mod_id label credit url _ <<< "$entry"
        printf '%s (%s): %s\n' "$label" "$credit" "$url"
    done
}

open_engine_tweak_nexus_url() {
    local url="$1"
    [[ -n "$url" ]] || return 0
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 &
    else
        log "Open in browser: $url"
    fi
}

get_nexus_api_key() {
    if [[ -n "${NEXUS_API_KEY:-}" ]]; then
        printf '%s' "$NEXUS_API_KEY" | tr -d '\r' | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
        return 0
    fi
    return 1
}

resolve_engine_preset_folder_name() {
    local hint="$1"
    local normalized
    normalized="$(printf '%s' "$hint" | tr '[:upper:]' '[:lower:]' | sed -E 's/[_-]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
    [[ -n "$normalized" ]] || return 1

    case "$normalized" in
        *potato*) printf '%s\n' 'Potato-PC'; return 0 ;;
        *ultra*performance*) printf '%s\n' 'Ultra-Performance'; return 0 ;;
        *balanced*performance*) printf '%s\n' 'Balanced-Performance'; return 0 ;;
        *high*performance*) printf '%s\n' 'High-Performance'; return 0 ;;
        *performance*) printf '%s\n' 'High-Performance'; return 0 ;;
        *balanced*quality*) printf '%s\n' 'Balanced-Quality'; return 0 ;;
        *high*quality*) printf '%s\n' 'High-Quality'; return 0 ;;
    esac

    local entry presets preset preset_norm
    for entry in "${ENGINE_TWEAK_NEXUS_SOURCES[@]}"; do
        IFS='|' read -r _ _ _ _ presets <<< "$entry"
        IFS=',' read -ra preset_list <<< "$presets"
        for preset in "${preset_list[@]}"; do
            preset_norm="$(printf '%s' "$preset" | tr '[:upper:]' '[:lower:]' | sed -E 's/[_-]+/ /g')"
            if [[ "$normalized" == "$preset_norm" || "$normalized" == *"$preset_norm"* ]]; then
                printf '%s\n' "$preset"
                return 0
            fi
        done
    done
    return 1
}

import_engine_ini_from_archive() {
    local extract_root="$1"
    local allowed_csv="$2"
    local imported=()
    local ini_file relative folder_hint preset_folder dest_dir

    while IFS= read -r ini_file; do
        [[ -n "$ini_file" ]] || continue
        relative="${ini_file#"$extract_root"/}"
        folder_hint="$(dirname "$relative")"
        if [[ "$folder_hint" == "." ]]; then
            folder_hint="$(basename "$ini_file" .ini)"
        fi
        folder_hint="${folder_hint##*/}"

        preset_folder="$(resolve_engine_preset_folder_name "$folder_hint" || true)"
        if [[ -z "$preset_folder" ]]; then
            preset_folder="$(resolve_engine_preset_folder_name "$relative" || true)"
        fi
        [[ -n "$preset_folder" ]] || continue

        if [[ -n "$allowed_csv" ]] && ! echo ",$allowed_csv," | grep -q ",$preset_folder,"; then
            continue
        fi

        dest_dir="$ENGINE_TWEAKS/$preset_folder"
        mkdir -p "$dest_dir"
        cp -f "$ini_file" "$dest_dir/Engine.ini"
        if ! printf '%s\n' "${imported[@]:-}" | grep -qx "$preset_folder"; then
            imported+=("$preset_folder")
        fi
        log "  Installed $preset_folder preset"
    done < <(find "$extract_root" -iname 'Engine.ini' -type f 2>/dev/null)

    printf '%s\n' "${imported[@]:-}"
}

invoke_fetch_engine_tweaks_from_nexus() {
    local filter_ids="${1:-}"
    local api_key
    api_key="$(get_nexus_api_key || true)"
    if [[ -z "$api_key" ]]; then
        log '[ERROR] NEXUS_API_KEY is required in Helpers/.env to fetch engine presets.'
        log 'Manual download links:'
        get_engine_tweak_nexus_links_text | while IFS= read -r line; do log "$line"; done
        return 1
    fi

    local entry mod_id label credit url presets
    for entry in "${ENGINE_TWEAK_NEXUS_SOURCES[@]}"; do
        IFS='|' read -r mod_id label credit url presets <<< "$entry"
        if [[ -n "$filter_ids" ]] && ! echo " $filter_ids " | grep -q " $mod_id "; then
            continue
        fi

        log "Fetching $label engine.ini presets from Nexus mod $mod_id..."
        local files_info file_id dl_info dl_link temp_zip temp_extract imported_count

        files_info="$(curl -fsS -H "apikey: $api_key" "https://api.nexusmods.com/v1/games/subnautica2/mods/$mod_id/files.json")" || {
            log "  Failed to query files for mod $mod_id."
            log "  Manual download: $url"
            continue
        }

        file_id="$(printf '%s' "$files_info" | jq -r '.files | map(select(.category_name == "MAIN")) | sort_by(.uploaded_timestamp) | reverse | .[0].file_id // empty')"
        if [[ -z "$file_id" ]]; then
            file_id="$(printf '%s' "$files_info" | jq -r '.files | sort_by(.uploaded_timestamp) | reverse | .[0].file_id // empty')"
        fi
        if [[ -z "$file_id" ]]; then
            log "  No downloadable files found for mod $mod_id."
            continue
        fi

        dl_info="$(curl -fsS -H "apikey: $api_key" "https://api.nexusmods.com/v1/games/subnautica2/mods/$mod_id/files/$file_id/download_link.json")" || {
            log "  Failed to get download link for mod $mod_id."
            continue
        }
        dl_link="$(printf '%s' "$dl_info" | jq -r '.[0].URI // empty')"
        [[ -n "$dl_link" ]] || continue

        temp_zip="/tmp/nexus_engine_${mod_id}.zip"
        temp_extract="/tmp/nexus_engine_${mod_id}_extract"
        curl -fsSL "$dl_link" -o "$temp_zip"
        rm -rf "$temp_extract"
        mkdir -p "$temp_extract"
        unzip -q "$temp_zip" -d "$temp_extract"

        imported_count="$(import_engine_ini_from_archive "$temp_extract" "$presets" | wc -l | tr -d ' ')"
        if [[ "$imported_count" -eq 0 ]]; then
            log "  No matching Engine.ini presets found. Download manually: $url"
        else
            log "  Imported $imported_count preset(s) from $label pack."
        fi

        rm -f "$temp_zip"
        rm -rf "$temp_extract"
    done
}

invoke_fetch_mod51_tweaks() {
    invoke_fetch_engine_tweaks_from_nexus "51"
}

invoke_fetch_engine_tweaks() {
    invoke_fetch_engine_tweaks_from_nexus ""
}
