@echo off
REM ===========================================================================
REM  Bootstrap installer for the SAP MCP-RFC bridge.
REM
REM  Copy THIS ONE FILE to a new machine and run it. It clones the repo and
REM  runs setup.ps1 (installs deps, registers the MCP server(s)).
REM
REM  Usage:
REM    bootstrap.bat                       (uses REPO / DIR set below)
REM    bootstrap.bat <git-url>             (override repo URL)
REM    bootstrap.bat <git-url> <target>    (override repo URL + folder)
REM
REM  EDIT the REPO line below to your private git URL before first use.
REM ===========================================================================
setlocal

set "REPO=https://github.com/ChinhHN-DEV/MCP_SAP_PRIVATE.git"
set "DIR=%USERPROFILE%\MCP_SAP_PRIVATE"

if not "%~1"=="" set "REPO=%~1"
if not "%~2"=="" set "DIR=%~2"

echo === SAP MCP-RFC bridge bootstrap ===
echo Repo:   %REPO%
echo Target: %DIR%
echo.

where git >nul 2>nul
if errorlevel 1 (
    echo [FAIL] Git is not installed. Get it from https://git-scm.com/download/win
    pause
    exit /b 1
)

if exist "%DIR%\.git" (
    echo Updating existing clone ...
    git -C "%DIR%" pull --ff-only
) else (
    echo Cloning ...
    git clone "%REPO%" "%DIR%"
    if errorlevel 1 (
        echo [FAIL] git clone failed. Check the URL / your access rights.
        pause
        exit /b 1
    )
)

if not exist "%DIR%\setup.ps1" (
    echo [FAIL] setup.ps1 not found in %DIR% - is the REPO URL correct?
    pause
    exit /b 1
)

echo.
echo Running setup ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%\setup.ps1"

echo.
pause
