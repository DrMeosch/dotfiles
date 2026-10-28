<#
.SYNOPSIS
  Sets up the Windows side of a WSL2 machine: Nerd Font, WinGet packages,
  Windows Terminal color scheme and profile, and .wslconfig. No admin rights
  needed unless a WinGet package asks for them. Safe to run twice.

.DESCRIPTION
  On WSL the text is drawn by Windows Terminal with Windows' own fonts, so the
  Nerd Font icons used by starship, tmux and Neovim show up as boxes unless the
  font is installed on Windows too. This script:

    1. downloads the pinned Nerd Fonts release of GeistMono and verifies its SHA-256,
    2. copies the TTF/OTF files to %LOCALAPPDATA%\Microsoft\Windows\Fonts and
       registers them under HKCU (the per-user font mechanism of Windows 10 1809+)
       and loads them into the running session, so no sign-out is needed,
    3. applies the files the flake renders (`make windows` in WSL copies them to
       %USERPROFILE%\.dotfiles-windows, next to this script):
         configuration.winget            `winget configure test`, then `winget configure`
                                         when something is not in the desired state
                                         (this is what installs win32yank)
         windows-terminal-fragment.json  copied to %LOCALAPPDATA%\Microsoft\Windows Terminal\
                                         Fragments\dotfiles\ (color scheme + profile)
         .wslconfig                      copied to %USERPROFILE%\.wslconfig (an existing,
                                         different file is kept as .wslconfig.bak-<timestamp>)
    4. for each Windows Terminal settings.json found (stable, preview, unpackaged):
       backs it up, then sets profiles.defaults.font.face to the font. Skipped
       when already set; profiles with their own font keep it. Done last: a
       settings.json that cannot be parsed or written is reported as a warning
       and a non-zero exit, after everything else was applied.
       Without the rendered files, only steps 1 and 4 run.

  The font is the same Nerd Fonts release that nixpkgs ships to Arch and Ubuntu
  (nerd-fonts.geist-mono), so the glyphs match on every target.

  Windows Terminal's settings.json may contain comments; they are not kept when
  the file is rewritten, which is what the backup is for.

  winget configure does not uninstall what is later dropped from
  configuration.winget; remove such packages by hand (winget uninstall).

  Run from PowerShell:   powershell -ExecutionPolicy Bypass -File windows\setup.ps1

.PARAMETER Source
  Folder with the rendered files. Defaults to the folder of this script when it
  holds configuration.winget, else %USERPROFILE%\.dotfiles-windows.
#>
[CmdletBinding()]
param([string]$Source)

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

Add-Type -Namespace Win32 -Name Fonts -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceW(string path);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeoutW(IntPtr hWnd, uint msg, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
'@

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
            if ([Win32.Fonts]::AddFontResourceW($dest) -eq 0) { Write-Warning "Windows could not load $dest now; it will be available after the next sign-in." }
        }
        # WM_FONTCHANGE to all top-level windows, so running apps re-read the font list.
        $r = [UIntPtr]::Zero
        [void][Win32.Fonts]::SendMessageTimeoutW([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$r)
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
        $Obj | Add-Member -Force -NotePropertyName 'font' -NotePropertyValue ([pscustomobject]@{})
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
        $settings | Add-Member -Force -NotePropertyName 'profiles' -NotePropertyValue ([pscustomobject]@{})
    }

    # "profiles" is {defaults, list} in current Windows Terminal; very old files use a bare list, which has no defaults.
    if ($settings.profiles -is [array]) {
        Write-Warning "Legacy settings.json format (profiles is a list, no defaults); font not set in $Path - set it per profile by hand."
        return
    }
    if (-not $settings.profiles.PSObject.Properties['defaults'] -or $null -eq $settings.profiles.defaults) {
        $settings.profiles | Add-Member -Force -NotePropertyName 'defaults' -NotePropertyValue ([pscustomobject]@{})
    }
    $changed = Set-FontFace $settings.profiles.defaults $FontFace

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

# Copies $From to $To unless it is already there with the same content. With
# -Backup an existing, different file is kept as <name>.bak-<timestamp>.
function Copy-IfChanged([string]$From, [string]$To, [switch]$Backup) {
    New-Item -ItemType Directory -Path (Split-Path $To) -Force | Out-Null
    if (Test-Path $To) {
        if ((Get-FileHash $To -Algorithm SHA256).Hash -eq (Get-FileHash $From -Algorithm SHA256).Hash) {
            Write-Host "Already up to date: $To"
            return
        }
        if ($Backup) {
            $bak = "$To.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
            Copy-Item -Path $To -Destination $bak
            Write-Host "Backed up $To to $bak"
        }
    }
    Copy-Item -Path $From -Destination $To -Force
    Write-Host "Wrote $To"
}

# `winget configure test` first: nothing to do (and no changes) when the machine
# already matches the file. Otherwise apply it, then test again.
function Invoke-WinGetConfiguration([string]$File) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget not found. Install 'App Installer' from the Microsoft Store, then run this script again."
    }
    $common = @('--file', $File, '--disable-interactivity', '--accept-configuration-agreements')
    & winget configure test @common
    if ($LASTEXITCODE -eq 0) {
        Write-Host "WinGet configuration already in the desired state"
        return
    }
    & winget configure @common
    if ($LASTEXITCODE -ne 0) { throw "winget configure failed (exit code $LASTEXITCODE)" }
    & winget configure test @common
    if ($LASTEXITCODE -ne 0) { throw "winget configure test still fails after applying (exit code $LASTEXITCODE)" }
}

function Install-Rendered([string]$Dir) {
    Invoke-WinGetConfiguration (Join-Path $Dir 'configuration.winget')
    Copy-IfChanged (Join-Path $Dir 'windows-terminal-fragment.json') `
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\dotfiles\dotfiles.json')
    Copy-IfChanged (Join-Path $Dir '.wslconfig') (Join-Path $env:USERPROFILE '.wslconfig') -Backup
}

# The dot-sourcing guard lets the functions be tested without installing anything.
if ($MyInvocation.InvocationName -ne '.') {
    Install-Fonts

    if (-not $Source) {
        $Source = if (Test-Path (Join-Path $PSScriptRoot 'configuration.winget')) { $PSScriptRoot }
                  else { Join-Path $env:USERPROFILE '.dotfiles-windows' }
    }
    $rendered = Test-Path (Join-Path $Source 'configuration.winget')
    if ($rendered) { Install-Rendered $Source }

    # Last, and per file: an unreadable settings.json must not keep the rest from being applied.
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    $found = @($candidates | Where-Object { Test-Path $_ })
    if (-not $found) {
        Write-Host "No Windows Terminal settings.json found; set the font to '$FontFace' in your terminal by hand."
    }
    $failed = @()
    foreach ($path in $found) {
        try { Set-TerminalFont $path }
        catch {
            Write-Warning "Could not set the font in ${path}: $($_.Exception.Message)"
            $failed += $path
        }
    }

    if ($rendered) {
        Write-Host "Done. Restart Windows Terminal; run 'wsl --shutdown' for .wslconfig changes to take effect."
    }
    else {
        Write-Host "No rendered files in $Source. In WSL run 'make windows', then run this script again to apply them."
        Write-Host "Done with the font. Restart Windows Terminal to pick it up."
    }
    if ($failed) { throw "settings.json not updated (everything else was applied): $($failed -join ', ')" }
}
