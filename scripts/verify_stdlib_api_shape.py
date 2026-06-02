#!/usr/bin/env python3
"""Guard rolling stdlib API shape against known root-helper regressions."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = ("lib/std", "tests", "examples")
BANNED_TOKENS = (
    "try_get_text",
    "try_get_bytes",
    "try_request",
    "try_recv_text",
    "try_send_text",
    "try_send_text_client",
    "try_send_text_server",
    "try_new",
    "try_connect",
    "try_connect_resolver",
    "try_connect_resolver_opts",
    "try_accept",
    "try_accept_tls_pkcs12",
    "try_parse_url",
    "try_client_key_base64",
    "try_wrap_client",
    "try_wrap_server_pkcs12",
    "try_bind_local",
    "try_listen_local",
    "try_read_into",
    "try_write_from",
    "try_close",
    "try_send_to",
    "try_recv_into",
    "try_recv_from_into",
    "try_sockname_port",
    "try_peer_cert_sha256_hex",
    "try_negotiated_alpn",
    "try_decode",
    "try_encode",
    "try_parse",
    "try_decode_next",
    "try_decode_sequence",
    "try_encode_sequence",
    "try_encode_sequence_typed",
    "try_decode_next_typed",
    "try_decode_sequence_typed",
    "try_encode_bytes",
    "try_decode_bytes",
    "try_decode_bytes_strict",
    "try_compile",
    "try_is_match",
    "try_bytes",
    "try_fill",
    "try_decode_blocks",
    "try_decode_blocks_strict",
    "try_sha256_hex_der",
    "try_datetime_to_unix_ns",
    "try_parse_iso8601_utc",
    "try_decode_header_block",
    "try_encode_header_block",
    "try_parse_frame_header",
    "try_parse_settings_payload",
    "try_write_frame_header",
    "try_parse_hex",
    "try_encode_rgba",
)


def iter_sources() -> list[Path]:
    out: list[Path] = []
    for rel in SCAN_DIRS:
        base = ROOT / rel
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.suffix in {".oren", ".json", ".md"} and path.is_file():
                out.append(path)
    return sorted(out)


def main() -> int:
    token_re = re.compile(r"\b(" + "|".join(re.escape(t) for t in BANNED_TOKENS) + r")\b")
    public_buffer_fn_re = re.compile(r"\bfn\s+(try_[A-Za-z0-9_]+)\b")
    public_buffer_call_re = re.compile(r"\b(buffer\w*)\.(try_[A-Za-z0-9_]+)\b")
    public_bytes_fn_re = re.compile(r"\bfn\s+(try_[A-Za-z0-9_]+)\b")
    public_bytes_call_re = re.compile(r"\b(bytes\w*)\.(try_[A-Za-z0-9_]+)\b")
    public_strings_fn_re = re.compile(r"\bfn\s+(try_[A-Za-z0-9_]+)\b")
    public_strings_call_re = re.compile(r"\b(strings\w*)\.(try_[A-Za-z0-9_]+)\b")
    public_list_fn_re = re.compile(r"\bfn\s+(try_[A-Za-z0-9_]+)\b")
    public_list_call_re = re.compile(r"\b(list\w*)\.(try_[A-Za-z0-9_]+)\b")
    public_int_cast_fn_re = re.compile(r"\bfn\s+(try_[ui](?:8|16|32|64))\b")
    public_int_cast_call_re = re.compile(r"\b(ints|casts)\.(try_[ui](?:8|16|32|64))\b")
    public_mat_proj_fn_re = re.compile(r"\bfn\s+(try_mat_(?:row|col|diag|subview)[A-Za-z0-9_]*)\b")
    failures: list[str] = []
    for path in iter_sources():
        text = path.read_text(encoding="utf-8")
        for line_no, line in enumerate(text.splitlines(), 1):
            match = token_re.search(line)
            if match:
                failures.append(f"{path.relative_to(ROOT)}:{line_no}: banned public fallible helper `{match.group(1)}`")
            rel = path.relative_to(ROOT).as_posix()
            if rel == "lib/std/buffer.oren":
                buffer_fn = public_buffer_fn_re.search(line)
                if buffer_fn:
                    failures.append(f"{rel}:{line_no}: banned public buffer helper `{buffer_fn.group(1)}`")
            if rel == "lib/std/bytes.oren":
                bytes_fn = public_bytes_fn_re.search(line)
                if bytes_fn:
                    failures.append(f"{rel}:{line_no}: banned public bytes helper `{bytes_fn.group(1)}`")
            if rel == "lib/std/strings.oren":
                strings_fn = public_strings_fn_re.search(line)
                if strings_fn:
                    failures.append(f"{rel}:{line_no}: banned public strings helper `{strings_fn.group(1)}`")
            if rel == "lib/std/list.oren":
                list_fn = public_list_fn_re.search(line)
                if list_fn:
                    failures.append(f"{rel}:{line_no}: banned public list helper `{list_fn.group(1)}`")
            if rel in {"lib/std/ints.oren", "lib/std/casts.oren"}:
                int_cast_fn = public_int_cast_fn_re.search(line)
                if int_cast_fn:
                    failures.append(f"{rel}:{line_no}: banned public checked cast helper `{int_cast_fn.group(1)}`")
            if rel == "lib/std/buffer/mat_proj.oren":
                mat_proj_fn = public_mat_proj_fn_re.search(line)
                if mat_proj_fn:
                    failures.append(f"{rel}:{line_no}: banned public matrix projection helper `{mat_proj_fn.group(1)}`")
            if not rel.startswith("lib/std/buffer/"):
                buffer_call = public_buffer_call_re.search(line)
                if buffer_call:
                    failures.append(f"{rel}:{line_no}: banned buffer call `{buffer_call.group(1)}.{buffer_call.group(2)}`")
            bytes_call = public_bytes_call_re.search(line)
            if bytes_call:
                failures.append(f"{rel}:{line_no}: banned bytes call `{bytes_call.group(1)}.{bytes_call.group(2)}`")
            strings_call = public_strings_call_re.search(line)
            if strings_call:
                failures.append(f"{rel}:{line_no}: banned strings call `{strings_call.group(1)}.{strings_call.group(2)}`")
            list_call = public_list_call_re.search(line)
            if list_call:
                failures.append(f"{rel}:{line_no}: banned list call `{list_call.group(1)}.{list_call.group(2)}`")
            int_cast_call = public_int_cast_call_re.search(line)
            if int_cast_call:
                failures.append(f"{rel}:{line_no}: banned checked cast call `{int_cast_call.group(1)}.{int_cast_call.group(2)}`")

    if failures:
        print("stdlib API shape guard failed:")
        for failure in failures:
            print(failure)
        print("Use scoped/object APIs and normal fallible verbs returning value | oren_err; keep errno contracts under *_raw.")
        return 1

    print("OK: stdlib API shape guard passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
