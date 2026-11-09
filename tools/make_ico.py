#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
"""Pack square PNGs into a Windows .ico (PNG-compressed entries, Vista+).

Usage: make_ico.py OUT.ico IN.png [IN.png ...]
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path


def png_size(data: bytes) -> tuple[int, int]:
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    return struct.unpack(">II", data[16:24])


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    out, inputs = Path(argv[1]), [Path(p) for p in argv[2:]]
    images = []
    for p in inputs:
        data = p.read_bytes()
        w, h = png_size(data)
        if w != h or w > 256:
            raise SystemExit(f"{p}: icons must be square and at most 256 px (got {w}x{h})")
        images.append((w, data))
    images.sort()
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = len(header) + 16 * len(images)
    entries, blobs = b"", b""
    for w, data in images:
        side = 0 if w == 256 else w
        entries += struct.pack("<BBBBHHII", side, side, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
        blobs += data
    out.write_bytes(header + entries + blobs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
