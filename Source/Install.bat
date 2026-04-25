@echo off

set "VBS_PATH=%~dp0ComputedLife_Daemon.vbs"

schtasks /Create /F /TN "ComputedLife_Daemon" /TR "cmd.exe /c start /High wscript.exe //B \"%VBS_PATH%\"" /SC ONLOGON /RL HIGHEST
powershell -Command "$t = Get-ScheduledTask -TaskName 'ComputedLife_Daemon'; $s = $t.Settings; $s.AllowStartIfOnBatteries = $true; $s.StopIfGoingOnBatteries = $false; $s.ExecutionTimeLimit = 'PT0S'; $s.DisallowStartIfOnBatteries = $false; $s.StartWhenAvailable = $true; $s.Priority = 1; Set-ScheduledTask -InputObject $t" >nul 2>&1

pause