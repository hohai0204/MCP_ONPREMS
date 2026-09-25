@echo off
REM Double-click launcher for setup.ps1 (bypasses PowerShell execution policy
REM for this one run only). Uses the folder this .bat lives in.
REM Extra arguments are forwarded, e.g. setup.bat -NoVcRedist -SkipVerify
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
echo.
pause
