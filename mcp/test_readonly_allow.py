"""Offline tests for the read-only FM allowlist (no SAP connection needed).

    .venv/bin/python mcp/test_readonly_allow.py
"""
import importlib.util
import io
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.argv = ["x"]  # keep sap.config from picking up this script's arguments

from sap import tools  # noqa: E402
from sap.connection import SapConnectionError  # noqa: E402


def load_hook():
    spec = importlib.util.spec_from_file_location("guard", HERE.parent / "scripts/hooks/guard_sap_writes.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class FakeClient:
    def __init__(self, allow_write):
        self.config = mock.Mock(allow_write=allow_write)
        self.calls = []

    def call(self, fm, **kw):
        self.calls.append(fm)
        return {"ok": True}


class ToolsAllowlist(unittest.TestCase):
    def run_rfc(self, fm, allow_env, allow_write=False):
        client = FakeClient(allow_write)
        with mock.patch.dict(os.environ, {"SAP_RFC_READONLY_ALLOW": allow_env}), \
                mock.patch.object(tools, "get_client", return_value=client):
            return tools.run_rfc(fm, {}), client

    def test_listed_fm_runs_on_readonly_profile(self):
        res, client = self.run_rfc("ZMCPT_FM_GET_PO_INFO", "ZMCPT_FM_*")
        self.assertEqual(client.calls, ["ZMCPT_FM_GET_PO_INFO"])

    def test_unlisted_fm_still_blocked(self):
        with self.assertRaises(SapConnectionError):
            self.run_rfc("ZCTD_FM_CREATE_BP", "ZMCPT_FM_*")

    def test_empty_allowlist_blocks_everything(self):
        with self.assertRaises(SapConnectionError):
            self.run_rfc("RFC_GET_FUNCTION_INTERFACE", "")

    def test_denylist_beats_allowlist(self):
        with self.assertRaises(SapConnectionError) as cm:
            self.run_rfc("SXPG_COMMAND_EXECUTE", "SXPG_*")
        self.assertIn("deny list", str(cm.exception))

    def test_case_insensitive(self):
        _, client = self.run_rfc("zmcpt_fm_find_po", "zmcpt_fm_find_po")
        self.assertEqual(len(client.calls), 1)


class HookAllowlist(unittest.TestCase):
    def run_hook(self, tool, fm, allow):
        hook = load_hook()
        payload = {"tool_name": tool, "tool_input": {"function_name": fm}}
        with mock.patch.object(hook, "readonly_allowlist", return_value=allow), \
                mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), \
                mock.patch.object(sys, "stderr", io.StringIO()):
            return hook.main()

    def test_run_rfc_listed_on_readonly_server_allowed(self):
        self.assertEqual(self.run_hook("mcp__sap-s4d-360__sap_run_rfc", "ZMCPT_FM_X", ["ZMCPT_FM_*"]), 0)

    def test_run_rfc_unlisted_blocked(self):
        self.assertEqual(self.run_hook("mcp__sap-s4d-360__sap_run_rfc", "ZCTD_FM_CREATE_BP", ["ZMCPT_FM_*"]), 2)

    def test_other_write_tools_never_allowlisted(self):
        self.assertEqual(self.run_hook("mcp__sap-s4d-360__sap_write_program", "", ["*"]), 2)
        self.assertEqual(self.run_hook("mcp__sap-s4d-360__sap_activate", "", ["*"]), 2)

    def test_writable_server_unchanged(self):
        self.assertEqual(self.run_hook("mcp__sap-s4d-100__sap_run_rfc", "ANY_FM", []), 0)

    def test_allowlist_read_from_env_files(self):
        hook = load_hook()
        with mock.patch.object(Path, "read_text", side_effect=[
                "SAP_RFC_READONLY_ALLOW=BASE_*\n", "# c\nSAP_RFC_READONLY_ALLOW='zmcpt_*, RFC_X'\nOTHER=1\n"]):
            self.assertEqual(hook.readonly_allowlist("sap-s4d-360"), ["ZMCPT_*", "RFC_X"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
