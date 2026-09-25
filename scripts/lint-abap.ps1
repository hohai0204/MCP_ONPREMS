# lint-abap.ps1 - offline ABAP static analysis via abaplint (no SAP connection).
# Validation ladder step 0 (docs/product/spec-to-abap-workflow.md).
#
# Usage:
#   .\scripts\lint-abap.ps1                      # lint the whole abap/ folder
#   .\scripts\lint-abap.ps1 path\to\source.abap  # lint one file (any name)
#   .\scripts\lint-abap.ps1 file.abap -Kind fugr # treat as function-group source
#
# abaplint expects abapGit-style names (zfoo.prog.abap). Single files are
# copied into a temp workspace with a conforming name before linting.
param(
    [string]$Path = "",
    [ValidateSet("prog", "fugr", "clas", "intf")]
    [string]$Kind = "prog"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Warning "Node.js not found - abaplint step skipped. Install Node.js to enable offline linting."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Path)) {
    # Whole-repo mode: abaplint.jsonc already targets /abap/**/*.abap,
    # but those files lack abapGit-style names, so stage them as .prog.abap.
    $targets = Get-ChildItem -Path (Join-Path $Root "abap") -Filter *.abap -Recurse
} else {
    if (-not (Test-Path $Path)) { Write-Error "File not found: $Path"; exit 1 }
    $targets = @(Get-Item $Path)
}

$work = Join-Path $env:TEMP ("abaplint-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$workAbap = Join-Path $work "abap"
New-Item -ItemType Directory -Path $workAbap -Force | Out-Null

foreach ($f in $targets) {
    $base = [IO.Path]::GetFileNameWithoutExtension($f.Name).ToLower()
    if ($base -notmatch "\.(prog|fugr|clas|intf)$") { $base = "$base.$Kind" }
    Copy-Item $f.FullName (Join-Path $workAbap "$base.abap")
}

$cfg = Get-Content (Join-Path $Root "abaplint.jsonc") -Raw
Set-Content -Path (Join-Path $work "abaplint.jsonc") -Value $cfg -Encoding utf8

Push-Location $work
try {
    npx --yes @abaplint/cli abaplint.jsonc
    $code = $LASTEXITCODE
} finally {
    Pop-Location
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

if ($code -eq 0) { Write-Host "abaplint: PASS" } else { Write-Host "abaplint: FINDINGS (exit $code)" }
exit $code
