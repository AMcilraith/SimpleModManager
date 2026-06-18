param(
    [string[]]$PackagedRoots = @(),
    [string[]]$ModNames = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$enabledMods = Join-Path $repoRoot 'ModManager\EnabledMods'

function Import-PackagedMod {
    param(
        [string]$PackagedRoot,
        [string]$ModName
    )

    $subnautica2 = Join-Path $PackagedRoot "$ModName\Subnautica2"
    if (-not (Test-Path -LiteralPath $subnautica2 -PathType Container)) {
        Log "[SKIP] $ModName (no Subnautica2 folder under $PackagedRoot)"
        return
    }

    $ue4ssSrc = Join-Path $subnautica2 'Binaries\Win64\ue4ss\Mods'
    if (Test-Path -LiteralPath $ue4ssSrc -PathType Container) {
        $ue4ssDst = Join-Path $enabledMods 'Mods'
        foreach ($modDir in Get-ChildItem -LiteralPath $ue4ssSrc -Directory) {
            $target = Join-Path $ue4ssDst $modDir.Name
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            Log "Syncing UE4SS mod $($modDir.Name) from $ModName"
            Copy-Item -LiteralPath $modDir.FullName -Destination $target -Recurse -Force
        }
    }

    $paksSrc = Join-Path $subnautica2 'Content\Paks\~mods'
    if (Test-Path -LiteralPath $paksSrc -PathType Container) {
        $paksDst = Join-Path $enabledMods '~mods'
        foreach ($pakItem in Get-ChildItem -LiteralPath $paksSrc -Force) {
            $target = Join-Path $paksDst $pakItem.Name
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            Log "Syncing pak item $($pakItem.Name) from $ModName"
            Copy-Item -LiteralPath $pakItem.FullName -Destination $target -Recurse -Force
        }
    }
}

if ($PackagedRoots.Count -eq 0) {
    $defaultRoot = Join-Path (Split-Path -Parent $repoRoot) 'RealisticSurvival\Packaged'
    if (Test-Path -LiteralPath $defaultRoot) {
        $PackagedRoots = @($defaultRoot)
    }
    else {
        Fail 'No packaged roots specified and default RealisticSurvival\Packaged folder was not found.'
    }
}

foreach ($packagedRoot in $PackagedRoots) {
    if (-not (Test-Path -LiteralPath $packagedRoot -PathType Container)) {
        Log "[WARN] Skipping missing packaged root: $packagedRoot"
        continue
    }

    $names = if ($ModNames.Count -gt 0) {
        $ModNames
    }
    else {
        @(Get-ChildItem -LiteralPath $packagedRoot -Directory | ForEach-Object { $_.Name })
    }

    Log "Syncing $($names.Count) mod(s) from $packagedRoot"
    foreach ($modName in $names) {
        Import-PackagedMod -PackagedRoot $packagedRoot -ModName $modName
    }
}

Log 'Packaged mod sync finished.'
