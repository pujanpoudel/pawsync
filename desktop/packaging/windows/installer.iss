#define Version "0.3.0"
[Setup]
AppId={{1771EE53-EE9B-44A6-8538-7D568CC1F924}
AppName=PawSync
AppVersion={#Version}
DefaultDirName={localappdata}\Programs\PawSync
DefaultGroupName=PawSync
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename=PawSync-{#Version}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\PawSync.exe
[Files]
Source: "..\..\dist\PawSync\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\PawSync"; Filename: "{app}\PawSync.exe"
Name: "{autodesktop}\PawSync"; Filename: "{app}\PawSync.exe"; Tasks: desktopicon
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Run]
Filename: "{app}\PawSync.exe"; Description: "Open PawSync"; Flags: nowait postinstall skipifsilent
