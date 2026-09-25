#!/usr/bin/env bash
# One-shot installer for the SAP MCP-RFC bridge on macOS (Apple Silicon or Intel).
# macOS counterpart of setup.ps1 (Windows). Safe to re-run.
#
#   ./setup.sh                     # normal run
#   ./setup.sh --sdk ~/nwrfcsdk    # SAP NW RFC SDK lives elsewhere
#   ./setup.sh --python python3.12 # pick the interpreter used to build the venv
#   ./setup.sh --skip-verify       # offline: skip the MCP handshake check
#   ./setup.sh --skip-harness      # only the MCP bridge, no harness.db
#
# Steps (same numbering as setup.ps1, macOS-specific where noted):
#   0 preflight        macOS + layout
#   1 Python           pick 3.10-3.13 (3.12 preferred), create .venv
#   2 build tools      Xcode Command Line Tools (pyrfc is compiled from source)
#   3 Python deps      python-dotenv + mcp into .venv
#   4 NW RFC SDK       locate the macOS SDK, strip quarantine, fix dylib install names
#   5 pyrfc            build against the SDK, make sure it can find the dylibs
#   6 config           .env / profiles/<name>.env
#   7 Harness CLI      init/migrate harness.db (needs a macOS harness-cli)
#   8 MCP registration one `claude mcp add` per profile, with THIS folder's path
#   9 verification     scripts/mcp_probe.py (MCP handshake + sap_ping)
#
# Unlike Windows, the SAP NW RFC SDK for macOS is NOT bundled (SAP license, and
# the repo only carries the Windows build). Download "SAP NW RFC SDK 7.50 for
# MACOS on ARM64 / X86_64" from the SAP Software Center (S-user needed),
# extract it with SAPCAR and put it in mcp/vendor/nwrfcsdk-macos (or set
# SAPNWRFC_HOME).

set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP="$ROOT/mcp"
VENV="$ROOT/.venv"

SKIP_VERIFY=0
SKIP_HARNESS=0
PY_REQUEST=""
SDK_REQUEST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-verify)  SKIP_VERIFY=1 ;;
    --skip-harness) SKIP_HARNESS=1 ;;
    --python)       shift; PY_REQUEST="${1:-}" ;;
    --sdk)          shift; SDK_REQUEST="${1:-}" ;;
    -h|--help)      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

WARNINGS=()
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_CYN=$'\033[36m'
  C_MAG=$'\033[35m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_MAG=""; C_DIM=""; C_OFF=""
fi

step()  { printf '\n%s[%s] %s%s\n' "$C_CYN" "$1" "$2" "$C_OFF"; }
ok()    { printf '%s%s%s\n' "$C_GRN" "$1" "$C_OFF"; }
info()  { printf '%s%s%s\n' "$C_DIM" "$1" "$C_OFF"; }
warn()  { printf '%s[WARN] %s%s\n' "$C_YEL" "$1" "$C_OFF"; WARNINGS+=("$1"); }
fail()  { printf '%s[FAIL] %s%s\n' "$C_RED" "$1" "$C_OFF" >&2; exit 1; }
item()  { # item <done 0/1> <text>
  if [ "$1" = "1" ]; then printf '  %s[x] %s%s\n' "$C_GRN" "$2" "$C_OFF"
  else printf '  %s[ ] %s%s\n' "$C_YEL" "$2" "$C_OFF"; fi
}

printf '%s=== SAP MCP-RFC bridge setup (macOS) ===%s\n' "$C_CYN" "$C_OFF"
echo "Project folder: $ROOT"

# --- 0. preflight ------------------------------------------------------------
step "0/9" "Preflight ..."
[ "$(uname -s)" = "Darwin" ] || fail "This script is for macOS. On Windows run setup.ps1."
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ok "macOS $(sw_vers -productVersion) ($ARCH)" ;;
  *) fail "Unsupported CPU architecture: $ARCH" ;;
esac
for req in mcp/server.py mcp/sap/config.py mcp/sap/connection.py mcp/sap/tools.py; do
  [ -f "$ROOT/$req" ] || fail "Incomplete copy: $req is missing. Re-copy the whole folder (or git clone the repo)."
done
ok "Layout: mcp/server.py + sap/ package present"

# --- 1. Python + venv ---------------------------------------------------------
# Homebrew / python.org Pythons are "externally managed" (PEP 668), so a plain
# `pip install` is refused. Everything goes into a project-local .venv instead.
step "1/9" "Locating Python ..."
py_ok() { # py_ok <exe> -> 0 when it is a usable 3.10-3.13
  "$1" -c 'import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,13) else 1)' >/dev/null 2>&1
}
BASE_PY=""
if [ -n "$PY_REQUEST" ]; then
  command -v "$PY_REQUEST" >/dev/null 2>&1 || fail "--python $PY_REQUEST not found."
  BASE_PY="$(command -v "$PY_REQUEST")"
else
  for cand in python3.12 python3.13 python3.11 python3.10 python3 python; do
    p="$(command -v "$cand" 2>/dev/null)" || continue
    if py_ok "$p"; then BASE_PY="$p"; break; fi
  done
fi
if [ -z "$BASE_PY" ]; then
  echo "${C_RED}[FAIL] No Python 3.10-3.13 found.${C_OFF}" >&2
  echo "       Install one and re-run:  brew install python@3.12" >&2
  exit 1
fi
BASE_PY="$("$BASE_PY" -c 'import sys;print(sys.executable)')"
PY_VER="$("$BASE_PY" -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])')"
PY_MINOR="$("$BASE_PY" -c 'import sys;print(sys.version_info[1])')"
ok "Python: $BASE_PY ($PY_VER)"
if [ "$PY_MINOR" != "12" ]; then
  warn "Python 3.$PY_MINOR in use; pyrfc 3.3.x is built and tested on 3.12. If the pyrfc build fails, run: brew install python@3.12 && rm -rf .venv && ./setup.sh"
fi

# A venv made by a different interpreter than the one requested is rebuilt.
if [ -x "$VENV/bin/python" ]; then
  VENV_MINOR="$("$VENV/bin/python" -c 'import sys;print(sys.version_info[1])' 2>/dev/null)"
  if [ "$VENV_MINOR" != "$PY_MINOR" ]; then
    info "Existing .venv is Python 3.$VENV_MINOR, want 3.$PY_MINOR - recreating."
    rm -rf "$VENV"
  fi
fi
if [ ! -x "$VENV/bin/python" ]; then
  "$BASE_PY" -m venv "$VENV" || fail "Could not create $VENV"
  ok "Created virtualenv: $VENV"
else
  ok "Virtualenv present: $VENV"
fi
PY="$VENV/bin/python"

# --- 2. build tools -----------------------------------------------------------
# No macOS wheel of pyrfc is published, so pip compiles it (Cython + C).
step "2/9" "Checking compiler (Xcode Command Line Tools) ..."
if xcode-select -p >/dev/null 2>&1 && command -v cc >/dev/null 2>&1; then
  ok "Compiler present: $(xcode-select -p)"
else
  warn "Xcode Command Line Tools missing - pyrfc cannot be compiled. Run: xcode-select --install  (then re-run setup.sh)"
fi

# --- 3. base dependencies -----------------------------------------------------
step "3/9" "Installing python-dotenv + mcp ..."
"$PY" -m pip install --disable-pip-version-check --quiet --upgrade pip setuptools wheel \
  || fail "pip bootstrap failed. Check network / proxy, then re-run."
"$PY" -m pip install --disable-pip-version-check --quiet python-dotenv "mcp<2" \
  || fail "pip install failed. Check network / proxy, then re-run."
ok "python-dotenv + mcp installed."

# --- 4. SAP NW RFC SDK --------------------------------------------------------
step "4/9" "Checking SAP NW RFC SDK (macOS) ..."
SDK=""
if [ -n "$SDK_REQUEST" ]; then
  SDK="$SDK_REQUEST"
elif [ -n "${SAPNWRFC_HOME:-}" ]; then
  SDK="$SAPNWRFC_HOME"
else
  for cand in "$MCP/vendor/nwrfcsdk-macos" "$HOME/nwrfcsdk" "/usr/local/sap/nwrfcsdk" "/opt/nwrfcsdk"; do
    if [ -f "$cand/lib/libsapnwrfc.dylib" ]; then SDK="$cand"; break; fi
  done
fi
SDK_OK=0
if [ -z "$SDK" ]; then
  warn "SAP NW RFC SDK for macOS not found. Download 'NW RFC SDK 7.50 for MACOS on ${ARCH/arm64/ARM64}' from the SAP Software Center, extract with SAPCAR to mcp/vendor/nwrfcsdk-macos (or set SAPNWRFC_HOME / pass --sdk), then re-run."
elif [ ! -d "$SDK/lib" ]; then
  warn "SDK lib folder not found: $SDK/lib"
else
  SDK="$(cd "$SDK" && pwd)"
  missing=""
  for f in libsapnwrfc.dylib libsapucum.dylib; do
    [ -f "$SDK/lib/$f" ] || missing="$missing $f"
  done
  ls "$SDK"/lib/libicu*.dylib >/dev/null 2>&1 || missing="$missing libicu*.dylib"
  [ -f "$SDK/include/sapnwrfc.h" ] || missing="$missing include/sapnwrfc.h"
  if [ -n "$missing" ]; then
    warn "SDK at $SDK is incomplete - missing:$missing. Re-extract the full archive."
  else
    # The Windows SDK is not usable here - make sure this really is a Mach-O build.
    if ! file "$SDK/lib/libsapnwrfc.dylib" | grep -q "Mach-O"; then
      warn "$SDK/lib/libsapnwrfc.dylib is not a macOS library (Windows/Linux SDK?)."
    else
      SDK_OK=1
      ok "SDK complete at $SDK"
      # Files extracted from a browser download are quarantined; dlopen then fails.
      xattr -dr com.apple.quarantine "$SDK" 2>/dev/null || true

      # Make the dylibs relocatable (@rpath) so pyrfc finds them without
      # DYLD_LIBRARY_PATH (which SIP strips for many launch paths). Idempotent.
      changed=0
      for lib in "$SDK"/lib/*.dylib; do
        name="$(basename "$lib")"
        cur_id="$(otool -D "$lib" 2>/dev/null | sed -n '2p')"
        if [ "$cur_id" != "@rpath/$name" ]; then
          install_name_tool -id "@rpath/$name" "$lib" 2>/dev/null && changed=1
        fi
        # Sibling dependencies referenced by bare name -> @rpath/<name>.
        otool -L "$lib" 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r dep; do
          case "$dep" in
            /*|@*) ;;                                   # absolute / already @rpath
            *) if [ -f "$SDK/lib/$dep" ]; then
                 install_name_tool -change "$dep" "@rpath/$dep" "$lib" 2>/dev/null
               fi ;;
          esac
        done
      done
      # install_name_tool invalidates the ad-hoc signature; arm64 refuses unsigned code.
      for lib in "$SDK"/lib/*.dylib; do
        codesign --force --sign - "$lib" >/dev/null 2>&1 || true
      done
      [ "$changed" = "1" ] && info "Rewrote dylib install names to @rpath and re-signed (ad hoc)."
    fi
  fi
fi
[ "$SDK_OK" = "1" ] && export SAPNWRFC_HOME="$SDK"

# --- 5. pyrfc -----------------------------------------------------------------
step "5/9" "Installing pyrfc ..."
PYRFC_OK=0
if [ "$SDK_OK" != "1" ]; then
  warn "Skipping pyrfc: it is compiled against the SDK (step 4 must pass first)."
else
  if ! "$PY" -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('pyrfc') else 1)" >/dev/null 2>&1; then
    # Prefer a local macOS wheel if one was dropped into vendor/, else build from PyPI.
    WHEEL="$(ls "$MCP"/vendor/pyrfc-*macosx*.whl 2>/dev/null | head -1)"
    if [ -n "$WHEEL" ]; then
      echo "Installing $(basename "$WHEEL")"
      "$PY" -m pip install --disable-pip-version-check --quiet "$WHEEL" || warn "pyrfc wheel install failed."
    else
      # Every pyrfc release on PyPI is marked "yanked" (SAP archived the project),
      # so a range like ">=3.3" resolves to nothing - only an exact pin installs.
      echo "Building pyrfc 3.3.1 from source (1-2 min) ..."
      "$PY" -m pip install --disable-pip-version-check --quiet --no-cache-dir "pyrfc==3.3.1" \
        || warn "pyrfc build failed. Try: $PY -m pip install 'cython<3.1' && $PY -m pip install --no-build-isolation pyrfc==3.3.1  (needs Xcode CLT)."
    fi
  else
    ok "pyrfc already installed."
  fi

  # Make sure the extension module carries an rpath to the SDK lib folder.
  PURELIB="$("$PY" -c 'import sysconfig;print(sysconfig.get_paths()["platlib"])')"
  for so in "$PURELIB"/pyrfc/_pyrfc*.so; do
    [ -f "$so" ] || continue
    if ! otool -l "$so" | grep -A2 LC_RPATH | grep -q "path $SDK/lib "; then
      install_name_tool -add_rpath "$SDK/lib" "$so" 2>/dev/null \
        && codesign --force --sign - "$so" >/dev/null 2>&1
      info "Added rpath $SDK/lib to $(basename "$so")."
    fi
  done

  PROBE="$("$PY" -c "import sys; sys.path.insert(0, r'$MCP'); from sap.config import resolve_nwrfc_home; import pyrfc; print(pyrfc.__version__)" 2>&1 | tail -1)"
  if [ $? -eq 0 ] && echo "$PROBE" | grep -Eq '^[0-9]+\.[0-9]+'; then
    PYRFC_OK=1
    ok "pyrfc $PROBE loads the SDK successfully."
  else
    warn "pyrfc cannot load the SDK yet: $PROBE. Usual causes: quarantined/unsigned dylibs (re-run setup.sh) or SDK arch ($ARCH) != Python arch."
  fi
fi

# --- 6. .env / profiles -------------------------------------------------------
step "6/9" "Configuring connection files ..."
PROFILES=()
if [ -d "$MCP/profiles" ]; then
  for f in "$MCP"/profiles/*.env; do
    [ -f "$f" ] && PROFILES+=("$(basename "$f" .env)")
  done
fi
CFG_PENDING=()
if [ ${#PROFILES[@]} -gt 0 ]; then
  MULTI=1
  ok "Found ${#PROFILES[@]} profile(s): ${PROFILES[*]}"
  for p in "${PROFILES[@]}"; do
    grep -q 'YOUR_RFC_USER' "$MCP/profiles/$p.env" && CFG_PENDING+=("$p")
  done
  CFG_OK=$([ ${#CFG_PENDING[@]} -eq 0 ] && echo 1 || echo 0)
  CFG_TEXT="Fill in profiles: ${CFG_PENDING[*]}"
  [ "$CFG_OK" = "1" ] && CFG_TEXT="All profiles filled in"
else
  MULTI=0
  if [ -f "$MCP/.env" ]; then
    ok ".env already exists - left untouched."
  elif [ -f "$MCP/.env.example" ]; then
    cp "$MCP/.env.example" "$MCP/.env"
    printf '%s.env created from template - EDIT IT with your SAP credentials.%s\n' "$C_YEL" "$C_OFF"
  else
    warn ".env.example missing; cannot create .env."
  fi
  info "For multi-system use: cp mcp/profiles/s4d-360.env.example mcp/profiles/<name>.env, edit, re-run setup."
  if [ -f "$MCP/.env" ] && ! grep -q 'YOUR_RFC_USER' "$MCP/.env"; then CFG_OK=1; else CFG_OK=0; fi
  CFG_TEXT="Edit mcp/.env - SAP_USER / SAP_PASSWD / SAP_CLIENT / SAP_ASHOST / SAP_SAPROUTER"
fi
if [ "$CFG_OK" = "1" ]; then
  ok "Logon config looks filled in (no YOUR_RFC_USER placeholder left)."
else
  printf '%sLogon config still has placeholders: %s%s\n' "$C_YEL" "$CFG_TEXT" "$C_OFF"
fi

# --- 7. Harness durable layer -------------------------------------------------
step "7/9" "Bootstrapping the Harness durable layer ..."
if [ "$SKIP_HARNESS" = "1" ]; then
  info "Skipped (--skip-harness)."
elif [ ! -x "$ROOT/scripts/bin/harness-cli" ]; then
  # Only harness-cli.exe (Windows) ships with the folder; it is git-ignored too.
  warn "scripts/bin/harness-cli (macOS build) missing - harness.db not initialized. Install the macOS Harness CLI from its pinned release (scripts/harness-cli-release-tag), or pass --skip-harness."
elif [ ! -f "$ROOT/scripts/bootstrap-harness.sh" ]; then
  warn "scripts/bootstrap-harness.sh missing; cannot initialize harness.db."
else
  if bash "$ROOT/scripts/bootstrap-harness.sh"; then
    ok "Harness ready (harness.db initialized/migrated)."
  else
    warn "bootstrap-harness.sh failed."
  fi
fi

# --- 8. register MCP server(s) ------------------------------------------------
# Registration stores ABSOLUTE paths per project directory, so it must be re-run
# on every new machine / after moving the folder. SAPNWRFC_HOME is passed as env
# so the server finds the macOS SDK instead of the bundled Windows one.
step "8/9" "Registering MCP server(s) with Claude Code ..."
SERVER="$MCP/server.py"
REGISTERED=()
# .mcp.json launches profile servers via scripts/mcp_launch.py (portable, no
# absolute paths). Registering again would shadow it in local scope and cause a
# "Conflicting scopes" warning, so only register when .mcp.json does not cover
# the server or the SDK lives outside the default folder (needs SAPNWRFC_HOME).
mcp_json_has() { grep -q "\"$1\"" "$ROOT/.mcp.json" 2>/dev/null; }
register() { # register <server-name> [profile]
  local srv="$1" prof="${2:-}"
  if mcp_json_has "$srv" && { [ "$SDK_OK" != "1" ] || [ "$SDK" = "$MCP/vendor/nwrfcsdk-macos" ]; }; then
    ok "Covered by .mcp.json (scripts/mcp_launch.py): $srv - no local registration needed"
    REGISTERED+=("$srv")
    return
  fi
  claude mcp remove "$srv" >/dev/null 2>&1 || true
  local envargs=()
  [ "$SDK_OK" = "1" ] && envargs=(-e "SAPNWRFC_HOME=$SDK")
  local cmd=("$PY" "$SERVER")
  [ -n "$prof" ] && cmd+=(--profile "$prof")
  if claude mcp add "$srv" ${envargs[@]+"${envargs[@]}"} -- "${cmd[@]}" >/dev/null; then
    ok "Registered: $srv${prof:+ (profile $prof)}"
    REGISTERED+=("$srv")
  else
    warn "failed to register $srv"
  fi
}
if command -v claude >/dev/null 2>&1; then
  if [ "$MULTI" = "1" ]; then
    for p in "${PROFILES[@]}"; do register "sap-$p" "$p"; done
  else
    register "sap-rfc"
  fi
else
  warn "'claude' CLI not on PATH - MCP servers NOT registered."
  echo "       claude mcp add sap-rfc -e SAPNWRFC_HOME=\"$SDK\" -- \"$PY\" \"$SERVER\"" >&2
  echo "       (per system: claude mcp add sap-s4d-360 -e ... -- ... --profile s4d-360)" >&2
fi
SERVER_LIST="none"
[ ${#REGISTERED[@]} -gt 0 ] && SERVER_LIST="${REGISTERED[*]}"

# --- 9. verification ----------------------------------------------------------
step "9/9" "Verifying ..."
VERIFY_RAN=0
if [ "$SKIP_VERIFY" = "1" ]; then
  info "Skipped (--skip-verify)."
elif [ ! -f "$ROOT/scripts/mcp_probe.py" ]; then
  warn "scripts/mcp_probe.py not found; skipping verification."
elif [ "$PYRFC_OK" != "1" ]; then
  warn "Skipping the MCP handshake: pyrfc is not loadable yet (fix steps 4-5, then re-run)."
else
  probe() { "$PY" "$ROOT/scripts/mcp_probe.py" "$@"; }
  # Without filled-in credentials the SAP logon can only fail: stop at the handshake.
  if [ "$MULTI" = "1" ]; then
    for p in "${PROFILES[@]}"; do
      echo "--- profile $p"
      if grep -q 'YOUR_RFC_USER' "$MCP/profiles/$p.env"; then probe --profile "$p"
      else probe --profile "$p" --call sap_ping; fi || warn "probe failed for profile $p"
    done
  else
    if [ "$CFG_OK" = "1" ]; then probe --call sap_ping; else probe; fi || warn "MCP probe failed."
  fi
  VERIFY_RAN=1
fi

# --- done: TODO checklist -----------------------------------------------------
printf '\n%s=== Setup complete - TODO checklist ===%s\n' "$C_CYN" "$C_OFF"
echo "Mode: $([ "$MULTI" = "1" ] && echo "multi-system (${#PROFILES[@]} profiles)" || echo "single system")"
printf '%sDone by this script:%s\n' "$C_CYN" "$C_OFF"
item 1 "Python venv (.venv) + python-dotenv + mcp"
item "$SDK_OK" "SAP NW RFC SDK (macOS) located and prepared"
item "$PYRFC_OK" "pyrfc built and loads the SDK"
item "$([ ${#REGISTERED[@]} -gt 0 ] && echo 1 || echo 0)" "MCP server(s) registered with Claude Code: $SERVER_LIST"
item "$VERIFY_RAN" "Verification run (scripts/mcp_probe.py)"

printf '\n%sYou still need to:%s\n' "$C_CYN" "$C_OFF"
item "$CFG_OK" "$CFG_TEXT"
item 0 "Restart Claude Code so the tools bind (registration alone is not enough)"
item 0 "(optional) Install the ABAP helpers for screen/syntax/activate/CDS/textpool tools - see abap/README.md"
item 0 "(optional, DEV only) enable writes: SAP_ALLOW_WRITE=true (per-system)"

if [ ${#WARNINGS[@]} -gt 0 ]; then
  printf '\n%s%d warning(s) to review:%s\n' "$C_YEL" "${#WARNINGS[@]}" "$C_OFF"
  for w in "${WARNINGS[@]}"; do printf '%s  - %s%s\n' "$C_YEL" "$w" "$C_OFF"; done
fi

if [ "$SDK_OK" != "1" ]; then
  printf '\n%s>> Start here: install the macOS NW RFC SDK (see step 4), then re-run ./setup.sh%s\n' "$C_MAG" "$C_OFF"
elif [ "$CFG_OK" != "1" ]; then
  printf '\n%s>> Start here: fill in your SAP logon details, then re-run ./setup.sh%s\n' "$C_MAG" "$C_OFF"
elif [ ${#WARNINGS[@]} -gt 0 ]; then
  printf '\n%s>> Review the warnings above, then re-run: %s scripts/mcp_probe.py --call sap_ping%s\n' "$C_MAG" "$PY" "$C_OFF"
else
  printf '\n%s>> Ready. Restart Claude Code and the sap tools will be available.%s\n' "$C_MAG" "$C_OFF"
fi
