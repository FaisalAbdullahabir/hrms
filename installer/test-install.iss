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
OutputBaseFilename=LawnHiveTestSetup
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
Type: files; Name: "{app}\install-error.txt"
Type: files; Name: "{app}\install-error-code.txt"
Type: files; Name: "{app}\Launcher.vbs"
Type: files; Name: "{app}\Update.bat"
Type: files; Name: "{app}\lawnhive.ico"
Type: files; Name: "{app}\server-ip.txt"

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
    if ClientIdValue = '' then ClientIdValue := 'TEST001';
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
  Cmd, ErrorFile, ErrorMsg, FileContent, DebugFile: String;
  SL: TStringList;
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
    
    { DEBUG: Log the exact command and paths BEFORE executing }
    DebugFile := ExpandConstant('{app}\install-debug.txt');
    SL := TStringList.Create;
    try
      SL.Add('=== INSTALLER DEBUG LOG ===');
      SL.Add('Timestamp: ' + GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':'));
      SL.Add('{app} = ' + ExpandConstant('{app}'));
      SL.Add('{src} = ' + ExpandConstant('{src}'));
      SL.Add('{autopf} = ' + ExpandConstant('{autopf}'));
      SL.Add('{localappdata} = ' + ExpandConstant('{localappdata}'));
      SL.Add('ClientId = ' + ClientIdValue);
      if FileExists(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) then
        SL.Add('PowerShell.exe exists: YES')
      else
        SL.Add('PowerShell.exe exists: NO');
      SL.Add('Cmd = ' + Cmd);
      SL.Add('---');
      SL.SaveToFile(DebugFile);
    finally
      SL.Free;
    end;
    
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
    
    { DEBUG: Log the result }
    SL := TStringList.Create;
    try
      if FileExists(DebugFile) then
        SL.LoadFromFile(DebugFile);
      SL.Add('Exec returned: ResultCode=' + IntToStr(ResultCode) + ' InstallExitCode=' + IntToStr(InstallExitCode));
      if FileExists(ExpandConstant('{app}\install.ps1')) then
        SL.Add('install.ps1 exists after run: YES')
      else
        SL.Add('install.ps1 exists after run: NO');
      if FileExists(ExpandConstant('{app}\install.log')) then
        SL.Add('install.log exists after run: YES')
      else
        SL.Add('install.log exists after run: NO');
      if FileExists(ExpandConstant('{app}\install-error.txt')) then
        SL.Add('install-error.txt exists: YES')
      else
        SL.Add('install-error.txt exists: NO');
      SL.SaveToFile(DebugFile);
    finally
      SL.Free;
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
      
      { Try to read specific error from install.ps1 }
      ErrorMsg := '';
      ErrorFile := ExpandConstant('{app}\install-error.txt');
      if FileExists(ErrorFile) then
      begin
        SL := TStringList.Create;
        try
          SL.LoadFromFile(ErrorFile);
          ErrorMsg := SL.Text;
        finally
          SL.Free;
        end;
      end;
      
      if Trim(ErrorMsg) <> '' then
      begin
        Result := ErrorMsg;
      end else
      begin
        { DEBUG: Log that no error file was found }
        SL := TStringList.Create;
        try
          if FileExists(DebugFile) then
            SL.LoadFromFile(DebugFile);
          SL.Add('--- ERROR HANDLING ---');
          if FileExists(ExpandConstant('{app}\install-error.txt')) then
            SL.Add('install-error.txt in {app}: YES')
          else
            SL.Add('install-error.txt in {app}: NO');
          if FileExists(ExpandConstant('{localappdata}\Temp\lawnhive-error.txt')) then
            SL.Add('lawnhive-error.txt in temp: YES')
          else
            SL.Add('lawnhive-error.txt in temp: NO');
          SL.Add('Showing fallback error message to user');
          SL.SaveToFile(DebugFile);
        finally
          SL.Free;
        end;

        { Check fallback error location in temp dir }
        ErrorFile := ExpandConstant('{localappdata}\Temp\lawnhive-error.txt');
        if not FileExists(ErrorFile) then
          ErrorFile := ExpandConstant('{app}\install-error.txt');
        if FileExists(ErrorFile) then
        begin
          SL := TStringList.Create;
          try
            SL.LoadFromFile(ErrorFile);
            ErrorMsg := SL.Text;
          finally
            SL.Free;
          end;
        end;
        
        if Trim(ErrorMsg) <> '' then
        begin
          Result := ErrorMsg;
        end else
        begin
          Result := 'Installation failed (unknown error).'#13#10#13#10 +
            'The installer could not create the log file.'#13#10 +
            'This usually means the installation directory'#13#10 +
            'could not be created, or antivirus blocked the script.'#13#10#13#10 +
            'Please try these steps:'#13#10 +
            '1. Right-click the installer and choose "Run as administrator"'#13#10 +
            '2. Temporarily disable antivirus, then try again'#13#10 +
            '3. Restart your computer and try again'#13#10#13#10 +
            'Contact LawnHive support if the problem persists.';
        end;
      end;
      Exit;
    end;
    
  finally
    ProgressPage.Hide;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  IPFile, ServerIP, Msg: String;
  SL: TStringList;
begin
  if CurStep = ssPostInstall then
  begin
    { Read the server IP saved by install.ps1 }
    ServerIP := '';
    IPFile := ExpandConstant('{app}\server-ip.txt');
    if FileExists(IPFile) then
    begin
      SL := TStringList.Create;
      try
        SL.LoadFromFile(IPFile);
        if SL.Count > 0 then
          ServerIP := Trim(SL[0]);
      finally
        SL.Free;
      end;
    end;

    { Show post-install instructions }
    if ServerIP <> '' then
    begin
      Msg := 'Installation completed successfully!'#13#10#13#10 +
        '=== Your Office Network Address ==='#13#10 +
        'http://' + ServerIP + ':8000'#13#10#13#10 +
        'Other computers in your office can access LawnHive'#13#10 +
        'Workspace from their web browser using the address above.'#13#10#13#10 +
        '=== Setup for other computers ==='#13#10 +
        '1. Install "LawnHive Workspace Client" on each employee PC'#13#10 +
        '2. The client installer will find this server automatically'#13#10#13#10 +
        'IMPORTANT: Keep this computer turned on and running'#13#10 +
        'at all times so other computers can connect.';
    end else
    begin
      Msg := 'Installation completed successfully!'#13#10#13#10 +
        'Open your web browser and go to: http://localhost:8000'#13#10#13#10 +
        'To find your network address for other computers:'#13#10 +
        '1. Open Command Prompt (search "cmd")'#13#10 +
        '2. Type: ipconfig'#13#10 +
        '3. Look for "IPv4 Address" (e.g., 192.168.1.5)'#13#10 +
        '4. Other computers go to: http://192.168.1.5:8000';
    end;
    
    MsgBox(Msg, mbInformation, MB_OK);

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
