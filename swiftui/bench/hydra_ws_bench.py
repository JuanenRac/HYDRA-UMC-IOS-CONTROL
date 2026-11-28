#!/usr/bin/env python3
# =============================================================================
# HYDRA-UMC-IOS-CONTROL - swiftui/bench/hydra_ws_bench.py
# Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
# GPL-3.0-or-later - see LICENSE
# =============================================================================
"""The pretend server of test/fixtures/fake-server with the live link (`GET /ws`) added, for the tests of the native app.

The shared pretend server is not changed: this file adds the WebSocket on top of it. The token travels as the second
subprotocol; a token the server did not give closes with 1008. On open the state is sent, and after every POST the
reservations and the state are pushed to the open sockets. Standard library only; nothing here moves hardware.

    python swiftui/bench/hydra_ws_bench.py --port 0
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
os.environ.setdefault("HYDRA_FAKE_ANSWERS", str(ROOT / "test" / "fixtures" / "server-answers.json"))
sys.path.insert(0, str(ROOT / "test" / "fixtures" / "fake-server"))
import hydra_fake_server as fake  # noqa: E402

MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def frame(opcode: int, payload: bytes) -> bytes:
    head = bytes([0x80 | opcode])
    if len(payload) < 126:
        head += bytes([len(payload)])
    elif len(payload) < 65536:
        head += bytes([126]) + struct.pack(">H", len(payload))
    else:
        head += bytes([127]) + struct.pack(">Q", len(payload))
    return head + payload


class Live:
    """The open sockets."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.open: list[socket.socket] = []

    def send(self, connection: socket.socket, message: dict) -> None:
        with self.lock:
            try:
                connection.sendall(frame(1, json.dumps(message).encode("utf-8")))
            except OSError:
                pass

    def broadcast(self, state: fake.FakeHydra) -> None:
        with state.lock:
            claims = state.claims()[1]
            settings = state.settings()[1]
        with self.lock:
            targets = list(self.open)
        for connection in targets:
            self.send(connection, {"type": "claims", **claims})
            self.send(connection, {"type": "settings", "payload": settings})


LIVE = Live()


class Handler(fake.Handler):
    def _send(self, status: int, body) -> None:
        super()._send(status, body)
        if self.command == "POST" and self.path.startswith("/api/robot"):
            LIVE.broadcast(self.server.state)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.split("?")[0] != "/ws":
            super().do_GET()
            return
        protocols = [p.strip() for p in self.headers.get("Sec-WebSocket-Protocol", "").split(",")]
        key = self.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(hashlib.sha1((key + MAGIC).encode("ascii")).digest()).decode("ascii")
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.send_header("Sec-WebSocket-Protocol", "hydra.bearer")
        self.end_headers()
        self.wfile.flush()
        self.close_connection = True
        state = self.server.state
        with state.lock:
            known = len(protocols) == 2 and protocols[0] == "hydra.bearer" and protocols[1] in state.tokens
            settings = state.settings()[1]
        if not known:
            self.connection.sendall(frame(8, struct.pack(">H", 1008) + b"Access denied"))
            return
        with LIVE.lock:
            LIVE.open.append(self.connection)
        try:
            LIVE.send(self.connection, {"type": "settings", "payload": settings})
            self._read()
        finally:
            with LIVE.lock:
                if self.connection in LIVE.open:
                    LIVE.open.remove(self.connection)

    def _read(self) -> None:
        """Answers pings and ends on a close or a dropped connection."""
        while True:
            head = self.rfile.read(2)
            if len(head) < 2:
                return
            opcode, length = head[0] & 0x0F, head[1] & 0x7F
            if length == 126:
                length = struct.unpack(">H", self.rfile.read(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self.rfile.read(8))[0]
            mask = self.rfile.read(4) if head[1] & 0x80 else b"\0\0\0\0"
            if length > 1_000_000:
                return
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(self.rfile.read(length)))
            with LIVE.lock:
                if opcode == 9:
                    self.connection.sendall(frame(10, payload))
                elif opcode == 8:
                    self.connection.sendall(frame(8, payload))
            if opcode == 8:
                return


def start(port: int = 0, host: str = "127.0.0.1"):
    server = fake.FakeServer((host, port), fake.FakeHydra())
    server.RequestHandlerClass = Handler
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=3000)
    args = parser.parse_args()
    server, thread = start(args.port)
    print(f"bench on http://127.0.0.1:{server.server_address[1]}", flush=True)
    try:
        thread.join()
    except KeyboardInterrupt:
        server.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
