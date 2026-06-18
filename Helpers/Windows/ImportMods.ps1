param(
    [string]$SourceRoot = '',
    [switch]$IncludeUe4ssCore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mmBase = Join-Path $repoRoot 'ModManager'

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $repoRoot 'Staging\Subnautica2'
}

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    Fail "Source staging folder not found: $SourceRoot`nExpected a Subnautica2 layout (Binaries/Win64/ue4ss, Content/Paks/~mods, etc.)."
}

function Copy-Children {
    param([string]$SrcPath, [string]$DstPath)

    if (-not (Test-Path -LiteralPath $SrcPath)) {
        Log "[SKIP] $SrcPath not found"
        return
    }

    if (-not (Test-Path -LiteralPath $DstPath)) {
        New-Item -ItemType Directory -Path $DstPath -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $SrcPath -Force | ForEach-Object {
        Log "  -> $($_.Name)"
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DstPath $_.Name) -Recurse -Force
    }
}

if ($IncludeUe4ssCore) {
    Log 'Copying UE4SS core...'
    $ue4ssSrc = Join-Path $SourceRoot 'Binaries\Win64\ue4ss'
    $ue4ssDst = Join-Path $mmBase 'UE4SS\ue4ss'
    Copy-Children -SrcPath $ue4ssSrc -DstPath $ue4ssDst

    $dwmapiSrc = Join-Path $SourceRoot 'Binaries\Win64\dwmapi.dll'
    $dwmapiDst = Join-Path $mmBase 'UE4SS\dwmapi.dll'
    if (Test-Path -LiteralPath $dwmapiSrc) {
        Copy-Item -LiteralPath $dwmapiSrc -Destination $dwmapiDst -Force
        Log '  -> dwmapi.dll'
    }
}

Log 'Copying UE4SS mods...'
$modsSrc = Join-Path $SourceRoot 'Binaries\Win64\ue4ss\Mods'
$modsDst = Join-Path $mmBase 'EnabledMods\Mods'
if (Test-Path -LiteralPath $modsSrc) {
    if (-not (Test-Path -LiteralPath $modsDst)) {
        New-Item -ItemType Directory -Path $modsDst -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $modsSrc -Directory | ForEach-Object {
        Log "  -> $($_.Name)"
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $modsDst $_.Name) -Recurse -Force
    }
}

Log 'Copying LogicMods...'
Copy-Children -SrcPath (Join-Path $SourceRoot 'Content\Paks\LogicMods') -DstPath (Join-Path $mmBase 'EnabledMods\LogicMods')

Log 'Copying ~mods...'
Copy-Children -SrcPath (Join-Path $SourceRoot 'Content\Paks\~mods') -DstPath (Join-Path $mmBase 'EnabledMods\~mods')

Log "[DONE] Imported mods from $SourceRoot into $mmBase"
