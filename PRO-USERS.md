# Pro users — manual control, verification, rollback

For normal users, use **`Run-Fix.cmd`** and see [README.md](README.md).
This document is for people who want to review every change, install manually, or troubleshoot.

## Requirements

- Windows 10/11, 64-bit
- Razer Synapse 4 installed
- Razer BlackWidow V4 Pro (`VID_1532&PID_028D`)
- Administrator rights
- Internet access, or a local copy of `RazerAppEngineSetup-v4.0.699.exe`

## What the script changes

1. Verifies the installer:
   - Version `4.0.699.0`
   - SHA-256 `7030294462B2C43A875E5C5374451439281EB78A75F2297192782B0368847AF9`
   - Authenticode signature: valid, signer `Razer USA Ltd.`
2. Closes `RazerAppEngine.exe`.
3. Temporarily sets the Synapse version registry value to `0.0.0` (the setup refuses downgrades otherwise).
4. Runs the official setup silently (`/S`).
5. Sets the version to `4.0.699`.
6. Starts **Razer Elevation Service** if it is stopped.
7. Backs up `hosts`, then adds:
   ```text
   127.0.0.1 app-assets.razer.com
   ::1 app-assets.razer.com
   ```
   The write uses `[System.IO.File]::Replace`, so a failed write leaves the original hosts file intact.
8. Launches Synapse with `ELECTRON_RUN_AS_NODE` removed from the environment.

The old `app-4.0.896` folder is not deleted.

## Script parameters

| Parameter | Purpose |
|---|---|
| `-AllowUpdates` | Remove the hosts update block and flush DNS. |
| `-SkipLaunch` | Do not start Synapse at the end. |
| `-Force` | Skip the confirmation prompt and final pause. |
| `-InstallerPath "C:\path\RazerAppEngineSetup-v4.0.699.exe"` | Use a local installer instead of downloading. |

Examples:

```powershell
# Normal fix
.\Fix-RazerDial.ps1

# Install but do not start Synapse
.\Fix-RazerDial.ps1 -SkipLaunch

# Remove the update block
.\Fix-RazerDial.ps1 -AllowUpdates

# Offline / custom installer
.\Fix-RazerDial.ps1 -InstallerPath 'D:\Downloads\RazerAppEngineSetup-v4.0.699.exe'
```

## Verification

```powershell
(Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Razer\RazerAppEngine').version
# 4.0.699
```

```powershell
Get-CimInstance Win32_Process -Filter "Name='RazerAppEngine.exe'" |
    Select-Object ProcessId, ExecutablePath
# ...\app-4.0.699\RazerAppEngine.exe
```

```powershell
Resolve-DnsName app-assets.razer.com
# 127.0.0.1 or ::1
```

## Manual installation (review / offline)

> The script is safer. Use these steps only if you want to do each change yourself.

### 1. Download and verify the official installer

```powershell
$url = 'https://app-assets.razer.com/files/synapse/RazerAppEngineSetup-v4.0.699.exe'
$dst = "$env:ProgramData\RazerDialFix\RazerAppEngineSetup-v4.0.699.exe"
New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
Start-BitsTransfer -Source $url -Destination $dst

(Get-FileHash $dst -Algorithm SHA256).Hash
# 7030294462B2C43A875E5C5374451439281EB78A75F2297192782B0368847AF9

(Get-Item $dst).VersionInfo.FileVersion
# 4.0.699.0

Get-AuthenticodeSignature $dst | Format-List Status, SignerCertificate
# Status: Valid, signer: CN=Razer USA Ltd.
```

Stop if the hash, version, or signature does not match.

### 2. Close Synapse and install 4.0.699

Run in an elevated PowerShell:

```powershell
$key = 'HKLM:\SOFTWARE\WOW6432Node\Razer\RazerAppEngine'
$old = (Get-ItemProperty $key).version
taskkill /IM RazerAppEngine.exe /T /F

Set-ItemProperty $key -Name version -Value '0.0.0'
Start-Process 'C:\ProgramData\RazerDialFix\RazerAppEngineSetup-v4.0.699.exe' -ArgumentList '/S' -Wait

# Wait until the folder exists
Test-Path 'C:\Program Files\Razer\RazerAppEngine\app-4.0.699\RazerAppEngine.exe'

Set-ItemProperty $key -Name version -Value '4.0.699'
```

If the app folder was not created, restore the old value:

```powershell
Set-ItemProperty $key -Name version -Value $old
```

### 3. Start the elevation service

```powershell
Start-Service 'Razer Elevation Service'
Get-Service 'Razer Elevation Service'
```

### 4. Block the update server

Back up first:

```powershell
Copy-Item "$env:WINDIR\System32\drivers\etc\hosts" "$env:ProgramData\RazerDialFix\hosts.backup" -Force
```

Add these lines to `C:\Windows\System32\drivers\etc\hosts`:

```text
127.0.0.1 app-assets.razer.com
::1 app-assets.razer.com
```

Then:

```powershell
ipconfig /flushdns
```

### 5. Start Synapse

Remove `ELECTRON_RUN_AS_NODE` if you are in a VS Code/agent terminal, then start the launcher:

```powershell
Remove-Item Env:\ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
Start-Process 'C:\Program Files\Razer\RazerAppEngine\RazerAppEngine.exe' -ArgumentList '--url-params=apps=synapse'
```

## Rollback / allow updates

```powershell
.\Fix-RazerDial.ps1 -AllowUpdates
```

Then update Synapse from the app or install the latest from https://www.razer.com/synapse-4.

Or remove these lines manually and run `ipconfig /flushdns`:

```text
127.0.0.1 app-assets.razer.com
::1 app-assets.razer.com
```

## Troubleshooting

### Synapse does not start

1. Reboot.
2. Check `Razer Elevation Service` in `services.msc`.
3. Start Synapse from the Start menu.

### Synapse exits immediately from a terminal

`ELECTRON_RUN_AS_NODE=1` in the environment (VS Code sets this) makes Razer's Electron app run as Node and exit with `bad option`. The script removes it for its own launch. Use `Run-Fix.cmd` or a normal PowerShell window.

### The download is blocked

Download the official installer manually:

```text
https://app-assets.razer.com/files/synapse/RazerAppEngineSetup-v4.0.699.exe
```

Then:

```powershell
.\Fix-RazerDial.ps1 -InstallerPath 'C:\path\RazerAppEngineSetup-v4.0.699.exe'
```

### SHA-256 mismatch

Delete the cached copy in `C:\ProgramData\RazerDialFix\` and retry. If it still mismatches while the signature is valid, open an issue with the new hash.

### The hosts file cannot be updated

The script aborts without changing the file. Add the two lines manually (see above) and run `ipconfig /flushdns`.

### Other Razer devices lost features

Synapse is shared by all Razer devices. Downgrading removes fixes/features added after 4.0.699. Use `-AllowUpdates` and wait for Razer's official fix if you need a newer device.

## Files and backups

```text
C:\ProgramData\RazerDialFix\
  RazerAppEngineSetup-v4.0.699.exe   cached installer
  hosts.backup-*                     timestamped hosts backups
```

The script is plain PowerShell. Review it before running.
