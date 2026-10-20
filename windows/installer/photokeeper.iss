; Compile with Inno Setup 6 after building the Windows release and bundling the VC++ runtime.
#define BundleDir AddBackslash(SourcePath) + "..\..\build\windows\x64\runner\Release"
#define AppVersion GetVersionNumbersString(BundleDir + "\photokeeper.exe")

[Setup]
AppId=dev.photokeeper.photokeeper
AppName=PhotoKeeper
AppVersion={#AppVersion}
AppPublisher=PhotoKeeper
DefaultDirName={localappdata}\Programs\PhotoKeeper
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\photokeeper.exe
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir=..\..
OutputBaseFilename=photokeeper-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\PhotoKeeper"; Filename: "{app}\photokeeper.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\PhotoKeeper"; Filename: "{app}\photokeeper.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\photokeeper.exe"; Description: "Launch PhotoKeeper"; Flags: nowait postinstall skipifsilent
; The in-app updater runs Setup silently with /RELAUNCH=1 after quitting, and expects the app back.
Filename: "{app}\photokeeper.exe"; Flags: nowait; Check: Relaunch

[Code]
function Relaunch: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;
