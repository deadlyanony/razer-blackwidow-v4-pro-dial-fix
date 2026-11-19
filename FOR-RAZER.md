# For Razer — Command Dial bug report

This page is a support-ready description of the defect. It can be pasted into a Razer support ticket or an Insider thread.
It is written from a user/community investigation, not by Razer.

---

## Title

**BlackWidow V4 Pro: Command Dial rotation changes keyboard brightness instead of horizontal scrolling (Synapse 4.0.821+)**

## Product

- Razer BlackWidow V4 Pro (full-size, with Command Dial)
- USB ID: `VID_1532 PID_028D`
- Connection: USB
- Firmware: unchanged during testing; the dial works correctly in onboard mode, so the hardware is not the cause

## Environment

- Windows 11 Home Single Language, build 26200 (25H2), 64-bit
- Razer Synapse 4
- Broken builds tested: **4.0.820, 4.0.821, 4.0.823, 4.0.827, 4.0.896**
- Last known-good build: **4.0.699**

## Summary

On Synapse 4 builds from 4.0.820/4.0.821 onward, rotating the Command Dial changes the keyboard's Chroma brightness instead of producing horizontal scroll.

The dial is configured for **Horizontal Scrolling** in Synapse. Pressing the dial still cycles modes. Assigning rotation to a mouse scroll action or a macro also produces brightness instead of the assigned action. The bug persists across profiles, including fresh/custom profiles.

Fully exiting Synapse and using the keyboard's onboard firmware restores horizontal scrolling, which confirms the hardware and HID reports are healthy.

## Steps to reproduce

1. Install Synapse 4.0.821 or later (reproduced on 4.0.820, 4.0.821, 4.0.823, 4.0.827, 4.0.896).
2. Connect a BlackWidow V4 Pro.
3. Set the Command Dial rotation to **Horizontal Scrolling** in Synapse.
4. Open Excel or a wide web page.
5. Rotate the Command Dial clockwise and counter-clockwise.

## Expected result

- The page scrolls left/right.
- Windows receives horizontal wheel / Consumer AC Pan events.

## Actual result

- The keyboard's RGB brightness increases/decreases.
- No horizontal scrolling occurs in any application.
- No dial rotation events reach Windows Raw Input while Synapse is running.
- Pressing the dial still works and cycles modes.

## Evidence

### 1. Dial rotation is absent from Windows Raw Input

A Raw Input listener registered for keyboard, consumer-control, and mouse devices was run while Synapse was open.

Test: press `A`, rotate the dial clockwise, press `A`, rotate counter-clockwise, press `A`.

- `A` key events were received (`VKey 0x41`), proving the listener works.
- Dial rotation produced **zero** Raw Input events.
- Normal mouse movement was received from the physical mouse.

### 2. The dial press is still reported

Pressing the dial sends this report on the keyboard vendor interface (`MI_03`):

```text
04 60 00 00 00 00 00 00
04 00 00 00 00 00 00 00
```

`0x60` is the dial-press code documented by OpenRazer. Press handling is intact; only rotation is redirected.

### 3. The keyboard is in Razer driver mode

Razer HID control command **Get Device Mode** (class `0x00`, command `0x84`, data size `2`) returns:

```text
status = 0x02 (success)
class  = 0x00
cmd    = 0x84
arg0   = 0x03   (driver mode)
```

### 4. Rotation protocol is Consumer AC Pan

OpenRazer's protocol reference for this keyboard documents the rotation reports on the mouse interface (interface 2), one report per detent:

```text
clockwise:         00 00 01 00 00 00 00 00   (Consumer AC Pan +1)
counter-clockwise: 00 00 FF 00 00 00 00 00   (Consumer AC Pan -1)
```

In a healthy setup these become horizontal wheel (`WM_MOUSEHWHEEL`) events. Synapse 4.0.820+ consumes them and applies them to brightness instead.

## Regression

The Synapse updater log on the affected machine shows:

```text
[2026/09/09 06:19:17] ... version=4.0.821 ...
[2026/09/09 06:19:31] version: 4.0.821 result: UPDATE   (old: 4.0.699)
```

Razer Insider bug reports begin on the same date.

| Date | Build | Result |
|---|---|---|
| — | **4.0.699** | **works (verified)** |
| 2026-09-09 | **4.0.821** | broken |
| 2026-09-19 | 4.0.823 | broken |
| 2026-10-01 | 4.0.827 | broken |
| 2026-10-28 | 4.0.896 | broken |
| 2026-11-17 | 4.0.86.2610281118 | still broken; no fix in release notes |

A manual test of **4.0.820** also reproduced the bug, so the regression landed in the 4.0.820/4.0.821 range.

## Impact

- The Command Dial's primary horizontal-scroll function is unusable.
- Rotation unexpectedly changes keyboard brightness, which is disruptive during work and gaming.
- Users cannot work around it inside Synapse: remapping rotation, changing profiles, and using macros all still produce brightness.
- The only current workaround is to close Synapse or downgrade to 4.0.699 and block updates.

## Workaround (not a fix)

Downgrade the Synapse engine to **4.0.699** and block the update CDN. This restores horizontal scrolling but loses newer fixes/features. Community instructions and a verified script:

https://github.com/deadlyanony/razer-blackwidow-v4-pro-dial-fix

## Request

1. Restore the Command Dial rotation mapping so it produces horizontal scroll again (Consumer AC Pan / `WM_MOUSEHWHEEL`), or reliably honors the action configured in Synapse.
2. Add a regression test for dial rotation across all dial modes.
3. Confirm the affected build range and provide an ETA for an official fix.
4. If useful, provide a diagnostic build or logging instructions to capture Synapse's dial handling.

## References

- Razer Insider bug report:
  https://insider.razer.com/razer-synapse-4-55/critical-bug-blackwidow-v4-pro-full-size-command-dial-rotating-dial-adjusts-keyboard-brightness-in-synapse4-built-in-preset-custom-mouse-binding-and-macro-all-troubleshooting-failed-keyboard-firmware-v1-5-0-0-91351
- Earlier report:
  https://insider.razer.com/razer-support-45/razer-blackwidow-v4-pro-horizontal-command-dial-fixed-on-changes-brightnes-91281
- OpenRazer Command Dial protocol reference:
  https://github.com/openrazer/openrazer/issues/2228
- Synapse 4 release notes:
  https://insider.razer.com/release-versions-feedback-67
