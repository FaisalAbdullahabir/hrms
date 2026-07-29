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
DisableDirPage=no
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
Type: files; Name: "{app}\install-progress.txt"
Type: files; Name: "{app}\install-progress-done.txt"
Type: files; Name: "{app}\install.pid"
Type: files; Name: "{app}\force-internet.txt"
Type: files; Name: "{app}\lawnhive-debug.txt"
Type: filesandordirs; Name: "{app}"
Type: files; Name: "{autodesktop}\Resume LawnHive Installation.lnk"
Type: files; Name: "{group}\Resume Installation.lnk"

[Code]
type
  TMsgPoint = record
    X: Integer;
    Y: Integer;
  end;
  TMsg = record
    hwnd: Integer;
    message: Integer;
    wParam: Integer;
    lParam: Integer;
    time: Integer;
    pt: TMsgPoint;
  end;

function PeekMessageA(var lpMsg: TMsg; hWnd: Integer; wMsgFilterMin: Integer; wMsgFilterMax: Integer; wRemoveMsg: Integer): Integer;
external 'PeekMessageA@user32.dll stdcall';
function TranslateMessage(var lpMsg: TMsg): Integer;
external 'TranslateMessage@user32.dll stdcall';
function DispatchMessageA(var lpMsg: TMsg): Integer;
external 'DispatchMessageA@user32.dll stdcall';
function SetWindowPos(hWnd: Integer; hWndInsertAfter: Integer; X: Integer; Y: Integer; cx: Integer; cy: Integer; uFlags: Integer): Integer;
external 'SetWindowPos@user32.dll stdcall';
function GetForegroundWindow(): Integer;
external 'GetForegroundWindow@user32.dll stdcall';
function GetDiskFreeSpaceEx(lpDirectoryName: AnsiString; var lpFreeBytesAvailableToCaller: Int64;
  var lpTotalNumberOfBytes: Int64; var lpTotalNumberOfFreeBytes: Int64): Boolean;
external 'GetDiskFreeSpaceExA@kernel32.dll stdcall';

var
  ClientIdPage: TInputQueryWizardPage;
  ProgressPage: TOutputProgressWizardPage;
  ClientIdValue: String;
  NeedsRestart: Boolean;
  InstallExitCode: Integer;
  InstallPrepared: Boolean;
  CmdLine: String;
  DebugFile: String;
  CancelRequested: Boolean;
  ForceContinueUsed: Boolean;

procedure ProcessMessages;
var
  Msg: TMsg;
begin
  while PeekMessageA(Msg, 0, 0, 0, 1) <> 0 do
  begin
    TranslateMessage(Msg);
    DispatchMessageA(Msg);
  end;
end;

const
  HWND_TOPMOST = -1;
  SWP_NOMOVE = $0002;
  SWP_NOSIZE = $0001;
  SWP_NOACTIVATE = $0010;
  SWP_SHOWWINDOW = $0040;

procedure KeepWizardOnTop;
var
  Wnd: Integer;
begin
  Wnd := WizardForm.Handle;
  SetWindowPos(Wnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE or SWP_SHOWWINDOW);
end;

function ExpandStr(const S: String): String;
begin
  Result := ExpandConstant(S);
end;

function GetDriveFreeSpace(const Dir: String): Int64;
var
  FreeAvailable, TotalBytes, TotalFree: Int64;
begin
  Result := 0;
  if GetDiskFreeSpaceEx(Dir, FreeAvailable, TotalBytes, TotalFree) then
    Result := FreeAvailable;
end;

function WarnLowDriveSpace(const DriveLabel, DriveRoot: String; const NeededGB: Integer): Boolean;
var
  FreeBytes, NeededBytes: Int64;
  FreeGB: Integer;
begin
  Result := True;
  NeededBytes := NeededGB * 1024 * 1024 * 1024;
  FreeBytes := GetDriveFreeSpace(DriveRoot);
  FreeGB := FreeBytes div (1024 * 1024 * 1024);
  if FreeBytes < NeededBytes then
  begin
    if MsgBox('Warning: ' + DriveLabel + ' (' + DriveRoot + ') has only about ' +
      IntToStr(FreeGB) + 'GB free.' + #13#10 + #13#10 +
      'The workspace needs at least ' + IntToStr(NeededGB) + 'GB free on this drive.' + #13#10 + #13#10 +
      'Do you want to continue anyway?',
      mbConfirmation, MB_YESNO) = IDNO then
      Result := False;
  end;
end;

function CheckDiskSpaceOnDrive(const AppDir: String): Boolean;
var
  AppDrive: String;
begin
  Result := True;

  { Always check C: drive — Docker stores data there }
  if not WarnLowDriveSpace('C: drive (for Docker data)', 'C:\', 6) then
  begin
    Result := False;
    Exit;
  end;

  { Check selected install drive }
  AppDrive := Copy(AppDir, 1, 2);
  if AppDrive <> 'C:' then
  begin
    if not WarnLowDriveSpace('Selected install drive', AppDrive + '\', 1) then
    begin
      Result := False;
      Exit;
    end;
  end;
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
  CancelRequested := False;
  ForceContinueUsed := False;
end;

procedure InitializeWizard;
begin
  WizardForm.Caption := '{#MyAppName} Setup';
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
  end
  else if CurPageID = wpSelectDir then
  begin
    if not CheckDiskSpaceOnDrive(ExpandConstant('{app}')) then
    begin
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
    'The installer will configure everything automatically.' + NewLine +
    'Please do not turn off your computer during setup.' + NewLine + NewLine +
    'Note: Docker Desktop stores its data on C: drive.' + NewLine +
    'Make sure C: has at least 6GB free space.';
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  NeedsRestart := False;
  InstallPrepared := False;

  ProgressPage := CreateOutputProgressPage(
    'Installing',
    'Installation in progress, please wait.');
  ProgressPage.Show;
  ProgressPage.SetText('Preparing installation...', '');
  ProgressPage.SetProgress(5, 100);
  Sleep(300);

  InstallPrepared := True;
end;

procedure RunInstallScript;
var
  ResultCode: Integer;
  ErrorFile, ErrorMsg: String;
  SL: TStringList;
  ProgressFile, DoneFile, PidFile: String;
  Progress, LastProgress, MaxPolls, PollCount, PipePos: Integer;
  StatusText, LastStatus, DoneCode, Line: String;
  Done: Boolean;
  ErrorCode, ErrorCodeFile: String;
  DialogChoice: Integer;
  ForceFile: String;
begin
  ProgressFile := ExpandConstant('{app}\install-progress.txt');
  DoneFile := ExpandConstant('{app}\install-progress-done.txt');
  PidFile := ExpandConstant('{app}\install.pid');

  DeleteFile(ProgressFile);
  DeleteFile(DoneFile);
  DeleteFile(PidFile);

  CmdLine := '-NoProfile -ExecutionPolicy Bypass -File "' +
    ExpandConstant('{app}\install.ps1') +
    '" -ClientId "' + ClientIdValue +
    '" -InstallDir "' + ExpandConstant('{app}') +
    '" -SourceDir "' + ExpandConstant('{src}') + '"';

  DebugFile := ExpandConstant('{tmp}\lawnhive-install-debug.txt');
  SL := TStringList.Create;
  try
    SL.Add('=== INSTALLER DEBUG LOG ===');
    SL.Add('Timestamp: ' + GetDateTimeString('yyyy-mm-dd hh:nn:ss', '-', ':'));
    SL.Add('{app} = ' + ExpandConstant('{app}'));
    SL.Add('{src} = ' + ExpandConstant('{src}'));
    SL.Add('ClientId = ' + ClientIdValue);
    if FileExists(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe')) then
      SL.Add('PowerShell.exe exists: YES')
    else
      SL.Add('PowerShell.exe exists: NO');
    if FileExists(ExpandConstant('{app}\install.ps1')) then
      SL.Add('install.ps1 exists before Exec: YES')
    else
      SL.Add('install.ps1 exists before Exec: NO');
    SL.Add('Cmd = ' + CmdLine);
    SL.Add('---');
    SL.SaveToFile(DebugFile);
  finally
    SL.Free;
  end;

  if not FileExists(ExpandConstant('{app}\install.ps1')) then
  begin
    ProgressPage.Hide;
    MsgBox('Installation error: install.ps1 not found at:'#13#10 +
      ExpandConstant('{app}\install.ps1') + #13#10#13#10 +
      'Please try downloading the installer again or contact support.',
      mbError, MB_OK);
    InstallExitCode := -999;
    Exit;
  end;

  WizardForm.Visible := True;
  WizardForm.Caption := '{#MyAppName} Setup - Installing...';

  InstallExitCode := 0;
  if not Exec('powershell.exe', CmdLine, ExpandConstant('{app}'), SW_HIDE, ewNoWait, ResultCode) then
  begin
    InstallExitCode := -1;
    ProgressPage.Hide;
    MsgBox('Failed to start the installation script.'#13#10#13#10 +
      'Please try running the installer as administrator.', mbError, MB_OK);
    Exit;
  end;

  LastProgress := 5;
  LastStatus := '';
  MaxPolls := 1800;
  PollCount := 0;
  Done := False;

  while not Done do
  begin
    ProcessMessages;
    Sleep(500);
    PollCount := PollCount + 1;

    if (PollCount mod 4 = 0) then
      KeepWizardOnTop;

    if CancelRequested then
    begin
      InstallExitCode := -3;
      Done := True;
    end;

    if not Done and FileExists(DoneFile) then
    begin
      SL := TStringList.Create;
      try
        SL.LoadFromFile(DoneFile);
        if SL.Count > 0 then
          DoneCode := Trim(SL[0])
        else
          DoneCode := '0';
      finally
        SL.Free;
      end;
      InstallExitCode := StrToIntDef(DoneCode, 1);
      Done := True;
    end;

    if not Done and (PollCount >= MaxPolls) then
    begin
      InstallExitCode := -2;
      Done := True;
    end;

    if not Done and FileExists(ProgressFile) then
    begin
      SL := TStringList.Create;
      try
        SL.LoadFromFile(ProgressFile);
        if SL.Count > 0 then
        begin
          Line := Trim(SL[0]);
          PipePos := Pos('|', Line);
          if PipePos > 0 then
          begin
            Progress := StrToIntDef(Copy(Line, 1, PipePos - 1), LastProgress);
            StatusText := Copy(Line, PipePos + 1, Length(Line) - PipePos);
          end;
        end;
      finally
        SL.Free;
      end;

      if Progress <> LastProgress then
      begin
        ProgressPage.SetProgress(Progress, 100);
        LastProgress := Progress;
      end;

      if StatusText <> LastStatus then
      begin
        ProgressPage.SetText(StatusText, IntToStr(Progress) + '% complete');
        LastStatus := StatusText;
      end;
    end;
  end;

  KeepWizardOnTop;
  ProgressPage.SetProgress(100, 100);
  ProgressPage.SetText('Installation complete!', '');

  SL := TStringList.Create;
  try
    if FileExists(DebugFile) then
      SL.LoadFromFile(DebugFile);
    SL.Add('PollCount=' + IntToStr(PollCount) + ' InstallExitCode=' + IntToStr(InstallExitCode));
    SL.SaveToFile(DebugFile);
  finally
    SL.Free;
  end;

  if InstallExitCode = 3010 then
  begin
    NeedsRestart := False;
    ProgressPage.Hide;
    
    if MsgBox('Docker Desktop and system components have been installed.'#13#10#13#10 +
      'Your computer needs to restart to complete the setup.'#13#10#10 +
      'After restart, the installation will continue automatically.'#13#10#10 +
      'Would you like to restart now?'#13#10 +
      '(Click "Yes" to restart now, "No" to restart manually later)',
      mbConfirmation, MB_YESNO) = IDYES then
    begin
      NeedsRestart := True;
    end;
    Exit;
  end;

  if InstallExitCode <> 0 then
  begin
    ProgressPage.Hide;

    ErrorCodeFile := ExpandConstant('{app}\install-error-code.txt');
    ErrorCode := '';
    if FileExists(ErrorCodeFile) then
    begin
      SL := TStringList.Create;
      try
        SL.LoadFromFile(ErrorCodeFile);
        if SL.Count > 0 then
          ErrorCode := Trim(SL[0]);
      finally
        SL.Free;
      end;
    end;

    if (ErrorCode = 'NO_INTERNET_NO_DOCKER') or (ErrorCode = 'NO_IMAGE_NO_INTERNET') then
    begin
      DialogChoice := MsgBox(
        'Internet connection could not be verified.'#13#10#13#10 +
        'This may be due to a firewall, antivirus, or network restriction.'#13#10#13#10 +
        'If you are sure the internet is working, you can try:'#13#10 +
        '  - Click "Retry" to check again'#13#10 +
        '  - Click "Continue" to skip the internet check'#13#10#13#10 +
        'Note: To continue without internet, you must have:'#13#10 +
        '  - Docker Desktop already installed, OR'#13#10 +
        '  - The lawnhive-image.tar file in the same folder as this installer.'#13#10#13#10 +
        'Would you like to retry or continue anyway?',
        mbConfirmation, MB_YESNOCANCEL);

      if DialogChoice = IDYES then
      begin
        ForceContinueUsed := False;
        ProgressPage.Show;
        ProgressPage.SetText('Retrying internet check...', '');
        ProgressPage.SetProgress(5, 100);
        RunInstallScript;
      end
      else if DialogChoice = IDNO then
      begin
        ForceContinueUsed := True;
        ForceFile := ExpandConstant('{app}\force-internet.txt');
        SL := TStringList.Create;
        try
          SL.Add('user-confirmed');
          SL.SaveToFile(ForceFile);
        finally
          SL.Free;
        end;
        ProgressPage.Show;
        ProgressPage.SetText('Continuing installation (internet check skipped)...', '');
        ProgressPage.SetProgress(5, 100);
        RunInstallScript;
      end
      else
        InstallExitCode := -3;
    end
    else
    begin
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

      if Trim(ErrorMsg) = '' then
      begin
        ErrorFile := ExpandConstant('{localappdata}\Temp\lawnhive-error.txt');
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
      end;

      if Trim(ErrorMsg) <> '' then
        MsgBox(ErrorMsg, mbError, MB_OK)
      else if InstallExitCode = -3 then
        MsgBox('Installation cancelled.'#13#10#13#10 +
          'You can run the installer again when ready.', mbInformation, MB_OK)
      else if InstallExitCode = -2 then
        MsgBox('Installation timed out after 30 minutes.'#13#10#13#10 +
          'Please check your internet connection and try again.', mbError, MB_OK)
      else
        MsgBox('Installation failed with exit code ' + IntToStr(InstallExitCode) + '.'#13#10#13#10 +
          'Check these files for details:'#13#10 +
          ExpandConstant('{app}\install.log') + #13#10#13#10 +
          'Try: Run as administrator, disable antivirus, or contact support.',
          mbError, MB_OK);
    end;
  end;
end;

function ClickCancelButton: Boolean;
var
  SL: TStringList;
  PID, PIDFile: String;
  ResultCode: Integer;
begin
  Result := False;

  if MsgBox('Are you sure you want to cancel the installation?'#13#10#13#10 +
    'The installation will be incomplete and you may need to run it again.',
    mbConfirmation, MB_YESNO) = IDNO then
    Exit;

  PIDFile := ExpandConstant('{app}\install.pid');
  if FileExists(PIDFile) then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile(PIDFile);
      if SL.Count > 0 then
      begin
        PID := Trim(SL[0]);
        Exec('cmd.exe', '/c taskkill /pid ' + PID + ' /f /t', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      end;
    finally
      SL.Free;
    end;
  end;

  CancelRequested := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  IPFile, ServerIP, Msg: String;
  SL: TStringList;
begin
  if CurStep = ssPostInstall then
  begin
    if InstallPrepared then
      RunInstallScript;

    if InstallExitCode <> 0 then
      Exit;

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
    Exec('wscript.exe', '"' + ExpandConstant('{app}\Launcher.vbs') + '"',
      ExpandConstant('{app}'), SW_SHOW, ewNoWait, ResultCode);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  ComposeFile: String;
  CleanupScript: String;
  SL: TStringList;
begin
  if CurUninstallStep = usUninstall then
  begin
    if MsgBox('Remove all LawnHive Workspace data?' + #13#10 + #13#10 +
      'This will permanently delete:' + #13#10 +
      '  - All workspace containers and settings' + #13#10 +
      '  - All database data (employees, records, files)' + #13#10 +
      '  - All backups' + #13#10 + #13#10 +
      'This cannot be undone. Continue?',
      mbConfirmation, MB_YESNO) = IDYES then
    begin
      ComposeFile := ExpandConstant('{app}\docker-compose.yml');

      if FileExists(ComposeFile) then
      begin
        { Step 1: Stop and remove containers + networks + volumes }
        CleanupScript := ExpandConstant('{tmp}\lawnhive-docker-cleanup.ps1');
        SL := TStringList.Create;
        try
          SL.Add('# Auto-generated cleanup script');
          SL.Add('$ErrorActionPreference = ''Continue''');
          SL.Add('');
          SL.Add('# Stop and remove containers, networks');
          SL.Add('docker compose -f "' + ComposeFile + '" down --remove-orphans 2>$null');
          SL.Add('');
          SL.Add('# Remove named volumes');
          SL.Add('docker volume rm lawnhiveworkspace_frappe_sites 2>$null');
          SL.Add('docker volume rm lawnhiveworkspace_frappe_backups 2>$null');
          SL.Add('docker volume rm lawnhiveworkspace_mariadb_data 2>$null');
          SL.Add('docker volume rm lawnhiveworkspace_redis_data 2>$null');
          SL.Add('docker volume rm lawnhiveworkspace_frappe_logs 2>$null');
          SL.Add('');
          SL.Add('# Also try volume names without prefix (older installs)');
          SL.Add('docker volume rm frappe_sites 2>$null');
          SL.Add('docker volume rm frappe_backups 2>$null');
          SL.Add('docker volume rm mariadb_data 2>$null');
          SL.Add('docker volume rm redis_data 2>$null');
          SL.Add('docker volume rm frappe_logs 2>$null');
          SL.Add('');
          SL.Add('# Remove lawnHive-branded images');
          SL.Add('docker rmi faisalabdullahabir/workspace:latest 2>$null');
          SL.SaveToFile(CleanupScript);
        finally
          SL.Free;
        end;

        Exec('powershell.exe',
          '-NoProfile -ExecutionPolicy Bypass -File "' + CleanupScript + '"',
          '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

        DeleteFile(CleanupScript);

        if ResultCode <> 0 then
        begin
          MsgBox('Warning: Some Docker resources could not be removed.' + #13#10 +
            'You may need to manually remove them:' + #13#10 + #13#10 +
            '  docker volume rm lawnhiveworkspace_frappe_sites' + #13#10 +
            '  docker volume rm lawnhiveworkspace_mariadb_data' + #13#10 +
            '  docker volume rm lawnhiveworkspace_redis_data' + #13#10 +
            '  docker volume rm lawnhiveworkspace_frappe_backups' + #13#10 +
            '  docker volume rm lawnhiveworkspace_frappe_logs',
            mbInformation, MB_OK);
        end;
      end;
    end;
  end;
end;

procedure DeinitializeSetup;
var
  ResultCode: Integer;
  ResumeLnk: String;
begin
  if not NeedsRestart then
  begin
    DeleteFile(ExpandConstant('{app}\install.ps1'));
    DeleteFile(ExpandConstant('{app}\install-progress.txt'));
    DeleteFile(ExpandConstant('{app}\install-progress-done.txt'));
    DeleteFile(ExpandConstant('{app}\install.pid'));
    DeleteFile(ExpandConstant('{app}\force-internet.txt'));
    DeleteFile(ExpandConstant('{app}\lawnhive-debug.txt'));

    ResumeLnk := ExpandConstant('{autodesktop}\Resume LawnHive Installation.lnk');
    if FileExists(ResumeLnk) then
      DeleteFile(ResumeLnk);
  end;

  if NeedsRestart then
  begin
    Exec('shutdown.exe', '/r /t 5 /c "LawnHive Workspace setup will continue after restart"',
      '', SW_HIDE, ewNoWait, ResultCode);
  end;
end;
