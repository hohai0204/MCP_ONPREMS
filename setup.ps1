<#
.SYNOPSIS
    One-shot installer for the SAP MCP-RFC bridge on a new Windows machine.

    Run from anywhere inside the moved/copied folder:
        powershell -ExecutionPolicy Bypass -File .\setup.ps1
    or just double-click setup.bat.

    It checks every prerequisite, installs what is missing, and verifies the
    result end to end:
      0. preflight          Windows x64, PowerShell, elevation, folder layout
      1. Python             locate an interpreter, gate the version
      2. VC++ runtime       download+install vc_redist.x64.exe if absent
      3. Python deps        python-dotenv + mcp
      4. pyrfc              matching wheel from vendor/, else download
      5. NW RFC SDK         all required DLLs present
      6. config             .env / profiles/<name>.env, report what is unfilled
      7. Harness CLI        bootstrap the durable layer (init/migrate harness.db)
      8. MCP registration   one server per profile, with THIS folder's path
      9. verification       run scripts\check-mcp.ps1

.PARAMETER NoVcRedist
    Never download or install the Visual C++ runtime; only warn when missing.

.PARAMETER SkipVerify
    Skip step 9 (the check-mcp.ps1 run). Use when offline.

.PARAMETER SkipHarness
    Skip step 7 (harness.db bootstrap). Use when you only want the MCP bridge.
#>
[CmdletBinding()]
param(
    [switch]$NoVcRedist,
    [switch]$SkipVerify,
    [switch]$SkipHarness
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Mcp  = Join-Path $Root "mcp"   # the MCP server lives here
$Warnings = [System.Collections.Generic.List[string]]::new()

function Warn($text) {
    Write-Host "[WARN] $text" -ForegroundColor Yellow
    $Warnings.Add($text)
}
function Fail($text) {
    Write-Host "[FAIL] $text" -ForegroundColor Red
    exit 1
}

Write-Host "=== SAP MCP-RFC bridge setup ===" -ForegroundColor Cyan
Write-Host "Project folder: $Root"

# --- 0. preflight -----------------------------------------------------------
Write-Host "`n[0/9] Preflight ..." -ForegroundColor Cyan

if (-not [Environment]::Is64BitOperatingSystem) {
    Fail "This bridge needs 64-bit Windows: the bundled NW RFC SDK and the pyrfc wheel are win_amd64."
}
Write-Host "Windows: $([Environment]::OSVersion.VersionString) (x64), PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green

# Elevation decides whether the VC++ runtime can be installed unattended.
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($IsAdmin) {
    Write-Host "Elevation: running as Administrator" -ForegroundColor Green
} else {
    Write-Host "Elevation: standard user (fine unless the VC++ runtime must be installed)" -ForegroundColor DarkGray
}

# Fail fast on an incomplete copy rather than deep inside a later step.
foreach ($req in @("mcp\server.py", "mcp\sap\config.py", "mcp\sap\connection.py", "mcp\sap\tools.py")) {
    if (-not (Test-Path (Join-Path $Root $req))) {
        Fail "Incomplete copy: $req is missing. Re-copy the whole folder (or git clone the repo)."
    }
}
Write-Host "Layout: mcp\server.py + sap\ package present" -ForegroundColor Green

# --- 1. locate Python (return the full interpreter path) --------------------
Write-Host "`n[1/9] Locating Python ..." -ForegroundColor Cyan
function Resolve-PythonExe {
    # Try python / python3 directly, then the 'py' launcher with -3.
    foreach ($exe in @("python", "python3")) {
        if (Get-Command $exe -ErrorAction SilentlyContinue) {
            try {
                $p = (& $exe -c "import sys;print(sys.executable)" 2>$null)
                if ($LASTEXITCODE -eq 0 -and $p) { return $p.Trim() }
            } catch { }
        }
    }
    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        try {
            $p = (& py -3 -c "import sys;print(sys.executable)" 2>$null)
            if ($LASTEXITCODE -eq 0 -and $p) { return $p.Trim() }
        } catch { }
    }
    return $null
}

$PyExe = Resolve-PythonExe
if (-not $PyExe) {
    Write-Host "[FAIL] Python not found. Install Python 3.12 (x64) and re-run:" -ForegroundColor Red
    Write-Host "       https://www.python.org/downloads/release/python-3128/" -ForegroundColor Red
    Write-Host "       Tick 'Add python.exe to PATH' in the installer." -ForegroundColor Red
    exit 1
}

# Version tag for wheel matching + architecture. $PyExe is a full path, so it is
# used consistently for pip, imports and the MCP registration below.
$PyTag = (& $PyExe -c "import sys;print('cp%d%d'%sys.version_info[:2])").Trim()
$Arch  = (& $PyExe -c "import platform;print('win_amd64' if platform.machine().endswith('64') else 'win32')").Trim()
$PyVer = (& $PyExe -c "import sys;print('%d.%d.%d'%sys.version_info[:3])").Trim()
$PyMinor = [int](& $PyExe -c "import sys;print(sys.version_info[1])").Trim()
Write-Host "Python: $PyExe  ($PyVer / $PyTag / $Arch)" -ForegroundColor Green

if ($Arch -ne "win_amd64") {
    Fail "32-bit Python ($Arch) cannot load the 64-bit NW RFC SDK. Install Python 3.12 x64."
}
# The vendored wheel is cp312. Other versions need a matching wheel from the
# SAP-archive/PyRFC releases, which does not publish one for every version.
if ($PyMinor -ne 12) {
    Warn "Python 3.$PyMinor detected; the vendored wheel is cp312. Setup will try to download a $PyTag wheel - if that fails, install Python 3.12 x64."
}

# --- 2. Visual C++ runtime (SAP Note 2573790) -------------------------------
# The NW RFC SDK DLL links against vcruntime140.dll. Without it `import pyrfc`
# dies with an opaque loader error, so install it BEFORE touching pyrfc.
Write-Host "`n[2/9] Checking Microsoft Visual C++ runtime ..." -ForegroundColor Cyan
$VcDll = Join-Path $env:SystemRoot "System32\vcruntime140.dll"
$VcDll1 = Join-Path $env:SystemRoot "System32\vcruntime140_1.dll"
if ((Test-Path $VcDll) -and (Test-Path $VcDll1)) {
    Write-Host "vcruntime140.dll + vcruntime140_1.dll present." -ForegroundColor Green
} elseif ($NoVcRedist) {
    Warn "VC++ 2015-2022 x64 runtime missing and -NoVcRedist given. pyrfc will fail to load the SDK. Install https://aka.ms/vs/17/release/vc_redist.x64.exe"
} elseif (-not $IsAdmin) {
    Warn "VC++ 2015-2022 x64 runtime missing and this shell is not elevated. Re-run setup.ps1 as Administrator, or install it manually: https://aka.ms/vs/17/release/vc_redist.x64.exe"
} else {
    $VcUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $VcExe = Join-Path $env:TEMP "vc_redist.x64.exe"
    Write-Host "Missing - downloading $VcUrl ..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $VcUrl -OutFile $VcExe -UseBasicParsing
        Write-Host "Installing (quiet, no restart) ..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $VcExe -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
        switch ($proc.ExitCode) {
            0    { Write-Host "VC++ runtime installed." -ForegroundColor Green }
            1638 { Write-Host "A newer VC++ runtime is already installed." -ForegroundColor Green }
            3010 { Warn "VC++ runtime installed but Windows wants a REBOOT before the DLLs load reliably." }
            default { Warn "vc_redist.x64.exe exited with code $($proc.ExitCode). Install it manually: $VcUrl" }
        }
    } catch {
        Warn "Could not download/install the VC++ runtime ($($_.Exception.Message)). Install manually: $VcUrl"
    }
}

# --- 3. base dependencies ---------------------------------------------------
Write-Host "`n[3/9] Installing python-dotenv + mcp ..." -ForegroundColor Cyan
& $PyExe -m pip install --disable-pip-version-check --quiet python-dotenv "mcp<2"
if ($LASTEXITCODE -ne 0) { Fail "pip install failed. Check network / proxy, then re-run." }
Write-Host "python-dotenv + mcp installed." -ForegroundColor Green

# --- 4. pyrfc wheel ---------------------------------------------------------
Write-Host "`n[4/9] Installing pyrfc ..." -ForegroundColor Cyan
try { & $PyExe -c "import pyrfc" *> $null } catch { }
$PyrfcPresent = ($LASTEXITCODE -eq 0)
# A bare `import pyrfc` also fails when only the SDK DLL path is unregistered,
# so treat "module resolvable" as the real test.
& $PyExe -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('pyrfc') else 1)" *> $null
if ($LASTEXITCODE -eq 0) { $PyrfcPresent = $true }

if ($PyrfcPresent) {
    Write-Host "pyrfc already installed - skipping." -ForegroundColor Green
} else {
    $PyrfcVer = "3.3.1"
    $Wheel = "pyrfc-$PyrfcVer-$PyTag-$PyTag-$Arch.whl"
    $VendorDir = Join-Path $Mcp "vendor"
    $WheelPath = Join-Path $VendorDir $Wheel
    if (-not (Test-Path $WheelPath)) {
        Write-Host "No matching wheel in vendor/ ($Wheel). Trying to download ..." -ForegroundColor Yellow
        if (-not (Test-Path $VendorDir)) { New-Item -ItemType Directory -Path $VendorDir | Out-Null }
        $Url = "https://github.com/SAP-archive/PyRFC/releases/download/v$PyrfcVer/$Wheel"
        try {
            Invoke-WebRequest -Uri $Url -OutFile $WheelPath -UseBasicParsing
        } catch {
            Write-Host "[FAIL] Could not get a pyrfc wheel for $PyTag/$Arch." -ForegroundColor Red
            Write-Host "       Download it manually from:" -ForegroundColor Red
            Write-Host "       https://github.com/SAP-archive/PyRFC/releases" -ForegroundColor Red
            Write-Host "       and place it in mcp\vendor\, then re-run." -ForegroundColor Red
            Write-Host "       Easiest alternative: install Python 3.12 x64 - its wheel is bundled." -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "Installing $Wheel"
    & $PyExe -m pip install --disable-pip-version-check --quiet "$WheelPath"
    if ($LASTEXITCODE -ne 0) { Fail "pyrfc install failed." }
    Write-Host "pyrfc installed." -ForegroundColor Green
}

# --- 5. SAP NW RFC SDK ------------------------------------------------------
Write-Host "`n[5/9] Checking SAP NW RFC SDK ..." -ForegroundColor Cyan
$SdkHome = if ($env:SAPNWRFC_HOME) { $env:SAPNWRFC_HOME } else { Join-Path $Mcp "vendor\nwrfcsdk" }
$SdkLibDir = Join-Path $SdkHome "lib"
# The loader needs the ICU and sapucum DLLs next to sapnwrfc.dll, not just the
# main DLL - a partial copy fails at import time, not here.
$SdkDlls = @("sapnwrfc.dll", "libsapucum.dll", "icudt57.dll", "icuin57.dll", "icuuc57.dll")
$MissingDlls = @($SdkDlls | Where-Object { -not (Test-Path (Join-Path $SdkLibDir $_)) })
if (-not (Test-Path $SdkLibDir)) {
    Warn "SDK lib folder not found: $SdkLibDir. Set SAPNWRFC_HOME to your SDK, or restore mcp\vendor\nwrfcsdk (~60 MB) from the repo."
} elseif ($MissingDlls.Count -gt 0) {
    Warn "SDK at $SdkLibDir is incomplete - missing: $($MissingDlls -join ', '). Re-copy mcp\vendor\nwrfcsdk in full."
} else {
    Write-Host "SDK complete at $SdkHome ($($SdkDlls.Count) DLLs, auto-detected at runtime)." -ForegroundColor Green
}

# Prove the whole native stack loads, exactly the way the bridge does it.
$PyrfcProbe = @"
import sys
sys.path.insert(0, r'$Mcp')
from sap.config import resolve_nwrfc_home
from sap.connection import _register_sdk_dlls
_register_sdk_dlls(resolve_nwrfc_home())
from pyrfc import Connection
import pyrfc
print(pyrfc.__version__)
"@
$ProbeOut = (& $PyExe -c $PyrfcProbe 2>&1 | Select-Object -Last 1)
if ($LASTEXITCODE -eq 0) {
    Write-Host "pyrfc $($ProbeOut.ToString().Trim()) loads the SDK successfully." -ForegroundColor Green
} else {
    Warn "pyrfc cannot load the SDK yet: $($ProbeOut.ToString().Trim()). Usual cause: VC++ runtime missing (see step 2) or an incomplete nwrfcsdk copy."
}

# --- 6. .env / profiles -----------------------------------------------------
Write-Host "`n[6/9] Configuring connection files ..." -ForegroundColor Cyan
$EnvFile = Join-Path $Mcp ".env"
$EnvExample = Join-Path $Mcp ".env.example"
$ProfilesDir = Join-Path $Mcp "profiles"
$Profiles = @()
if (Test-Path $ProfilesDir) {
    $Profiles = @(Get-ChildItem -Path $ProfilesDir -Filter *.env -File |
                  Where-Object { $_.Name -notlike "*.example" })
}

if ($Profiles.Count -gt 0) {
    Write-Host "Found $($Profiles.Count) profile(s): $(($Profiles | ForEach-Object { $_.BaseName }) -join ', ')" -ForegroundColor Green
} else {
    # No per-system profile: fall back to the single-system base .env.
    if (Test-Path $EnvFile) {
        Write-Host ".env already exists - left untouched." -ForegroundColor Green
    } elseif (Test-Path $EnvExample) {
        Copy-Item $EnvExample $EnvFile
        Write-Host ".env created from template - EDIT IT with your SAP credentials." -ForegroundColor Yellow
    } else {
        Warn ".env.example missing; cannot create .env."
    }
    $ProfileExample = Join-Path $ProfilesDir "s4d-360.env.example"
    if (Test-Path $ProfileExample) {
        Write-Host "For multi-system use: copy mcp\profiles\s4d-360.env.example to <name>.env, then re-run setup." -ForegroundColor DarkGray
    }
}

function Test-Configured($file) {
    if (-not (Test-Path $file)) { return $false }
    return ((Get-Content $file -Raw) -notmatch 'YOUR_RFC_USER')  # still template?
}

$multiSystem = ($Profiles.Count -gt 0)
if ($multiSystem) {
    $pending = @($Profiles | Where-Object { -not (Test-Configured $_.FullName) } |
                 ForEach-Object { $_.Name })
    $configOk = ($pending.Count -eq 0)
    $configText = if ($configOk) { "All profiles filled in" }
                  else { "Fill in profiles: $($pending -join ', ')" }
    $testHint = "`"$PyExe`" mcp\test_connection.py --profile <name>"
} else {
    $configOk = Test-Configured $EnvFile
    $configText = "Edit .env - SAP_USER / SAP_PASSWD / SAP_CLIENT / SAP_ASHOST / SAP_SAPROUTER"
    $testHint = "`"$PyExe`" mcp\test_connection.py"
}
if ($configOk) {
    Write-Host "Logon config looks filled in (no YOUR_RFC_USER placeholder left)." -ForegroundColor Green
} else {
    Write-Host "Logon config still has placeholders: $configText" -ForegroundColor Yellow
}

# --- 7. Harness durable layer ----------------------------------------------
Write-Host "`n[7/9] Bootstrapping the Harness durable layer ..." -ForegroundColor Cyan
$HarnessCli = Join-Path $Root "scripts\bin\harness-cli.exe"
$HarnessBootstrap = Join-Path $Root "scripts\bootstrap-harness.ps1"
if ($SkipHarness) {
    Write-Host "Skipped (-SkipHarness)." -ForegroundColor DarkGray
} elseif (-not (Test-Path $HarnessCli)) {
    # harness-cli.exe and harness.db are git-ignored, so a fresh CLONE lacks
    # them while a folder COPY carries them along.
    Warn "scripts\bin\harness-cli.exe missing (expected after a git clone, not after a folder copy). Re-install the harness to restore it - see scripts\README.md - or pass -SkipHarness if you only want the MCP bridge."
} elseif (-not (Test-Path $HarnessBootstrap)) {
    Warn "scripts\bootstrap-harness.ps1 missing; cannot initialize harness.db."
} else {
    try {
        & $HarnessBootstrap
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Harness ready (harness.db initialized/migrated)." -ForegroundColor Green
        } else {
            Warn "bootstrap-harness.ps1 exited with code $LASTEXITCODE."
        }
    } catch {
        Warn "Harness bootstrap failed: $($_.Exception.Message)"
    }
}

# --- 8. register MCP server(s) ----------------------------------------------
# Multi-system: one MCP server "sap-<name>" per profiles\<name>.env file.
# Single-system fallback: one server "sap-rfc" from the base .env.
# Registration stores ABSOLUTE paths per project directory, which is why this
# step must be re-run on every new machine even when all files were copied.
Write-Host "`n[8/9] Registering MCP server(s) with Claude Code ..." -ForegroundColor Cyan
$ServerPath = Join-Path $Mcp "server.py"
$Script:RegisteredServers = @()

if (Get-Command claude -ErrorAction SilentlyContinue) {
    if ($multiSystem) {
        foreach ($p in $Profiles) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($p.Name)
            $srv = "sap-$name"
            try { & claude mcp remove $srv *> $null } catch { }
            & claude mcp add $srv -- "$PyExe" "$ServerPath" --profile $name
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Registered: $srv (profile $name)" -ForegroundColor Green
                $Script:RegisteredServers += $srv
            } else {
                Warn "failed to register $srv"
            }
        }
    } else {
        try { & claude mcp remove sap-rfc *> $null } catch { }
        & claude mcp add sap-rfc -- "$PyExe" "$ServerPath"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Registered: sap-rfc (base .env)" -ForegroundColor Green
            $Script:RegisteredServers += "sap-rfc"
        } else {
            Warn "'claude mcp add' failed; register manually."
        }
    }
} else {
    Warn "'claude' CLI not on PATH - MCP servers NOT registered."
    Write-Host "       claude mcp add sap-rfc -- `"$PyExe`" `"$ServerPath`"" -ForegroundColor Yellow
    Write-Host "       (per system: claude mcp add sap-s4d-360 -- ... --profile s4d-360)" -ForegroundColor Yellow
}
$mcpRegistered = ($Script:RegisteredServers.Count -gt 0)
$serverList = if ($mcpRegistered) { $Script:RegisteredServers -join ", " } else { "none" }

# --- 9. end-to-end verification --------------------------------------------
Write-Host "`n[9/9] Verifying ..." -ForegroundColor Cyan
$CheckScript = Join-Path $Root "scripts\check-mcp.ps1"
$verifyRan = $false
if ($SkipVerify) {
    Write-Host "Skipped (-SkipVerify)." -ForegroundColor DarkGray
} elseif (-not (Test-Path $CheckScript)) {
    Warn "scripts\check-mcp.ps1 not found; skipping verification."
} else {
    # Without filled-in credentials the SAP logon can only fail, so stop at the
    # MCP handshake instead of reporting a misleading failure.
    if ($configOk) {
        & $CheckScript
    } else {
        Write-Host "(config incomplete - running local layers only)" -ForegroundColor DarkGray
        & $CheckScript -SkipSap
    }
    $verifyRan = $true
}

# --- done: TODO checklist ---------------------------------------------------
function Item($done, $text) {
    if ($done) { Write-Host "  [x] $text" -ForegroundColor Green }
    else       { Write-Host "  [ ] $text" -ForegroundColor Yellow }
}

Write-Host "`n=== Setup complete - TODO checklist ===" -ForegroundColor Cyan
Write-Host "Mode: $(if ($multiSystem) { "multi-system ($($Profiles.Count) profiles)" } else { 'single system' })"
Write-Host "Done by this script:" -ForegroundColor Cyan
Item $true  "Python + dependencies (python-dotenv, mcp, pyrfc)"
Item $true  "VC++ runtime + SAP NW RFC SDK checked"
Item $mcpRegistered "MCP server(s) registered with Claude Code: $serverList"
Item $verifyRan "Verification run (scripts\check-mcp.ps1)"

Write-Host "`nYou still need to:" -ForegroundColor Cyan
Item $configOk $configText
Item $false "Restart Claude Code so the tools bind (registration alone is not enough)"
Item $false "(optional) Install the ABAP helpers for screen/syntax/activate/CDS/"
Write-Host "          textpool tools - see abap\README.md, flag both FMs Remote-Enabled" -ForegroundColor Yellow
Item $false "(optional, DEV only) enable writes: SAP_ALLOW_WRITE=true (per-system)"

if ($Warnings.Count -gt 0) {
    Write-Host "`n$($Warnings.Count) warning(s) to review:" -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
}

if (-not $configOk) {
    Write-Host "`n>> Start here: fill in your SAP logon details, then re-run setup." -ForegroundColor Magenta
} elseif ($Warnings.Count -gt 0) {
    Write-Host "`n>> Review the warnings above, then re-run .\scripts\check-mcp.ps1" -ForegroundColor Magenta
} else {
    Write-Host "`n>> Ready. Restart Claude Code and the sap tools will be available." -ForegroundColor Magenta
}
