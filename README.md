# Razer BlackWidow V4 Pro — Command Dial horizontal scroll fix

A community workaround for the **Razer BlackWidow V4 Pro** Command Dial bug where rotating the dial changes **keyboard brightness** instead of scrolling horizontally in Synapse 4.

> **Status (2026-11-19):** Razer has not shipped an official fix. The latest stable Synapse 4 build and the current beta still do not mention this bug in their release notes. This repository pins Synapse to the last known-good build and blocks auto-updates until Razer fixes it.

**This is an unofficial workaround. It is not affiliated with or endorsed by Razer. Use at your own risk.**

---

## Symptoms

- Rotating the Command Dial changes the keyboard's **brightness** instead of scrolling horizontally.
- Pressing the dial still cycles dial modes.
- Fully exiting Synapse makes horizontal scrolling work again.
- The keyboard is detected as `VID_1532&PID_028D` (BlackWidow V4 Pro, full-size).
- The problem started after the **2026-09-09** Synapse update.

## Root cause (short version)

Synapse 4's engine build **4.0.821** (and the 4.0.820 build that preceded it in some channels) changed how the Command Dial is handled. The keyboard's dial rotation is consumed by Razer's driver and Synapse translates it into a Chroma brightness change instead of horizontal scroll.

When Synapse is closed, the keyboard's onboard firmware handles the dial and horizontal scrolling works. No user-mode shim can fix this because Synapse consumes the dial events before Windows raw input sees them.

The last known-good build is **4.0.699**. On the test machine the Synapse updater log shows:

```text
2026/09/09 06:19  version: 4.0.821 result: UPDATE   (current 4.0.699)
```

…which matches the date the bug reports started.

## The fix

The script in this repository:

1. Verifies and installs Razer's **official 4.0.699 setup**.
2. Pins `HKLM\SOFTWARE\WOW6432Node\Razer\RazerAppEngine\version` to `4.0.699`.
3. Blocks `app-assets.razer.com` in the Windows hosts file so Synapse cannot auto-update.
4. Starts Razer Elevation Service if needed and relaunches Synapse.

Your profiles, macros, and Razer ID data are left alone. The old `app-4.0.896` folder is not deleted.

---

## Requirements

- Windows 10/11, 64-bit
- Razer Synapse 4 installed
- Razer BlackWidow V4 Pro (`1532:028D`)
- Administrator rights (the script self-elevates)
- Internet access to download Razer's official installer (or a local copy via `-InstallerPath`)

## Quick start

1. Download this repository as a ZIP (**Code → Download ZIP**) and extract it.
2. Double-click **`Run-Fix.cmd`** and approve the UAC prompt.
3. Wait for the installer and Synapse to restart.
4. Open Excel or a wide web page and rotate the Command Dial.

If Windows blocks the script, open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Fix-RazerDial.ps1
```

If Synapse asks to update, **decline**. The hosts block should prevent the download anyway.

## Verify it worked

```powershell
(Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Razer\RazerAppEngine').version
# 4.0.699
```

Task Manager → `RazerAppEngine.exe` → **Open file location** should point to:

```text
C:\Program Files\Razer\RazerAppEngine\app-4.0.699\
```

Then rotate the dial in Excel. It should scroll left/right.

## Rollback / allow updates

When Razer releases a fixed build, remove the update block:

```powershell
.\Fix-RazerDial.ps1 -AllowUpdates
```

Then update Synapse normally from the app or install the latest from https://www.razer.com/synapse-4.

You can also remove these lines from `C:\Windows\System32\drivers\etc\hosts` manually:

```text
# Razer Synapse 4.0.699 pin (Command Dial fix) - remove to allow updates
127.0.0.1 app-assets.razer.com
::1 app-assets.razer.com
```

Then run `ipconfig /flushdns`.

The script keeps timestamped hosts backups in:

```text
C:\ProgramData\RazerDialFix\hosts.backup-*
```

To re-apply the fix later, run the script again.

---

## What the script actually does

1. Self-elevates if not running as Administrator.
2. Checks that Synapse 4 is installed and Windows is 64-bit.
3. Detects `VID_1532&PID_028D` and warns if the keyboard is not present.
4. Downloads `RazerAppEngineSetup-v4.0.699.exe` from Razer's official CDN (or uses `-InstallerPath`).
5. Verifies:
   - File version `4.0.699.0`
   - SHA-256 `7030294462B2C43A875E5C5374451439281EB78A75F2297192782B0368847AF9`
   - Authenticode signature: **Valid**, signer **Razer USA Ltd.**
6. Closes Synapse.
7. Temporarily sets the version registry value to `0.0.0` (the setup refuses downgrades otherwise), runs the silent setup, then sets the version to `4.0.699`.
8. Restores the original version value if installation fails.
9. Starts **Razer Elevation Service** if it is stopped.
10. Backs up the hosts file and adds the update block using an **atomic replace** (the original is preserved if the write fails).
11. Removes `ELECTRON_RUN_AS_NODE` from its own environment and launches Synapse.

## Script parameters

| Parameter | Purpose |
|---|---|
| `-AllowUpdates` | Remove the hosts update block and allow Synapse to update again. |
| `-SkipLaunch` | Do not start Synapse at the end. |
| `-Force` | Skip the confirmation prompt and final pause. |
| `-InstallerPath "C:\path\RazerAppEngineSetup-v4.0.699.exe"` | Use a local installer instead of downloading. |

Examples:

```powershell
.\Fix-RazerDial.ps1
.\Fix-RazerDial.ps1 -SkipLaunch
.\Fix-RazerDial.ps1 -AllowUpdates
.\Fix-RazerDial.ps1 -InstallerPath 'D:\Downloads\RazerAppEngineSetup-v4.0.699.exe'
```

---

## Troubleshooting

### Synapse does not start after the fix

1. Reboot once.
2. Check that **Razer Elevation Service** is running (`services.msc`).
3. Run Synapse from the Start menu (not from a VS Code terminal).

### Synapse exits immediately when launched from a terminal

Your terminal probably has `ELECTRON_RUN_AS_NODE=1` set (VS Code and some agent tools do this). Razer's Electron app then runs as plain Node and exits with `bad option`. The script removes this variable for its own launch. Use `Run-Fix.cmd` or a normal PowerShell window.

### The download is blocked by a proxy or firewall

Download the official installer manually:

```text
https://app-assets.razer.com/files/synapse/RazerAppEngineSetup-v4.0.699.exe
```

Then run:

```powershell
.\Fix-RazerDial.ps1 -InstallerPath 'C:\path\RazerAppEngineSetup-v4.0.699.exe'
```

The script still verifies the hash and Razer signature.

### The script cannot update the hosts file

The script stops without changing the hosts file and prints the error. Add the update block manually:

```text
# Razer Synapse 4.0.699 pin (Command Dial fix) - remove to allow updates
127.0.0.1 app-assets.razer.com
::1 app-assets.razer.com
```

Then run `ipconfig /flushdns`.

### The script reports a SHA-256 mismatch

Razer may have re-published the file, or the download is corrupted. Delete the cached copy in `C:\ProgramData\RazerDialFix\` and try again. If the mismatch persists while the Razer signature is valid, open an issue with the new hash.

### The dial still changes brightness

1. Confirm Synapse is running from `app-4.0.699` (Task Manager → Open file location).
2. Reboot.
3. Make sure you did not allow an update.
4. If it still fails, open an issue with:
   - Windows version
   - Synapse version from the registry
   - Keyboard PID
   - Whether horizontal scroll works with Synapse fully closed

### Other Razer devices lost features after the downgrade

The Synapse engine is shared by all Razer devices. Downgrading to 4.0.699 removes fixes and features added after July 2026. If you rely on a newer device, use `-AllowUpdates` and wait for the official dial fix instead.

---

## Technical investigation

### Evidence from the affected machine

- With Synapse running, rotating the dial produced **zero events** in Windows Raw Input. Normal keystrokes (`A`, VK 0x41) were captured in the same test, proving the listener worked.
- The dial press arrives as report `04 60` on the keyboard's vendor interface (MI_03).
- The keyboard was in Razer **driver mode** (`device_mode = 0x03`), confirmed with Razer's HID command class `0x00`, command `0x04`.
- OpenRazer's reverse-engineering shows that in driver mode the dial rotation is sent as **Consumer AC Pan** on the keyboard's mouse interface (interface 2), one report per detent:

```text
00 00 01 00 00 00 00 00   clockwise
00 00 FF 00 00 00 00 00   counter-clockwise
```

- Synapse intercepts those reports and, in the affected builds, applies them to Chroma brightness instead of horizontal scroll.
- Closing Synapse returns the keyboard to onboard handling and horizontal scroll works.

### Why not a background shim?

A user-mode listener cannot see the dial while Synapse runs, so it cannot re-inject horizontal wheel events. The fix has to change Synapse's handling (or stop Synapse), which is why this repository pins Synapse to the last good build.

### Version timeline (from the affected machine's updater log)

| Date | Version | Notes |
|---|---|---|
| 2026-07-19 | 4.0.697 | earlier |
| 2026-07-22 | 4.0.698 | earlier |
| 2026-09-09 | **4.0.821** | bug appears |
| 2026-09-19 | 4.0.823 | bug present |
| 2026-10-01 | 4.0.827 | bug present |
| 2026-10-28 | 4.0.896 | bug present |
| 2026-11-17 | 4.0.86.2610281118 | latest stable; bug still present |

`4.0.699` is the last build before the regression.

### Installer verification data

```text
File:          RazerAppEngineSetup-v4.0.699.exe
Size:          181,745,288 bytes
File version:  4.0.699.0
SHA-256:       7030294462B2C43A875E5C5374451439281EB78A75F2297192782B0368847AF9
Signature:     Valid
Signer:        CN=Razer USA Ltd., O=Razer USA Ltd., L=Irvine, S=California, C=US
```

Razer's official engine manifest for the same release (Upgrade package) publishes:

```text
sha256: 95E4E7901657FED33E3F1D9A0B46760A94ABC92C6130F25CE4AC27CCDC53DE08
url:    https://app-assets.razer.com/files/synapse/RazerAppEngineUpgrade-v4.0.699.exe
```

The script uses the **full Setup** package rather than the engine-only Upgrade package so that matching services and components are installed. The Upgrade package is also published with its own SHA-256, but it is intended for in-app upgrades.

---

## Official fix status

As of **2026-11-19**, Razer has not released a fix.

- Stable release notes (2026-11-17) do not mention the Command Dial:
  https://insider.razer.com/release-versions-feedback-67
- Bug report (Razer Insider):
  https://insider.razer.com/razer-synapse-4-55/critical-bug-blackwidow-v4-pro-full-size-command-dial-rotating-dial-adjusts-keyboard-brightness-in-synapse4-built-in-preset-custom-mouse-binding-and-macro-all-troubleshooting-failed-keyboard-firmware-v1-5-0-0-91351
- Earlier report:
  https://insider.razer.com/razer-support-45/razer-blackwidow-v4-pro-horizontal-command-dial-fixed-on-changes-brightnes-91281

When Razer ships a fix, run `.\Fix-RazerDial.ps1 -AllowUpdates` and update.

## References

- OpenRazer Command Dial protocol reference (issue #2228 and attached protocol notes):
  https://github.com/openrazer/openrazer/issues/2228
- Razer Synapse 4 release notes:
  https://insider.razer.com/release-versions-feedback-67

## License

MIT — see [LICENSE](LICENSE). No warranty. Not affiliated with Razer.
