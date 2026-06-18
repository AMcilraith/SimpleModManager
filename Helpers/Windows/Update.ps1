function Invoke-UpdateUE4SS {
    if (-not $script:SourceRoot) {
        $script:SourceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }
    if (-not $script:ModUpdates) {
        $script:ModUpdates = Join-Path $script:SourceRoot 'Helpers\ModUpdates'
    }
    if (-not (Test-Path -LiteralPath $script:ModUpdates -PathType Container)) {
        New-Item -ItemType Directory -Path $script:ModUpdates -Force | Out-Null
    }
    $script:UpdateRunLog = Join-Path $script:ModUpdates 'update_run.log'
    Add-Content -Path $script:UpdateRunLog -Value ("`n=== UE4SS update run started: $(Get-Date) ===")

    . (Join-Path $PSScriptRoot 'Install-Ue4ssRelease.ps1')
    try {
        Install-Ue4ssFromGitHubRelease | Out-Null
    }
    catch {
        Log "[ERROR] Failed to install UE4SS from GitHub: $($_.Exception.Message)"
        Log 'Source: https://github.com/UE4SS-RE/RE-UE4SS/releases'
    }
}
