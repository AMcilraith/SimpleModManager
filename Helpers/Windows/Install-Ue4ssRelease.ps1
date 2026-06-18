function Install-Ue4ssFromExtractedArchive {
    param(
        [string]$ExtractedRoot,
        [string]$VersionLabel = 'unknown',
        [string]$Ue4ssRoot = $script:UE4SSRoot
    )

    if (-not $Ue4ssRoot) {
        $sourceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $Ue4ssRoot = Join-Path $sourceRoot 'ModManager\UE4SS'
    }

    $extractedDwmapi = Get-ChildItem -LiteralPath $ExtractedRoot -Filter 'dwmapi.dll' -Recurse | Select-Object -First 1
    if (-not $extractedDwmapi) {
        throw 'dwmapi.dll not found in the UE4SS archive.'
    }

    $dwmapiRoot = Split-Path -Parent $extractedDwmapi.FullName
    $extractedUe4ss = Join-Path $dwmapiRoot 'ue4ss'
    $normalizedUe4ss = Join-Path ([System.IO.Path]::GetTempPath()) "ue4ss_install_$([Guid]::NewGuid().ToString('N'))"

    try {
        New-Item -ItemType Directory -Path $normalizedUe4ss -Force | Out-Null

        if (Test-Path -LiteralPath $extractedUe4ss -PathType Container) {
            Copy-Item -LiteralPath (Join-Path $extractedUe4ss '*') -Destination $normalizedUe4ss -Recurse -Force
        }
        else {
            $ue4ssPayloadNames = @(
                'UE4SS.dll', 'UE4SS-settings.ini', 'Mods', 'LICENSE', 'README.md',
                'UE4SS_Signatures', 'MemberVarLayoutTemplates', 'VTableLayoutTemplates',
                'CustomGameConfigs', 'MapGenBP', 'Changelog.md'
            )
            foreach ($name in $ue4ssPayloadNames) {
                $sourcePath = Join-Path $dwmapiRoot $name
                if (Test-Path -LiteralPath $sourcePath) {
                    Copy-Item -LiteralPath $sourcePath -Destination $normalizedUe4ss -Recurse -Force
                }
            }
            if (-not (Test-Path -LiteralPath (Join-Path $normalizedUe4ss 'UE4SS.dll') -PathType Leaf)) {
                throw 'UE4SS.dll not found in the UE4SS archive.'
            }
        }

        if (-not (Test-Path -LiteralPath $Ue4ssRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $Ue4ssRoot -Force | Out-Null
        }

        Copy-Item -LiteralPath $extractedDwmapi.FullName -Destination $Ue4ssRoot -Force

        $targetUe4ss = Join-Path $Ue4ssRoot 'ue4ss'
        if (Test-Path -LiteralPath $targetUe4ss -PathType Container) {
            Remove-Item -LiteralPath $targetUe4ss -Recurse -Force
        }
        Copy-Item -LiteralPath $normalizedUe4ss -Destination $targetUe4ss -Recurse -Force

        $versionFile = Join-Path $Ue4ssRoot 'ue4ss_version.txt'
        Set-Content -LiteralPath $versionFile -Value $VersionLabel -Encoding UTF8

        Log "Installed UE4SS $VersionLabel to $Ue4ssRoot"
        return $VersionLabel
    }
    finally {
        if (Test-Path -LiteralPath $normalizedUe4ss -PathType Container) {
            Remove-Item -LiteralPath $normalizedUe4ss -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-Ue4ssReleaseAsset {
    param($Release)

    $asset = $Release.assets | Where-Object {
        $_.name -match '^UE4SS_v.+\.zip$' -and $_.name -notmatch '^z'
    } | Select-Object -First 1

    if (-not $asset) {
        $asset = $Release.assets | Where-Object {
            $_.name -match '^UE4SS_Standard_.+\.zip$'
        } | Select-Object -First 1
    }

    if (-not $asset) {
        return $null
    }

    $downloadUrl = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/$($Release.tag_name)/$($asset.name)"
    return [pscustomobject]@{
        TagName     = $Release.tag_name
        Name        = $asset.name
        Size        = $asset.size
        DownloadUrl = $downloadUrl
    }
}

function Resolve-LatestUe4ssGitHubRelease {
    param([string]$TagName)

    $headers = @{ 'User-Agent' = 'SimpleModManager' }

    if ($TagName) {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases/tags/$TagName" -Headers $headers -TimeoutSec 30 -ErrorAction Stop
        $asset = Get-Ue4ssReleaseAsset -Release $release
        if (-not $asset) {
            throw "No standard UE4SS zip asset found in release '$TagName'."
        }
        return $asset
    }

    Log 'Querying UE4SS releases from GitHub...'
    $releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/UE4SS-RE/RE-UE4SS/releases?per_page=30' -Headers $headers -TimeoutSec 30 -ErrorAction Stop

    foreach ($release in $releases) {
        if ($release.prerelease) { continue }
        $asset = Get-Ue4ssReleaseAsset -Release $release
        if ($asset) {
            return $asset
        }
    }

    throw 'No stable UE4SS release with a standard zip asset was found on GitHub.'
}

function Install-Ue4ssFromGitHubRelease {
    param(
        [string]$TagName,
        [string]$Ue4ssRoot = $script:UE4SSRoot,
        [switch]$Force
    )

    if (-not $Ue4ssRoot) {
        $sourceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $Ue4ssRoot = Join-Path $sourceRoot 'ModManager\UE4SS'
    }

    $asset = Resolve-LatestUe4ssGitHubRelease -TagName $TagName
    $versionFile = Join-Path $Ue4ssRoot 'ue4ss_version.txt'
    if (-not $Force -and (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
        $installedVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
        if ($installedVersion -eq $asset.TagName) {
            Log "UE4SS $($asset.TagName) is already installed."
            return $asset.TagName
        }
        Log "Updating UE4SS from $installedVersion to $($asset.TagName)..."
    }
    else {
        Log "Installing UE4SS $($asset.TagName) from GitHub..."
    }

    $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "ue4ss_$($asset.TagName).zip"
    $tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) "ue4ss_$($asset.TagName)_extract"

    try {
        $sizeMb = if ($asset.Size) { [math]::Round($asset.Size / 1MB, 2) } else { '?' }
        Log "Downloading $($asset.Name) ($sizeMb MB)..."
        Log "  $($asset.DownloadUrl)"
        Invoke-WebRequest -Uri $asset.DownloadUrl -OutFile $tempZip -UserAgent 'SimpleModManager' -ErrorAction Stop

        if (Test-Path -LiteralPath $tempExtract) {
            Remove-Item -LiteralPath $tempExtract -Recurse -Force
        }
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        return Install-Ue4ssFromExtractedArchive -ExtractedRoot $tempExtract -VersionLabel $asset.TagName -Ue4ssRoot $Ue4ssRoot
    }
    finally {
        if (Test-Path -LiteralPath $tempZip -PathType Leaf) {
            Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $tempExtract -PathType Container) {
            Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    . (Join-Path $PSScriptRoot 'Common.ps1')
    Install-Ue4ssFromGitHubRelease @args
}
