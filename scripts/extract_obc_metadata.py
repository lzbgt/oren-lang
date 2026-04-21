#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


TYPE_NIL = 0
TYPE_INT = 1
TYPE_BOOL = 2
TYPE_FLOAT = 3
TYPE_STRING = 4
TYPE_BYTES = 8

META_PREFIX = b"OREN_META\n1\n"


class ObcFormatError(RuntimeError):
    pass


def read_u8(data: bytes, pos: int) -> tuple[int, int]:
    if pos + 1 > len(data):
        raise ObcFormatError("unexpected EOF while reading u8")
    return data[pos], pos + 1


def read_u16(data: bytes, pos: int) -> tuple[int, int]:
    if pos + 2 > len(data):
        raise ObcFormatError("unexpected EOF while reading u16")
    return int.from_bytes(data[pos:pos + 2], "little"), pos + 2


def read_u32(data: bytes, pos: int) -> tuple[int, int]:
    if pos + 4 > len(data):
        raise ObcFormatError("unexpected EOF while reading u32")
    return int.from_bytes(data[pos:pos + 4], "little"), pos + 4


def read_u64(data: bytes, pos: int) -> tuple[int, int]:
    if pos + 8 > len(data):
        raise ObcFormatError("unexpected EOF while reading u64")
    return int.from_bytes(data[pos:pos + 8], "little"), pos + 8


def read_bytes(data: bytes, pos: int, length: int) -> tuple[bytes, int]:
    if pos + length > len(data):
        raise ObcFormatError(f"unexpected EOF while reading {length} bytes")
    return data[pos:pos + length], pos + length


def find_metadata_constant(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 4 or data[:2] != b"\xcd\x0e":
        raise ObcFormatError("invalid OBC magic")
    n_consts = int.from_bytes(data[2:4], "little")
    pos = 4
    found = None
    for idx in range(n_consts):
        ty, pos = read_u8(data, pos)
        if ty == TYPE_NIL:
            continue
        if ty == TYPE_INT or ty == TYPE_FLOAT:
            _, pos = read_u64(data, pos)
            continue
        if ty == TYPE_BOOL:
            _, pos = read_u8(data, pos)
            continue
        if ty == TYPE_STRING:
            length, pos = read_u16(data, pos)
            _, pos = read_bytes(data, pos, length)
            continue
        if ty == TYPE_BYTES:
            length, pos = read_u32(data, pos)
            blob, pos = read_bytes(data, pos, length)
            if blob.startswith(META_PREFIX):
                if found is not None:
                    raise ObcFormatError("multiple OREN_META constants found")
                payload = blob[len(META_PREFIX):]
                try:
                    metadata = json.loads(payload.decode("utf-8"))
                except Exception as exc:  # pragma: no cover - surfaced as tool error
                    raise ObcFormatError(f"invalid OREN_META JSON: {exc}") from exc
                found = {
                    "schema": "oren.obc.metadata.extract.v1",
                    "obc_path": str(path),
                    "constant_index": idx,
                    "constant_length": length,
                    "metadata": metadata,
                }
            continue
        raise ObcFormatError(f"unsupported constant type tag: {ty}")
    if found is None:
        raise ObcFormatError("OREN_META constant not found")
    return found


def main() -> int:
    ap = argparse.ArgumentParser(description="Extract embedded OREN_META JSON from an .obc file")
    ap.add_argument("obc_path", help="Path to the .obc artifact")
    ap.add_argument("-o", "--out", help="Write extracted JSON to this path instead of stdout")
    args = ap.parse_args()

    result = find_metadata_constant(Path(args.obc_path))
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
