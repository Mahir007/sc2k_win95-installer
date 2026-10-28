# Manual test results

The Pester tests can't run a real install: that needs the CD's ISO, a UAC
prompt and SC2000X. These are the checks done by hand on Windows instead.

Last run: 28 October 2026, at `e3b28dc`, in a Windows 11 VM with the USA
1998 rerelease ISO. Every item passed.

## Install

- [x] Fresh install with the file picker, on Windows PowerShell 5.1
- [x] Install with `-Iso`, on Windows PowerShell 5.1 and PowerShell 7
- [x] Decline the UAC prompt, on 5.1 and 7: "Error: Administrator rights
      were not granted."
- [x] Accept the UAC prompt, on 5.1 and 7: the elevated window opens
- [x] Cancel the file picker: "No ISO selected."
- [x] Pick an ISO that isn't the Special Edition: "The ISO doesn't look like
      SimCity 2000 Special Edition (no WIN95\GOODIES folder)."
- [x] SC2000X and SC2KRepainter download from this repository and pass the
      hash check
- [x] The name prompts show `Mayor McSim` and `Maxis, Inc.` highlighted
- [x] Typing replaces the default straight away, without Backspace
- [x] Enter on an untouched default, or on a field cleared with Backspace,
      uses the default
- [x] The names show in the game
- [x] The game launches with intro movies and palette animation
- [x] `-GitHubToken` works in a development copy
- [x] A copy with a release version refuses `-GitHubToken`

## C:\DATA

- [x] Existing `C:\DATA` folder: rename, then uninstall puts it back
- [x] Existing `C:\DATA` folder: rename, then force a failure and check
      rollback puts it back and removes `HKCU\Software\Maxis\SimCity 2000`
- [x] Kill the window partway through an install, delete the install folder
      by hand, then run again. It replaces the leftover `C:\DATA` link
      without asking or saying so.
- [x] After that rerun, with an earlier `C:\DATA` renamed to `C:\DATA.old`,
      uninstall moves `C:\DATA.old` back to `C:\DATA`

## Shortcuts

- [x] Start Menu has a `Maxis` folder with `SimCity 2000`,
      `SimCity Urban Renewal Kit` and `Uninstall SimCity 2000® Special Edition`
- [x] The uninstall shortcut shows the CD's uninstaller icon (a bin with "UN"
      on it), not the PowerShell icon
- [x] Answer Y to the desktop shortcut: it's named `SimCity 2000` and starts
      the game
- [x] Answer N: no desktop shortcut
- [x] Uninstall removes the desktop shortcut
- [x] Put another shortcut in the `Maxis` folder, then uninstall. The folder
      and that shortcut stay.

## Settings > Apps entry

- [x] Shows `SimCity 2000® Special Edition`, publisher `Maxis, Inc.`, version,
      size and the game's icon
- [x] Offers Uninstall only, no Modify or Repair

## File types and App Paths

- [x] Double-click a city whose path has a space, such as `New City.sc2`. The
      game opens that city and SC2KRepainter runs.
- [x] Double-click a `.scn` scenario
- [x] Double-click a `.mif` tile set: the Urban Renewal Kit opens it
- [x] `.sc2`, `.scn` and `.mif` files show the game's icons
- [x] Win+R `simcity` starts the game, and `winscurk` starts the Urban
      Renewal Kit
- [x] Set another program as the default for `.mif`, then uninstall. That
      program keeps `.mif`.

## Reinstall and uninstall

- [x] Rerun on an install and pick Reinstall, with one saved city and one
      edited default city. The backup zip has only those two.
- [x] Uninstall from the Start Menu
- [x] Uninstall from Settings > Apps
- [x] Uninstall with `-Uninstall`
- [x] Other programs' entries under the `Layers` key survive install and
      uninstall

## Registry after uninstall

- [x] `HKCU\Software\Maxis` is gone, unless another Maxis game uses it
- [x] `HKCU\Software\Classes` has no `SimCity2000.Document.*` keys, and no
      `.sc2`, `.scn` or `.mif` key pointing at them
- [x] `HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths` has no
      `SimCity.exe` or `WinScurk.exe`
- [x] `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\SimCity2000CDv1`
      is gone
