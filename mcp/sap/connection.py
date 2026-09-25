"""Thin, lazily-connecting wrapper around a pyrfc Connection.

pyrfc is imported lazily so the MCP server can still start (and report a clear,
actionable error) on a machine where the SAP NW RFC SDK / pyrfc is not yet
installed. The connection is created on first use and transparently re-created
if it has dropped.
"""
from __future__ import annotations

import os
import sys
import threading
from pathlib import Path
from typing import Any

from .config import SapConfig, load_config

_dll_registered = False


def _register_sdk_dlls(nwrfc_home: str) -> None:
    """On Windows, make the SAP NW RFC SDK DLLs discoverable to the pyrfc
    extension module. Since Python 3.8 the loader ignores PATH for extension
    DLLs, so os.add_dll_directory is required."""
    global _dll_registered
    if _dll_registered or not nwrfc_home:
        return
    lib = Path(nwrfc_home) / "lib"
    if sys.platform == "win32" and lib.is_dir():
        try:
            os.add_dll_directory(str(lib))
        except (OSError, AttributeError):
            pass
        # Also prepend to PATH for good measure (helps dependent DLL lookup).
        os.environ["PATH"] = str(lib) + os.pathsep + os.environ.get("PATH", "")
    _dll_registered = True


class SapConnectionError(RuntimeError):
    """Raised for any connection-level problem, with a human-friendly message."""


class SapClient:
    def __init__(self, config: SapConfig | None = None) -> None:
        self._config = config or load_config()
        self._conn: Any = None
        self._lock = threading.Lock()

    # -- lifecycle ---------------------------------------------------------
    def _import_pyrfc(self):
        _register_sdk_dlls(self._config.nwrfc_home)
        try:
            from pyrfc import Connection  # type: ignore
            return Connection
        except ImportError as exc:  # SDK / wheel missing
            raise SapConnectionError(
                "pyrfc could not be imported. Ensure the SAP NW RFC SDK is "
                "present (SAPNWRFC_HOME or the bundled nwrfcsdk folder) and "
                "`pip install pyrfc` succeeded. See README.md. "
                f"Underlying error: {exc}"
            ) from exc

    def _connect(self):
        Connection = self._import_pyrfc()
        if not self._config.conn_params.get("user"):
            raise SapConnectionError(
                "No SAP credentials configured. Copy .env.example to .env and "
                "fill in SAP_USER / SAP_PASSWD / SAP_CLIENT / SAP_ASHOST."
            )
        try:
            return Connection(**self._config.conn_params)
        except Exception as exc:  # pyrfc.RFCError and friends
            raise SapConnectionError(f"RFC logon failed: {exc}") from exc

    def _ensure(self):
        """Return a live connection, (re)connecting as needed. Caller holds lock."""
        if self._conn is None:
            self._conn = self._connect()
            return self._conn
        try:
            self._conn.ping()
        except Exception:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = self._connect()
        return self._conn

    # -- public API --------------------------------------------------------
    @property
    def config(self) -> SapConfig:
        return self._config

    def call(self, func_name: str, **kwargs) -> dict:
        """Invoke a remote-enabled function module and return its result dict."""
        with self._lock:
            conn = self._ensure()
            try:
                return conn.call(func_name, **kwargs)
            except Exception as exc:
                raise SapConnectionError(f"RFC call {func_name} failed: {exc}") from exc

    def close(self) -> None:
        with self._lock:
            if self._conn is not None:
                try:
                    self._conn.close()
                finally:
                    self._conn = None


# Module-level singleton reused across all tool calls.
_client: SapClient | None = None
_client_lock = threading.Lock()


def get_client() -> SapClient:
    global _client
    if _client is None:
        with _client_lock:
            if _client is None:
                _client = SapClient()
    return _client
