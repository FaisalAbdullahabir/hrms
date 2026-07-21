' LawnHive Workspace - Launcher
' Silently ensures Docker containers are running, then opens browser

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

installDir = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\LawnHive Workspace"
composeFile = installDir & "\docker-compose.yml"

' Check if Docker Desktop is running
dockerRunning = False
On Error Resume Next
Set colServices = GetObject("winmgmts:\\.\root\cimv2").ExecQuery( _
    "SELECT Name FROM Win32_Service WHERE Name = 'com.docker.service'")
If colServices.Count > 0 Then
    dockerRunning = True
End If
On Error GoTo 0

If Not dockerRunning Then
    ' Try to start Docker Desktop
    dockerExe = ""
    If fso.FileExists("C:\Program Files\Docker\Docker\Docker Desktop.exe") Then
        dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    ElseIf fso.FileExists(WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Docker\app\version\bin\Docker Desktop.exe") Then
        dockerExe = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Docker\app\version\bin\Docker Desktop.exe"
    End If
    
    If dockerExe <> "" Then
        WshShell.Run """" & dockerExe & """", 1, False
        
        ' Wait for Docker Desktop to be ready (check every 5s, max 120s)
        waited = 0
        Do While waited < 120
            WScript.Sleep 5000
            waited = waited + 5
            Set colServices2 = GetObject("winmgmts:\\.\root\cimv2").ExecQuery( _
                "SELECT Name FROM Win32_Service WHERE Name = 'com.docker.service'")
            If colServices2.Count > 0 Then
                dockerRunning = True
                Exit Do
            End If
        Loop
    End If
End If

' Ensure containers are running via docker compose
If fso.FileExists(composeFile) Then
    WshShell.CurrentDirectory = installDir
    WshShell.Run "cmd /c docker compose up -d", 0, True
End If

' Wait for the web server to respond
url = "http://localhost:8000"
ready = False
waited = 0
Do While Not ready And waited < 180
    WScript.Sleep 3000
    waited = waited + 3
    On Error Resume Next
    Set http = CreateObject("MSXML2.XMLHTTP")
    http.Open "GET", url, False
    http.Send
    If Err.Number = 0 And http.Status = 200 Then
        ready = True
    End If
    On Error GoTo 0
Loop

' Open browser
If ready Then
    WshShell.Run url
Else
    ' Still try opening browser even if not fully ready
    WshShell.Run url
End If
