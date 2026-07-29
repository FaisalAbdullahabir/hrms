' LawnHive Workspace - Robust Launcher
' Ensures Docker is running, starts containers, opens browser
' Shows visible error messages on failure (never silent)

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

installDir = fso.GetParentFolderName(WScript.ScriptFullName)
composeFile = installDir & "\docker-compose.yml"
url = "http://localhost:8000"

' ============================================================
' Helper: Run a command and return its output
' ============================================================
Function RunCmd(cmd)
    On Error Resume Next
    Dim objExec
    Set objExec = WshShell.Exec("cmd /c " & cmd)
    Dim output
    output = ""
    If Not objExec Is Nothing Then
        ' Wait up to 10 seconds for output
        Dim waitCount
        waitCount = 0
        Do While objExec.Status = 0 And waitCount < 20
            WScript.Sleep 500
            waitCount = waitCount + 1
        Loop
        If objExec.Status = 1 Then
            output = objExec.StdOut.ReadAll()
        End If
    End If
    On Error GoTo 0
    RunCmd = output
End Function

' ============================================================
' Helper: Check if Docker daemon is responsive
' ============================================================
Function IsDockerReady()
    Dim result
    result = RunCmd("docker info >nul 2>&1 && echo YES || echo NO")
    IsDockerReady = (InStr(result, "YES") > 0)
End Function

' ============================================================
' PHASE 1: Check if Docker is already ready
' ============================================================
dockerReady = IsDockerReady()

If dockerReady Then
    ' Docker is already running — skip straight to containers
Else
    ' ============================================================
    ' PHASE 2: Docker not ready — try to start it
    ' ============================================================
    
    ' Strategy A: Start the Windows Service (most reliable, no GUI needed)
    On Error Resume Next
    Dim svcObj
    Set svcObj = GetObject("winmgmts:\\.\root\cimv2").ExecQuery( _
        "SELECT Name,State FROM Win32_Service WHERE Name='com.docker.service'")
    If svcObj.Count > 0 Then
        Dim svcItem
        For Each svcItem In svcObj
            If svcItem.State <> "Running" Then
                WshShell.Run "cmd /c net start ""com.docker.service""", 0, True
            End If
        Next
    End If
    On Error GoTo 0
    
    ' Wait up to 30s for service-based start
    waited = 0
    Do While Not dockerReady And waited < 30
        WScript.Sleep 5000
        waited = waited + 5
        dockerReady = IsDockerReady()
    Loop
    
    ' Strategy B: If service didn't work, find and launch Docker Desktop GUI
    If Not dockerReady Then
        dockerExe = ""
        
        ' Try registry paths
        On Error Resume Next
        Dim regPath1, regPath2, regPath3
        regPath1 = WshShell.RegRead("HKLM\SOFTWARE\Docker Inc.\Docker Desktop\InstallPath")
        If Err.Number = 0 And regPath1 <> "" Then
            If fso.FileExists(regPath1 & "\Docker Desktop.exe") Then
                dockerExe = regPath1 & "\Docker Desktop.exe"
            End If
        End If
        Err.Clear
        
        If dockerExe = "" Then
            regPath2 = WshShell.RegRead("HKLM\SOFTWARE\WOW6432Node\Docker Inc.\Docker Desktop\InstallPath")
            If Err.Number = 0 And regPath2 <> "" Then
                If fso.FileExists(regPath2 & "\Docker Desktop.exe") Then
                    dockerExe = regPath2 & "\Docker Desktop.exe"
                End If
            End If
            Err.Clear
        End If
        
        If dockerExe = "" Then
            regPath3 = WshShell.RegRead("HKCU\SOFTWARE\Docker Inc.\Docker Desktop\InstallPath")
            If Err.Number = 0 And regPath3 <> "" Then
                If fso.FileExists(regPath3 & "\Docker Desktop.exe") Then
                    dockerExe = regPath3 & "\Docker Desktop.exe"
                End If
            End If
            Err.Clear
        End If
        On Error GoTo 0
        
        ' Try known paths if registry didn't work
        If dockerExe = "" Then
            If fso.FileExists("C:\Program Files\Docker\Docker\Docker Desktop.exe") Then
                dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
            ElseIf fso.FileExists(WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Docker\app\version\bin\Docker Desktop.exe") Then
                dockerExe = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Docker\app\version\bin\Docker Desktop.exe"
            End If
        End If
        
        If dockerExe <> "" Then
            WshShell.Run """" & dockerExe & """", 1, False
        Else
            ' Last resort: try PowerShell app registration
            On Error Resume Next
            WshShell.Run "powershell.exe -NoProfile -Command ""Start-Process 'Docker Desktop' -WindowStyle Minimized""", 0, False
            On Error GoTo 0
        End If
        
        ' Wait for daemon to become ready (check docker info)
        waited = 0
        Do While Not dockerReady And waited < 120
            WScript.Sleep 5000
            waited = waited + 5
            dockerReady = IsDockerReady()
        Loop
    End If
End If

' ============================================================
' PHASE 3: Start containers if Docker is ready
' ============================================================
containersStarted = False
If dockerReady Then
    If fso.FileExists(composeFile) Then
        WshShell.CurrentDirectory = installDir
        WshShell.Run "cmd /c docker compose up -d", 0, True
        containersStarted = True
    End If
Else
    ' Docker never started — show error and exit
    MsgBox "LawnHive Workspace could not start because Docker Desktop is not running." & vbCrLf & vbCrLf & _
        "To fix this:" & vbCrLf & _
        "1. Press the Windows key and type 'Docker Desktop'" & vbCrLf & _
        "2. Click on Docker Desktop to open it" & vbCrLf & _
        "3. Wait 1-2 minutes for the whale icon to appear in the taskbar" & vbCrLf & _
        "4. Then double-click the LawnHive Workspace icon again" & vbCrLf & vbCrLf & _
        "If Docker Desktop won't open, restart your computer and try again.", _
        vbExclamation, "LawnHive Workspace"
    WshShell.Run url
    WScript.Quit
End If

' ============================================================
' PHASE 4: Wait for web server
' ============================================================
webReady = False
waited = 0
Do While Not webReady And waited < 180
    WScript.Sleep 3000
    waited = waited + 3
    On Error Resume Next
    Set http = CreateObject("MSXML2.XMLHTTP")
    http.Open "GET", url, False
    http.Send
    If Err.Number = 0 And (http.Status = 200 Or http.Status = 302) Then
        webReady = True
    End If
    On Error GoTo 0
Loop

' ============================================================
' PHASE 5: Open browser or show error
' ============================================================
If webReady Then
    WshShell.Run url
Else
    If Not containersStarted Then
        MsgBox "Docker is running but the workspace containers could not start." & vbCrLf & vbCrLf & _
            "Try restarting your computer and double-clicking the icon again.", _
            vbExclamation, "LawnHive Workspace"
    Else
        MsgBox "The workspace is still loading. This can take 2-3 minutes on first start." & vbCrLf & vbCrLf & _
            "Please wait a few minutes, then double-click the LawnHive Workspace icon again." & vbCrLf & _
            "If this keeps happening, restart your computer.", _
            vbInformation, "LawnHive Workspace"
    End If
    WshShell.Run url
End If
