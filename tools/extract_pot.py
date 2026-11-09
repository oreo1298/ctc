#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
"""Extract translatable strings into game/locale/messages.pot and keep
game/locale/en.po complete (English msgids, identity translations).

Sources:
  * tr("...") and tr_n("...", "...") literals in game/**/*.gd
  * translatable fields of game/data/**/*.json (names, descriptions,
    grievances, taglines)

Usage: extract_pot.py GAME_DIR [--check]
  --check   exit 1 if messages.pot or en.po would change (for CI)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

TR_RE = re.compile(r'\btr\(\s*"((?:[^"\\]|\\.)*)"\s*[),]')
TRN_RE = re.compile(r'\btr_n\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"')
DATA_KEYS = {"name", "description", "grievance", "tagline"}
HEADER = '''# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: CC-BY-SA-4.0
#
# {title}
# Regenerate with `make pot`; do not edit messages.pot by hand.
msgid ""
msgstr ""
"Project-Id-Version: {project}\\n"
{lang}"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\\n"
'''


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def unesc(s: str) -> str:
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def collect(game: Path) -> tuple[dict[str, set[str]], dict[str, tuple[str, set[str]]]]:
    singles: dict[str, set[str]] = {}
    plurals: dict[str, tuple[str, set[str]]] = {}
    for gd in sorted(game.rglob("*.gd")):
        rel = gd.relative_to(game)
        if rel.parts[0] in ("addons", ".godot"):
            continue
        text = gd.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), 1):
            ref = f"{rel}:{lineno}"
            for m in TRN_RE.finditer(line):
                one, many = unesc(m.group(1)), unesc(m.group(2))
                plurals.setdefault(one, (many, set()))[1].add(ref)
            for m in TR_RE.finditer(line):
                singles.setdefault(unesc(m.group(1)), set()).add(ref)
    for js in sorted((game / "data").rglob("*.json")):
        rel = js.relative_to(game)
        if "schemas" in rel.parts:
            continue
        def walk(node: object, path: str) -> None:
            if isinstance(node, dict):
                for k, v in node.items():
                    if k in DATA_KEYS and isinstance(v, str) and v.strip():
                        singles.setdefault(v, set()).add(f"{rel}:{path}/{k}")
                    else:
                        walk(v, f"{path}/{k}")
            elif isinstance(node, list):
                for i, v in enumerate(node):
                    walk(v, f"{path}/{i}")
        walk(json.loads(js.read_text(encoding="utf-8")), "")
    for k in plurals:
        singles.pop(k, None)
    return singles, plurals


def render(singles: dict[str, set[str]], plurals: dict[str, tuple[str, set[str]]], project: str, lang: str | None) -> str:
    title = "Translation template." if lang is None else f"{lang} catalogue (English msgids)."
    out = [HEADER.format(title=title, project=project, lang=f'"Language: {lang}\\n"\n' if lang else "")]
    for msgid in sorted(singles):
        out.append("")
        for ref in sorted(singles[msgid])[:4]:
            out.append(f"#: {ref}")
        if "%" in msgid:
            out.append("#, c-format")
        out.append(f'msgid "{esc(msgid)}"')
        out.append(f'msgstr "{esc(msgid) if lang == "en" else ""}"')
    for one in sorted(plurals):
        many, refs = plurals[one]
        out.append("")
        for ref in sorted(refs)[:4]:
            out.append(f"#: {ref}")
        out.append("#, c-format")
        out.append(f'msgid "{esc(one)}"')
        out.append(f'msgid_plural "{esc(many)}"')
        out.append(f'msgstr[0] "{esc(one) if lang == "en" else ""}"')
        out.append(f'msgstr[1] "{esc(many) if lang == "en" else ""}"')
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if len(argv) >= 2 else 2
    game = Path(argv[1])
    check = "--check" in argv[2:]
    project = "game"
    m = re.search(r'^config/name="([^"]*)"', (game / "project.godot").read_text(), re.M)
    if m:
        project = m.group(1)
    singles, plurals = collect(game)
    outputs = {
        game / "locale" / "messages.pot": render(singles, plurals, project, None),
        game / "locale" / "en.po": render(singles, plurals, project, "en"),
    }
    changed = []
    for path, text in outputs.items():
        old = path.read_text(encoding="utf-8") if path.exists() else ""
        if old != text:
            changed.append(path)
            if not check:
                path.write_text(text, encoding="utf-8")
    n = len(singles) + len(plurals)
    if check and changed:
        print(f"translation catalogues out of date: {', '.join(str(c) for c in changed)}; run `make pot`")
        return 1
    print(f"{n} strings; {'checked' if check else 'wrote'} {len(outputs)} catalogue(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
