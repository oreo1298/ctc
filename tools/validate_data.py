#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
"""Validate every JSON data file against its JSON Schema.

Each data file names its schema with a relative "$schema" key. Files under a
`schemas/` directory are themselves checked as Draft 2020-12 schemas.
Usage: validate_data.py DATA_DIR
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if len(argv) == 2 else 2
    root = Path(argv[1])
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 2
    failures = 0
    checked = 0
    for path in sorted(root.rglob("*.json")):
        rel = path.relative_to(root)
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"FAIL {rel}: invalid JSON: {exc}")
            failures += 1
            continue
        if "schemas" in rel.parts:
            Draft202012Validator.check_schema(doc)
            checked += 1
            continue
        schema_ref = doc.get("$schema") if isinstance(doc, dict) else None
        if not schema_ref:
            print(f"FAIL {rel}: no \"$schema\" key")
            failures += 1
            continue
        schema_path = (path.parent / schema_ref).resolve()
        if not schema_path.is_file():
            print(f"FAIL {rel}: schema {schema_ref} not found")
            failures += 1
            continue
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        errors = sorted(Draft202012Validator(schema).iter_errors(doc), key=lambda e: list(e.path))
        for e in errors:
            loc = "/".join(str(p) for p in e.path) or "<root>"
            print(f"FAIL {rel}: {loc}: {e.message}")
        failures += len(errors)
        checked += 1
    print(f"validated {checked} file(s), {failures} problem(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
