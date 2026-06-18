function Copy-MergeDirectoryContents {
    param([string]$Source, [string]$Target)
    Require-Directory -Path $Source
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }
    $children = Get-ChildItem -LiteralPath $Source -Force
    foreach ($child in $children) {
        Copy-Item -LiteralPath $child.FullName -Destination $Target -Recurse -Force
    }
}

function Clear-DirectoryContents {
    param([string]$Target)
    if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        return
    }
    foreach ($item in (Get-ChildItem -LiteralPath $Target -Force)) {
        try {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
        } catch [System.UnauthorizedAccessException] {
            throw [System.UnauthorizedAccessException]::new("Cannot delete '$($item.Name)' - file is locked by another process.")
        } catch {
            throw
        }
    }
}

function Reset-Directory {
    param([string]$Target)
    if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}

function Set-FilesReadOnly {
    param([string]$Target)
    $files = Get-ChildItem -LiteralPath $Target -File -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $files) {
        Log "No files found in $Target"
        return
    }
    foreach ($file in $files) {
        if ($file.Name -ieq 'GameUserSettings.ini') {
            $file.IsReadOnly = $false
            continue
        }
        $file.IsReadOnly = $true
    }
}

function Prepare-PlayerTweaksSource {
    Require-Directory -Path $script:PlayerTweaks
    $files = Get-ChildItem -LiteralPath $script:PlayerTweaks -File -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $files) {
        Log "No files found in $script:PlayerTweaks"
        return
    }
    Log 'Setting PlayerTweaks source files read-only'
    foreach ($file in $files) { $file.IsReadOnly = $true }
}

function Deploy-Mods {
    param([string]$GameRoot, [string]$AppId, [string]$LocalAppDataRoot)

    Prepare-PlayerTweaksSource

    $targetPlayerTweaks = Join-Path $LocalAppDataRoot 'Subnautica2\Saved\Config\Windows'
    $targetGameIni      = Join-Path $targetPlayerTweaks 'game.ini'

    $targetUe4ss     = Join-Path $GameRoot 'Binaries\Win64\ue4ss'
    $targetUe4ssMods = Join-Path $targetUe4ss 'Mods'
    $targetMods      = Join-Path $GameRoot 'Content\Paks\~mods'
    $targetLogicMods = Join-Path $GameRoot 'Content\Paks\LogicMods'
    $targetDwmapi    = Join-Path $GameRoot 'Binaries\Win64\dwmapi.dll'

    $sourceUe4ssMods = Join-Path $script:EnabledMods 'Mods'
    $sourceMods      = Join-Path $script:EnabledMods '~mods'
    $sourceLogicMods = Join-Path $script:EnabledMods 'LogicMods'
    $sourceDwmapi    = Join-Path $script:UE4SSRoot 'dwmapi.dll'
    $sourceUe4ss     = Join-Path $script:UE4SSRoot 'ue4ss'

    Require-Directory -Path $sourceUe4ssMods
    Require-Directory -Path $sourceMods
    Require-Directory -Path $sourceLogicMods

    try {
        if (Test-Path -LiteralPath $targetGameIni -PathType Leaf) {
            Log "Deleting existing game.ini at $targetGameIni"
            Remove-Item -LiteralPath $targetGameIni -Force
        }

        Log "Copying $script:PlayerTweaks -> $targetPlayerTweaks"
        Copy-MergeDirectoryContents -Source $script:PlayerTweaks -Target $targetPlayerTweaks
        Set-FilesReadOnly -Target $targetPlayerTweaks

        if (-not (Test-Path -LiteralPath $sourceDwmapi -PathType Leaf)) {
            Log "[WARN] UE4SS is not installed. Run: powershell -File Helpers\Windows\Install-Ue4ssRelease.ps1"
            Log "[WARN] Or use the updater: .\Helpers\Operations.ps1 -Action updateue4ss"
        }

        Log "Copying UE4SS Core -> $targetUe4ss"
        if (Test-Path -LiteralPath $sourceUe4ss -PathType Container) {
            Copy-MergeDirectoryContents -Source $sourceUe4ss -Target $targetUe4ss
        }

        $sourceBuiltinMods = Join-Path $sourceUe4ss 'Mods'
        Log "Clearing $targetUe4ssMods"
        Clear-DirectoryContents -Target $targetUe4ssMods

        if (Test-Path -LiteralPath $sourceBuiltinMods -PathType Container) {
            Log "Copying UE4SS built-in mods -> $targetUe4ssMods"
            Copy-MergeDirectoryContents -Source $sourceBuiltinMods -Target $targetUe4ssMods
        }

        Log "Merging enabled UE4SS mods -> $targetUe4ssMods"
        Copy-MergeDirectoryContents -Source $sourceUe4ssMods -Target $targetUe4ssMods

        Log "Resetting $targetMods"
        Reset-Directory -Target $targetMods
        Log "Copying $sourceMods -> $targetMods"
        Copy-ModDirectories -SourcePath $sourceMods -TargetPath $targetMods

        Log "Resetting $targetLogicMods"
        Reset-Directory -Target $targetLogicMods
        Log "Copying $sourceLogicMods -> $targetLogicMods"
        Copy-ModDirectories -SourcePath $sourceLogicMods -TargetPath $targetLogicMods

        if (Test-Path -LiteralPath $sourceDwmapi -PathType Leaf) {
            $dwmapiDir = Split-Path -Parent $targetDwmapi
            if (-not (Test-Path -LiteralPath $dwmapiDir -PathType Container)) {
                New-Item -ItemType Directory -Path $dwmapiDir -Force | Out-Null
            }
            Log "Copying dwmapi.dll -> $targetDwmapi"
            Copy-Item -LiteralPath $sourceDwmapi -Destination $targetDwmapi -Force
        }

        Log "Mods deployed for app $AppId"
        return $true
    }
    catch {
        $msg = $_.Exception.Message
        # Detect file-locking errors (access denied, sharing violation)
        if ($msg -match 'Access.*denied|being used by another|sharing violation|UnauthorizedAccess|locked' -or
            $_.Exception -is [System.UnauthorizedAccessException] -or
            $_.Exception.HResult -eq -2147024864) {
            Log "[ERROR] Cannot write to game directory - a file is locked."
            Log "[ERROR] Please close Subnautica 2 completely before deploying mods."
        } else {
            Log "[ERROR] Deploy failed: $msg"
        }
        # Return false instead of re-throwing so the menu stays open
        return $false
    }
}


function Copy-ModDirectories {
    param([string]$SourcePath, [string]$TargetPath)
    
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) { return }

    # Copy loose files (e.g. .pak, .ucas, .utoc) directly in the source folder
    $looseFiles = @(Get-ChildItem -LiteralPath $SourcePath -File -Force)
    foreach ($file in $looseFiles) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $TargetPath $file.Name) -Force
    }

    # Copy mod subdirectories (UE4SS-style mods stored in subfolders) preserving folder name
    $modDirs = @(Get-ChildItem -LiteralPath $SourcePath -Directory | Sort-Object Name)
    foreach ($modDirInfo in $modDirs) {
        $destDir = Join-Path $TargetPath $modDirInfo.Name
        if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $modDirInfo.FullName -Destination $destDir -Recurse -Force
    }
}
