function Fail {
    param([string]$Message)
    throw "Error: $Message"
}

function Log {
    param([string]$Message, [string]$Level = "INFO")
    
    $cleanMsg = $Message.Trim()
    if ($cleanMsg -match "^\[(INFO|WARN|ERROR|SUCCESS|DEBUG)\]\s*(.*)") {
        $Level = $Matches[1]
        $cleanMsg = $Matches[2]
    }
    
    $color = "Cyan"
    if ($Level -eq "WARN") { $color = "Yellow" }
    elseif ($Level -eq "ERROR") { $color = "Red" }
    elseif ($Level -eq "SUCCESS") { $color = "Green" }
    elseif ($Level -eq "DEBUG") { $color = "DarkGray" }
    
    Write-Host "  [$Level] " -NoNewline -ForegroundColor $color
    Write-Host $cleanMsg
}

function Require-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Fail "Required directory not found: $Path"
    }
}

function Require-File {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "Required file not found: $Path"
    }
}

function Get-SteamRoot {
    if ($env:STEAM_ROOT) { return $env:STEAM_ROOT }
    $regPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if ($regPath -and (Test-Path -LiteralPath (Join-Path $regPath 'steamapps') -PathType Container)) {
        return $regPath
    }
    $regPath2 = (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    if ($regPath2 -and (Test-Path -LiteralPath (Join-Path $regPath2 'steamapps') -PathType Container)) {
        return $regPath2
    }
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Steam'),
        (Join-Path $env:ProgramFiles 'Steam'),
        (Join-Path $env:LocalAppData 'Steam')
    ) | Where-Object { $_ }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'steamapps') -PathType Container) {
            return $candidate
        }
    }
    Fail 'Unable to locate Steam root. Set STEAM_ROOT to override.'
}

function Get-SteamLibraries {
    param([string]$SteamRoot)
    $libraries = New-Object System.Collections.Generic.List[string]
    $libraries.Add($SteamRoot)
    $libraryFile = Join-Path $SteamRoot 'steamapps\libraryfolders.vdf'
    if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) { return $libraries.ToArray() }
    $pattern = '"[Pp][Aa][Tt][Hh]"\s+"([^"]+)"'
    foreach ($line in Get-Content -LiteralPath $libraryFile) {
        $match = [regex]::Match($line, $pattern)
        if (-not $match.Success) { continue }
        $libraryPath = ($match.Groups[1].Value -replace '\\\\', '\').TrimEnd('\').TrimEnd('/')
        if (-not [string]::IsNullOrWhiteSpace($libraryPath) -and -not $libraries.Contains($libraryPath)) {
            $libraries.Add($libraryPath)
        }
    }
    return $libraries.ToArray()
}

function Resolve-AppManifest {
    param([string]$SteamRoot)
    foreach ($library in Get-SteamLibraries -SteamRoot $SteamRoot) {
        $steamApps = Join-Path $library 'steamapps'
        if (-not (Test-Path -LiteralPath $steamApps -PathType Container)) { continue }
        $manifests = Get-ChildItem -LiteralPath $steamApps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue
        foreach ($manifest in $manifests) {
            if (Select-String -LiteralPath $manifest.FullName -Pattern '"name"\s+"Subnautica 2"|"name"\s+"Subnautica2"' -Quiet) {
                return $manifest.FullName
            }
        }
    }
    return $null
}

function Get-AppIdFromManifest {
    param([string]$ManifestPath)
    $baseName = Split-Path -Leaf $ManifestPath
    $match = [regex]::Match($baseName, '^appmanifest_(\d+)\.acf$')
    if (-not $match.Success) { Fail "Failed to extract Steam app ID from $ManifestPath" }
    return $match.Groups[1].Value
}

function Resolve-GameRoot {
    param([string]$SteamRoot)
    if ($env:TARGET_GAME_ROOT) { return $env:TARGET_GAME_ROOT }
    foreach ($library in Get-SteamLibraries -SteamRoot $SteamRoot) {
        $base = Join-Path $library 'steamapps\common\Subnautica2'
        $candidates = @((Join-Path $base 'Subnautica2'), $base)
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath (Join-Path $candidate 'Content\Paks') -PathType Container) {
                return $candidate
            }
        }
    }
    Fail 'Unable to locate Subnautica2 game root. Set TARGET_GAME_ROOT to override.'
}

function Resolve-LocalAppDataRoot {
    param([string]$SteamRoot, [string]$AppId, [string]$GameRoot)
    if ($env:LOCALAPPDATA) { return $env:LOCALAPPDATA }
    foreach ($library in Get-SteamLibraries -SteamRoot $SteamRoot) {
        $candidate = Join-Path $library "steamapps\compatdata\$AppId\pfx\drive_c\users\steamuser\AppData\Local"
        if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
    $compatCandidate = Join-Path (Split-Path -Parent (Split-Path -Parent $GameRoot)) "compatdata\$AppId\pfx\drive_c\users\steamuser\AppData\Local"
    if (Test-Path -LiteralPath $compatCandidate -PathType Container) { return $compatCandidate }
    Fail "Unable to locate local app data for app $AppId. Launch the game once in Steam or set TARGET_GAME_ROOT/STEAM_APP_ID correctly."
}

function Set-IniValue {
    param([string]$Path, [string]$Key, [string]$Value)
    Require-File -Path $Path
    $lines = Get-Content -LiteralPath $Path
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) {
            $lines[$i] = "$Key = $Value"
            $updated = $true
        }
    }
    if (-not $updated) { $lines += "$Key = $Value" }
    Set-Content -LiteralPath $Path -Value $lines
}

function Resolve-Context {
    $steamRoot = Get-SteamRoot
    $manifest = Resolve-AppManifest -SteamRoot $steamRoot
    if (-not $manifest) { Fail 'Unable to determine Steam app manifest for Subnautica 2.' }
    $appId = if ($env:STEAM_APP_ID) { $env:STEAM_APP_ID } else { Get-AppIdFromManifest -ManifestPath $manifest }
    $gameRoot = Resolve-GameRoot -SteamRoot $steamRoot
    $localAppDataRoot = Resolve-LocalAppDataRoot -SteamRoot $steamRoot -AppId $appId -GameRoot $gameRoot
    return [pscustomobject]@{
        SteamRoot        = $steamRoot
        AppId            = $appId
        GameRoot         = $gameRoot
        LocalAppDataRoot = $localAppDataRoot
    }
}

function Show-HelpPopup {
    param([string]$Title, [string]$Description)
    Clear-Host
    
    $cleanTitle = $Title -replace '^\[[a-zA-Z0-9]\]\s+', ''
    
    $cTopLeft = [char]0x250C
    $cHorizontal = [char]0x2500
    $cTopRight = [char]0x2510
    $cVertical = [char]0x2502
    $cDividerLeft = [char]0x251C
    $cDividerRight = [char]0x2524
    $cBottomLeft = [char]0x2514
    $cBottomRight = [char]0x2518

    $borderLine = "$($cHorizontal)" * 60
    
    Write-Host "$cTopLeft$borderLine$cTopRight" -ForegroundColor Cyan
    $head = " HELP: $cleanTitle"
    $head = $head.PadRight(60)
    Write-Host "$cVertical" -NoNewline -ForegroundColor Cyan
    Write-Host $head -ForegroundColor Yellow -NoNewline
    Write-Host "$cVertical" -ForegroundColor Cyan
    Write-Host "$cDividerLeft$borderLine$cDividerRight" -ForegroundColor Cyan
    
    $rawLines = $Description -split '\r?\n'
    $lines = @()
    foreach ($rLine in $rawLines) {
        $words = $rLine -split '\s+'
        $currentLine = ""
        foreach ($word in $words) {
            if ($word -eq "") { continue }
            if (($currentLine.Length + $word.Length + 1) -gt 56) {
                $lines += $currentLine
                $currentLine = $word
            }
            else {
                if ($currentLine -eq "") { $currentLine = $word }
                else { $currentLine += " $word" }
            }
        }
        if ($currentLine -ne "") {
            $lines += $currentLine
        }
        else {
            $lines += ""
        }
    }
    
    foreach ($line in $lines) {
        $formatted = "  $line"
        $formatted = $formatted.PadRight(60)
        Write-Host "$cVertical" -NoNewline -ForegroundColor Cyan
        Write-Host $formatted -ForegroundColor Gray -NoNewline
        Write-Host "$cVertical" -ForegroundColor Cyan
    }
    
    Write-Host "$cDividerLeft$borderLine$cDividerRight" -ForegroundColor Cyan
    $foot = "  Press any key to return..."
    $foot = $foot.PadRight(60)
    Write-Host "$cVertical" -NoNewline -ForegroundColor Cyan
    Write-Host $foot -ForegroundColor DarkGray -NoNewline
    Write-Host "$cVertical" -ForegroundColor Cyan
    Write-Host "$cBottomLeft$borderLine$cBottomRight" -ForegroundColor Cyan
    
    [Console]::ReadKey($true) | Out-Null
}

function Get-MenuSelection {
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$DefaultIndex = 0,
        [string[]]$Colors = $null,
        [string[]]$Descriptions = $null,
        [switch]$MultiSelect
    )
    Clear-Host
    $selectedIndices = @()
    $cTopLeft    = [char]0x250C
    $cHorizontal = [char]0x2500
    $cTopRight   = [char]0x2510
    $cVertical   = [char]0x2502
    $cDivLeft    = [char]0x251C
    $cDivRight   = [char]0x2524
    $cBotLeft    = [char]0x2514
    $cBotRight   = [char]0x2518

    $borderLine    = $cHorizontal.ToString() * 60
    $topBorder     = "$cTopLeft$borderLine$cTopRight"
    $dividerBorder = "$cDivLeft$borderLine$cDivRight"
    $bottomBorder  = "$cBotLeft$borderLine$cBotRight"

    $ESC         = [char]27
    $clearLine   = "$ESC[2K`r"
    $resetColor  = "$ESC[0m"

    $colorMap = @{
        'Cyan'    = "$ESC[96m"
        'Green'   = "$ESC[92m"
        'Red'     = "$ESC[91m"
        'Yellow'  = "$ESC[93m"
        'Gray'    = "$ESC[37m"
        'DarkGray'= "$ESC[90m"
        'White'   = "$ESC[97m"
    }
    $colCyan     = $colorMap['Cyan']
    $colGray     = $colorMap['Gray']
    $colDarkGray = $colorMap['DarkGray']

    $global:MenuAction = "Select"
    $hotkeyMap = @{}
    for ($i = 0; $i -lt $Options.Length; $i++) {
        if ($Options[$i] -eq '-') { continue }
        if ($Options[$i] -match '\[([a-zA-Z0-9])\]') {
            $hotkeyMap[$Matches[1].ToUpper()] = $i
        }
    }

    $cursor = $DefaultIndex
    if ($cursor -lt 0 -or $cursor -ge $Options.Length) { $cursor = 0 }
    while ($cursor -lt $Options.Length -and $Options[$cursor] -eq '-') { $cursor++ }
    if ($cursor -ge $Options.Length) { $cursor = 0 }

    $menuTop = -1  # row where menu starts; -1 means first draw

    while ($true) {
        # On first draw, record position. On subsequent draws, jump back.
        if ($menuTop -lt 0) {
            $menuTop = [Console]::CursorTop
        } else {
            [Console]::SetCursorPosition(0, $menuTop)
        }

        $sb = [System.Text.StringBuilder]::new(4096)

        # Title
        [void]$sb.Append("$clearLine$colCyan$topBorder$resetColor`n")
        $pad = [Math]::Max(0, [Math]::Floor((60 - $Title.Length) / 2))
        $titleLine = ((' ' * $pad) + $Title).PadRight(60)
        [void]$sb.Append("$clearLine$colCyan$cVertical$resetColor$titleLine$colCyan$cVertical$resetColor`n")
        [void]$sb.Append("$clearLine$colCyan$dividerBorder$resetColor`n")

        for ($i = 0; $i -lt $Options.Length; $i++) {
            if ($Options[$i] -eq '-') {
                [void]$sb.Append("$clearLine$colCyan$dividerBorder$resetColor`n")
                continue
            }

            $prefixAnsi = if ($i -eq $cursor) { "$ESC[96m-->" } else { "$ESC[37m   " }
            $fg = if ($Colors -and $i -lt $Colors.Length -and $Colors[$i] -and $colorMap.ContainsKey($Colors[$i])) {
                $colorMap[$Colors[$i]]
            } else { $colGray }

            $checkStr = ''
            if ($MultiSelect) {
                $checkStr = if ($selectedIndices -contains $i) { '[X] ' } else { '[ ] ' }
            }

            $rawText = $Options[$i]
            $padLen  = [Math]::Max(0, 56 - $rawText.Length - $checkStr.Length)
            $padStr  = ' ' * $padLen

            if ($rawText -match '^(\[[0-9a-zA-Z]+\])(.*)$') {
                $content = "$checkStr$fg$($Matches[1])$colGray$($Matches[2])$padStr"
            } else {
                $content = "$checkStr$fg$rawText$padStr"
            }

            [void]$sb.Append("$clearLine$colCyan$cVertical$resetColor$prefixAnsi $resetColor$content$colCyan$cVertical$resetColor`n")
        }

        [void]$sb.Append("$clearLine$colCyan$bottomBorder$resetColor`n")

        [Console]::Write($sb.ToString())

        $key    = [Console]::ReadKey($true)
        $isCtrl = ($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0

        switch ($key.Key) {
            "UpArrow" {
                if ($isCtrl) { $global:MenuAction = "CtrlUp"; return $cursor }
                do {
                    $cursor--
                    if ($cursor -lt 0) { $cursor = $Options.Length - 1 }
                } while ($Options[$cursor] -eq '-')
            }
            "DownArrow" {
                if ($isCtrl) { $global:MenuAction = "CtrlDown"; return $cursor }
                do {
                    $cursor++
                    if ($cursor -ge $Options.Length) { $cursor = 0 }
                } while ($Options[$cursor] -eq '-')
            }
            "Enter" {
                if ($MultiSelect) {
                    $global:MenuAction = "Select"
                    if ($selectedIndices.Count -eq 0) { return ,@($cursor) }
                    return ,@($selectedIndices)
                } else {
                    $global:MenuAction = "Toggle"
                    return $cursor
                }
            }
            "Spacebar" {
                if ($MultiSelect) {
                    if ($selectedIndices -contains $cursor) {
                        $selectedIndices = @($selectedIndices | Where-Object { $_ -ne $cursor })
                    } else {
                        $selectedIndices += $cursor
                    }
                }
            }
            "Escape" {
                $global:MenuAction = "Select"
                if ($hotkeyMap.ContainsKey('X')) { return $hotkeyMap['X'] }
                if ($hotkeyMap.ContainsKey('B')) { return $hotkeyMap['B'] }
                return -1
            }
            "H" {
                if ($Descriptions) {
                    $desc = if ($Descriptions[$cursor]) { $Descriptions[$cursor] } else { "No description available." }
                    Show-HelpPopup -Title $Options[$cursor] -Description $desc
                    # Full clear after popup so menu redraws cleanly from current position
                    Clear-Host
                    $menuTop = -1
                }
            }
            default {
                $char = $key.KeyChar.ToString().ToUpper()
                if ($hotkeyMap.ContainsKey($char)) { $global:MenuAction = "Select"; return $hotkeyMap[$char] }
                if ($char -eq 'T') { $global:MenuAction = "Toggle"; return $cursor }
                if ($char -eq 'D') { $global:MenuAction = "Delete"; return $cursor }
            }
        }
    }
}


function Get-CurrentLoadOrder {
    param([string]$EnabledPath, [string]$DisabledPath, [string]$LoadOrderFile, [bool]$IsUe4ss)
    
    $existingNames = @()
    if (Test-Path -LiteralPath $EnabledPath -PathType Container) {
        $existingNames += Get-ChildItem -LiteralPath $EnabledPath -Directory | Select-Object -ExpandProperty Name
    }
    if (Test-Path -LiteralPath $DisabledPath -PathType Container) {
        $existingNames += Get-ChildItem -LiteralPath $DisabledPath -Directory | Select-Object -ExpandProperty Name
    }
    
    if (-not $IsUe4ss) {
        return ($existingNames | Sort-Object -Unique)
    }

    $order = @()
    if ($IsUe4ss) {
        if (Test-Path -LiteralPath $LoadOrderFile -PathType Leaf) {
            foreach ($line in Get-Content -LiteralPath $LoadOrderFile) {
                if ($line -match '^\s*([^;:][^:]+?)\s*:\s*(0|1)') {
                    $name = $Matches[1].Trim()
                    if ($existingNames -contains $name) {
                        $order += $name
                    }
                }
            }
        }
    }
    
    $missing = @()
    foreach ($name in $existingNames) {
        if (-not $order.Contains($name)) {
            $missing += $name
        }
    }
    $missing = $missing | Sort-Object
    return ($order + $missing)
}

function Save-CurrentLoadOrder {
    param([string[]]$Order, [string]$LoadOrderFile, [string]$EnabledPath, [bool]$IsUe4ss)
    
    if (-not $IsUe4ss) {
        if (Test-Path -LiteralPath $LoadOrderFile -PathType Leaf) {
            Remove-Item -LiteralPath $LoadOrderFile -Force
        }
        return
    }

    $lines = @()
    $enabledDirs = @()
    if (Test-Path -LiteralPath $EnabledPath -PathType Container) {
        $enabledDirs = Get-ChildItem -LiteralPath $EnabledPath -Directory | Select-Object -ExpandProperty Name
    }

    foreach ($name in $Order) {
        if ($name -eq "Keybinds" -or $name -eq "UnlockAllConstructs") { continue }
        $state = if ($enabledDirs -contains $name) { "1" } else { "0" }
        $lines += "$name : $state"
    }

    $lines += ""
    $lines += "; Built-in keybinds, do not move up!"
    $keybindState = if ($enabledDirs -contains "Keybinds") { "1" } else { "0" }
    $lines += "Keybinds : $keybindState"
    $lines += "UnlockAllConstructs : 1"

    Set-Content -LiteralPath $LoadOrderFile -Value $lines
}
