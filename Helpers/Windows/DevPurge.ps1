# DevPurge.ps1 - Developer utility to wipe all mods from the mod manager's EnabledMods and DisabledMods
# Usage: powershell -ExecutionPolicy Bypass -File DevPurge.ps1
# WARNING: This permanently deletes all mod content from the mod manager. Re-import via ImportMods.ps1.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mmBase = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'ModManager'

$targets = @(
    @{ Label = 'EnabledMods\Mods (UE4SS)';      Path = Join-Path $mmBase 'EnabledMods\Mods' },
    @{ Label = 'EnabledMods\~mods (BP Patch)';   Path = Join-Path $mmBase 'EnabledMods\~mods' },
    @{ Label = 'EnabledMods\LogicMods (BP Logic)';Path = Join-Path $mmBase 'EnabledMods\LogicMods' },
    @{ Label = 'DisabledMods\Mods';              Path = Join-Path $mmBase 'DisabledMods\Mods' },
    @{ Label = 'DisabledMods\~mods';             Path = Join-Path $mmBase 'DisabledMods\~mods' },
    @{ Label = 'DisabledMods\LogicMods';         Path = Join-Path $mmBase 'DisabledMods\LogicMods' },
    @{ Label = 'UE4SS (core + dwmapi.dll)';      Path = Join-Path $mmBase 'UE4SS' }
)

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "  ║          DEV PURGE - MOD MANAGER WIPE            ║" -ForegroundColor Red
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""
Write-Host "  This will DELETE all mods from the SimpleModManager_Base" -ForegroundColor Yellow
Write-Host "  mod library. Run ImportMods.ps1 to restore from source." -ForegroundColor Yellow
Write-Host ""
Write-Host "  The following directories will be EMPTIED:" -ForegroundColor DarkGray
foreach ($t in $targets) {
    Write-Host "    - $($t.Label)" -ForegroundColor DarkGray
}
Write-Host ""
$confirm = Read-Host "  Type 'yes' to confirm and proceed"
if ($confirm -ne 'yes') {
    Write-Host "  Aborted." -ForegroundColor Cyan
    exit 0
}

Write-Host ""
foreach ($t in $targets) {
    $path = $t.Path
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Write-Host "  [SKIP] $($t.Label) — directory not found" -ForegroundColor DarkGray
        continue
    }
    Write-Host "  [WIPE] $($t.Label)..." -ForegroundColor Yellow
    Get-ChildItem -LiteralPath $path -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "  [DONE] Mod manager wiped. Re-import mods with:" -ForegroundColor Green
Write-Host "         powershell -ExecutionPolicy Bypass -File Helpers\Windows\ImportMods.ps1" -ForegroundColor Cyan
Write-Host ""
