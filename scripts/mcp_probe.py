"""Probe an MCP stdio server with a real JSON-RPC handshake.

Spawns `python <server.py> [--profile <name>]`, performs initialize ->
notifications/initialized -> tools/list, and optionally calls one tool. This
exercises the MCP protocol layer itself, which `test_connection.py` does not:
test_connection.py imports the bridge directly and never speaks MCP.

    python scripts/mcp_probe.py --profile s4d-360
    python scripts/mcp_probe.py --profile s4d-360 --call sap_ping
    python scripts/mcp_probe.py --profile s4d-360 --json

Exit code 0 = handshake + tools/list succeeded (and the --call tool, if given,
returned without an error). Non-zero = failure; details on stdout.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import threading
from pathlib import Path
from queue import Empty, Queue

_ROOT = Path(__file__).resolve().parent.parent
_SERVER = _ROOT / "mcp" / "server.py"
PROTOCOL_VERSION = "2024-11-05"


class ProbeError(RuntimeError):
    pass


class StdioClient:
    """Minimal newline-delimited JSON-RPC client over a child process' stdio."""

    def __init__(self, argv: list[str], timeout: float) -> None:
        self.timeout = timeout
        self._next_id = 0
        self._stderr: list[str] = []
        self.proc = subprocess.Popen(
            argv,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            cwd=str(_ROOT),
        )
        self._out: Queue[str | None] = Queue()
        threading.Thread(target=self._pump_stdout, daemon=True).start()
        threading.Thread(target=self._pump_stderr, daemon=True).start()

    def _pump_stdout(self) -> None:
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            self._out.put(line)
        self._out.put(None)  # EOF sentinel

    def _pump_stderr(self) -> None:
        assert self.proc.stderr is not None
        for line in self.proc.stderr:
            self._stderr.append(line.rstrip())

    @property
    def stderr_tail(self) -> str:
        return "\n".join(self._stderr[-15:]).strip()

    def _send(self, payload: dict) -> None:
        assert self.proc.stdin is not None
        try:
            self.proc.stdin.write(json.dumps(payload) + "\n")
            self.proc.stdin.flush()
        except OSError as exc:
            raise ProbeError(f"server closed stdin ({exc}); stderr:\n{self.stderr_tail}") from exc

    def notify(self, method: str, params: dict | None = None) -> None:
        self._send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def request(self, method: str, params: dict | None = None) -> dict:
        self._next_id += 1
        req_id = self._next_id
        self._send({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params or {}})
        # Skip server-initiated notifications / mismatched ids until ours lands.
        while True:
            try:
                line = self._out.get(timeout=self.timeout)
            except Empty:
                raise ProbeError(
                    f"timeout after {self.timeout:.0f}s waiting for '{method}' reply; "
                    f"stderr:\n{self.stderr_tail}"
                ) from None
            if line is None:
                rc = self.proc.poll()
                raise ProbeError(
                    f"server exited (code {rc}) before answering '{method}'; "
                    f"stderr:\n{self.stderr_tail}"
                )
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue  # non-JSON banner line on stdout
            if msg.get("id") != req_id:
                continue
            if "error" in msg:
                raise ProbeError(f"{method} -> JSON-RPC error: {msg['error']}")
            return msg.get("result") or {}

    def close(self) -> None:
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
            self.proc.wait(timeout=5)
        except Exception:  # noqa: BLE001
            self.proc.kill()


def _tool_text(result: dict) -> str:
    """Flatten an MCP tools/call result to text for display."""
    parts = [c.get("text", "") for c in result.get("content", []) if c.get("type") == "text"]
    return "\n".join(p for p in parts if p).strip()


def main() -> int:
    ap = argparse.ArgumentParser(description="MCP stdio handshake probe")
    ap.add_argument("--profile", help="SAP profile passed through to the server")
    ap.add_argument("--server", default=str(_SERVER), help="path to server.py")
    ap.add_argument("--call", help="tool to invoke after tools/list (e.g. sap_ping)")
    ap.add_argument("--args", default="{}", help="JSON arguments for --call")
    ap.add_argument("--timeout", type=float, default=60.0, help="per-request timeout (s)")
    ap.add_argument("--json", action="store_true", help="emit a machine-readable result")
    opts = ap.parse_args()

    report: dict = {"server": opts.server, "profile": opts.profile or "default"}
    if not Path(opts.server).is_file():
        print(f"[FAIL] server not found: {opts.server}")
        return 2

    argv = [sys.executable, opts.server]
    if opts.profile:
        argv += ["--profile", opts.profile]

    # FastMCP writes its banner to stderr; keep the child's env but force UTF-8
    # so a non-ASCII SAP message cannot break the pipe decoding.
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")

    client = None
    try:
        client = StdioClient(argv, opts.timeout)
        init = client.request(
            "initialize",
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "mcp-probe", "version": "1.0"},
            },
        )
        client.notify("notifications/initialized")
        server_info = init.get("serverInfo") or {}
        report["server_name"] = server_info.get("name")
        report["server_version"] = server_info.get("version")
        report["protocol"] = init.get("protocolVersion")

        listed = client.request("tools/list")
        names = sorted(t.get("name", "?") for t in listed.get("tools", []))
        report["tool_count"] = len(names)
        report["tools"] = names

        if opts.call:
            if opts.call not in names:
                raise ProbeError(f"tool '{opts.call}' not exposed by the server")
            try:
                call_args = json.loads(opts.args)
            except json.JSONDecodeError as exc:
                raise ProbeError(f"--args is not valid JSON: {exc}") from exc
            res = client.request("tools/call", {"name": opts.call, "arguments": call_args})
            text = _tool_text(res)
            report["call"] = {"tool": opts.call, "isError": bool(res.get("isError")), "text": text}
            if res.get("isError"):
                raise ProbeError(f"{opts.call} returned isError=true:\n{text}")
    except ProbeError as exc:
        report["error"] = str(exc)
        print(json.dumps(report, indent=2) if opts.json else f"[FAIL] {exc}")
        return 1
    except Exception as exc:  # noqa: BLE001
        report["error"] = f"{type(exc).__name__}: {exc}"
        print(json.dumps(report, indent=2) if opts.json else f"[FAIL] unexpected: {exc}")
        return 1
    finally:
        if client:
            client.close()

    if opts.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"[OK] handshake with '{report.get('server_name')}' "
              f"(protocol {report.get('protocol')}, profile {report['profile']})")
        print(f"[OK] tools/list -> {report['tool_count']} tools")
        if opts.call:
            print(f"[OK] {opts.call} ->")
            print(report["call"]["text"] or "(empty result)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
