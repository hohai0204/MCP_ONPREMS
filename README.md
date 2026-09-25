# MCP-RFC bridge for SAP ABAP (RFC-only / SAProuter / ECC R3)

An MCP server that lets an MCP client (e.g. Claude Code) work with SAP ABAP
objects **over RFC** instead of ADT/HTTP. Because it speaks RFC + SAProuter, it
reaches systems that expose no HTTP/ADT endpoint — including classic ECC / R/3.

> Inspired by the SAP Community blog "Using Claude for SAP ABAP development on
> RFC-only / SAProuter systems (even ECC R/3)". This is an independent,
> prototype implementation — not an official SAP or Anthropic product.

## Architecture

```
Claude Code  --stdio/MCP-->  server.py (FastMCP)
                                   |
                             sap/tools.py      (wraps standard SAP FMs)
                                   |
                             sap/connection.py (pyrfc Connection, reconnect)
                                   |
                             sap/config.py     (.env -> conn params, SAProuter)
                                   |
                                 pyrfc  --RFC/SAProuter-->  SAP system
```

## Tools exposed

| Tool                        | Purpose                              | Needs write? |
|-----------------------------|--------------------------------------|:------------:|
| `sap_ping`                  | Test connection, system info         | no           |
| `sap_read_table`            | Read a table (RFC_READ_TABLE)        | no           |
| `sap_read_program`          | Read ABAP report source              | no           |
| `sap_read_function_module`  | Read FM source + interface           | no           |
| `sap_read_class`            | Read class/interface source          | no           |
| `sap_read_method`           | Read ONE method of a class           | no           |
| `sap_class_api`             | Public API only (+ dependency APIs)  | no           |
| `sap_dead_code`             | Unused-method scan for a package     | no           |
| `sap_search_objects`        | Search TADIR for repository objects  | no           |
| `sap_ddic_info`             | Describe table/structure fields      | no           |
| `sap_list_dumps`            | Recent ST22 runtime errors           | no           |
| `sap_list_transports`       | List transport requests (E070)       | no           |
| `sap_read_transport`        | One transport + its object list      | no           |
| `sap_where_used`            | Where-used via WBCROSSGT index       | no           |
| `sap_read_screen`           | Read Dynpro definition (via Z-FM)    | no           |
| `sap_read_gui_status`       | Read GUI status/CUA (via Z-FM)       | no           |
| `sap_syntax_check`          | Syntax-check source, no save (Z-FM)  | no           |
| `sap_read_cds`              | Read CDS/DDL source (Z-FM)           | no           |
| `sap_textpool_read`         | Read program text elements (Z-FM)    | no           |
| `sap_run_unit_tests`        | Run ABAP Unit for a class (Z-FM)     | no           |
| `sap_run_atc`               | Run ATC check (Z-FM stub)            | no           |
| `sap_adt_dispatch`          | Raw ZMCP_ADT_DISPATCH call           | read: no / write: **yes** |
| `sap_activate`              | Activate inactive objects (Z-FM)     | **yes**      |
| `sap_textpool_write`        | Write program text elements (Z-FM)   | **yes**      |
| `sap_write_program`         | Create/update program (INACTIVE)     | **yes**      |
| `sap_run_rfc`               | Call an arbitrary RFC-enabled FM     | **yes**      |

### Custom dispatcher `ZMCP_ADT_DISPATCH`

The Z-FM tools above route through a custom RFC-enabled FM **`ZMCP_ADT_DISPATCH`**
(function group `ZMCP_ADT_UTILS`) installed on the SAP system — the escape hatch
for features no standard RFC FM exposes. It runs *inside* SAP, so it can call
non-remote workbench APIs (`SYNTAX-CHECK`, `RS_WORKING_OBJECTS_ACTIVATE`,
`READ/INSERT TEXTPOOL`, `DDDDLSRC`, ABAP Unit, ATC) and return JSON.

Install the two FMs from [`abap/`](abap/) on any SAP system you want to drive
(see [`abap/README.md`](abap/README.md) for the interfaces and step-by-step
setup). Action → tool map:

| Action | Tool | Underlying ABAP |
|--------|------|-----------------|
| `SYNTAX_CHECK`   | `sap_syntax_check`    | `SYNTAX-CHECK FOR` |
| `READ_DDLS`      | `sap_read_cds`        | `SELECT … FROM DDDDLSRC` |
| `RUN_UNIT_TESTS` | `sap_run_unit_tests`  | `CL_AUCV_TEST_RUNNER_STANDARD` |
| `ATC_CHECK`      | `sap_run_atc`         | `CL_SATC_API_FACTORY` (stub — fill in) |
| `ACTIVATE`       | `sap_activate`        | `RS_WORKING_OBJECTS_ACTIVATE` |
| `DYNPRO_*` / `CUA_*` | `sap_read_screen` / `sap_read_gui_status` | `RPY_DYNPRO_*` / `RS_CUA_INTERNAL_*` |

`RUN_UNIT_TESTS` and `ATC_CHECK` use release-sensitive class APIs — verify/adjust
the ABAP in SE24 for your system (`ATC_CHECK` ships as an explicit stub). Every
write action goes through the same `SAP_ALLOW_WRITE` guard.

**Text elements** use a separate dedicated FM, **`ZMCP_ADT_TEXTPOOL`** (same
function group), driven by `sap_textpool_read` / `sap_textpool_write`. Flag it
Remote-Enabled in SE37 to use it. `sap_textpool_write` defaults to
`WRITE_INACTIVE` (staged; published on program activation), matching the
"nothing goes live until activate" model; pass `active=true` to write directly.

Write tools are disabled unless `SAP_ALLOW_WRITE=true`.

**Sensitive-table policy:** `sap_read_table` refuses tables holding
credentials/PII (USR02, PA0*, SECSTORE*, …). Override the pattern list via
`SAP_TABLE_BLOCKLIST` (comma-separated, `*` wildcards) in `.env`.

**Package whitelist for writes:** set `SAP_ALLOWED_PACKAGES` (e.g.
`$TMP,ZPK_SANDBOX*`) to restrict `sap_write_program` to specific packages.
Unset = no package restriction (only `SAP_ALLOW_WRITE` applies).

**FM deny list:** `sap_run_rfc` refuses high-risk function modules (OS command
execution, arbitrary ABAP, mass delete, raw SQL, user admin, file transfer,
kernel admin) even with `SAP_ALLOW_WRITE=true`. Override the pattern list via
`SAP_FM_DENYLIST` (comma-separated, `*` wildcards).

## Project layout

```
MCP_SAP_PRIVATE/
  bootstrap.bat              copy to a new machine: clones repo + runs setup
  setup.ps1 / setup.bat      installer + MCP registration
  README.md
  mcp/                       the MCP server (everything it needs to run)
    server.py                MCP server entrypoint (FastMCP, stdio)
    test_connection.py       standalone connectivity check
    requirements.txt
    .env / .env.example      base/shared settings (real .env is git-ignored)
    profiles/                one <name>.env per SAP system (multi-system)
      s4d-360.env.example    per-system profile template
    sap/                     Python package (the bridge)
      config.py              .env -> pyrfc params, SAProuter, SDK discovery
      connection.py          pyrfc wrapper, reconnect, DLL registration
      tools.py               FM wrappers behind each MCP tool
    vendor/                  third-party / licensed binaries
      nwrfcsdk/              SAP NW RFC SDK (not in repo - install locally, auto-detected)
      pyrfc-3.3.1-*.whl      prebuilt pyrfc wheel (offline install)
  abap/                      ABAP to install on the SAP system (reusable)
    README.md                install guide + FM interfaces
    zmcp_adt_dispatch.abap   ZMCP_ADT_DISPATCH (screens, syntax, activate, …)
    zmcp_adt_textpool.abap   ZMCP_ADT_TEXTPOOL (text elements)
```

## Deploy via git (clone-and-go)

The public repo does **not** contain the SAP NW RFC SDK (`mcp/vendor/nwrfcsdk`,
SAP license — no redistribution): download it from the SAP Support Portal and
unpack it to `mcp/vendor/nwrfcsdk` or point `SAPNWRFC_HOME` at it. The pyrfc
wheel is committed. Secrets are **not** committed — `mcp/profiles/*.env` are
git-ignored (copy the `*.env.example`); each machine fills them in locally.
Host names / IPs in docs are placeholders (`<sap-app-host>`, `<saprouter-host>`).

### First push (once, from this folder)
```powershell
git init
git add .
git commit -m "SAP MCP-RFC bridge"
git remote add origin https://github.com/ChinhHN-DEV/MCP_SAP_PRIVATE.git
git push -u origin main
```
> The commit includes the ~60 MB SDK. Keep the remote **private** — the SDK is
> licensed and must not be public.

### On a new machine (one command)
Edit the `REPO=` line in **`bootstrap.bat`**, copy just that one file to the new
machine, and run it (or `bootstrap.bat <git-url>`). It clones the repo and runs
`setup.ps1`. Afterwards, create your connection config:
```powershell
# single system:
copy mcp\.env.example mcp\.env            # then edit
# or multi-system:
copy mcp\profiles\s4d-360.env.example mcp\profiles\s4d-360.env   # then edit, re-run setup.ps1
```

## Quick install on macOS

```bash
./setup.sh                       # same 9 steps as setup.ps1, macOS flavour
./setup.sh --sdk ~/nwrfcsdk      # SDK not in mcp/vendor/nwrfcsdk-macos
./setup.sh --python python3.12   # choose the interpreter for .venv
```

Differences from Windows:

* The repo only carries the **Windows** SDK. Download *NW RFC SDK 7.50 for
  MACOS on ARM64 / X86_64* from the SAP Software Center (S-user), extract it
  with SAPCAR into `mcp/vendor/nwrfcsdk-macos` (or set `SAPNWRFC_HOME`). The
  script strips the quarantine flag, rewrites the dylib install names to
  `@rpath` and re-signs them ad hoc.
* No macOS wheel of `pyrfc` exists, so it is compiled from source against the
  SDK (needs Xcode Command Line Tools: `xcode-select --install`). Python 3.12
  is recommended (`brew install python@3.12`).
* Dependencies live in a project-local `.venv` (Homebrew Python refuses global
  `pip install`). The MCP servers are registered with that interpreter and
  `SAPNWRFC_HOME` as an env var.
* No VC++ runtime step; verification uses `scripts/mcp_probe.py` directly
  (there is no `check-mcp.sh`). The Harness step needs a macOS `harness-cli`
  in `scripts/bin/` — otherwise it warns, or pass `--skip-harness`.

## Quick install on a new Windows machine

Copy the whole folder over, then from inside it run **one** of:

```powershell
# Windows (PowerShell) - run As Administrator the first time so the VC++
# runtime can be installed unattended if it is missing
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```
…or just **double-click `setup.bat`** (it forwards any arguments).

`setup.ps1` checks every prerequisite, installs what is missing, and verifies
the result — nine steps, and it is safe to re-run:

| Step | Does |
| --- | --- |
| 0 preflight | 64-bit Windows, PowerShell, elevation, complete folder copy |
| 1 Python | locate interpreter; reject 32-bit; warn when not 3.12 (the bundled wheel is `cp312`) |
| 2 VC++ runtime | **downloads and installs** `vc_redist.x64.exe` when `vcruntime140*.dll` is missing (SAP Note 2573790) |
| 3 deps | `python-dotenv` + `mcp` |
| 4 pyrfc | matching wheel from `mcp/vendor/`, else download from SAP-archive/PyRFC |
| 5 NW RFC SDK | all 5 required DLLs (`sapnwrfc`, `libsapucum`, `icu*57`), then a real load probe through `sap.connection` |
| 6 config | profiles or `.env`; never overwrites an existing one; reports which files still hold `YOUR_RFC_USER` |
| 7 Harness | runs `scripts/bootstrap-harness.ps1` to init/migrate `harness.db` |
| 8 registration | one `sap-<profile>` MCP server per profile, using **this folder's** absolute path |
| 9 verification | runs `scripts/check-mcp.ps1` (falls back to `-SkipSap` when the logon config is still a template) |

Flags: `-NoVcRedist` (never touch the system runtime), `-SkipHarness` (MCP bridge
only), `-SkipVerify` (offline).

Two things it cannot do for you: **install Python** (it prints the download link
and stops) and **restart Claude Code** — MCP registration alone does not bind the
tools into a running session.

### Folder copy vs `git clone`

`mcp/.env`, `mcp/profiles/*.env`, `harness.db` and `scripts/bin/harness-cli.exe`
are git-ignored. A **folder copy** carries them; a **fresh clone** does not, so
after cloning you must recreate the profile from `.env.example` and reinstall the
harness CLI. Note that a folder copy also carries your **SAP credentials in
plaintext** — use a dedicated RFC user rather than moving shared credentials onto
a machine you do not control.

The manual steps below are the same thing by hand.

## Multiple SAP systems

Run one MCP server per system, each selected by a **profile** file. Claude Code
then sees separate, namespaced tool sets (`mcp__sap-s4d-360__…`, `mcp__sap-qa4__…`)
and picks the right system by server name.

1. Put per-system logon in `mcp/profiles/<name>.env` (copy `mcp/profiles/s4d-360.env.example`):
   ```
   profiles/s4d-360.env  # DEV, SAP_ALLOW_WRITE=true
   profiles/qa4.env      # QA,  read-only
   profiles/prd.env      # PROD, read-only
   ```
   Shared policy (`SAP_TABLE_BLOCKLIST`, `SAP_FM_DENYLIST`, …) stays in the base
   `.env`; each profile **overrides** the base and holds that system's
   credentials + `SAP_ALLOW_WRITE`.
2. Run `setup.ps1` — it registers one server `sap-<name>` per profile file
   (falls back to a single `sap-rfc` from `.env` when no profiles exist).
3. Test a specific system:
   ```powershell
   python mcp\test_connection.py --profile qa4
   ```

Profile selection precedence: `--env-file <path>` > `--profile <name>` >
`SAP_PROFILE` env var > base `.env`. `sap_ping` reports which `profile` answered.
Keep DEV writable and QA/PROD read-only (`SAP_ALLOW_WRITE=false`) so the deny
guards differ per system automatically.

## Setup (manual)

### 1. SAP NW RFC SDK (prerequisite for pyrfc)
`pyrfc` wraps the **SAP NetWeaver RFC SDK** (licensed; from the SAP Support
Portal, not included in the repo). Unpack the **Windows** SDK to `mcp/vendor/nwrfcsdk`;
it is auto-detected and registered at runtime (via `os.add_dll_directory`). No PATH
edits needed. To use a different SDK location, set `SAPNWRFC_HOME` — it takes
precedence over `mcp/vendor/nwrfcsdk`.

#### OS runtime prerequisite for the SDK (SAP Note 2573790)
The NW RFC SDK DLL needs the **Microsoft Visual C++ 2015-2022 Redistributable
x64** (`vcruntime140.dll`) present — without it, `import pyrfc` fails with a
cryptic load error. `setup.ps1` warns and links the installer if it is missing.
Patch level of an installed SDK: `findstr Patch sapnwrfc.dll`.

### 2. Install Python dependencies
`pyrfc` has no PyPI wheel for recent Python, so a matching prebuilt wheel is
vendored in `mcp/vendor/`:
```powershell
python -m pip install python-dotenv mcp
python -m pip install mcp/vendor/pyrfc-3.3.1-cp312-cp312-win_amd64.whl
```
The wheel is `cp312 / win_amd64` (Python 3.12, Windows 64-bit) from the
`SAP-archive/PyRFC` GitHub releases. For a different Python version, fetch the
matching wheel from there.

### 3. Configure the connection
```powershell
Copy-Item mcp\.env.example mcp\.env
# then edit .env
```
SAProuter example — either put the full route in `SAP_ASHOST`:
```
SAP_ASHOST=/H/saprouter.example.com/S/3299/H/sapappserver.internal
SAP_SYSNR=00
```
…or keep a plain host and set the router prefix separately:
```
SAP_ASHOST=sapappserver.internal
SAP_SYSNR=00
SAP_SAPROUTER=/H/saprouter.example.com/S/3299
```

### 4. Test connectivity (no MCP needed)
```powershell
python mcp\test_connection.py
```

### 5. Register the server with Claude Code
```powershell
claude mcp add sap-rfc -- python "c:\Users\Administrator\Desktop\MCP_SAP_PRIVATE\mcp\server.py"
```
Or add to your MCP client config:
```json
{
  "mcpServers": {
    "sap-rfc": {
      "command": "python",
      "args": ["c:\\Users\\Administrator\\Desktop\\MCP_SAP_PRIVATE\\mcp\\server.py"]
    }
  }
}
```

## Health check — "is the MCP actually working?"

```powershell
.\scripts\check-mcp.ps1                     # all profiles, incl. a real sap_ping
.\scripts\check-mcp.ps1 -ProfileName s4d-360    # one profile
.\scripts\check-mcp.ps1 -SkipSap            # local layers only (offline / off-VPN)
.\scripts\check-mcp.ps1 -Json               # machine-readable
```

Seven layers, cheapest first — Python → deps (`import pyrfc` the way the bridge
does it, with the SDK DLL dir registered) → SDK + VC++ runtime → profile config
→ **MCP `initialize` + `tools/list` over stdio** → `tools/call sap_ping` →
`claude mcp list`. Exit code 0 = nothing FAILed. Layer 5 is what
`test_connection.py` cannot tell you: it starts `mcp/server.py` exactly as an MCP
client does and speaks the protocol. The probe itself is reusable standalone:

```powershell
python scripts\mcp_probe.py --profile s4d-360 --call sap_ping
python scripts\mcp_probe.py --profile s4d-360 --json
```

From Claude Code, `/mcp-check` runs the same script and additionally verifies
that the *current session* has the `mcp__sap-<profile>__*` tools bound. For the
target-system health check (bridge Z-FMs, ST22 dumps, stale transports) use the
`sap-doctor` skill instead.

## Safety

* **Read-only by default.** Keep `SAP_ALLOW_WRITE=false` unless you intend to
  modify objects, and only enable writes against a **DEV** system.
* Writes are saved **INACTIVE** — nothing goes live until you activate it in SAP.
* Use an RFC user with the **minimum** authorizations required.
* `.env` holds credentials — it is git-ignored; never commit it.

## Verified on

Read tools (`sap_ping`, `sap_read_table`, `sap_read_program`,
`sap_read_function_module`, `sap_read_class`, `sap_search_objects`) verified
end-to-end against an **S/4HANA system (SAP_BASIS 758)** reached through a
SAProuter. Class source uses the remote-enabled `SIW_RFC_READ_CLIF_SOURCE`.

## Caveats / limits over pure RFC

* Only **remote-enabled** function modules are callable over RFC. Many workbench
  FMs (e.g. the `SEO_*` class APIs, the ABAP `SYNTAX-CHECK`) are **not** RFC-
  enabled, so some ADT-style features simply aren't reachable this way.
* **CDS/DDL source read is not available** over pure RFC on the tested system —
  there is no remote-enabled FM that returns DDL source text. Use ADT for that.
* **Object activation and syntax check** are likewise not wired up: no clean
  remote-enabled FM was found on the tested release. Writes therefore stay
  **INACTIVE**; activate in SAP GUI/ADT.
* `RFC_READ_TABLE` cannot select rows wider than 512 bytes or long/deep fields;
  long WHERE clauses are auto-wrapped to the 72-char OPTIONS line limit.
* FM availability/interfaces can still vary by release — validate on your target.
```
