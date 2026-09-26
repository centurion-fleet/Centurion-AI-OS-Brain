#!/usr/bin/env python3
"""Serve the Conjunction prototype on the LAN, with a live bridge behind it.

The Brain's Mission Deck serves only its built SPA from dist/, so this is a
stand-in host for one page: it serves conjunction.html and exposes the same
POST /api/bridge endpoint the deck provides, talking to the Brain's own bridge
daemon over its Unix socket.

No dependencies, no build step, read-only against the Brain.
"""
from __future__ import annotations

import json
import os
import socket
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
PAGE = HERE / "stillpoint.html"
SOCK = Path(os.environ.get("CENTURION_BRIDGE_SOCKET") or
            Path(os.path.expanduser("~/.centurion/run/bridge.sock")))
PORT = int(os.environ.get("CONJUNCTION_PORT", "8791"))
HOST = os.environ.get("CONJUNCTION_HOST", "0.0.0.0")


def ask(payload: dict, timeout: float = 45.0) -> dict:
    """One request to the bridge daemon, one JSON reply."""
    req = {"id": "conjunction"}
    req.update(payload)
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(timeout)
    s.connect(str(SOCK))
    s.sendall((json.dumps(req) + "\n").encode())
    s.shutdown(socket.SHUT_WR)
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    if not buf.strip():
        raise RuntimeError("the Brain's bridge did not answer")
    return json.loads(buf.decode().splitlines()[0])


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):        # keep the console quiet
        pass

    def _send(self, code: int, body: bytes, ctype: str):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/stillpoint", "/stillpoint.html", "/conjunction", "/collab"):
            if not PAGE.exists():
                self._send(500, b"stillpoint.html is missing", "text/plain")
                return
            self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
            return
        if self.path.startswith("/fonts/"):
            name = os.path.basename(self.path)
            fp = HERE.parents[1] / "public" / "fonts" / name
            if fp.exists() and fp.suffix == ".woff2" and ".." not in name:
                self._send(200, fp.read_bytes(), "font/woff2")
            else:
                self._send(404, b"no font", "text/plain")
            return
        if self.path == "/health":
            self._send(200, json.dumps({"ok": True, "socket": str(SOCK),
                                        "socket_present": SOCK.exists()}).encode(),
                       "application/json")
            return
        self._send(404, b"not found", "text/plain")

    def do_POST(self):
        if self.path != "/api/bridge":
            self._send(404, b"not found", "text/plain")
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(length) or b"{}")
        except Exception as exc:
            self._send(400, json.dumps({"ok": False, "error": f"bad request: {exc}"}).encode(),
                       "application/json")
            return
        try:
            reply = ask(payload)
        except Exception as exc:
            self._send(502, json.dumps({"ok": False, "error": str(exc)}).encode(),
                       "application/json")
            return
        self._send(200, json.dumps(reply).encode(), "application/json")


if __name__ == "__main__":
    if not PAGE.exists():
        sys.exit(f"missing {PAGE}")
    print(f"conjunction: http://{HOST}:{PORT}/  (bridge socket {SOCK})", flush=True)
    print("open it on the phone with the Brain's LAN address, e.g. "
          "http://192.168.10.109:%d/" % PORT, flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
