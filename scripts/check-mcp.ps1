<#
.SYNOPSIS
    Layered health check for the SAP MCP-RFC bridge: is the MCP server actually
    working, end to end?

    powershell -ExecutionPolicy Bypass -File .\scripts\check-mcp.ps1
    .\scripts\check-mcp.ps1 -Profile s4d-360      # one profile only
    .\scripts\check-mcp.ps1 -SkipSap              # local layers only, no SAP logon
    .\scripts\check-mcp.ps1 -Json                 # machine-readable summary

    Layers, cheapest first:
      1. Python interpreter
      2. Python deps          (mcp, dotenv, pyrfc import)
      3. NW RFC SDK           (bundled DLL + VC++ runtime, SAP Note 2573790)
      4. Config               (.env / profiles/*.env keys, write gate)
      5. MCP handshake        (initialize + tools/list over stdio)
      6. SAP round-trip       (tools/call sap_ping through MCP)
      7. Client registration  (claude mcp list)

    Read-only: no SAP object is written, no config is modified. Exit code 0 when
    no layer FAILed, 1 otherwise.
#>
[CmdletBinding()]
param(
    # Restrict checks to a single profile name (default: every mcp/profiles/*.env).
    # Not named -Profile: that would shadow PowerShell's automatic $PROFILE.
    [Alias("Profile")]
    [string]$ProfileName,
    # Skip layers 6 (SAP logon) — useful when offline or off-VPN.
    [switch]$SkipSap,
    # Emit JSON instead of the human-readable table.
    [switch]$Json,
    # Per-request timeout for the MCP probe, in seconds.
    [int]$TimeoutSec = 60
)

$ErrorActionPreference = "Continue"
$Root  = Split-Path -Parent $PSScriptRoot
$McpDir = Join-Path $Root "mcp"
$Probe  = Join-Path $PSScriptRoot "mcp_probe.py"

$Results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param(
        [string]$Layer,
        [ValidateSet("PASS", "WARN", "FAIL", "SKIP")][string]$Status,
        [string]$Detail
    )
    $Results.Add([pscustomobject]@{ layer = $Layer; status = $Status; detail = $Detail })
    if (-not $Json) {
        $color = switch ($Status) {
            "PASS" { "Green" } "WARN" { "Yellow" } "FAIL" { "Red" } default { "DarkGray" }
        }
        Write-Host ("{0,-22} {1,-5} {2}" -f $Layer, $Status, $Detail) -ForegroundColor $color
    }
}

if (-not $Json) {
    Write-Host "=== MCP bridge check ===" -ForegroundColor Cyan
    Write-Host "Project: $Root`n"
}

# --- 1. Python --------------------------------------------------------------
function Resolve-PythonExe {
    foreach ($exe in @("python", "python3")) {
        if (Get-Command $exe -ErrorAction SilentlyContinue) {
            $p = (& $exe -c "import sys;print(sys.executable)" 2>$null)
            if ($LASTEXITCODE -eq 0 -and $p) { return $p.Trim() }
        }
    }
    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        $p = (& py -3 -c "import sys;print(sys.executable)" 2>$null)
        if ($LASTEXITCODE -eq 0 -and $p) { return $p.Trim() }
    }
    return $null
}

$PyExe = Resolve-PythonExe
if (-not $PyExe) {
    Add-Result "1 Python" "FAIL" "no interpreter found - install Python 3.8-3.12, then run setup.ps1"
    if ($Json) { $Results | ConvertTo-Json -Depth 4 }
    exit 1
}
$PyVer = (& $PyExe -c "import sys;print('%d.%d.%d'%sys.version_info[:3])").Trim()
Add-Result "1 Python" "PASS" "$PyVer  ($PyExe)"

# --- 2. Python deps ---------------------------------------------------------
$depDetail = @()
$depStatus = "PASS"
foreach ($mod in @("mcp", "dotenv")) {
    & $PyExe -c "import $mod" *> $null
    if ($LASTEXITCODE -ne 0) { $depStatus = "FAIL"; $depDetail += "$mod MISSING" } else { $depDetail += "$mod ok" }
}
# A bare `import pyrfc` cannot load _cyrfc: the SDK DLL directory is only
# registered lazily by SapClient._import_pyrfc. So test pyrfc the way the bridge
# actually does it - register the SDK first, then import Connection. Anything
# else reports a false FAIL (or a PASS with a scary DLL message attached).
$pyrfcProbe = @"
import sys
sys.path.insert(0, r'$McpDir')
from sap.config import resolve_nwrfc_home
from sap.connection import _register_sdk_dlls
_register_sdk_dlls(resolve_nwrfc_home())
from pyrfc import Connection
import pyrfc
print(pyrfc.__version__)
"@
$pyrfcOut = (& $PyExe -c $pyrfcProbe 2>&1 | Select-Object -Last 1)
if ($LASTEXITCODE -eq 0) {
    $depDetail += "pyrfc $($pyrfcOut.ToString().Trim()) (Connection loadable)"
} else {
    $depStatus = "FAIL"
    $depDetail += "pyrfc Connection import FAILED: $($pyrfcOut.ToString().Trim())"
}
Add-Result "2 Python deps" $depStatus ($depDetail -join ", ")

# --- 3. NW RFC SDK + VC++ runtime ------------------------------------------
$sdkHome = if ($env:SAPNWRFC_HOME) { $env:SAPNWRFC_HOME } else { Join-Path $McpDir "vendor\nwrfcsdk" }
$sdkDll  = Join-Path $sdkHome "lib\sapnwrfc.dll"
$vcDll   = Join-Path $env:SystemRoot "System32\vcruntime140.dll"
if (Test-Path $sdkDll) {
    # findstr on a DLL yields a binary-noise line; keep only a short readable slice.
    $patch = (& findstr /C:"Patch" $sdkDll 2>$null | Select-Object -First 1)
    $sdkNote = "sapnwrfc.dll found"
    if ($patch) {
        $slice = ($patch -replace '[^\x20-\x7E]', ' ') -replace '\s+', ' '
        if ($slice.Length -gt 60) { $slice = $slice.Substring(0, 60) }
        $sdkNote += " ($($slice.Trim()))"
    }
    if (Test-Path $vcDll) {
        Add-Result "3 NW RFC SDK" "PASS" "$sdkNote; vcruntime140.dll present"
    } else {
        Add-Result "3 NW RFC SDK" "WARN" "$sdkNote; vcruntime140.dll MISSING - install VC++ 2015-2022 x64 (SAP Note 2573790)"
    }
} else {
    Add-Result "3 NW RFC SDK" "FAIL" "sapnwrfc.dll not found under $sdkHome - set SAPNWRFC_HOME or restore mcp/vendor/nwrfcsdk"
}

# --- 4. Config / profiles ---------------------------------------------------
$profileFiles = @()
$profileDir = Join-Path $McpDir "profiles"
if (Test-Path $profileDir) {
    $profileFiles = Get-ChildItem -Path $profileDir -Filter "*.env" -File |
                    Where-Object { $_.Name -notlike "*.example" }
}
if ($ProfileName) {
    $profileFiles = $profileFiles | Where-Object { $_.BaseName -eq $ProfileName }
    if (-not $profileFiles) {
        Add-Result "4 Config" "FAIL" "profile '$ProfileName' not found in mcp/profiles/"
    }
}

$Targets = [System.Collections.Generic.List[string]]::new()
if ($profileFiles) {
    foreach ($f in $profileFiles) {
        # Read keys only - never echo credential VALUES.
        $keys = @{}
        foreach ($line in Get-Content $f.FullName) {
            if ($line -match '^\s*([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$') { $keys[$Matches[1]] = $Matches[2].Trim() }
        }
        $missing = @("SAP_USER", "SAP_PASSWD", "SAP_CLIENT", "SAP_ASHOST") | Where-Object { -not $keys[$_] }
        $write = if ($keys["SAP_ALLOW_WRITE"] -eq "true") { "WRITE ENABLED" } else { "read-only" }
        if ($missing) {
            Add-Result "4 Config [$($f.BaseName)]" "FAIL" "missing/empty: $($missing -join ', ')"
        } else {
            Add-Result "4 Config [$($f.BaseName)]" "PASS" "logon keys complete, $write"
        }
        $Targets.Add($f.BaseName)
    }
} elseif (-not $ProfileName) {
    $baseEnv = Join-Path $McpDir ".env"
    if (Test-Path $baseEnv) {
        Add-Result "4 Config" "WARN" "no profiles/*.env - falling back to base mcp/.env (single-system mode)"
        $Targets.Add("")   # empty = no --profile arg
    } else {
        Add-Result "4 Config" "FAIL" "neither mcp/.env nor mcp/profiles/*.env exists - copy from .env.example"
    }
}

# --- 5/6. MCP handshake + SAP round-trip -----------------------------------
if (-not (Test-Path $Probe)) {
    Add-Result "5 MCP handshake" "FAIL" "probe script missing: $Probe"
} elseif ($Targets.Count -eq 0) {
    Add-Result "5 MCP handshake" "SKIP" "no usable config to start the server with"
} else {
    foreach ($t in $Targets) {
        $label = if ($t) { $t } else { "default" }
        $argv = @($Probe, "--json", "--timeout", $TimeoutSec)
        if ($t) { $argv += @("--profile", $t) }
        if (-not $SkipSap) { $argv += @("--call", "sap_ping") }

        $raw = (& $PyExe @argv 2>&1) -join "`n"
        $ok = ($LASTEXITCODE -eq 0)
        $rep = $null
        try { $rep = $raw | ConvertFrom-Json } catch { }

        if ($rep -and $rep.tool_count) {
            Add-Result "5 MCP [$label]" "PASS" "$($rep.server_name) / protocol $($rep.protocol) / $($rep.tool_count) tools"
        } else {
            $why = if ($rep -and $rep.error) { $rep.error } else { $raw }
            Add-Result "5 MCP [$label]" "FAIL" ($why -replace "\s+", " ")
            continue
        }

        if ($SkipSap) {
            Add-Result "6 SAP ping [$label]" "SKIP" "-SkipSap given"
        } elseif ($ok -and $rep.call -and -not $rep.call.isError) {
            $summary = ($rep.call.text -replace "\s+", " ")
            if ($summary.Length -gt 220) { $summary = $summary.Substring(0, 220) + " ..." }
            Add-Result "6 SAP ping [$label]" "PASS" $summary
        } else {
            $why = if ($rep.error) { $rep.error } elseif ($rep.call) { $rep.call.text } else { $raw }
            Add-Result "6 SAP ping [$label]" "FAIL" ($why -replace "\s+", " ")
        }
    }
}

# --- 7. Client registration -------------------------------------------------
if (Get-Command claude -ErrorAction SilentlyContinue) {
    $list = (& claude mcp list 2>&1) -join "`n"
    $sapLines = ($list -split "`n" | Where-Object { $_ -match "sap" }) -join " | "
    if ($sapLines) {
        # 'Pending approval' counts as not-usable, same as a failed connection.
        $status = if ($sapLines -match "(?i)fail|error|pending|needs auth|✗") { "WARN" } else { "PASS" }
        Add-Result "7 Registration" $status ($sapLines -replace "\s+", " ")
    } else {
        Add-Result "7 Registration" "WARN" "no sap-* server registered for this project - run setup.ps1 or 'claude mcp add'"
    }
} else {
    Add-Result "7 Registration" "SKIP" "'claude' CLI not on PATH"
}

# --- verdict ----------------------------------------------------------------
$failed = @($Results | Where-Object { $_.status -eq "FAIL" })
$warned = @($Results | Where-Object { $_.status -eq "WARN" })

if ($Json) {
    [pscustomobject]@{
        project  = $Root
        python   = $PyExe
        profiles = $Targets
        layers   = $Results
        verdict  = if ($failed.Count) { "FAIL" } elseif ($warned.Count) { "WARN" } else { "PASS" }
    } | ConvertTo-Json -Depth 5
} else {
    Write-Host ""
    if ($failed.Count) {
        Write-Host "Overall: FAIL - $($failed.Count) layer(s) broken; first: $($failed[0].layer)" -ForegroundColor Red
    } elseif ($warned.Count) {
        Write-Host "Overall: WARN - MCP works, $($warned.Count) advisory finding(s)" -ForegroundColor Yellow
    } else {
        Write-Host "Overall: PASS - MCP server reachable and answering SAP calls" -ForegroundColor Green
    }
}

if ($failed.Count) { exit 1 } else { exit 0 }
