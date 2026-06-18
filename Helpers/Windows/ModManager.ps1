function Show-ToggleMenu {
    param([string]$Title, [string]$EnabledPath, [string]$DisabledPath)
    
    $cursor = 0
    
    $isUe4ss = $Title -like "*UE4SS*"
    $loadOrderFile = if ($isUe4ss) {
        Join-Path $EnabledPath "mods.txt"
    }
    else {
        Join-Path $EnabledPath "loadorder.txt"
    }
    
    while ($true) {
        $enabledDirs = @()
        if (Test-Path -LiteralPath $EnabledPath -PathType Container) {
            $enabledDirs = @(Get-ChildItem -LiteralPath $EnabledPath -Directory | Select-Object -ExpandProperty Name)
        }
        $disabledDirs = @()
        if (Test-Path -LiteralPath $DisabledPath -PathType Container) {
            $disabledDirs = @(Get-ChildItem -LiteralPath $DisabledPath -Directory | Select-Object -ExpandProperty Name)
        }
        
        $allNames = Get-CurrentLoadOrder -EnabledPath $EnabledPath -DisabledPath $DisabledPath -LoadOrderFile $loadOrderFile -IsUe4ss $isUe4ss
        
        if ($isUe4ss -and -not (Test-Path -LiteralPath $loadOrderFile -PathType Leaf)) {
            Save-CurrentLoadOrder -Order $allNames -LoadOrderFile $loadOrderFile -EnabledPath $EnabledPath -IsUe4ss $isUe4ss
        }
        
        $allMods = @()
        $options = @()
        $colors = @()
        $descriptions = @()
        $idx = 1
        
        foreach ($name in $allNames) {
            $isEnabled = $enabledDirs -contains $name
            $source = if ($isEnabled) { Join-Path $EnabledPath $name } else { Join-Path $DisabledPath $name }
            $target = if ($isEnabled) { Join-Path $DisabledPath $name } else { Join-Path $EnabledPath $name }
            $state = if ($isEnabled) { 'Enabled' } else { 'Disabled' }
            
            $options += "[$idx] $name"
            $allMods += [pscustomobject]@{ Name = $name; Source = $source; Target = $target; State = $state }
            $colors += if ($isEnabled) { "Green" } else { "Red" }
            $descriptions += "Mod: $name (Currently $state). Press [Enter]/[T] to toggle or [D] to delete."
            $idx++
        }
        
        $choice = Get-MenuSelection -Title $Title -Options $options -DefaultIndex $cursor -Colors $colors -Descriptions $descriptions
        $cursor = $choice
        
        if ($choice -eq -1) { return }
        
        if ($choice -lt $allMods.Count) {
            $selected = $allMods[$choice]
            $action = $global:MenuAction
            
            if ($action -eq 'CtrlUp' -or $action -eq 'CtrlDown') {
                Log 'Load order editing is disabled.'
                Start-Sleep -Milliseconds 250
                continue
            }
            
            if ($action -eq 'Delete') {
                Clear-Host
                Write-Host ""
                Write-Host "WARNING: You are about to permanently delete mod: $($selected.Name)" -ForegroundColor Yellow
                $confirm = Read-Host "Are you sure you want to proceed? (y/N)"
                if ($confirm -ieq 'y') {
                    Remove-Item -LiteralPath $selected.Source -Recurse -Force
                    $newOrder = $allNames | Where-Object { $_ -ne $selected.Name }
                    Save-CurrentLoadOrder -Order $newOrder -LoadOrderFile $loadOrderFile -EnabledPath $EnabledPath -IsUe4ss $isUe4ss
                    Log "Deleted mod $($selected.Name)."
                    Start-Sleep -Milliseconds 500
                }
            }
            else {
                # Toggle/Select
                $targetDir = Split-Path -Parent $selected.Target
                if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                Move-Item -LiteralPath $selected.Source -Destination $selected.Target -Force
                if ($isUe4ss) {
                    Save-CurrentLoadOrder -Order $allNames -LoadOrderFile $loadOrderFile -EnabledPath $EnabledPath -IsUe4ss $isUe4ss
                }
                Log "Toggled $($selected.Name) to $(if ($selected.State -eq 'Enabled') { 'Disabled' } else { 'Enabled' })"
                Start-Sleep -Milliseconds 250
            }
        }
    }
}

function Show-EngineTweakMenu {
    $cursor = 0
    while ($true) {
        $tweaks = @()
        $options = @()
        $descriptions = @()
        $idx = 1
        
        $activeIni = Join-Path $script:PlayerTweaks 'engine.ini'
        $statusStr = if (Test-Path -LiteralPath $activeIni -PathType Leaf) { "Status: Active Custom Tweak" } else { "Status: Default (No Tweak)" }
        
        if (Test-Path -LiteralPath $script:EngineTweaks -PathType Container) {
            $qualityOrder = @("High-Quality", "Balanced-Quality", "Balanced-Performance", "High-Performance", "Ultra-Performance", "Potato-PC")
            foreach ($name in $qualityOrder) {
                $dirPath = Join-Path $script:EngineTweaks $name
                if (Test-Path -LiteralPath $dirPath -PathType Container) {
                    $iniFile = @(Get-ChildItem -LiteralPath $dirPath -Filter 'Engine.ini' -Recurse | Select-Object -First 1)
                    if ($iniFile) {
                        $options += "[$idx] Apply $name Preset"
                        $desc = switch ($name) {
                            "High-Quality" {
                                "High Quality Preset`n`nWhat this config focuses on:`n- Texture streaming behavior`n- Async loading and IO behavior`n- Shader pipeline cache / PSO behavior`n- Garbage collection tuning`n- General frame-time stability`n`nWhat this config does NOT try to do:`n- No intentional visual downgrade`n- No forced low LOD look`n- No color or tonemapper overhaul`n- No aggressive shadow or lighting cuts`n- No Lumen disable`n- No Nanite disable`n- No Virtual Shadow Map disable`n- No 'potato mode' changes`n`nNote: Removes post-process clutter like motion blur, lens flares, film grain, and chromatic aberration."
                            }
                            "Balanced-Quality" {
                                "Balanced Quality Preset`n`nWhat this config focuses on:`n- Texture streaming behavior`n- Async loading and IO behavior`n- Shader pipeline cache / PSO behavior`n- Garbage collection tuning`n- General frame-time stability`n`nWhat this config does NOT try to do:`n- No intentional visual downgrade`n- No forced low LOD look`n- No color or tonemapper overhaul`n- No aggressive shadow or lighting cuts`n- No Lumen disable`n- No Nanite disable`n- No Virtual Shadow Map disable`n- No 'potato mode' changes`n`nNote: Purely lossless performance/streaming optimization with no visual changes."
                            }
                            "Balanced-Performance" {
                                "Balanced Performance Preset`n`nThis preset keeps most visuals intact while disabling expensive shadow features such as Dynamic Global Illumination for better performance without heavily changing the game's appearance.`n`n(Disables Lumen, so interior lights may be less effective at illuminating your base. Just put some extra lights, and it should be fine.)"
                            }
                            "High-Performance" {
                                "High Performance Preset`n`nThis preset fully disables shadows and some other visual effects to provide the highest possible FPS boost without hurting graphics too much.`n`n(Disables Lumen, so interior lights may be less effective at illuminating your base. Just put some extra lights, and it should be fine.)"
                            }
                            "Ultra-Performance" {
                                "Ultra Performance Preset`n`nThis preset removes almost all visual effects for the maximum possible FPS increase, significantly reducing graphical quality in exchange for the highest performance gains.`n`n(Disables Lumen, so interior lights may be less effective at illuminating your base. Just put some extra lights, and it should be fine.)"
                            }
                            "Potato-PC" {
                                "Potato PC Preset`n`nThis preset removes basically all visual effects from the game. It is not recommended, but if you really want to play, this may be your last option.`n`n(Disables Lumen, so interior lights may be less effective at illuminating your base. Just put some extra lights, and it should be fine.)"
                            }
                            default {
                                "Applies the custom engine.ini preset from $name to optimize game graphics/performance."
                            }
                        }
                        $descriptions += $desc
                        $tweaks += [pscustomobject]@{ Name = $name; SourceIni = $iniFile.FullName }
                        $idx++
                    }
                }
            }
        }
        
        $fetchIdx = $options.Count
        $options += "-"
        $descriptions += ""
        $options += "[F] Fetch presets from Nexus"
        $descriptions += "Downloads Engine.ini presets from Nexus Mods 51 (performance) and 37 (quality). Requires NEXUS_API_KEY in Helpers/.env.`n`n$(Get-EngineTweakNexusLinksText)"
        $perfLinkIdx = $options.Count
        $options += "[P] Open Performance presets (Nexus mod 51)"
        $descriptions += "Opens Ghostiexd's Subnautica 2 Performance Mod in your browser:`nhttps://www.nexusmods.com/subnautica2/mods/51"
        $qualLinkIdx = $options.Count
        $options += "[Q] Open Quality presets (Nexus mod 37)"
        $descriptions += "Opens Vercadi's quality Engine.ini tweaks in your browser:`nhttps://www.nexusmods.com/subnautica2/mods/37"
        $options += "-"
        $descriptions += ""
        $options += "[D] Disable current Engine Tweak"
        $descriptions += "Disables the current active custom engine.ini tweak preset, reverting back to game defaults."
        $disableIdx = $options.Count - 1
        
        $choice = Get-MenuSelection -Title "ENGINE TWEAKS ($statusStr)" -Options $options -DefaultIndex $cursor -Descriptions $descriptions
        $cursor = $choice
        
        if ($choice -eq -1) { return }
        
        if ($choice -eq $fetchIdx) {
            Invoke-FetchEngineTweaksFromNexus
            Start-Sleep -Milliseconds 600
            continue
        }
        if ($choice -eq $perfLinkIdx) {
            Open-EngineTweakNexusUrl -Url 'https://www.nexusmods.com/subnautica2/mods/51'
            continue
        }
        if ($choice -eq $qualLinkIdx) {
            Open-EngineTweakNexusUrl -Url 'https://www.nexusmods.com/subnautica2/mods/37'
            continue
        }
        
        if ($choice -eq $disableIdx) {
            if (Test-Path -LiteralPath $activeIni -PathType Leaf) {
                Remove-Item -LiteralPath $activeIni -Force
                Log "Engine Tweak disabled."
            }
            else {
                Log "Engine Tweak already disabled."
            }
            Start-Sleep -Milliseconds 350
            continue
        }
        
        if ($choice -lt $tweaks.Count) {
            $selected = $tweaks[$choice]
            if (-not (Test-Path -LiteralPath $script:PlayerTweaks -PathType Container)) {
                New-Item -ItemType Directory -Path $script:PlayerTweaks -Force | Out-Null
            }
            Copy-Item -LiteralPath $selected.SourceIni -Destination $activeIni -Force
            Log "Applied $($selected.Name) preset!"
            Start-Sleep -Milliseconds 350
        }
    }
}

function Install-ModFromZip {
    Write-Host ""
    $zipPath = Read-Host "Enter path to the mod/modpack .zip file"
    if ([string]::IsNullOrWhiteSpace($zipPath)) { return }
    $zipPath = $zipPath.Trim()
    
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        Log "Error: File not found at $zipPath"
        Start-Sleep -Seconds 2
        return
    }
    
    $resolvedZip = (Get-Item -LiteralPath $zipPath).FullName
    Log "Extracting $resolvedZip to temporary folder..."
    
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("sn2_install_" + (New-Guid).Guid)
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    try {
        Expand-Archive -Path $resolvedZip -DestinationPath $tempDir -Force
        
        $foundStructured = $false
        
        $searchDirs = @($tempDir)
        $subDirs = @(Get-ChildItem -LiteralPath $tempDir -Directory -Recurse -Depth 1)
        if ($subDirs) { $searchDirs += $subDirs.FullName }
        
        foreach ($dir in $searchDirs) {
            $hasMods = Test-Path -LiteralPath (Join-Path $dir 'Mods') -PathType Container
            $hasPaks = Test-Path -LiteralPath (Join-Path $dir '~mods') -PathType Container
            $hasLogic = Test-Path -LiteralPath (Join-Path $dir 'LogicMods') -PathType Container
            
            if ($hasMods -or $hasPaks -or $hasLogic) {
                Log "Found structured modpack layout at: $(Split-Path $dir -Leaf)"
                if ($hasMods) {
                    Log "  Copying UE4SS Mods..."
                    Copy-MergeDirectoryContents -Source (Join-Path $dir 'Mods') -Target (Join-Path $script:EnabledMods 'Mods')
                }
                if ($hasPaks) {
                    Log "  Copying BP Patch Pak Mods..."
                    Copy-MergeDirectoryContents -Source (Join-Path $dir '~mods') -Target (Join-Path $script:EnabledMods '~mods')
                }
                if ($hasLogic) {
                    Log "  Copying BP Logic Pak Mods..."
                    Copy-MergeDirectoryContents -Source (Join-Path $dir 'LogicMods') -Target (Join-Path $script:EnabledMods 'LogicMods')
                }
                $foundStructured = $true
                break
            }
        }
        
        if (-not $foundStructured) {
            Log "Analyzing individual mod files..."
            
            $mainLua = @(Get-ChildItem -LiteralPath $tempDir -Filter 'main.lua' -Recurse | Where-Object {
                $_.Directory.Name -ieq 'Scripts'
            } | Select-Object -First 1)
            
            if ($mainLua) {
                $modFolder = $mainLua.Directory.Parent
                Log "Detected UE4SS Mod: $($modFolder.Name)"
                $targetModPath = Join-Path $script:EnabledMods "Mods\$($modFolder.Name)"
                Copy-MergeDirectoryContents -Source $modFolder.FullName -Target $targetModPath
            }
            else {
                $pakFiles = @(Get-ChildItem -LiteralPath $tempDir -Filter '*.pak' -Recurse)
                if ($pakFiles) {
                    foreach ($pak in $pakFiles) {
                        if ($pak.FullName -match 'LogicMods') {
                            Log "Detected BP Logic Pak Mod: $($pak.Name)"
                            $targetPath = Join-Path $script:EnabledMods 'LogicMods'
                        }
                        else {
                            Log "Detected BP Patch Pak Mod: $($pak.Name)"
                            $targetPath = Join-Path $script:EnabledMods '~mods'
                        }
                        
                        if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
                            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                        }
                        
                        Copy-Item -LiteralPath $pak.FullName -Destination $targetPath -Force
                        
                        # Copy associated .ucas and .utoc files if they exist
                        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($pak.Name)
                        $dirName = $pak.DirectoryName
                        $ucasFile = Join-Path $dirName "$baseName.ucas"
                        $utocFile = Join-Path $dirName "$baseName.utoc"
                        
                        if (Test-Path -LiteralPath $ucasFile -PathType Leaf) {
                            Copy-Item -LiteralPath $ucasFile -Destination $targetPath -Force
                        }
                        if (Test-Path -LiteralPath $utocFile -PathType Leaf) {
                            Copy-Item -LiteralPath $utocFile -Destination $targetPath -Force
                        }
                    }
                }
                else {
                    Log "Warning: No recognizable .pak files or UE4SS scripts found in the zip."
                }
            }
        }
        
        Log "Success: Mod files successfully extracted and categorized."
        Start-Sleep -Seconds 2
    }
    catch {
        Log "Error extracting mod: $($_.Exception.Message)"
        Start-Sleep -Seconds 3
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-OrderedEnabledMods {
    param(
        [string]$EnabledPath,
        [string]$DisabledPath,
        [bool]$IsUe4ss = $false
    )

    $loadOrderFile = if ($IsUe4ss) {
        Join-Path $EnabledPath 'mods.txt'
    }
    else {
        Join-Path $EnabledPath 'loadorder.txt'
    }

    $enabledDirs = @()
    if (Test-Path -LiteralPath $EnabledPath -PathType Container) {
        $enabledDirs = @(Get-ChildItem -LiteralPath $EnabledPath -Directory | Select-Object -ExpandProperty Name)
    }

    $orderedNames = Get-CurrentLoadOrder -EnabledPath $EnabledPath -DisabledPath $DisabledPath -LoadOrderFile $loadOrderFile -IsUe4ss $IsUe4ss
    $enabledOrder = @()
    foreach ($name in $orderedNames) {
        if ($enabledDirs -contains $name) {
            $enabledOrder += $name
        }
    }

    return $enabledOrder
}

function Set-OrderedEnabledMods {
    param(
        [string]$Title,
        [string]$EnabledPath,
        [string]$DisabledPath,
        [string[]]$DesiredEnabled,
        [bool]$IsUe4ss = $false
    )

    $loadOrderFile = if ($IsUe4ss) {
        Join-Path $EnabledPath 'mods.txt'
    }
    else {
        Join-Path $EnabledPath 'loadorder.txt'
    }

    $allNames = Get-CurrentLoadOrder -EnabledPath $EnabledPath -DisabledPath $DisabledPath -LoadOrderFile $loadOrderFile -IsUe4ss $IsUe4ss
    $existing = @{}
    foreach ($name in $allNames) {
        $existing[$name] = $true
    }

    $desiredSet = @{}
    $missing = @()
    $orderedDesired = @()
    foreach ($name in $DesiredEnabled) {
        if ([string]::IsNullOrWhiteSpace($name) -or $desiredSet.ContainsKey($name)) {
            continue
        }
        $desiredSet[$name] = $true
        if ($existing.ContainsKey($name)) {
            $orderedDesired += $name
        }
        else {
            $missing += $name
        }
    }

    foreach ($name in $allNames) {
        $shouldEnable = $desiredSet.ContainsKey($name)
        $enabledItem = Join-Path $EnabledPath $name
        $disabledItem = Join-Path $DisabledPath $name
        $currentlyEnabled = Test-Path -LiteralPath $enabledItem -PathType Container

        if ($shouldEnable -and -not $currentlyEnabled -and (Test-Path -LiteralPath $disabledItem -PathType Container)) {
            if (-not (Test-Path -LiteralPath $EnabledPath -PathType Container)) {
                New-Item -ItemType Directory -Path $EnabledPath -Force | Out-Null
            }
            Move-Item -LiteralPath $disabledItem -Destination $enabledItem -Force
        }
        elseif (-not $shouldEnable -and $currentlyEnabled) {
            if (-not (Test-Path -LiteralPath $DisabledPath -PathType Container)) {
                New-Item -ItemType Directory -Path $DisabledPath -Force | Out-Null
            }
            Move-Item -LiteralPath $enabledItem -Destination $disabledItem -Force
        }
    }

    $remaining = @()
    foreach ($name in $allNames) {
        if (-not $desiredSet.ContainsKey($name)) {
            $remaining += $name
        }
    }

    Save-CurrentLoadOrder -Order ($orderedDesired + $remaining) -LoadOrderFile $loadOrderFile -EnabledPath $EnabledPath -IsUe4ss $IsUe4ss

    if ($missing.Count -gt 0) {
        Log "$Title collection entries not found locally: $($missing -join ', ')"
    }
}

function Reset-PlayerTweaksDirectory {
    if (Test-Path -LiteralPath $script:PlayerTweaks -PathType Container) {
        Get-ChildItem -LiteralPath $script:PlayerTweaks -Force | Remove-Item -Recurse -Force
    }
    else {
        New-Item -ItemType Directory -Path $script:PlayerTweaks -Force | Out-Null
    }
}

function Get-CollectionManifestLines {
    return @(
        '# Addi-Pack Collection Zip v2',
        '[UE4SS Mods]'
    ) +
    (Get-OrderedEnabledMods -EnabledPath (Join-Path $script:EnabledMods 'Mods') -DisabledPath (Join-Path $script:DisabledMods 'Mods') -IsUe4ss $true) +
    @(
        '',
        '[BP Patch Mods]'
    ) +
    (Get-OrderedEnabledMods -EnabledPath (Join-Path $script:EnabledMods '~mods') -DisabledPath (Join-Path $script:DisabledMods '~mods')) +
    @(
        '',
        '[BP Logic Mods]'
    ) +
    (Get-OrderedEnabledMods -EnabledPath (Join-Path $script:EnabledMods 'LogicMods') -DisabledPath (Join-Path $script:DisabledMods 'LogicMods'))
}

function Copy-CollectionDirectory {
    param([string]$SourcePath, [string]$DestinationPath)

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        return
    }

    $destinationParent = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $DestinationPath -PathType Container) {
        Remove-Item -LiteralPath $DestinationPath -Recurse -Force
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Recurse -Force
}

function Export-CollectionCategory {
    param(
        [string]$EnabledPath,
        [string]$DisabledPath,
        [string]$ExportPath,
        [bool]$IsUe4ss = $false
    )

    foreach ($name in Get-OrderedEnabledMods -EnabledPath $EnabledPath -DisabledPath $DisabledPath -IsUe4ss $IsUe4ss) {
        Copy-CollectionDirectory -SourcePath (Join-Path $EnabledPath $name) -DestinationPath (Join-Path $ExportPath $name)
    }
}

function Read-CollectionManifest {
    param([string]$ManifestPath)

    $sections = @{
        'UE4SS Mods'    = @()
        'BP Patch Mods' = @()
        'BP Logic Mods' = @()
    }
    $currentSection = $null

    foreach ($rawLine in Get-Content -LiteralPath $ManifestPath) {
        $line = $rawLine.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }
        if ($line -match '^\[(.+)\]$') {
            $sectionName = $Matches[1]
            $currentSection = if ($sections.ContainsKey($sectionName)) { $sectionName } else { $null }
            continue
        }
        if ($currentSection) {
            $sections[$currentSection] += $line
        }
    }

    return $sections
}

function Import-CollectionCategory {
    param(
        [string]$Title,
        [string]$EnabledPath,
        [string]$DisabledPath,
        [string]$ImportPath,
        [string[]]$DesiredEnabled,
        [bool]$IsUe4ss = $false
    )

    $loadOrderFile = if ($IsUe4ss) {
        Join-Path $EnabledPath 'mods.txt'
    }
    else {
        Join-Path $EnabledPath 'loadorder.txt'
    }

    $allNames = Get-CurrentLoadOrder -EnabledPath $EnabledPath -DisabledPath $DisabledPath -LoadOrderFile $loadOrderFile -IsUe4ss $IsUe4ss
    $knownNames = @{}
    foreach ($name in $allNames) {
        $knownNames[$name] = $true
    }

    $desiredSet = @{}
    $orderedDesired = @()
    $missing = @()

    foreach ($name in $DesiredEnabled) {
        if ([string]::IsNullOrWhiteSpace($name) -or $desiredSet.ContainsKey($name)) {
            continue
        }
        $desiredSet[$name] = $true

        $enabledItem = Join-Path $EnabledPath $name
        $disabledItem = Join-Path $DisabledPath $name
        $sourceItem = Join-Path $ImportPath $name

        if (Test-Path -LiteralPath $sourceItem -PathType Container) {
            Copy-CollectionDirectory -SourcePath $sourceItem -DestinationPath $enabledItem
            if (Test-Path -LiteralPath $disabledItem -PathType Container) {
                Remove-Item -LiteralPath $disabledItem -Recurse -Force
            }
            if (-not $knownNames.ContainsKey($name)) {
                $allNames += $name
                $knownNames[$name] = $true
            }
            $orderedDesired += $name
            continue
        }

        if (Test-Path -LiteralPath $disabledItem -PathType Container) {
            if (-not (Test-Path -LiteralPath $EnabledPath -PathType Container)) {
                New-Item -ItemType Directory -Path $EnabledPath -Force | Out-Null
            }
            Move-Item -LiteralPath $disabledItem -Destination $enabledItem -Force
            $orderedDesired += $name
            continue
        }

        if (Test-Path -LiteralPath $enabledItem -PathType Container) {
            $orderedDesired += $name
            continue
        }

        $missing += $name
    }

    foreach ($name in $allNames) {
        if ($desiredSet.ContainsKey($name)) {
            continue
        }

        $enabledItem = Join-Path $EnabledPath $name
        $disabledItem = Join-Path $DisabledPath $name
        if (Test-Path -LiteralPath $enabledItem -PathType Container) {
            if (-not (Test-Path -LiteralPath $DisabledPath -PathType Container)) {
                New-Item -ItemType Directory -Path $DisabledPath -Force | Out-Null
            }
            if (Test-Path -LiteralPath $disabledItem -PathType Container) {
                Remove-Item -LiteralPath $disabledItem -Recurse -Force
            }
            Move-Item -LiteralPath $enabledItem -Destination $disabledItem -Force
        }
    }

    $remaining = @()
    foreach ($name in $allNames) {
        if (-not $desiredSet.ContainsKey($name)) {
            $remaining += $name
        }
    }

    Save-CurrentLoadOrder -Order ($orderedDesired + $remaining) -LoadOrderFile $loadOrderFile -EnabledPath $EnabledPath -IsUe4ss $IsUe4ss

    if ($missing.Count -gt 0) {
        Log "$Title collection entries not found in the zip or local mod library: $($missing -join ', ')"
    }
}

function Export-ModCollection {
    Write-Host ''
    $filePath = Read-Host 'Enter the path for the collection zip file (.zip suggested)'
    if ([string]::IsNullOrWhiteSpace($filePath)) { return }

    $resolvedPath = [System.IO.Path]::GetFullPath($filePath.Trim())
    if ([System.IO.Path]::GetExtension($resolvedPath) -eq '') {
        $resolvedPath += '.zip'
    }
    $parentDir = Split-Path -Parent $resolvedPath
    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("sn2_collection_" + (New-Guid).Guid)
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        Export-CollectionCategory -EnabledPath (Join-Path $script:EnabledMods 'Mods') -DisabledPath (Join-Path $script:DisabledMods 'Mods') -ExportPath (Join-Path $tempDir 'Mods') -IsUe4ss $true
        Export-CollectionCategory -EnabledPath (Join-Path $script:EnabledMods '~mods') -DisabledPath (Join-Path $script:DisabledMods '~mods') -ExportPath (Join-Path $tempDir '~mods')
        Export-CollectionCategory -EnabledPath (Join-Path $script:EnabledMods 'LogicMods') -DisabledPath (Join-Path $script:DisabledMods 'LogicMods') -ExportPath (Join-Path $tempDir 'LogicMods')

        if (Test-Path -LiteralPath $script:PlayerTweaks -PathType Container) {
            Copy-MergeDirectoryContents -Source $script:PlayerTweaks -Target (Join-Path $tempDir 'PlayerTweaks')
        }

        Set-Content -LiteralPath (Join-Path $tempDir 'collection_manifest.txt') -Value (Get-CollectionManifestLines) -Encoding UTF8
        if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
            Remove-Item -LiteralPath $resolvedPath -Force
        }
        Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $resolvedPath -Force
        Log "Collection exported to $resolvedPath"
    }
    finally {
        if (Test-Path -LiteralPath $tempDir -PathType Container) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Start-Sleep -Milliseconds 900
}

function Import-ModCollection {
    Write-Host ''
    $filePath = Read-Host 'Enter the path to the collection zip file'
    if ([string]::IsNullOrWhiteSpace($filePath)) { return }

    $resolvedPath = [System.IO.Path]::GetFullPath($filePath.Trim())
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        Log "Collection file not found: $resolvedPath"
        Start-Sleep -Seconds 2
        return
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("sn2_collection_import_" + (New-Guid).Guid)
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        Expand-Archive -LiteralPath $resolvedPath -DestinationPath $tempDir -Force
        $manifestPath = Join-Path $tempDir 'collection_manifest.txt'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Log 'Collection zip is missing collection_manifest.txt'
            Start-Sleep -Seconds 2
            return
        }

        $sections = Read-CollectionManifest -ManifestPath $manifestPath
        Import-CollectionCategory -Title 'UE4SS Mods' -EnabledPath (Join-Path $script:EnabledMods 'Mods') -DisabledPath (Join-Path $script:DisabledMods 'Mods') -ImportPath (Join-Path $tempDir 'Mods') -DesiredEnabled $sections['UE4SS Mods'] -IsUe4ss $true
        Import-CollectionCategory -Title 'BP Patch Mods' -EnabledPath (Join-Path $script:EnabledMods '~mods') -DisabledPath (Join-Path $script:DisabledMods '~mods') -ImportPath (Join-Path $tempDir '~mods') -DesiredEnabled $sections['BP Patch Mods']
        Import-CollectionCategory -Title 'BP Logic Mods' -EnabledPath (Join-Path $script:EnabledMods 'LogicMods') -DisabledPath (Join-Path $script:DisabledMods 'LogicMods') -ImportPath (Join-Path $tempDir 'LogicMods') -DesiredEnabled $sections['BP Logic Mods']

        Reset-PlayerTweaksDirectory
        $importTweaksPath = Join-Path $tempDir 'PlayerTweaks'
        if (Test-Path -LiteralPath $importTweaksPath -PathType Container) {
            Copy-MergeDirectoryContents -Source $importTweaksPath -Target $script:PlayerTweaks
        }

        Log "Collection imported from $resolvedPath"
    }
    finally {
        if (Test-Path -LiteralPath $tempDir -PathType Container) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Start-Sleep -Milliseconds 900
}

function Start-ModManager {
    $cursor = 0
    while ($true) {
        $options = @(
            "[1] Toggle UE4SS Mods",
            "[2] Toggle BP Patch Mods",
            "[3] Toggle BP Logic Mods",
            "[4] Engine Tweaks",
            "[5] Install Mod from Zip",
            "[6] Export Collection",
            "[7] Import Collection"
        )
        $descriptions = @(
            "View and toggle Lua-based scripting mods that run via the UE4SS framework.",
            "View and toggle BP patch (.pak) mods located in the ~mods folder.",
            "View and toggle BP logic (.pak) mods located in the LogicMods folder.",
            "Choose, apply, or disable custom engine configuration presets to tweak game graphics and performance.",
            "Import and automatically install new mods or modpacks directly from a downloaded .zip file.",
            "Save the current enabled mods and PlayerTweaks config files into a reusable collection file.",
            "Load a collection file to restore a saved set of enabled mods and PlayerTweaks config files."
        )
        $choice = Get-MenuSelection -Title "MOD MANAGER" -Options $options -DefaultIndex $cursor -Descriptions $descriptions
        $cursor = $choice
        switch ($choice) {
            0 { Show-ToggleMenu -Title "UE4SS Mods" -EnabledPath (Join-Path $script:EnabledMods 'Mods') -DisabledPath (Join-Path $script:DisabledMods 'Mods'); $cursor = 0 }
            1 { Show-ToggleMenu -Title "BP Patch Mods (~mods)" -EnabledPath (Join-Path $script:EnabledMods '~mods') -DisabledPath (Join-Path $script:DisabledMods '~mods'); $cursor = 1 }
            2 { Show-ToggleMenu -Title "BP Logic Mods" -EnabledPath (Join-Path $script:EnabledMods 'LogicMods') -DisabledPath (Join-Path $script:DisabledMods 'LogicMods'); $cursor = 2 }
            3 { Show-EngineTweakMenu; $cursor = 3 }
            4 { Install-ModFromZip; $cursor = 4 }
            5 { Export-ModCollection; $cursor = 5 }
            6 { Import-ModCollection; $cursor = 6 }
            -1 { return }
        }
    }
}
