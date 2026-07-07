#!/usr/bin/env python3
"""Small network helpers used by verify_libavm_ios.sh."""

from __future__ import annotations

import argparse
import base64
import functools
import hashlib
import http.server
import pathlib
import socket
import socketserver
import sys
import time


def mark_ready(path: str) -> None:
    pathlib.Path(path).write_text("ready\n", encoding="utf-8")


def run_http_fixed(args: argparse.Namespace) -> int:
    body = pathlib.Path(args.body).read_bytes()
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(5)
    mark_ready(args.ready)
    try:
        for _ in range(args.requests):
            conn, _addr = srv.accept()
            try:
                conn.recv(4096)
                header = (
                    b"HTTP/1.1 200 OK\r\n"
                    + b"Content-Type: text/plain\r\n"
                    + b"Content-Length: "
                    + str(len(body)).encode("ascii")
                    + b"\r\nConnection: close\r\n\r\n"
                )
                conn.sendall(header + body)
            finally:
                conn.close()
    finally:
        srv.close()
    return 0


def run_tcp_ping(args: argparse.Namespace) -> int:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(2)
    mark_ready(args.ready)
    try:
        for _ in range(args.requests):
            conn, _addr = srv.accept()
            try:
                if conn.recv(4) == b"ping":
                    conn.sendall(b"pong")
            finally:
                conn.close()
    finally:
        srv.close()
    return 0


def run_udp_ping(args: argparse.Namespace) -> int:
    srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    mark_ready(args.ready)
    try:
        data, addr = srv.recvfrom(16)
        if data == b"ping":
            srv.sendto(b"pong", addr)
    finally:
        srv.close()
    return 0


def recv_exact(conn: socket.socket, n: int) -> bytes:
    out = bytearray()
    while len(out) < n:
        chunk = conn.recv(n - len(out))
        if not chunk:
            raise RuntimeError("short read")
        out.extend(chunk)
    return bytes(out)


def run_ws_echo(args: argparse.Namespace) -> int:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(1)
    mark_ready(args.ready)
    conn, _addr = srv.accept()
    try:
        header = bytearray()
        while b"\r\n\r\n" not in header:
            chunk = conn.recv(1024)
            if not chunk:
                raise RuntimeError("closed before handshake")
            header.extend(chunk)
        key = None
        for line in header.decode("ascii", "strict").split("\r\n"):
            if line.lower().startswith("sec-websocket-key:"):
                key = line.split(":", 1)[1].strip()
                break
        if not key:
            raise RuntimeError("missing websocket key")
        accept = base64.b64encode(
            hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
        ).decode("ascii")
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        )
        conn.sendall(response.encode("ascii"))
        opcode, payload = recv_ws_frame(conn)
        if opcode != 1 or payload != b"ping":
            raise RuntimeError("unexpected websocket text payload")
        conn.sendall(b"\x81\x04pong")
        opcode, payload = recv_ws_frame(conn)
        if opcode != 2 or payload != b"bin!":
            raise RuntimeError("unexpected websocket binary payload")
        conn.sendall(b"\x82\x04bong")
        conn.sendall(b"\x81\x04text")
    finally:
        conn.close()
        srv.close()
    return 0


def recv_ws_frame(conn: socket.socket) -> tuple[int, bytes]:
    h = recv_exact(conn, 2)
    opcode = h[0] & 0x0F
    length = h[1] & 0x7F
    if length == 126:
        ext = recv_exact(conn, 2)
        length = (ext[0] << 8) | ext[1]
    elif length == 127:
        raise RuntimeError("64-bit websocket length unsupported in verifier")
    mask = recv_exact(conn, 4) if (h[1] & 0x80) else b"\x00\x00\x00\x00"
    payload = bytearray(recv_exact(conn, length))
    for i in range(len(payload)):
        payload[i] ^= mask[i & 3]
    return opcode, bytes(payload)


def run_static_http(args: argparse.Namespace) -> int:
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(pathlib.Path(args.root)))
    with socketserver.TCPServer(("127.0.0.1", args.port), handler) as srv:
        mark_ready(args.ready)
        srv.serve_forever()
    return 0


def run_tcp_listen_client(args: argparse.Namespace) -> int:
    last: Exception | None = None
    for _ in range(args.attempts):
        try:
            with socket.create_connection(("127.0.0.1", args.port), timeout=0.2) as s:
                s.sendall(b"ping")
                data = s.recv(4)
                if data != b"pong":
                    raise RuntimeError(f"unexpected response: {data!r}")
                return 0
        except Exception as exc:
            last = exc
            time.sleep(0.05)
    raise SystemExit(f"tcp listen verifier client failed: {last}")


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("http-fixed")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--body", required=True)
    p.add_argument("--ready", required=True)
    p.add_argument("--requests", type=int, default=8)
    p.set_defaults(func=run_http_fixed)

    p = sub.add_parser("tcp-ping")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--ready", required=True)
    p.add_argument("--requests", type=int, default=2)
    p.set_defaults(func=run_tcp_ping)

    p = sub.add_parser("udp-ping")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--ready", required=True)
    p.set_defaults(func=run_udp_ping)

    p = sub.add_parser("ws-echo")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--ready", required=True)
    p.set_defaults(func=run_ws_echo)

    p = sub.add_parser("static-http")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--root", required=True)
    p.add_argument("--ready", required=True)
    p.set_defaults(func=run_static_http)

    p = sub.add_parser("tcp-listen-client")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--attempts", type=int, default=100)
    p.set_defaults(func=run_tcp_listen_client)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
