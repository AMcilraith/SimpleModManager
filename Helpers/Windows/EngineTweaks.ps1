$script:EngineTweakNexusSources = @(
    @{
        ModId   = 51
        Label   = 'Performance'
        Credit  = 'Ghostiexd'
        Url     = 'https://www.nexusmods.com/subnautica2/mods/51'
        Presets = @('Balanced-Performance', 'High-Performance', 'Ultra-Performance', 'Potato-PC')
    },
    @{
        ModId   = 37
        Label   = 'Quality'
        Credit  = 'Vercadi'
        Url     = 'https://www.nexusmods.com/subnautica2/mods/37'
        Presets = @('High-Quality', 'Balanced-Quality')
    }
)

function Get-EngineTweakNexusLinksText {
    ($script:EngineTweakNexusSources | ForEach-Object {
        "$($_.Label) ($($_.Credit)): $($_.Url)"
    }) -join "`n"
}

function Open-EngineTweakNexusUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return }
    Start-Process $Url | Out-Null
}

function Get-NexusApiKey {
    if ($env:NEXUS_API_KEY) {
        return $env:NEXUS_API_KEY.Trim().Trim('"').Trim("'")
    }
    return $null
}

function Resolve-EnginePresetFolderName {
    param([string]$Hint)

    if ([string]::IsNullOrWhiteSpace($Hint)) { return $null }

    $normalized = ([regex]::Replace($Hint, '[_\-]+', ' ')).ToLowerInvariant()
    $normalized = [regex]::Replace($normalized, '\s+', ' ').Trim()

    $rules = @(
        @{ Pattern = 'potato'; Folder = 'Potato-PC' },
        @{ Pattern = 'ultra\s*performance'; Folder = 'Ultra-Performance' },
        @{ Pattern = 'balanced\s*performance'; Folder = 'Balanced-Performance' },
        @{ Pattern = 'high\s*performance'; Folder = 'High-Performance' },
        @{ Pattern = '(?<!balanced\s)(?<!ultra\s)performance'; Folder = 'High-Performance' },
        @{ Pattern = 'balanced\s*quality'; Folder = 'Balanced-Quality' },
        @{ Pattern = 'high\s*quality'; Folder = 'High-Quality' }
    )

    foreach ($rule in $rules) {
        if ($normalized -match $rule.Pattern) {
            return $rule.Folder
        }
    }

    foreach ($source in $script:EngineTweakNexusSources) {
        foreach ($preset in $source.Presets) {
            $presetNorm = ([regex]::Replace($preset, '[_\-]+', ' ')).ToLowerInvariant()
            if ($normalized -eq $presetNorm -or $normalized.Contains($presetNorm)) {
                return $preset
            }
        }
    }

    return $null
}

function Import-EngineIniFromArchive {
    param(
        [string]$ExtractRoot,
        [string[]]$AllowedPresets
    )

    $imported = @()
    $iniFiles = Get-ChildItem -LiteralPath $ExtractRoot -Filter 'Engine.ini' -Recurse -File -ErrorAction SilentlyContinue
  foreach ($iniFile in $iniFiles) {
        $relative = $iniFile.FullName.Substring($ExtractRoot.Length).TrimStart('\')
        $folderHint = Split-Path -Parent $relative
        if ([string]::IsNullOrWhiteSpace($folderHint)) {
            $folderHint = [System.IO.Path]::GetFileNameWithoutExtension($iniFile.Name)
        }
        $folderHint = ($folderHint -split '[\\/]')[-1]

        $presetFolder = Resolve-EnginePresetFolderName -Hint $folderHint
        if (-not $presetFolder) {
            $presetFolder = Resolve-EnginePresetFolderName -Hint $relative
        }
        if (-not $presetFolder) { continue }
        if ($AllowedPresets -and ($AllowedPresets -notcontains $presetFolder)) { continue }

        $destDir = Join-Path $script:EngineTweaks $presetFolder
        if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        $destIni = Join-Path $destDir 'Engine.ini'
        Copy-Item -LiteralPath $iniFile.FullName -Destination $destIni -Force
        if ($imported -notcontains $presetFolder) {
            $imported += $presetFolder
        }
        Log "  Installed $presetFolder preset"
    }

    return $imported
}

function Invoke-FetchEngineTweaksFromNexus {
    param(
        [int[]]$ModIds
    )

    $apiKey = Get-NexusApiKey
    if (-not $apiKey) {
        Log '[ERROR] NEXUS_API_KEY is required in Helpers/.env to fetch engine presets.'
        Log 'Manual download links:'
        Log (Get-EngineTweakNexusLinksText)
        return
    }

    $headers = @{ apikey = $apiKey }
    $sources = $script:EngineTweakNexusSources
    if ($ModIds) {
        $sources = @($sources | Where-Object { $ModIds -contains $_.ModId })
    }

    foreach ($source in $sources) {
        Log "Fetching $($source.Label) engine.ini presets from Nexus mod $($source.ModId)..."
        $tempZip = $null
        $tempExtract = $null
        try {
            $filesInfo = Invoke-RestMethod -Uri "https://api.nexusmods.com/v1/games/subnautica2/mods/$($source.ModId)/files.json" -Headers $headers -TimeoutSec 30
            $primaryFile = $filesInfo.files | Where-Object { $_.category_name -eq 'MAIN' } | Sort-Object uploaded_timestamp -Descending | Select-Object -First 1
            if (-not $primaryFile) {
                $primaryFile = $filesInfo.files | Sort-Object uploaded_timestamp -Descending | Select-Object -First 1
            }
            if (-not $primaryFile) {
                Log "  No downloadable files found for mod $($source.ModId)."
                continue
            }

            $dlInfo = Invoke-RestMethod -Uri "https://api.nexusmods.com/v1/games/subnautica2/mods/$($source.ModId)/files/$($primaryFile.file_id)/download_link.json" -Headers $headers -TimeoutSec 30
            $dlLink = $dlInfo[0].URI

            $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "nexus_engine_$($source.ModId).zip"
            $tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) "nexus_engine_$($source.ModId)_extract"
            Invoke-WebRequest -Uri $dlLink -OutFile $tempZip -ErrorAction Stop
            if (Test-Path -LiteralPath $tempExtract) {
                Remove-Item -LiteralPath $tempExtract -Recurse -Force
            }
            Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

            $imported = Import-EngineIniFromArchive -ExtractRoot $tempExtract -AllowedPresets $source.Presets
            if ($imported.Count -eq 0) {
                Log "  No matching Engine.ini presets found in the archive. Download manually: $($source.Url)"
            }
            else {
                Log "  Imported $($imported.Count) preset(s) from $($source.Label) pack."
            }
        }
        catch {
            Log "  Failed to fetch mod $($source.ModId): $($_.Exception.Message)"
            Log "  Manual download: $($source.Url)"
        }
        finally {
            if ($tempZip -and (Test-Path -LiteralPath $tempZip)) { Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue }
            if ($tempExtract -and (Test-Path -LiteralPath $tempExtract)) { Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Invoke-FetchMod51Tweaks {
    Invoke-FetchEngineTweaksFromNexus -ModIds @(51)
}
