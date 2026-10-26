# sc2k_win95-installer

Installs the Windows 95 version of SimCity 2000: Special Edition on Windows 10
and 11 from an ISO of the original CD.

## Quick start

1. Download `sc2k_install.ps1` from the
   [latest release](https://github.com/Mahir007/sc2k_win95-installer/releases/latest).
2. Right-click it and choose Run with PowerShell. Accept the administrator
   prompt.
3. Select your SimCity 2000 Special Edition ISO.
4. When SC2000X opens, right-click in its window to paste the path to
   `SIMCITY.EXE`, which the installer has copied to the clipboard. Press Enter
   in the installer window once SC2000X says it has finished.

Launch the game from the Start Menu or the desktop shortcut.

## Usage

From a PowerShell or Command Prompt window:

```
powershell -ExecutionPolicy Bypass -File .\sc2k_install.ps1 [-Iso <path>] [-Reinstall]
powershell -ExecutionPolicy Bypass -File .\sc2k_install.ps1 -Uninstall
```

| Parameter | |
| --- | --- |
| `-Iso <path>` | Use this ISO instead of opening a file picker |
| `-Reinstall` | Reinstall without asking, if already installed |
| `-Uninstall` | Uninstall |
| `-Version` | Show the version |

`Get-Help .\sc2k_install.ps1` or `-?` shows the same help.

Running the script on a machine where the game is already installed asks
whether to reinstall or uninstall. You can also uninstall from the Start Menu
or from Settings > Apps.

Before a reinstall or uninstall removes the game, the script offers to back up
cities you saved in the install folder to a zip in Documents. Cities that
ship with the game are left out unless you saved over them.

## What it does

- Extracts the game from the ISO to
  `%LOCALAPPDATA%\Programs\SimCity 2000 Special Edition`. It downloads
  [lessmsi](https://github.com/activescott/lessmsi) and
  [7-Zip](https://github.com/ip7z/7zip) to a temporary folder to do this.
- Creates `C:\DATA` as a hidden link to the game's `DATA` folder. The game
  only plays its intro movies from there. This is why the script needs
  administrator rights.
- Patches the game with [SC2000X](https://github.com/alekasm/SC2000X) and
  sets it to run in 256-colour mode.
- Adds [SC2KRepainter](https://github.com/Guspaz/SC2KRepainter), which
  restores palette animation. The shortcuts start it
  alongside the game.
- Creates Start Menu shortcuts for the game, the Urban Renewal Kit and the
  uninstaller, and optionally a desktop shortcut.

## Troubleshooting

### "Running scripts is disabled on this system"

Run the script with the command under [Usage](#usage), which bypasses the
execution policy for that run only.

### C:\DATA already exists

The script offers to rename it to `C:\DATA.old`, and renames it back when you
uninstall. If you skip this step the game works, but the intro movies don't
play.

### "The ISO doesn't look like SimCity 2000 Special Edition"

The ISO has no `WIN95\SC2K`, `WIN95\GOODIES` or `DATA` folder. It is probably
not the Special Edition CD.

## License

GPL-3.0. See [LICENSE](LICENSE).
