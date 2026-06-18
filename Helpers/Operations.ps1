param(
    [string]$Action = 'menu'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:SourceRoot = Split-Path -Parent $script:ScriptDir

$script:EnabledMods  = Join-Path $script:SourceRoot 'ModManager\EnabledMods'
$script:DisabledMods = Join-Path $script:SourceRoot 'ModManager\DisabledMods'
$script:UE4SSRoot    = Join-Path $script:SourceRoot 'ModManager\UE4SS'
$script:DisabledUE4SS= Join-Path $script:SourceRoot 'ModManager\DisabledUE4SS'
$script:EngineTweaks = Join-Path $script:SourceRoot 'ModManager\EngineTweaks'
$script:PlayerTweaks = Join-Path $script:SourceRoot 'ModManager\PlayerTweaks'

$requiredScripts = @(
    (Join-Path $script:ScriptDir 'Windows\Common.ps1'),
    (Join-Path $script:ScriptDir 'Windows\Deploy.ps1'),
    (Join-Path $script:ScriptDir 'Windows\Purge.ps1'),
    (Join-Path $script:ScriptDir 'Windows\Launch.ps1'),
    (Join-Path $script:ScriptDir 'Windows\ModManager.ps1'),
    (Join-Path $script:ScriptDir 'Windows\Update.ps1'),
    (Join-Path $script:ScriptDir 'Windows\Install-Ue4ssRelease.ps1'),
    (Join-Path $script:ScriptDir 'Windows\EngineTweaks.ps1')
)
foreach ($scriptFile in $requiredScripts) {
    if (-not (Test-Path -LiteralPath $scriptFile -PathType Leaf)) {
        Write-Error "Required helper script not found: $scriptFile"
        Read-Host 'Press Enter to exit' | Out-Null
        exit 1
    }
}

. (Join-Path $script:ScriptDir 'Windows\Common.ps1')
. (Join-Path $script:ScriptDir 'Windows\Deploy.ps1')
. (Join-Path $script:ScriptDir 'Windows\Purge.ps1')
. (Join-Path $script:ScriptDir 'Windows\Launch.ps1')
. (Join-Path $script:ScriptDir 'Windows\ModManager.ps1')
. (Join-Path $script:ScriptDir 'Windows\Update.ps1')
. (Join-Path $script:ScriptDir 'Windows\Install-Ue4ssRelease.ps1')
. (Join-Path $script:ScriptDir 'Windows\EngineTweaks.ps1')

if (Test-Path -LiteralPath (Join-Path $script:ScriptDir '.env') -PathType Leaf) {
    Get-Content -LiteralPath (Join-Path $script:ScriptDir '.env') | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            $name = $Matches[1].Trim()
            $value = $Matches[2].Trim().Trim('"').Trim("'")
            Set-Item -Path "env:$name" -Value $value
        }
    }
}

function Show-UpdaterMenu {
    Invoke-UpdateUE4SS
}

function Show-PlayMenu {
    $cursor = 0
    while ($true) {
        $options = @(
            "[1] Launch Standard",
            "[2] Launch with Debug Console"
        )
        $descriptions = @(
            "Launches Subnautica 2 normally via Steam with your active mods enabled.",
            "Launches the game and opens the UE4SS debug console window for troubleshooting and viewing logs."
        )
        $context = Resolve-Context
        $choice = Get-MenuSelection -Title "PLAY GAME" -Options $options -DefaultIndex $cursor -Descriptions $descriptions
        $cursor = $choice
        switch ($choice) {
            0 { Launch-Game -AppId $context.AppId; return }
            1 {
                Enable-Ue4ssDebugConsole -GameRoot $context.GameRoot
                Launch-Game -AppId $context.AppId -DebugLog
                return
            }
            -1 { return }
        }
    }
}

function Reset-TerminalToMenu {
    Clear-Host
}

function Reset-InvalidInputToMenu {
    param([string]$InputValue)
    if ([string]::IsNullOrWhiteSpace($InputValue)) { Log 'No selection entered.' }
    else { Log "Invalid selection: $InputValue" }
    Reset-TerminalToMenu
}

function Invoke-Action {
    param([string]$SelectedAction)
    $context = Resolve-Context
    switch ($SelectedAction) {
        'launch'     { Launch-Game -AppId $context.AppId }
        'debug'      {
            Enable-Ue4ssDebugConsole -GameRoot $context.GameRoot
            Launch-Game -AppId $context.AppId -DebugLog
        }
        'deploy'     { Deploy-Mods -GameRoot $context.GameRoot -AppId $context.AppId -LocalAppDataRoot $context.LocalAppDataRoot }
        'purge'      { Purge-Mods -GameRoot $context.GameRoot -LocalAppDataRoot $context.LocalAppDataRoot }
        'modmanager' { Start-ModManager }
        'updateue4ss' { Invoke-UpdateUE4SS }
        default      { Fail "Unknown action: $SelectedAction" }
    }
}

function Start-InteractiveMenu {
    $cursor = 0
    while ($true) {
        $options = @(
            "[1] Play Game",
            "-",
            "[2] Mod Manager",
            "[3] Deploy Mods to Game",
            "[4] Purge Mods and Revert to Vanilla",
            "[5] Updater"
        )
        $descriptions = @(
            "Opens the Play Game sub-menu, offering options to launch the game normally or with the debug console.",
            "",
            "Opens the Mod Manager, where you can toggle individual mods, modpacks, and engine/player tweaks.",
            "Deploys your configured mods, plugins, and tweaks to the game directories so they load when playing.",
            "Removes all deployed mods, plugins, and configurations from the game directories, reverting to clean vanilla.",
            "Queries https://github.com/UE4SS-RE/RE-UE4SS/releases for the latest stable UE4SS build."
        )
        $choice = Get-MenuSelection -Title "SIMPLE SN2 MODLOADER" -Options $options -DefaultIndex $cursor -Descriptions $descriptions
        $cursor = $choice
        switch ($choice) {
            0 { Show-PlayMenu; $cursor = 0 }
            2 { Start-ModManager; $cursor = 2 }
            3 { Invoke-Action -SelectedAction 'deploy'; Reset-TerminalToMenu; $cursor = 3 }
            4 { Invoke-Action -SelectedAction 'purge'; Reset-TerminalToMenu; $cursor = 4 }
            5 { Show-UpdaterMenu; Reset-TerminalToMenu; $cursor = 5 }
            -1 { exit 0 }
        }
    }
}


function Show-Usage {
    @'
Usage: .\Operations.ps1 [-Action menu|launch|debug|deploy|purge|modmanager|updateue4ss|info|help]

Engine.ini preset sources:
  Performance (Ghostiexd): https://www.nexusmods.com/subnautica2/mods/51
  Quality (Vercadi):       https://www.nexusmods.com/subnautica2/mods/37

Environment overrides:
  STEAM_ROOT        Override the detected Steam root.
  TARGET_GAME_ROOT  Override the detected Subnautica2 install root.
  STEAM_APP_ID      Override the detected Steam app ID.

Workflow tips:
    1) Use Mod Manager to toggle mods and presets first.
    2) Run Deploy to apply your selections to the game folder.
    3) Use Purge to cleanly return to vanilla.

First-time setup:
    Install UE4SS: .\Helpers\Operations.ps1 -Action updateue4ss
    Or: powershell -File Helpers\Windows\Install-Ue4ssRelease.ps1

Layout expectations:
    ModManager\EnabledMods\{Mods,~mods,LogicMods} must exist.
    ModManager\UE4SS is populated by the UE4SS installer (not stored in git).
'@ | Write-Host
}

function Show-GeneralHelp {
    $text = @'
USAGE
    .\Operations.ps1 -Action menu
    .\Operations.ps1 -Action deploy
    .\Operations.ps1 -Action purge
    .\Operations.ps1 -Action modmanager
    .\Operations.ps1 -Action updateue4ss

MANAGING MODS
    - Use Mod Manager to toggle mods and engine/player tweaks.
    - After changes, run Deploy to sync files into the game directory.
    - Use Purge to remove all deployed files and return to vanilla.

TROUBLESHOOTING
    - If Steam or the game root is not detected, set STEAM_ROOT or TARGET_GAME_ROOT.
    - Missing helper scripts or mod folders will stop execution with an error.
'@
    Show-HelpPopup -Title 'INFO / USAGE' -Description $text
}

try {
    $normalizedAction = if ($null -eq $Action) { 'menu' } else { $Action.Trim().ToLowerInvariant() }
    switch ($normalizedAction) {
        'menu' { Start-InteractiveMenu }
        'help' { Show-Usage }
        'info' { Show-GeneralHelp }
        '-h' { Show-Usage }
        '--help' { Show-Usage }
        default {
            Invoke-Action -SelectedAction $normalizedAction
            Reset-TerminalToMenu
            Start-InteractiveMenu
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    Read-Host 'Press Enter to exit' | Out-Null
    exit 1
}
