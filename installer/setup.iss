; ══════════════════════════════════════════════════════════════════════
; LawnHive HRM Software — Inno Setup Installer
; ══════════════════════════════════════════════════════════════════════

[Setup]
AppId={{B7E3C1A0-5F4D-4E9B-A2C8-1D6F8E3B7A90}
AppName=LawnHive HRM Software
AppVersion=1.0
AppPublisher=LawnHive
DefaultDirName={autopf}\LawnHive HRM
DefaultGroupName=LawnHive HRM Software
OutputDir=..\output
OutputBaseFilename=LawnHive-HRM-Setup
Compression=lzma2
SolidCompression=yes
SetupIconFile=..\lawnhive_branding\public\images\logo.ico
UninstallDisplayIcon={app}\logo.ico
WizardStyle=modern
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\docker\docker-compose.yml"; DestDir: "{app}\docker"; Flags: ignoreversion
Source: "..\docker\start.sh"; DestDir: "{app}\docker"; Flags: ignoreversion
Source: "..\lawnhive_branding\*"; DestDir: "{app}\lawnhive_branding"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\license_control\*"; DestDir: "{app}\license_control"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "install.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{app}\sites"

[Icons]
Name: "{group}\LawnHive HRM Dashboard"; Filename: "http://localhost:8080"
Name: "{group}\Uninstall"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install.ps1"" -AppDir ""{app}"" -ClientId ""{ClientId}"""; StatusMsg: "Installing LawnHive HRM..."; Flags: runhidden waituntilterminated

[Code]
var
  ClientIdPage: TNewInputQueryWizardPage;

procedure InitializeWizard;
begin
  ClientIdPage := CreateInputQueryPage(wpWelcome, 'Client ID', 'Enter the client ID for this installation', 'This ID is provided by LawnHive (e.g. NGO001, biz_001).');
  ClientIdPage.Add('Client ID:', False);
  ClientIdPage.Values[0] := 'NGO001';
end;

function GetClientId: String;
begin
  Result := ClientIdPage.Values[0];
end;
