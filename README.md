# photokeeper

A cross-platform photo keep/delete classifier.

On Windows, download `photokeeper-windows-x64-setup.exe` from the
[latest release](https://github.com/aritroCoder/photokeeper/releases/tag/latest).
The installer includes the app and all its dependencies, installs for the current
user without administrator access, and creates a Start menu shortcut. A desktop
shortcut is optional. Install a newer version in the same location to upgrade;
remove it through Windows Settings > Apps to uninstall.

The Windows CI job builds the installer with Inno Setup 6 and tests installation,
upgrading in place, and uninstallation before publishing it. To package locally,
build the Windows release, copy the VC++ runtime DLLs as shown in
`.github/workflows/build.yml`, then run `ISCC.exe windows\installer\photokeeper.iss`.
