' LawnHive Workspace - Employee Launcher
' Reads server address and opens browser

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

installDir = WshShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\LawnHive Workspace"
configFile = installDir & "\server.conf"
url = ""

' Read saved server address
If fso.FileExists(configFile) Then
    Set f = fso.OpenTextFile(configFile, 1)
    If Not f.AtEndOfStream Then
        url = Trim(f.ReadLine)
    End If
    f.Close
End If

' Fallback: try localhost
If url = "" Then
    url = "http://localhost:8000"
Else
    url = "http://" & url
End If

' Quick health check before opening
ready = False
On Error Resume Next
Set http = CreateObject("MSXML2.XMLHTTP")
http.Open "GET", url, False
http.Timeout = 3000
http.Send
If Err.Number = 0 And (http.Status = 200 Or http.Status = 301 Or http.Status = 302) Then
    ready = True
End If
On Error GoTo 0

If ready Then
    WshShell.Run url
Else
    ' Server might be starting up, try anyway
    WshShell.Run url
End If
