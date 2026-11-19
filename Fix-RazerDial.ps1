#requires -Version 5.1
<#
.SYNOPSIS
    Restores Razer BlackWidow V4 Pro Command Dial horizontal scrolling by pinning
    Razer Synapse 4 to the last known-good engine build (4.0.699).

.DESCRIPTION
    Synapse 4 engine builds from 4.0.820/4.0.821 onward hijack Command Dial rotation
    and turn it into keyboard brightness. This script installs the last known-good
    official Razer build, pins the version, blocks the update CDN, and restarts Synapse.

    The script self-elevates and verifies Razer's Authenticode signature plus the
    installer SHA-256 before running anything.

.PARAMETER AllowUpdates
    Remove the update block and allow Synapse to update again.
    Use this after Razer ships an official fix.

.PARAMETER SkipLaunch
    Do not start Synapse at the end.

.PARAMETER Force
    Skip the confirmation prompt and the final pause (unattended use).

.PARAMETER InstallerPath
    Use a local copy of RazerAppEngineSetup-v4.0.699.exe instead of downloading it.

.EXAMPLE
    .\Fix-RazerDial.ps1

.EXAMPLE
    .\Fix-RazerDial.ps1 -AllowUpdates

.NOTES
    Unofficial community workaround. Not affiliated with Razer.
#>

[CmdletBinding()]
param(
    [switch]$AllowUpdates,
    [switch]$SkipLaunch,
    [switch]$Force,
    [string]$InstallerPath = ""
)

$ErrorActionPreference = 'Stop'

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Self-elevate
if (-not (Test-Admin)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($AllowUpdates) { $argList += '-AllowUpdates' }
    if ($SkipLaunch) { $argList += '-SkipLaunch' }
    if ($Force) { $argList += '-Force' }
    if ($InstallerPath) { $argList += @('-InstallerPath', "`"$InstallerPath`"") }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    } catch {
        Write-Host "Could not elevate. Right-click PowerShell and choose 'Run as administrator'." -ForegroundColor Red
    }
    return
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$RazerKey         = 'HKLM:\SOFTWARE\WOW6432Node\Razer\RazerAppEngine'
$Launcher         = 'C:\Program Files\Razer\RazerAppEngine\RazerAppEngine.exe'
$AppExe699        = 'C:\Program Files\Razer\RazerAppEngine\app-4.0.699\RazerAppEngine.exe'
$WorkDir          = Join-Path $env:ProgramData 'RazerDialFix'
$HostsPath        = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$HostsMarker      = '# Razer Synapse 4.0.699 pin (Command Dial fix) - remove to allow updates'
$HostsEntry4      = '127.0.0.1 app-assets.razer.com'
$HostsEntry6      = '::1 app-assets.razer.com'
$PinnedVersion    = '4.0.699'
$InstallerUrl     = 'https://app-assets.razer.com/files/synapse/RazerAppEngineSetup-v4.0.699.exe'
$ExpectedHash     = '7030294462B2C43A875E5C5374451439281EB78A75F2297192782B0368847AF9'
$ExpectedFileVer  = '4.0.699.0'

function Write-Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Write-Ok($text)   { Write-Host "  OK: $text" -ForegroundColor Green }
function Write-Warn($text) { Write-Host "  WARN: $text" -ForegroundColor Yellow }

function Flush-Dns {
    & ipconfig.exe /flushdns | Out-Null
}

function Write-HostsFile {
    param([string[]]$Lines)

    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    $backup = Join-Path $WorkDir ('hosts.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $HostsPath -Destination $backup -Force

    $temp = Join-Path (Split-Path -Parent $HostsPath) 'hosts.razerdialfix.tmp'
    $replaceBackup = Join-Path $WorkDir 'hosts.replace.bak'
    $encoding = New-Object System.Text.ASCIIEncoding
    [System.IO.File]::WriteAllLines($temp, $Lines, $encoding)

    try {
        if (Test-Path -LiteralPath $replaceBackup) {
            Remove-Item -LiteralPath $replaceBackup -Force
        }
        # Atomic replace: if this fails, the original hosts file is untouched.
        [System.IO.File]::Replace($temp, $HostsPath, $replaceBackup)
        Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue
    } catch {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue
        throw "Could not update the hosts file. The original was left intact. Error: $($_.Exception.Message)"
    }

    Flush-Dns
    return $backup
}

function Set-UpdateBlock {
    $lines = @(Get-Content -LiteralPath $HostsPath -ErrorAction SilentlyContinue)
    $filtered = @($lines | Where-Object {
        $_ -notmatch 'app-assets\.razer\.com' -and $_ -notmatch 'Razer Synapse 4\.0\.699 pin'
    })
    if ($filtered.Count -gt 0 -and $filtered[-1] -ne '') { $filtered += '' }
    $filtered += $HostsMarker
    $filtered += $HostsEntry4
    $filtered += $HostsEntry6
    if ($filtered.Count -eq 0) { $filtered = @('') }

    $backup = Write-HostsFile -Lines $filtered
    Write-Ok "update CDN blocked (hosts backup: $backup)"
}

function Remove-UpdateBlock {
    $lines = @(Get-Content -LiteralPath $HostsPath -ErrorAction SilentlyContinue)
    $filtered = @($lines | Where-Object {
        $_ -notmatch 'app-assets\.razer\.com' -and $_ -notmatch 'Razer Synapse 4\.0\.699 pin'
    })
    if ($filtered.Count -eq 0) { $filtered = @('') }

    $backup = Write-HostsFile -Lines $filtered
    Write-Ok "update block removed; Synapse can update again (hosts backup: $backup)"
}

function Assert-Installer([string]$File) {
    if (-not (Test-Path -LiteralPath $File)) {
        throw "Installer not found: $File"
    }
    $fileVer = (Get-Item -LiteralPath $File).VersionInfo.FileVersion
    if ($fileVer -notlike "$ExpectedFileVer*") {
        throw "Unexpected installer version: $fileVer"
    }
    $hash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
    if ($hash -ne $ExpectedHash) {
        throw "SHA256 mismatch.`nExpected: $ExpectedHash`nActual:   $hash"
    }
    $sig = Get-AuthenticodeSignature -LiteralPath $File
    if ($sig.Status -ne 'Valid') {
        throw "Installer signature is not valid: $($sig.Status)"
    }
    if ($sig.SignerCertificate.Subject -notmatch 'Razer USA Ltd\.') {
        throw "Installer is not signed by Razer USA Ltd."
    }
    Write-Ok "installer verified (v$fileVer, Razer-signed, SHA256 matches)"
}

function Get-Installer {
    param([string]$File)

    if ($File) {
        $full = (Resolve-Path -LiteralPath $File).Path
        Assert-Installer $full
        return $full
    }

    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    $cached = Join-Path $WorkDir 'RazerAppEngineSetup-v4.0.699.exe'

    if (Test-Path -LiteralPath $cached) {
        try {
            Assert-Installer $cached
            return $cached
        } catch {
            Write-Warn "cached installer invalid; re-downloading"
            Remove-Item -LiteralPath $cached -Force
        }
    }

    Write-Step "Downloading official Razer 4.0.699 setup"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        Start-BitsTransfer -Source $InstallerUrl -Destination $cached -ErrorAction Stop
    } catch {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $cached -UseBasicParsing
    }
    Unblock-File -LiteralPath $cached -ErrorAction SilentlyContinue
    Assert-Installer $cached
    return $cached
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Razer BlackWidow V4 Pro - Command Dial fix (Synapse 4)" -ForegroundColor White
Write-Host "------------------------------------------------------" -ForegroundColor DarkGray

if ($AllowUpdates) {
    Write-Step "Removing Synapse update block"
    Remove-UpdateBlock
    Write-Host ""
    Write-Host "Done. Synapse can update again." -ForegroundColor Green
    Write-Host "Update only after Razer ships a build that fixes the Command Dial."
    if (-not $Force) { Read-Host "Press Enter to exit" | Out-Null }
    return
}

if (-not (Test-Path -LiteralPath $RazerKey)) {
    throw "Razer Synapse 4 is not installed. This fix is for Synapse 4 only."
}
if (-not [Environment]::Is64BitOperatingSystem) {
    throw "64-bit Windows is required."
}

$currentVersion = (Get-ItemProperty -LiteralPath $RazerKey -Name version -ErrorAction SilentlyContinue).version
if (-not $currentVersion) { $currentVersion = 'unknown' }

try {
    $kbd = Get-PnpDevice -PresentOnly -ErrorAction Stop |
        Where-Object { $_.InstanceId -match 'VID_1532&PID_028D' }
    if ($kbd) {
        Write-Ok "BlackWidow V4 Pro (1532:028D) detected"
    } else {
        Write-Warn "BlackWidow V4 Pro (1532:028D) was not detected; continuing anyway"
    }
} catch {
    Write-Warn "could not query PnP devices; continuing"
}

Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  1. Close Razer Synapse"
Write-Host "  2. Install the last good official Synapse engine 4.0.699"
Write-Host "  3. Pin the version and block the Synapse update CDN"
Write-Host "  4. Restart Synapse"
Write-Host ""
Write-Host "Warning: Synapse is downgraded for ALL Razer devices on this PC." -ForegroundColor Yellow
Write-Host "Features/fixes added after 4.0.699 will be missing until you allow updates."
Write-Host ""

if (-not $Force) {
    $answer = Read-Host "Type YES to continue"
    if ($answer -ne 'YES') {
        Write-Host "Cancelled."
        return
    }
}

$originalVersion = $currentVersion
$needInstall = $true

if ($currentVersion -eq $PinnedVersion -and (Test-Path -LiteralPath $AppExe699)) {
    $needInstall = $false
    Write-Step "Synapse is already on $PinnedVersion"
}

if ($needInstall) {
    $installer = Get-Installer -File $InstallerPath

    Write-Step "Closing Razer Synapse"
    & taskkill.exe /IM RazerAppEngine.exe /T /F 2>$null | Out-Null
    Start-Sleep -Seconds 4

    try {
        Write-Step "Installing Synapse $PinnedVersion (official Razer setup)"
        Set-ItemProperty -LiteralPath $RazerKey -Name version -Value '0.0.0'

        $proc = Start-Process -FilePath $installer -ArgumentList '/S' -PassThru -Wait
        if ($proc.ExitCode -ne 0) {
            throw "Installer exited with code $($proc.ExitCode)."
        }

        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $AppExe699)) {
            Start-Sleep -Seconds 2
        }
        if (-not (Test-Path -LiteralPath $AppExe699)) {
            throw "app-4.0.699 was not created; installation did not complete."
        }

        Set-ItemProperty -LiteralPath $RazerKey -Name version -Value $PinnedVersion
        Write-Ok "Synapse $PinnedVersion installed and pinned"
    } catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Warn "restoring previous version value: $originalVersion"
        try { Set-ItemProperty -LiteralPath $RazerKey -Name version -Value $originalVersion } catch { }
        throw
    }
}

Write-Step "Ensuring Razer Elevation Service is running"
$service = Get-Service -Name 'Razer Elevation Service' -ErrorAction SilentlyContinue
if ($service -and $service.Status -ne 'Running') {
    try {
        Start-Service -Name 'Razer Elevation Service'
        Write-Ok "elevation service started"
    } catch {
        Write-Warn "could not start elevation service: $($_.Exception.Message)"
    }
} elseif ($service) {
    Write-Ok "elevation service is running"
} else {
    Write-Warn "Razer Elevation Service not found"
}

Write-Step "Blocking Synapse auto-update"
Set-UpdateBlock

if (-not $SkipLaunch) {
    Write-Step "Starting Synapse"
    Remove-Item Env:\ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
    Remove-Item Env:\ELECTRON_NO_ATTACH_CONSOLE -ErrorAction SilentlyContinue
    Start-Process -FilePath $Launcher -ArgumentList '--url-params=apps=synapse'
    Start-Sleep -Seconds 15

    $running = Get-CimInstance Win32_Process -Filter "Name='RazerAppEngine.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -like '*app-4.0.699*' }

    if ($running) {
        Write-Ok "Synapse 4.0.699 is running"
    } else {
        Write-Warn "Synapse did not start yet; reboot and open Synapse normally"
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Test: open Excel or a wide web page and rotate the Command Dial." -ForegroundColor White
Write-Host "If it still changes brightness, reboot once and retest."
Write-Host ""
Write-Host "Rollback / allow updates later:" -ForegroundColor DarkGray
Write-Host "  .\Fix-RazerDial.ps1 -AllowUpdates" -ForegroundColor DarkGray
Write-Host "Then update Synapse normally (or install the latest from razer.com/synapse-4)."
Write-Host ""

if (-not $Force) { Read-Host "Press Enter to exit" | Out-Null }
