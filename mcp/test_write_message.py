"""Offline tests for ops.write_message_class (no SAP connection needed)."""
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sap import ops  # noqa: E402
from sap.connection import SapConnectionError  # noqa: E402


class FakeClient:
    def __init__(self, subrc=0):
        self.subrc, self.calls = subrc, []

    def call(self, fm, **kw):
        self.calls.append((fm, kw))
        return {"EV_SUBRC": self.subrc, "EV_MESSAGE": "ok" if not self.subrc else "boom",
                "EV_RESULT": json.dumps({"class": "ZMC_X", "count": 1})}


def patched(client, rows):
    return mock.patch.multiple(
        ops, _require_write=mock.DEFAULT, get_client=lambda: client,
        read_table=lambda *a, **k: {"rows": rows})


class WriteMessageClass(unittest.TestCase):
    def test_upsert_pads_number_and_verifies(self):
        c = FakeClient()
        with patched(c, [{"MSGNR": "005", "TEXT": "hello"}]):
            out = ops.write_message_class("zmc_x", [{"number": "5", "text": "hello"}], "S4DK000001")
        sent = json.loads(c.calls[0][1]["IV_PARAMS"])
        self.assertEqual(sent["messages"], [{"number": "005", "text": "hello"}])
        self.assertEqual((sent["class"], sent["action"], sent["transport"]), ("ZMC_X", "UPSERT", "S4DK000001"))
        self.assertTrue(out["verified"])

    def test_not_verified_when_text_differs(self):
        with patched(FakeClient(), [{"MSGNR": "005", "TEXT": "other"}]):
            out = ops.write_message_class("ZMC_X", [{"number": "5", "text": "hello"}])
        self.assertFalse(out["verified"])

    def test_delete_verified_when_gone(self):
        c = FakeClient()
        with patched(c, []):
            out = ops.write_message_class("ZMC_X", [{"number": "5"}], delete=True)
        self.assertEqual(json.loads(c.calls[0][1]["IV_PARAMS"])["action"], "DELETE")
        self.assertTrue(out["verified"])

    def test_rejects_bad_input(self):
        with patched(FakeClient(), []):
            for cls, msgs in (("T100", [{"number": "1", "text": "x"}]),
                              ("ZMC_X", []),
                              ("ZMC_X", [{"number": "1000", "text": "x"}]),
                              ("ZMC_X", [{"number": "1", "text": "a"}, {"number": "001", "text": "b"}])):
                with self.assertRaises(SapConnectionError):
                    ops.write_message_class(cls, msgs)

    def test_sap_error_is_raised(self):
        with patched(FakeClient(subrc=4), []):
            with self.assertRaises(SapConnectionError):
                ops.write_message_class("ZMC_X", [{"number": "1", "text": "x"}])


if __name__ == "__main__":
    unittest.main(verbosity=2)
