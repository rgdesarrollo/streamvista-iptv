#ifndef AppVersion
  #define AppVersion "1.0.6"
#endif

[Setup]
AppId={{EB8E22EA-4027-447A-A8CE-F02B7D12C748}
AppName=StreamVista IPTV
AppVersion={#AppVersion}
AppPublisher=StreamVista
DefaultDirName={localappdata}\StreamVista IPTV
DefaultGroupName=StreamVista IPTV
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=StreamVista-IPTV-Setup-v{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\streamvista_iptv.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\windows\runner\resources\app_icon.ico"; DestDir: "{app}"; DestName: "streamvista.ico"; Flags: ignoreversion

[Icons]
Name: "{group}\StreamVista IPTV"; Filename: "{app}\streamvista_iptv.exe"
Name: "{autodesktop}\StreamVista IPTV"; Filename: "{app}\streamvista_iptv.exe"

[Run]
Filename: "{app}\streamvista_iptv.exe"; Description: "Open StreamVista IPTV"; Flags: nowait postinstall skipifsilent
