# Windows software update scripts

PowerShell scripts that update installed software on a Windows computer. Each script can be run on its own, including as a script in [Action1](https://www.action1.com/).

## How a script behaves

Each file in `single_update/` handles one application. When it runs, the script:

1. Reads the installed version from the Windows uninstall registry.
2. Stops when the application is not installed, or when it is already at the target version or newer.
3. Downloads the vendor installer and runs a silent install when an update is needed.
4. Checks the installed version again.
5. Deletes the installer from the temp folder.
6. Exits with a code the caller can use for success, failure, and reboot.

The target version is set at the top of each script. Change that value, and the installer URL if the vendor path changes, before you use a newer release.

## Exit codes

| Code | Result |
| --- | --- |
| `0` | The product is updated, already current, or not installed. |
| `3010` | The update finished and Windows reported that a reboot is required. |
| `1` | The update failed. |

The script also prints a final status line (`Esito Action1: ...`) and how long the run took.

## Scripts

| Script | Application |
| --- | --- |
| `single_update/chrome_update.ps1` | Google Chrome (enterprise MSI) |
| `single_update/python_update.ps1` | Python for Windows |
| `single_update/winrar_update.ps1` | WinRAR |
| `single_update/visualstudio_community_update.ps1` | Visual Studio Community 2026 |

`msc/test_action1.ps1` only prints the computer name and the current time, then exits `0`.

## Before you run a script

The account that runs it must be allowed to install software. Allow enough time for the download and the silent install. Read the script before you run it.

## Disclaimer

You are responsible for reviewing the scripts, for having permission to run them, and for complying with the license terms of each installer and with the rules of the computer owner.
