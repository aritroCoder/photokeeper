# photokeeper

A extremely fast lightweight cross-platform gallery organizer.

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

## Releasing and updates

"Check for updates" on the start screen compares the app's version with the newest non-prerelease
GitHub Release and installs that release's asset for the platform: Android opens the system installer,
Windows reruns the installer silently, Linux and macOS replace the app folder and restart.
iOS sideloads can't install anything, so they get a link to the release.

To release, bump `version:` in `pubspec.yaml`, commit, then tag it: `git tag v0.0.2 && git push origin v0.0.2`.
CI refuses a tag that doesn't match `pubspec.yaml`. Android only accepts updates signed with the installed
app's key, so tags also refuse to build without the release keystore. Create it once, back it up, and add it
as repository secrets:

    keytool -genkeypair -keystore photokeeper-release.jks -storetype PKCS12 -alias photokeeper \
      -keyalg RSA -keysize 4096 -validity 10000 -dname CN=PhotoKeeper
    base64 -w0 photokeeper-release.jks | gh secret set ANDROID_KEYSTORE_B64
    gh secret set ANDROID_KEYSTORE_PASSWORD
