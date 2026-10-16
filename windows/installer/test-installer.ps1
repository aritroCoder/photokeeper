param(
    [Parameter(Mandatory)][string]$InstallerPath,
    [Parameter(Mandatory)][string]$BundleDir
)

$ErrorActionPreference = "Stop"
$installer = (Resolve-Path $InstallerPath).Path
$bundle = (Resolve-Path $BundleDir).Path
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("photokeeper-installer-" + [guid]::NewGuid())
$installDir = Join-Path $testRoot "PhotoKeeper"
New-Item -ItemType Directory -Path $testRoot | Out-Null
$shortcuts = @(
    (Join-Path ([Environment]::GetFolderPath("Programs")) "PhotoKeeper.lnk"),
    (Join-Path ([Environment]::GetFolderPath("DesktopDirectory")) "PhotoKeeper.lnk")
foreach ($shortcut in $shortcuts) {
    if (Test-Path $shortcut) { throw "Run this smoke test on a clean Windows runner: $shortcut already exists" }
}

# A second installation checks that the stable AppId supports upgrades in place.
foreach ($pass in 1, 2) {
    $process = Start-Process -FilePath $installer -Wait -PassThru -ArgumentList @(
        "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/TASKS=desktopicon",
        "/DIR=`"$installDir`"", "/LOG=`"$testRoot\install-$pass.log`""
    )
    if ($process.ExitCode -ne 0) { throw "Installer failed with exit code $($process.ExitCode); logs: $testRoot" }
}

# Compare the entire payload, including nested Flutter assets and native libraries.
foreach ($source in Get-ChildItem $bundle -Recurse -File) {
    $relative = [IO.Path]::GetRelativePath($bundle, $source.FullName)
    $installed = Join-Path $installDir $relative
    if (!(Test-Path $installed -PathType Leaf)) { throw "Missing installed file: $relative" }
    if ((Get-FileHash $source.FullName).Hash -ne (Get-FileHash $installed).Hash) {
        throw "Installed file differs from release bundle: $relative"
    }
}
foreach ($shortcut in $shortcuts) {
    if (!(Test-Path $shortcut -PathType Leaf)) { throw "Missing shortcut: $shortcut" }
}

$uninstaller = Join-Path $installDir "unins000.exe"
$process = Start-Process -FilePath $uninstaller -Wait -PassThru -ArgumentList @(
    "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/LOG=`"$testRoot\uninstall.log`""
)
if ($process.ExitCode -ne 0) { throw "Uninstaller failed with exit code $($process.ExitCode); logs: $testRoot" }
foreach ($source in Get-ChildItem $bundle -Recurse -File) {
    $installed = Join-Path $installDir ([IO.Path]::GetRelativePath($bundle, $source.FullName))
    if (Test-Path $installed) { throw "Uninstaller left an app file behind: $installed" }
}
foreach ($shortcut in $shortcuts) {
    if (Test-Path $shortcut) { throw "Uninstaller left a shortcut behind: $shortcut" }
}
Write-Host "Installer passed: install, upgrade, complete payload, shortcuts, and uninstall."
