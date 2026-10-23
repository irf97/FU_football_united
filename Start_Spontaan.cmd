@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0fu\local-mobile.ps1" %*
if errorlevel 1 echo Spontaan could not start. See the message above.
pause
