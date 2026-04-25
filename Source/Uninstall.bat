@echo off

schtasks /Delete /TN "ComputedLife_Daemon" /F

powershell -Command "Get-Process powershell | Where-Object {$_.CommandLine -like '*ComputedLife*'} | Stop-Process -Force -ErrorAction SilentlyContinue"

pause