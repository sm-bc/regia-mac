# Regia for Mac

**English** · [Italiano](README.it.md)

A free app for **macOS 14 or later** (Apple Silicon and Intel) that analyzes your Mac and optimizes it safely. It is the Mac version of [Regia for Windows](https://github.com/sm-bc/regia).

**[⬇ Download the latest version](https://github.com/sm-bc/regia-mac/releases/latest)**

## What it does
- **English or Italian interface**: switch it at the bottom left of the sidebar, in the Language menu or in Settings (⌘,).
- **Overview** with live data: processor, memory, network, disk, battery and temperature. Plus tips with one-click fixes and a **restart** reminder when the Mac has been on for several days.
- **Tips**: security checks (FileVault, firewall, Gatekeeper, automatic updates, Time Machine), settings worth changing by hand and good habits.
- **Profiles**: Maximum, Balanced and Safe. You can also save your own.
- **Tweaks**: 37 single settings for speed, Dock, Finder, efficiency, keyboard, screenshots, energy and privacy.
- **App Updates**: checks App Store apps, apps downloaded from developers' websites (Sparkle) and Homebrew.
- **Cleanup** of caches, logs and Xcode files. Files go to the Trash, so they can be recovered.
- **Leftovers** of deleted apps, and **Installed Apps** with "Uninstall and Clean".
- **Startup**: the programs that launch on their own.
- **Maintenance**: disk, battery, macOS updates, network latency and speed, DNS cache, Spotlight.
- **Feedback**: "Feedback" at the bottom left prepares a bug report or an idea and opens the GitHub page (you submit it yourself).

## Why it's safe
- **Test mode** is on at every launch: you see everything as a preview, but nothing changes.
- Before every change: a "now → after" preview, a confirmation and a backup of the settings involved.
- **Undo All** puts back the previous values.
- It never touches macOS protected system files. It sends no personal data: it only goes online to check for updates (of Regia and of your apps: the public App Store catalog and developers' websites) and when you run a network test.

## Install
1. Open **[Releases](https://github.com/sm-bc/regia-mac/releases/latest)** and download `Regia-Mac_x.y.zip`.
2. Open the zip and drag **Regia** to **Applications**.
3. On first launch macOS says it can't verify the developer, because Regia isn't signed with a paid Apple certificate. Open **System Settings › Privacy & Security** and click **Open Anyway**.

## Updates
At launch Regia checks for a new version. When there is one, an **Update** button appears at the bottom left. Before installing it asks for confirmation and checks:
- the SHA-256 fingerprint of the package;
- the app identifier;
- the version number;
- the code signature.

The previous version is kept in `~/Library/Application Support/Regia/Versioni`.

## Report a problem or suggest an idea
Use **Feedback** inside the app, or open a new [issue](https://github.com/sm-bc/regia-mac/issues).

## Build from source
Requires Xcode command line tools (Swift 5.9 or later). No external dependencies.
```bash
./crea-app.sh              # builds Regia.app (Apple Silicon + Intel)
./crea-app.sh --installa   # ...and copies it to /Applications
./Regia.app/Contents/MacOS/Regia --autotest   # tests everything on fake data
./Regia.app/Contents/MacOS/Regia --analisi    # read-only report in Terminal
```

## Disclaimer
Changing system settings always carries a small risk. Use Test mode and read the previews. The software is provided "as is", without warranty (see `LICENSE`).

## License
MIT.
