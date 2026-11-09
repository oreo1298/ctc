#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
"""Merge validator search reports (par + proofs) into the level files.

Usage: apply_report.py GAME_DIR REPORT.json [REPORT.json ...]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    game = Path(argv[1])
    realm_of: dict[str, str] = {}
    for rp in (game / "data" / "realms").glob("*.json"):
        r = json.loads(rp.read_text())
        for lid in r.get("levels", []):
            realm_of[lid] = r["id"]
    applied = 0
    for rep in argv[2:]:
        report = json.loads(Path(rep).read_text())
        for lid, entry in report.items():
            if not entry.get("ok") or "par" not in entry:
                print(f"skip {lid}: {entry.get('error', 'not ok')}")
                continue
            path = game / "data" / "levels" / realm_of[lid] / f"{lid}.json"
            lvl = json.loads(path.read_text())
            par = {k: int(v) for k, v in entry["par"].items()}
            lvl["par"] = {"gold": par["gold"], "silver": par["silver"], "bronze": par["bronze"]}
            lvl.setdefault("par_override", None)
            for key in ("solution", "solution_basic"):
                lvl[key] = [
                    {"ammo": s["ammo"], "phase": round(float(s["phase"]), 4), "tap": round(float(s["tap"]), 3)}
                    for s in entry[key]
                ]
            path.write_text(json.dumps(lvl, indent=2) + "\n")
            applied += 1
    print(f"applied {applied} level(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
