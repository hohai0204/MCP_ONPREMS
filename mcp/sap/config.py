"""Build pyrfc connection parameters from environment variables.

All SAP-specific env vars are read here so the rest of the code never touches
os.environ directly. A SAProuter route prefix is merged into `ashost` when
provided, which is what lets the bridge reach RFC-only systems behind a router.
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

# Project root = parent of this `sap/` package.
_PROJECT_ROOT = Path(__file__).resolve().parent.parent
_PROFILES_DIR = _PROJECT_ROOT / "profiles"


def _resolve_profile() -> tuple[str, Path | None]:
    """Pick which system profile to load, for multi-system setups.

    Precedence: `--env-file <path>` arg > `--profile <name>` arg >
    SAP_PROFILE env var. Returns (profile_name, env_file_path). When nothing is
    given, profile name is 'default' and only the base .env is used.
    """
    argv = sys.argv[1:]
    for i, a in enumerate(argv):
        if a == "--env-file" and i + 1 < len(argv):
            p = Path(argv[i + 1])
            return (p.stem, p)
        if a == "--profile" and i + 1 < len(argv):
            name = argv[i + 1]
            return (name, _PROFILES_DIR / f"{name}.env")
    name = (os.getenv("SAP_PROFILE") or "").strip()
    if name:
        return (name, _PROFILES_DIR / f"{name}.env")
    return ("default", None)


_PROFILE_NAME, _PROFILE_FILE = _resolve_profile()

# Load the base .env (shared defaults) first, then the selected profile file on
# top (its values override the base). This lets common settings live in .env and
# per-system credentials live in profiles/<name>.env.
load_dotenv(_PROJECT_ROOT / ".env")
load_dotenv()  # also honour a .env in the current working dir, if any
if _PROFILE_FILE and _PROFILE_FILE.is_file():
    load_dotenv(_PROFILE_FILE, override=True)

# Bundled SDK shipped alongside this project (used if no env var overrides it).
_BUNDLED_SDK = _PROJECT_ROOT / "vendor" / "nwrfcsdk"


def _clean(value: str | None) -> str:
    return (value or "").strip()


def resolve_nwrfc_home() -> str:
    """Locate the SAP NW RFC SDK: env override first, then the bundled copy."""
    for env_key in ("SAPNWRFC_HOME", "SAP_NWRFC_HOME"):
        val = _clean(os.getenv(env_key))
        if val:
            return val
    if _BUNDLED_SDK.is_dir():
        return str(_BUNDLED_SDK)
    return ""


@dataclass
class SapConfig:
    conn_params: dict = field(default_factory=dict)
    allow_write: bool = False
    nwrfc_home: str = ""
    profile: str = "default"

    @property
    def masked(self) -> dict:
        """Connection params safe to log/return (password removed)."""
        return {k: v for k, v in self.conn_params.items() if k not in ("passwd",)}


def load_config() -> SapConfig:
    params: dict = {}

    user = _clean(os.getenv("SAP_USER"))
    passwd = _clean(os.getenv("SAP_PASSWD"))
    client = _clean(os.getenv("SAP_CLIENT"))
    lang = _clean(os.getenv("SAP_LANG")) or "EN"

    if user:
        params["user"] = user
    if passwd:
        params["passwd"] = passwd
    if client:
        params["client"] = client
    params["lang"] = lang

    # --- direct application-server logon ---
    # NWRFC-recommended SAProuter handling: keep `ashost` as the PLAIN target
    # host and pass the route to the router as a SEPARATE `saprouter` param.
    # Do NOT merge them into one string and also set saprouter — that makes
    # NWRFC send an empty target host ("hostname empty").
    ashost = _clean(os.getenv("SAP_ASHOST"))
    saprouter = _clean(os.getenv("SAP_SAPROUTER"))
    sysnr = _clean(os.getenv("SAP_SYSNR"))
    if ashost:
        ashost_is_route = ashost.startswith("/H/") or ashost.startswith("/S/")
        params["ashost"] = ashost
        if sysnr:
            params["sysnr"] = sysnr
        # Only attach saprouter separately when ashost is a plain host.
        if saprouter and not ashost_is_route:
            params["saprouter"] = saprouter

    # --- message-server / load-balanced logon (used only if no ashost) ---
    mshost = _clean(os.getenv("SAP_MSHOST"))
    if mshost and not ashost:
        params["mshost"] = mshost
        for env_key, p_key in (
            ("SAP_MSSERV", "msserv"),
            ("SAP_SYSID", "sysid"),
            ("SAP_GROUP", "group"),
        ):
            val = _clean(os.getenv(env_key))
            if val:
                params[p_key] = val

    # --- SNC (optional) ---
    snc_qop = _clean(os.getenv("SAP_SNC_QOP"))
    if snc_qop:
        params["snc_qop"] = snc_qop
        for env_key, p_key in (
            ("SAP_SNC_PARTNERNAME", "snc_partnername"),
            ("SAP_SNC_LIB", "snc_lib"),
            ("SAP_SNC_MYNAME", "snc_myname"),
        ):
            val = _clean(os.getenv(env_key))
            if val:
                params[p_key] = val

    allow_write = _clean(os.getenv("SAP_ALLOW_WRITE")).lower() == "true"
    return SapConfig(
        conn_params=params,
        allow_write=allow_write,
        nwrfc_home=resolve_nwrfc_home(),
        profile=_PROFILE_NAME,
    )
