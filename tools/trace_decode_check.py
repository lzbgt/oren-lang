#!/usr/bin/env python3
import binascii
import struct
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: trace_decode_check.py <trace_hex>", file=sys.stderr)
        return 2

    hx = sys.argv[1].strip()
    try:
        b = binascii.unhexlify(hx.encode())
    except Exception as e:
        print(f"invalid hex: {e}", file=sys.stderr)
        return 2

    if b[:8] != b"AVMTRC02":
        print(f"bad trace tag: {b[:8]!r}", file=sys.stderr)
        return 2

    pos = 8
    found_env = False

    while pos < len(b):
        kind = b[pos]
        pos += 1

        if kind == 1:  # STEP
            if pos + 4 + 1 + 2 > len(b):
                return 2
            _pc = struct.unpack_from("<I", b, pos)[0]
            pos += 4
            _op = b[pos]
            pos += 1
            ilen = struct.unpack_from("<H", b, pos)[0]
            pos += 2
            if pos + ilen > len(b):
                return 2
            pos += ilen
        elif kind == 2:  # NATIVE2
            if pos + 4 + 1 + 2 + 1 > len(b):
                return 2
            _pc = struct.unpack_from("<I", b, pos)[0]
            pos += 4
            dom = b[pos]
            pos += 1
            capop = struct.unpack_from("<H", b, pos)[0]
            pos += 2
            _nargs = b[pos]
            pos += 1
            if dom == 7 and capop == 0:
                found_env = True
        elif kind == 3:  # ABORT
            if pos + 4 + 2 > len(b):
                return 2
            _pc = struct.unpack_from("<I", b, pos)[0]
            pos += 4
            _code = struct.unpack_from("<H", b, pos)[0]
            pos += 2
        else:
            print(f"unknown trace event kind {kind}", file=sys.stderr)
            return 2

    if not found_env:
        print("missing ENV env native event (domain=7 op=0)", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

