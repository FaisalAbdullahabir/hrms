; ============================================================================
; LawnHive Workspace - Employee PC Client Installer
; ============================================================================
; Lightweight installer for employee PCs.
; No Docker, no containers — just a browser shortcut to the server.
;
; Flow:
;   1. Auto-detect server on local network (5-10 seconds)
;   2. If found: confirm with user
;   3. If not found or user declines: manual IP input
;   4. Health-check the IP
;   5. Create desktop + Start Menu shortcuts
;
; ============================================================================

#define MyAppName "LawnHive Workspace"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "LawnHive"
#define MyAppURL "https://lawnhive.com"

[Setup]
AppId={{B7E4F2A1-9C3D-4E5F-8A1B-2C3D4E5F6A7B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\LawnHive Workspace
DefaultGroupName={#MyAppName}
OutputDir=output
OutputBaseFilename=LawnHiveWorkspaceClient
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\assets\lawnhive.ico
UninstallDisplayIcon={app}\lawnhive.ico
WizardImageFile=..\assets\wizard_image.bmp
WizardSmallImageFile=..\assets\wizard_small.bmp
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DisableProgramGroupPage=yes
DisableReadyPage=no
DisableFinishedPage=yes
CloseApplications=no
RestartApplications=no
AllowNoIcons=yes
VersionInfoVersion=1.0.0.0
VersionInfoDescription={#MyAppName} Client Installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Files]
Source: "scripts\install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "scripts\launcher.vbs"; DestDir: "{app}"; DestName: "Launcher.vbs"; Flags: ignoreversion
Source: "..\assets\lawnhive.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "wscript.exe"; Parameters: """{app}\Launcher.vbs"""; IconFilename: "{app}\lawnhive.ico"; Comment: "Open {#MyAppName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"; IconFilename: "{app}\lawnhive.ico"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\server.conf"
Type: files; Name: "{app}\install.log"
Type: files; Name: "{app}\Launcher.vbs"
Type: files; Name: "{app}\lawnhive.ico"
Type: files; Name: "{app}\install.ps1"
Type: files; Name: "{autodesktop}\LawnHive Workspace.url"

[Code]
var
  ProgressPage: TOutputProgressWizardPage;
  InstallExitCode: Integer;

function InitializeSetup: Boolean;
begin
  Result := True;
  InstallExitCode := 0;
end;

procedure InitializeWizard;
begin
  WizardForm.Caption := '{#MyAppName} - Employee Setup';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  Cmd: String;
begin
  Result := '';
  NeedsRestart := False;

  ProgressPage := CreateOutputProgressPage(
    'Setting up {#MyAppName}',
    'Searching for your office server...');
  ProgressPage.Show;

  try
    ProgressPage.SetText('Searching for office server on your network...', '');
    ProgressPage.SetProgress(10, 100);

    Cmd := '-NoProfile -ExecutionPolicy Bypass -File "' +
      ExpandConstant('{app}\install.ps1') +
      '" -InstallDir "' + ExpandConstant('{app}') + '"';

    ProgressPage.SetText('Connecting to server...', '');
    ProgressPage.SetProgress(30, 100);

    WizardForm.Visible := False;

    InstallExitCode := 0;
    if not Exec('powershell.exe', Cmd, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      InstallExitCode := -1;
    end else
    begin
      InstallExitCode := ResultCode;
    end;

    WizardForm.Visible := True;
    ProgressPage.SetProgress(100, 100);

    if InstallExitCode <> 0 then
    begin
      ProgressPage.Hide;
      Result := 'Setup could not be completed.'#13#10#13#10 +
        'Please ensure you are connected to the office network and try again.'#13#10 +
        'If the problem persists, contact your office manager.';
      Exit;
    end;

  finally
    ProgressPage.Hide;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    { install.ps1 already created shortcuts and opened browser }
  end;
end;

procedure DeinitializeSetup;
begin
  DeleteFile(ExpandConstant('{app}\install.ps1'));
end;
