# Razer BlackWidow V4 Pro — Command Dial fix

**Does rotating the Command Dial change keyboard brightness instead of scrolling left/right?**
This repository fixes that.

It is an unofficial workaround for a **Razer Synapse 4** bug. Razer has not released an official fix yet (checked **2026-11-19**).

---

## Just fix it (normal users)

**Takes about 5 minutes. You need administrator rights.**

1. **Download:** [razer-blackwidow-v4-pro-dial-fix.zip](https://github.com/deadlyanony/razer-blackwidow-v4-pro-dial-fix/archive/refs/heads/main.zip)
2. Extract the ZIP anywhere.
3. Double-click **`Run-Fix.cmd`**.
4. Click **Yes** when Windows asks for administrator permission.
5. Wait for **Done**.
6. Open Excel (or any wide page) and rotate the dial.

That's it.

The script downloads Razer's official installer, checks that it is genuinely signed by Razer, installs the last good version, and stops Synapse from updating back to the broken one.

### Undo it later

Double-click **`Allow-Updates.cmd`**.

That removes the update block so Synapse can update normally.

### Check it worked

- The dial scrolls left/right in Excel.
- Task Manager → `RazerAppEngine.exe` → **Open file location** shows `app-4.0.699`.
- Synapse still detects the keyboard normally.

### If it did not work

1. Reboot once and test again.
2. Make sure **Razer Elevation Service** is running (`services.msc`).
3. Open an issue with your Windows version and Synapse version.

### Read this first (short warning)

- This downgrades **Synapse for all Razer devices** on the PC to 4.0.699.
- Newer Razer devices, or features added after July 2026, may lose functionality until you allow updates.
- It blocks one Razer update server (`app-assets.razer.com`) in the Windows hosts file. `Allow-Updates.cmd` removes the block.
- Your profiles, macros, and Razer ID data are not deleted.
- Not a Razer product. Use at your own risk.

---

## Need more than one-click?

| I want to... | Read |
|---|---|
| Understand every change, use manual steps, or troubleshoot | [PRO-USERS.md](PRO-USERS.md) |
| See how the bug was diagnosed and what was tested | [RESEARCH.md](RESEARCH.md) |
| Send a proper bug report to Razer | [FOR-RAZER.md](FOR-RAZER.md) |

## License

MIT. Not affiliated with Razer. See [LICENSE](LICENSE).
