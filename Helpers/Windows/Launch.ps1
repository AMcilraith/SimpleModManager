function Enable-Ue4ssDebugConsole {
    param([string]$GameRoot)
    $settingsPath = Join-Path $GameRoot 'Binaries\Win64\ue4ss\UE4SS-settings.ini'
    Require-File -Path $settingsPath
    Set-IniValue -Path $settingsPath -Key 'GuiConsoleEnabled' -Value '1'
    Set-IniValue -Path $settingsPath -Key 'GuiConsoleVisible' -Value '1'
    Log "Enabled UE4SS GUI console in $settingsPath"
}

function Launch-Game {
    param([string]$AppId, [switch]$DebugLog)
    if ($DebugLog) {
        Log "Launching Subnautica 2 via Steam app ID $AppId with -log"
        Start-Process "steam://run/$AppId//-log" | Out-Null
        return
    }
    Log "Launching Subnautica 2 via Steam app ID $AppId"
    Start-Process "steam://rungameid/$AppId" | Out-Null
}
