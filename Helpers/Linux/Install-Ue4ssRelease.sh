#!/usr/bin/env bash

UE4SS_GITHUB_REPO='UE4SS-RE/RE-UE4SS'

get_ue4ss_release_asset_json() {
    local release_json="$1"
    local asset_name asset_url tag

    tag="$(printf '%s' "$release_json" | jq -r '.tag_name // empty')"
    asset_name="$(printf '%s' "$release_json" | jq -r '.assets[] | select(.name | test("^UE4SS_v.+\\.zip$")) | .name' | head -n 1)"
    if [[ -z "$asset_name" ]]; then
        asset_name="$(printf '%s' "$release_json" | jq -r '.assets[] | select(.name | test("^UE4SS_Standard_.+\\.zip$")) | .name' | head -n 1)"
    fi
    [[ -n "$tag" && -n "$asset_name" ]] || return 1

    asset_url="https://github.com/${UE4SS_GITHUB_REPO}/releases/download/${tag}/${asset_name}"
    jq -n \
        --arg tag "$tag" \
        --arg name "$asset_name" \
        --arg url "$asset_url" \
        --argjson size "$(printf '%s' "$release_json" | jq --arg name "$asset_name" '.assets[] | select(.name == $name) | .size // 0')" \
        '{tag: $tag, name: $name, url: $url, size: $size}'
}

resolve_latest_ue4ss_github_asset() {
    local tag_name="${1:-}"
    local release_json asset_json

    if [[ -n "$tag_name" ]]; then
        release_json="$(curl -fsS -H 'User-Agent: SimpleModManager' "https://api.github.com/repos/${UE4SS_GITHUB_REPO}/releases/tags/${tag_name}")" || return 1
        get_ue4ss_release_asset_json "$release_json"
        return $?
    fi

    log 'Querying UE4SS releases from GitHub...'
    local releases_json
    releases_json="$(curl -fsS -H 'User-Agent: SimpleModManager' "https://api.github.com/repos/${UE4SS_GITHUB_REPO}/releases?per_page=30")" || return 1

    local count i
    count="$(printf '%s' "$releases_json" | jq 'length')"
    for ((i = 0; i < count; i++)); do
        release_json="$(printf '%s' "$releases_json" | jq -c ".[$i]")"
        if [[ "$(printf '%s' "$release_json" | jq -r '.prerelease // false')" == "true" ]]; then
            continue
        fi
        if asset_json="$(get_ue4ss_release_asset_json "$release_json")"; then
            printf '%s\n' "$asset_json"
            return 0
        fi
    done

    log '[ERROR] No stable UE4SS release with a standard zip asset was found on GitHub.'
    return 1
}

install_ue4ss_from_extracted_archive() {
    local extracted_root="$1"
    local version_label="${2:-unknown}"
    local ue4ss_root="${3:-$UE4SS_ROOT}"

    local extracted_dwmapi extracted_root_dir extracted_ue4ss normalized_ue4ss target_ue4ss
    extracted_dwmapi="$(find "$extracted_root" -name 'dwmapi.dll' -type f -print -quit)"
    [[ -n "$extracted_dwmapi" ]] || die 'dwmapi.dll not found in the UE4SS archive.'

    extracted_root_dir="$(dirname "$extracted_dwmapi")"
    extracted_ue4ss="$extracted_root_dir/ue4ss"
    normalized_ue4ss="$(mktemp -d)"

    if [[ -d "$extracted_ue4ss" ]]; then
        cp -a "$extracted_ue4ss/." "$normalized_ue4ss/"
    else
        local name
        for name in UE4SS.dll UE4SS-settings.ini Mods LICENSE README.md UE4SS_Signatures MemberVarLayoutTemplates VTableLayoutTemplates CustomGameConfigs MapGenBP Changelog.md; do
            if [[ -e "$extracted_root_dir/$name" ]]; then
                cp -a "$extracted_root_dir/$name" "$normalized_ue4ss/"
            fi
        done
        [[ -f "$normalized_ue4ss/UE4SS.dll" ]] || die 'UE4SS.dll not found in the UE4SS archive.'
    fi

    mkdir -p "$ue4ss_root"
    cp -f "$extracted_dwmapi" "$ue4ss_root/"
    target_ue4ss="$ue4ss_root/ue4ss"
    rm -rf "$target_ue4ss"
    cp -a "$normalized_ue4ss" "$target_ue4ss"
    rm -rf "$normalized_ue4ss"

    printf '%s\n' "$version_label" > "$ue4ss_root/ue4ss_version.txt"
    log "Installed UE4SS $version_label to $ue4ss_root"
    printf '%s\n' "$version_label"
}

install_ue4ss_from_github_release() {
    local tag_name="${1:-}"
    local ue4ss_root="${2:-$UE4SS_ROOT}"
    local force="${3:-0}"
    local asset_json tag asset_name asset_url version_file installed_version temp_zip temp_extract

    asset_json="$(resolve_latest_ue4ss_github_asset "$tag_name")" || return 1
    tag="$(printf '%s' "$asset_json" | jq -r '.tag')"
    asset_name="$(printf '%s' "$asset_json" | jq -r '.name')"
    asset_url="$(printf '%s' "$asset_json" | jq -r '.url')"

    version_file="$ue4ss_root/ue4ss_version.txt"
    if [[ "$force" != "1" && -f "$version_file" ]]; then
        installed_version="$(tr -d '\r\n' < "$version_file")"
        if [[ "$installed_version" == "$tag" ]]; then
            log "UE4SS $tag is already installed."
            printf '%s\n' "$tag"
            return 0
        fi
        log "Updating UE4SS from $installed_version to $tag..."
    else
        log "Installing UE4SS $tag from GitHub..."
    fi

    temp_zip="/tmp/ue4ss_${tag}.zip"
    temp_extract="/tmp/ue4ss_${tag}_extract"
    log "Downloading $asset_name..."
    log "  $asset_url"
    curl -fsSL -H 'User-Agent: SimpleModManager' "$asset_url" -o "$temp_zip" || return 1
    rm -rf "$temp_extract"
    mkdir -p "$temp_extract"
    unzip -q "$temp_zip" -d "$temp_extract" || return 1

    install_ue4ss_from_extracted_archive "$temp_extract" "$tag" "$ue4ss_root" >/dev/null
    rm -f "$temp_zip"
    rm -rf "$temp_extract"
    printf '%s\n' "$tag"
    return 0
}

invoke_update_ue4ss() {
    install_ue4ss_from_github_release "" "$UE4SS_ROOT" || {
        log '[ERROR] Failed to install UE4SS from GitHub.'
        log 'Source: https://github.com/UE4SS-RE/RE-UE4SS/releases'
        return 1
    }
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    SOURCE_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
    UE4SS_ROOT="$SOURCE_ROOT/ModManager/UE4SS"
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/Common.sh"
    install_ue4ss_from_github_release "" "$UE4SS_ROOT"
fi
