<#
.SYNOPSIS
  Installs the Geist Mono Nerd Font for the current Windows user and makes
  Windows Terminal use it. No admin rights needed. Safe to run twice.

.DESCRIPTION
  On WSL the text is drawn by Windows Terminal with Windows' own fonts, so the
  Nerd Font icons used by starship, tmux and Neovim show up as boxes unless the
  font is installed on Windows too. This script:

    1. downloads the pinned Nerd Fonts release of GeistMono and verifies its SHA-256,
    2. copies the TTF/OTF files to %LOCALAPPDATA%\Microsoft\Windows\Fonts and
       registers them under HKCU (the per-user font mechanism of Windows 10 1809+),
    3. for each Windows Terminal settings.json found (stable, preview, unpackaged):
       backs it up, then sets profiles.defaults.font.face (and the font of any
       WSL profile that overrides it) to the font. Skipped when already set.

  The font is the same Nerd Fonts release that nixpkgs ships to Arch and Ubuntu
  (nerd-fonts.geist-mono), so the glyphs match on every target.

  Windows Terminal's settings.json may contain comments; they are not kept when
  the file is rewritten, which is what the backup is for.

  Run from PowerShell:   powershell -ExecutionPolicy Bypass -File windows\setup.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Pinned release. When bumping, take the hash from the release's SHA-256.txt.
$Version  = 'v3.4.0'
$Archive  = 'GeistMono.zip'
$Sha256   = 'a9f61b7b7f0429db4fa9a526940f71190127ed95dbe3533163d80d7cafdb3ec9'
$Url      = "https://github.com/ryanoasis/nerd-fonts/releases/download/$Version/$Archive"
$FontFace = 'GeistMono Nerd Font'   # the family name Windows Terminal is given
# Only the "Nerd Font" cuts (not the *Mono or *Propo variants): what terminals want.
$FilePattern = 'GeistMonoNerdFont-*.otf'

$FontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$RegKey  = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

function Install-Fonts {
    $work = Join-Path ([IO.Path]::GetTempPath()) ("geistmono-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        $zip = Join-Path $work $Archive
        Write-Host "Downloading $Url"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing

        $actual = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $Sha256) {
            throw "SHA-256 mismatch for ${Archive}: expected $Sha256, got $actual"
        }
        Write-Host "SHA-256 verified"

        Expand-Archive -Path $zip -DestinationPath $work -Force
        New-Item -ItemType Directory -Path $FontDir -Force | Out-Null
        if (-not (Test-Path $RegKey)) { New-Item -Path $RegKey -Force | Out-Null }

        $fonts = Get-ChildItem -Path $work -Filter $FilePattern -File
        if (-not $fonts) { throw "No $FilePattern files in $Archive" }
        foreach ($f in $fonts) {
            $dest = Join-Path $FontDir $f.Name
            # A font that is already loaded can be locked; the same bytes need no copy.
            if (-not (Test-Path $dest) -or
                (Get-FileHash $dest -Algorithm SHA256).Hash -ne (Get-FileHash $f.FullName -Algorithm SHA256).Hash) {
                Copy-Item -Path $f.FullName -Destination $dest -Force
            }
            $name = [IO.Path]::GetFileNameWithoutExtension($f.Name) + ' (OpenType)'
            New-ItemProperty -Path $RegKey -Name $name -Value $dest -PropertyType String -Force | Out-Null
        }
        Write-Host "Installed $($fonts.Count) font files to $FontDir"
    }
    finally {
        Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Windows PowerShell 5.1 cannot parse JSON with comments or trailing commas,
# which Windows Terminal's settings.json usually has. Strip both, outside strings.
function Remove-JsonComments([string]$Text) {
    $sb = New-Object Text.StringBuilder
    $i = 0
    $n = $Text.Length
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($c -eq '"') {
            [void]$sb.Append($c); $i++
            while ($i -lt $n) {
                $c = $Text[$i]
                [void]$sb.Append($c); $i++
                if ($c -eq '\' -and $i -lt $n) { [void]$sb.Append($Text[$i]); $i++ }
                elseif ($c -eq '"') { break }
            }
        }
        elseif ($c -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '/') {
            while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }
        }
        elseif ($c -eq '/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '*') {
            $end = $Text.IndexOf('*/', $i + 2)
            if ($end -lt 0) { $i = $n } else { $i = $end + 2 }
        }
        else { [void]$sb.Append($c); $i++ }
    }
    # Second pass: drop a comma that is only followed by whitespace and a closer.
    $t = $sb.ToString()
    $sb = New-Object Text.StringBuilder
    $i = 0
    $n = $t.Length
    while ($i -lt $n) {
        $c = $t[$i]
        if ($c -eq '"') {
            [void]$sb.Append($c); $i++
            while ($i -lt $n) {
                $c = $t[$i]
                [void]$sb.Append($c); $i++
                if ($c -eq '\' -and $i -lt $n) { [void]$sb.Append($t[$i]); $i++ }
                elseif ($c -eq '"') { break }
            }
        }
        elseif ($c -eq ',') {
            $j = $i + 1
            while ($j -lt $n -and [char]::IsWhiteSpace($t[$j])) { $j++ }
            if ($j -lt $n -and ($t[$j] -eq '}' -or $t[$j] -eq ']')) { $i++ }
            else { [void]$sb.Append($c); $i++ }
        }
        else { [void]$sb.Append($c); $i++ }
    }
    return $sb.ToString()
}

# Sets <obj>.font.face to $Face, creating the pieces. Returns $true when it changed anything.
function Set-FontFace($Obj, [string]$Face) {
    if (-not $Obj.PSObject.Properties['font'] -or $null -eq $Obj.font) {
        $Obj | Add-Member -NotePropertyName 'font' -NotePropertyValue ([pscustomobject]@{})
    }
    if ($Obj.font.PSObject.Properties['face']) {
        if ($Obj.font.face -eq $Face) { return $false }
        $Obj.font.face = $Face
    }
    else {
        $Obj.font | Add-Member -NotePropertyName 'face' -NotePropertyValue $Face
    }
    return $true
}

function Set-TerminalFont([string]$Path) {
    $settings = (Remove-JsonComments (Get-Content -Path $Path -Raw -Encoding UTF8)) | ConvertFrom-Json
    if (-not $settings.PSObject.Properties['profiles'] -or $null -eq $settings.profiles) {
        $settings | Add-Member -NotePropertyName 'profiles' -NotePropertyValue ([pscustomobject]@{})
    }

    # "profiles" is {defaults, list} in current Windows Terminal; very old files use a bare list.
    $changed = $false
    $list = @()
    if ($settings.profiles -is [array]) {
        $list = $settings.profiles
    }
    else {
        if (-not $settings.profiles.PSObject.Properties['defaults'] -or $null -eq $settings.profiles.defaults) {
            $settings.profiles | Add-Member -NotePropertyName 'defaults' -NotePropertyValue ([pscustomobject]@{})
        }
        if (Set-FontFace $settings.profiles.defaults $FontFace) { $changed = $true }
        if ($settings.profiles.PSObject.Properties['list']) { $list = @($settings.profiles.list) }
    }
    # A WSL profile with its own font would win over the default: keep it in step.
    foreach ($p in $list) {
        $isWsl = ($p.PSObject.Properties['source'] -and $p.source -eq 'Windows.Terminal.Wsl') -or
                 ($p.PSObject.Properties['commandline'] -and $p.commandline -match '(^|[\\/ ])wsl(\.exe)?(\s|$)')
        if ($isWsl -and $p.PSObject.Properties['font'] -and $p.font -and $p.font.PSObject.Properties['face']) {
            if (Set-FontFace $p $FontFace) { $changed = $true }
        }
    }

    if (-not $changed) {
        Write-Host "Already set, nothing to do: $Path"
        return
    }
    $backup = "$Path.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -Path $Path -Destination $backup
    $json = $settings | ConvertTo-Json -Depth 100
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
    Write-Host "Set font to '$FontFace' in $Path (backup: $backup)"
}

# The dot-sourcing guard lets the functions be tested without installing anything.
if ($MyInvocation.InvocationName -ne '.') {
    Install-Fonts

    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    $found = $candidates | Where-Object { Test-Path $_ }
    if (-not $found) {
        Write-Host "No Windows Terminal settings.json found; set the font to '$FontFace' in your terminal by hand."
    }
    foreach ($path in $found) { Set-TerminalFont $path }

    Write-Host "Done. Restart Windows Terminal to pick up the font."
}
