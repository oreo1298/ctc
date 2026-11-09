#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
"""Summarise physics benchmark JSON reports into a Markdown table."""
from __future__ import annotations

import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def main() -> int:
    out_dir = Path(sys.argv[1])
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for p in sorted(out_dir.glob("*-*-*.json")):
        r = json.loads(p.read_text())
        groups[(r["scenario"], r["engine"])].append(r)
    lines = [
        "| scenario | engine | bodies | frame ms mean | p95 | max | max drift (m) "
        "| moved >0.5 m | all asleep at (s) | runs identical |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for (scenario, engine), runs in sorted(groups.items()):
        mean = statistics.mean(r["frame_ms_mean"] for r in runs)
        p95 = statistics.mean(r["frame_ms_p95"] for r in runs)
        mx = max(r["frame_ms_max"] for r in runs)
        drift = max(r["drift_max_m"] for r in runs)
        moved = max(r["moved_over_0_5m"] for r in runs)
        asleep = [r["all_asleep_at_s"] for r in runs]
        same = len({r["final_state_sha256"] for r in runs}) == 1
        asleep_s = "never" if any(a < 0 for a in asleep) else f"{max(asleep):.1f}"
        lines.append(
            f"| {scenario} | {engine} | {runs[0]['bodies']} | {mean:.2f} | {p95:.2f} | {mx:.2f} "
            f"| {drift:.3f} | {moved} | {asleep_s} | {'yes' if same else 'NO'} |"
        )
    text = "\n".join(lines) + "\n"
    (out_dir / "summary.md").write_text(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
