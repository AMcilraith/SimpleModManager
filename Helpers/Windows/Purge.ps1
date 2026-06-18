function Purge-Mods {
    param([string]$GameRoot, [string]$LocalAppDataRoot)

    $win64Root = Join-Path $GameRoot 'Binaries\Win64'
    $ue4ssRoot = Join-Path $win64Root 'ue4ss'
    $dwmapiPath = Join-Path $win64Root 'dwmapi.dll'
    $gameIniPath = Join-Path $LocalAppDataRoot 'Subnautica2\Saved\Config\Windows\game.ini'
    $engineIniPath = Join-Path $LocalAppDataRoot 'Subnautica2\Saved\Config\Windows\engine.ini'
    $extraModRoots = @(
        (Join-Path $GameRoot 'Content\Paks\~mods'),
        (Join-Path $GameRoot 'Content\Paks\LogicMods')
    )

    try {
        if (Test-Path -LiteralPath $ue4ssRoot -PathType Container) {
            Log "Removing $ue4ssRoot"
            Remove-Item -LiteralPath $ue4ssRoot -Recurse -Force -ErrorAction Stop
        } else { Log "UE4SS root not found: $ue4ssRoot" }

        if (Test-Path -LiteralPath $dwmapiPath -PathType Leaf) {
            Log "Removing $dwmapiPath"
            Remove-Item -LiteralPath $dwmapiPath -Force -ErrorAction Stop
        } else { Log "dwmapi.dll not present: $dwmapiPath" }

        if (Test-Path -LiteralPath $gameIniPath -PathType Leaf) {
            Log "Removing $gameIniPath"
            Remove-Item -LiteralPath $gameIniPath -Force -ErrorAction Stop
        } else { Log "game.ini not present: $gameIniPath" }

        if (Test-Path -LiteralPath $engineIniPath -PathType Leaf) {
            Log "Removing $engineIniPath"
            Remove-Item -LiteralPath $engineIniPath -Force -ErrorAction Stop
        } else { Log "engine.ini not present: $engineIniPath" }

        foreach ($extraModRoot in $extraModRoots) {
            if (Test-Path -LiteralPath $extraModRoot -PathType Container) {
                Log "Removing $extraModRoot"
                Remove-Item -LiteralPath $extraModRoot -Recurse -Force -ErrorAction Stop
            }
        }

        Log 'All UE4SS mods, game.ini, and engine.ini removed.'
        return $true
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'Access.*denied|being used by another|sharing violation|UnauthorizedAccess|locked' -or
            $_.Exception -is [System.UnauthorizedAccessException] -or
            $_.Exception.HResult -eq -2147024864) {
            Log '[ERROR] Cannot remove game files - a file is locked.'
            Log '[ERROR] Please close Subnautica 2 completely before purging mods.'
        } else {
            Log "[ERROR] Purge failed: $msg"
        }
        # Return false instead of re-throwing so the menu stays open
        return $false
    }
}
