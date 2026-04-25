Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

currentDir = fso.GetParentFolderName(WScript.ScriptFullName)
WshShell.CurrentDirectory = currentDir

ps1Path = currentDir & "\ComputedLife_Core.ps1"

Do
    WshShell.Run "powershell -ExecutionPolicy Bypass -File """ & ps1Path & """", 0, True
    WScript.Sleep 5000
Loop
