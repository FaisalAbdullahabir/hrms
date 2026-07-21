; ============================================================================
; LawnHive Workspace - Professional Client Installer
; ============================================================================
; 
; All system logic is in install.ps1. This script handles:
; - Wizard UI, branding, progress
; - Collecting Client ID
; - Running install.ps1 silently
; - Creating shortcuts
;
; ============================================================================

#define MyAppName "LawnHive Workspace"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "LawnHive"
#define MyAppURL "https://lawnhive.com"

[Setup]
AppId={{A8F2D3E1-7B4C-4D5A-9E6F-1C2B3A4D5E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\LawnHive Workspace
DefaultGroupName={#MyAppName}
OutputDir=output
OutputBaseFilename=LawnHiveWorkspaceSetup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=assets\lawnhive.ico
UninstallDisplayIcon={app}\lawnhive.ico
WizardImageFile=assets\wizard_image.bmp
WizardSmallImageFile=assets\wizard_small.bmp
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DisableProgramGroupPage=yes
DisableReadyPage=no
DisableFinishedPage=yes
CloseApplications=no
RestartApplications=no
AllowNoIcons=yes
VersionInfoVersion=1.0.0.0
VersionInfoDescription={#MyAppName} Installer
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Files]
Source: "..\docker\lawnhive-image\docker-compose.client.yml"; DestDir: "{app}"; DestName: "docker-compose.yml"; Flags: ignoreversion onlyifdoesntexist
Source: "scripts\install.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "scripts\launcher.vbs"; DestDir: "{app}"; DestName: "Launcher.vbs"; Flags: ignoreversion
Source: "scripts\update.bat"; DestDir: "{app}"; DestName: "Update.bat"; Flags: ignoreversion
Source: "assets\lawnhive.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "wscript.exe"; Parameters: """{app}\Launcher.vbs"""; IconFilename: "{app}\lawnhive.ico"; Comment: "Open {#MyAppName}"
Name: "{group}\Update {#MyAppName}"; Filename: "cmd.exe"; Parameters: "/c ""{app}\Update.bat"""; IconFilename: "{app}\lawnhive.ico"; Comment: "Update {#MyAppName} to latest version"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"; IconFilename: "{app}\lawnhive.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "wscript.exe"; Parameters: """{app}\Launcher.vbs"""; IconFilename: "{app}\lawnhive.ico"; Comment: "Open {#MyAppName}"; Tasks: desktopicon

[UninstallDelete]
Type: filesandordirs; Name: "{app}\.env"
Type: files; Name: "{app}\docker-compose.yml"
Type: files; Name: "{app}\install.ps1"
Type: files; Name: "{app}\install.log"
Type: files; Name: "{app}\Launcher.vbs"
Type: files; Name: "{app}\Update.bat"
Type: files; Name: "{app}\lawnhive.ico"

[Code]
var
  ClientIdPage: TInputQueryWizardPage;
  ProgressPage: TOutputProgressWizardPage;
  ClientIdValue: String;
  NeedsRestart: Boolean;
  InstallExitCode: Integer;

function ExpandStr(const S: String): String;
begin
  Result := ExpandConstant(S);
end;

function IsDockerInstalled: Boolean;
var
  P: String;
begin
  P := ExpandConstant('{autopf}\Docker\Docker\Docker Desktop.exe');
  Result := FileExists(P);
  if not Result then
  begin
    P := ExpandConstant('{localappdata}\Docker\app\version\bin\Docker Desktop.exe');
    Result := FileExists(P);
  end;
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  NeedsRestart := False;
  InstallExitCode := 0;
end;

procedure InitializeWizard;
begin
  { Welcome text }
  WizardForm.Caption := '{#MyAppName} Setup';
  
  { Client ID page after license/agreement page }
  ClientIdPage := CreateInputQueryPage(wpLicense,
    'Client Registration',
    'Enter your Client ID',
    'Your Client ID was provided by LawnHive during registration.'#13#10 +
    'Please enter it exactly as provided.');
  ClientIdPage.Add('Client ID:', False);
  ClientIdPage.Values[0] := '';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  if CurPageID = ClientIdPage.ID then
  begin
    ClientIdValue := Trim(ClientIdPage.Values[0]);
    if ClientIdValue = '' then
    begin
      MsgBox('Please enter your Client ID to continue.'#13#10#13#10 +
        'Contact LawnHive support if you do not have one.',
        mbError, MB_OK);
      Result := False;
      Exit;
    end;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := MemoDirInfo + NewLine + NewLine +
    'Client ID: ' + ClientIdValue + NewLine + NewLine +
    'The installer will configure everything automatically.'#13#10 +
    'Please do not turn off your computer during setup.';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
  Cmd: String;
begin
  Result := '';
  NeedsRestart := False;
  
  { Run the install script }
  ProgressPage := CreateOutputProgressPage(
    'Installing {#MyAppName}',
    'Please wait while we set up your workspace...');
  ProgressPage.Show;
  
  try
    ProgressPage.SetText('Preparing installation...', '');
    ProgressPage.SetProgress(10, 100);
    Sleep(500);

    Cmd := '-NoProfile -ExecutionPolicy Bypass -File "' +
      ExpandConstant('{app}\install.ps1') +
      '" -ClientId "' + ClientIdValue +
      '" -InstallDir "' + ExpandConstant('{app}') +
      '" -SourceDir "' + ExpandConstant('{src}') + '"';
    
    ProgressPage.SetText('Setting up components (this may take 15-30 minutes)...', '');
    ProgressPage.SetProgress(20, 100);
    
    { Hide the wizard window during installation }
    WizardForm.Visible := False;
    
    { Run the PowerShell script - this blocks until done }
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
    
    if InstallExitCode = 3010 then
    begin
      { Restart required }
      NeedsRestart := True;
    end
    else if InstallExitCode <> 0 then
    begin
      ProgressPage.Hide;
      Result := 'Installation encountered an issue.'#13#10#13#10 +
        'Please ensure you have an active internet connection and try again.'#13#10 +
        'If the problem persists, contact LawnHive support.';
      Exit;
    end;
    
  finally
    ProgressPage.Hide;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
  begin
    { Launch the app after install }
    Exec('wscript.exe', '"' + ExpandConstant('{app}\Launcher.vbs') + '"',
      ExpandConstant('{app}'), SW_SHOW, ewNoWait, ResultCode);
  end;
end;

procedure DeinitializeSetup;
begin
  { Clean up }
  DeleteFile(ExpandConstant('{app}\install.ps1'));
end;
