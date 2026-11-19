# Research — how the bug was found

This is the technical investigation behind the fix. For the simple solution, see [README.md](README.md).
For a support-ready report, see [FOR-RAZER.md](FOR-RAZER.md).

## TL;DR

- The Command Dial is physically fine. It sends the correct horizontal-scroll reports when Synapse is closed.
- Synapse 4 engine **4.0.821+** consumes those reports and maps them to keyboard brightness.
- The dial events never reach Windows raw input while the buggy Synapse is running, so a userspace shim cannot fix it.
- **4.0.699** is the last known-good engine. Downgrading to it restores horizontal scroll while Synapse stays open.

## Test environment

- Windows 11 Home Single Language, build 26200 (25H2), 64-bit
- Razer BlackWidow V4 Pro, `VID_1532&PID_028D`
- Synapse 4 builds tested: 4.0.699 (works), 4.0.820 (broken), 4.0.821/4.0.823/4.0.827/4.0.896 (broken)
- Keyboard firmware: not changed by this fix; the hardware works in onboard mode

## Symptom

When Synapse 4.0.821+ is running:

- Rotating the Command Dial changes the keyboard's RGB brightness.
- No horizontal scrolling occurs in Excel, browsers, or any horizontally scrollable window.
- Pressing the dial still cycles dial modes.
- Assigning rotation to another action in Synapse does not help.
- Fully exiting Synapse restores normal horizontal scrolling.

## Key observations

### 1. Windows raw input sees normal keys but not the dial

A Raw Input listener registered for keyboard, consumer-control, and mouse devices was run while Synapse was open.

Test sequence: press `A`, rotate the dial clockwise, press `A`, rotate counter-clockwise, press `A`.

Result:

- `A` key events were captured (`VKey 0x41`).
- Dial rotation produced **zero** Raw Input events.
- The mouse device (`VID_1532&PID_00AA`) produced normal mouse events when the physical mouse was moved.

This proves the listener worked and the dial events were consumed before Windows input.

### 2. The dial press is still reported

With the dial pressed, the keyboard's vendor interface (`MI_03`) emitted:

```text
04 60 00 00 00 00 00 00
04 00 00 00 00 00 00 00
```

`0x60` is the dial-press code reported by OpenRazer (`KEY_F24` in driver mode). Press handling was not broken; only rotation was redirected.

### 3. The keyboard was in Razer driver mode

Razer's HID control command **Get Device Mode** (class `0x00`, command `0x84`, data size `2`) returned:

```text
status = 0x02 (success)
class  = 0x00
cmd    = 0x84
arg0   = 0x03
```

`0x03` = driver mode. In driver mode, the dial is supposed to be handled by the host (Synapse).

### 4. Dial rotation protocol (from OpenRazer)

OpenRazer's protocol reference for the BlackWidow V4 Pro documents the rotation reports on the mouse interface (interface 2), consumer page AC Pan:

```text
Button 3 (Consumer AC Pan +1):  00 00 01 00 00 00 00 00   clockwise
Button 4 (Consumer AC Pan -1):  00 00 FF 00 00 00 00 00   counter-clockwise
```

One report per detent. In a healthy setup, Windows turns these into horizontal wheel (`WM_MOUSEHWHEEL`) events.

## Version regression

The updater log on the affected machine shows the change:

```text
[2026/09/09 06:19:17] ... version=4.0.821 ...
[2026/09/09 06:19:31] version: 4.0.821 result: UPDATE   (old: 4.0.699)
```

The bug reports on Razer Insider start on the same date.

| Date | Build | Result |
|---|---|---|
| 2026-07-19 | 4.0.697 | earlier |
| 2026-07-22 | 4.0.698 | earlier |
| — | **4.0.699** | **horizontal scroll works** |
| 2026-09-09 | **4.0.821** | bug appears |
| 2026-09-19 | 4.0.823 | bug present |
| 2026-10-01 | 4.0.827 | bug present |
| 2026-10-28 | 4.0.896 | bug present |
| 2026-11-17 | 4.0.86.2610281118 | latest stable; still no fix in release notes |

A manual test of **4.0.820** also reproduced the bug, so the regression landed in the 4.0.820/4.0.821 range.

## Things that were tried

- **Assigning the dial to horizontal scroll** in Synapse: ignored; rotation still changed brightness.
- **Assigning a mouse-wheel/macro action**: ignored (also reported by other users).
- **Switching the keyboard to device/onboard mode (`0x00`)** with Synapse running: rotation still changed brightness.
- **Raw Input/HID capture**: no rotation events while Synapse was running.
- **Closing Synapse**: horizontal scroll returns.
- **Downgrading Synapse**: 4.0.699 restores horizontal scroll; 4.0.820+ does not.

## Why a userspace shim cannot fix it

A shim would need to read the dial's AC Pan reports and re-inject `WM_MOUSEHWHEEL`. While the buggy Synapse is running, those reports do not reach Windows raw input (verified with the A-key control test). Synapse consumes them through Razer's driver path before user-mode input sees them.

Therefore the fix must change Synapse's handling or stop/pin Synapse. This repository pins Synapse to the last good build and blocks the update that reintroduces the bug.

## Installer verification

The fix uses Razer's official full setup, not the engine-only upgrade:

```text
File:          RazerAppEngineSetup-v4.0.699.exe
Size:          181,745,288 bytes
File version:  4.0.699.0
SHA-256:       7030294462B2C43A875E5C5374451439281EB78A75F2297192782B0368847AF9
Signature:     Valid
Signer:        CN=Razer USA Ltd., O=Razer USA Ltd., L=Irvine, S=California, C=US
```

Razer's official manifest for the same release (Upgrade package) publishes:

```text
sha256: 95E4E7901657FED33E3F1D9A0B46760A94ABC92C6130F25CE4AC27CCDC53DE08
url:    https://app-assets.razer.com/files/synapse/RazerAppEngineUpgrade-v4.0.699.exe
```

## Limitations

- The downgrade is global to Synapse, not per-device.
- Features/fixes added after 4.0.699 are missing until updates are allowed.
- Blocking `app-assets.razer.com` can also block non-critical online assets.
- Only the BlackWidow V4 Pro was tested. Other Command Dial keyboards may have a related bug but were not verified.

## References

- OpenRazer Command Dial protocol reference (issue #2228 and attachments):
  https://github.com/openrazer/openrazer/issues/2228
- Razer Synapse 4 release notes:
  https://insider.razer.com/release-versions-feedback-67
- Razer Insider bug report:
  https://insider.razer.com/razer-synapse-4-55/critical-bug-blackwidow-v4-pro-full-size-command-dial-rotating-dial-adjusts-keyboard-brightness-in-synapse4-built-in-preset-custom-mouse-binding-and-macro-all-troubleshooting-failed-keyboard-firmware-v1-5-0-0-91351
- Earlier report:
  https://insider.razer.com/razer-support-45/razer-blackwidow-v4-pro-horizontal-command-dial-fixed-on-changes-brightnes-91281
