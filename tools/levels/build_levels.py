#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
"""Campaign level designs (72 levels, 6 realms).

Each level is a short function written with building primitives that make
blocks touch exactly (no overlaps, no gaps), so castles stand still until
hit. Output is plain level JSON (docs/LEVEL_FORMAT.md) in
game/data/levels/<realm>/<id>.json, plus each realm's ordered level list.
Par and proofs are added afterwards by the validator bot
(`make validate-levels`), which this script preserves when regenerating.

Usage: build_levels.py GAME_DIR [--only ID]
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ENEMY_HALF = {"king": 0.55, "queen": 0.55, "knight": 0.575, "hostage": 0.5}


class L:
    def __init__(self, lid: str, realm: str, name: str, grievance: str, time: str, right: float = 52.0,
                 wind: float = 0.0):
        self.d = {
            "$schema": "../../schemas/level.schema.json",
            "format": "level",
            "version": 1,
            "id": lid,
            "name": name,
            "grievance": grievance,
            "time_of_day": time,
            "realm": realm,
            "world": {"right": right, "kill_y": -10},
            "trebuchet": {"x": 0, "y": 0},
            "terrain": [],
            "blocks": [],
            "enemies": [],
        }
        if wind:
            # m/s along +x: positive is a tailwind towards the castle.
            self.d["wind"] = wind
        self.style = {"greenmantle": "grass", "saffron": "sand", "frostfang": "snow",
                      "mirefen": "grass", "cinderreach": "rock", "skyreach": "rock"}[realm]

    # ----- terrain -----
    def ground(self, *points: tuple[float, float]) -> "L":
        self.d["terrain"].append({"points": [[round(x, 3), round(y, 3)] for x, y in points], "style": self.style})
        return self

    def flat(self, y: float = 0.0) -> "L":
        return self.ground((-24, 0), (21, 0), (24.5, y), (90, y)) if y else self.ground((-24, 0), (90, 0))

    # ----- blocks -----
    def rect(self, cx: float, cy: float, w: float, h: float, mat: str, rot: float = 0.0,
             static: bool = False) -> None:
        b = {"shape": "rect", "material": mat, "pos": [round(cx, 3), round(cy, 3)], "size": [round(w, 3), round(h, 3)]}
        if rot:
            b["rot"] = rot
        if static:
            b["static"] = True
        self.d["blocks"].append(b)

    def ledge(self, x0: float, x1: float, top: float, h: float = 0.5, mat: str = "stone") -> float:
        """An anchored (static, unbreakable) shelf, e.g. bolted to a cliff face."""
        self.rect((x0 + x1) / 2, top - h / 2, x1 - x0, h, mat, static=True)
        return top

    def casks(self, x0: float, base: float, n: int = 1) -> float:
        """A row of `n` touching powder casks from x0; returns the row's right end."""
        for i in range(n):
            self.rect(x0 + 0.4 + 0.8 * i, base + 0.45, 0.8, 0.9, "powder")
        return x0 + 0.8 * n

    def col(self, x: float, base: float, w: float, h: float, mat: str) -> float:
        """Upright block centred on x, bottom at `base`. Returns its top."""
        self.rect(x, base + h / 2, w, h, mat)
        return base + h

    def beam(self, x0: float, x1: float, base: float, h: float, mat: str) -> float:
        self.rect((x0 + x1) / 2, base + h / 2, x1 - x0, h, mat)
        return base + h

    def room(self, x0: float, x1: float, base: float, h: float, wall: str, floor: str,
             wall_w: float = 0.3, floor_h: float = 0.3) -> float:
        """Two pillars and a lintel; returns the top of the lintel."""
        self.col(x0 + wall_w / 2, base, wall_w, h, wall)
        self.col(x1 - wall_w / 2, base, wall_w, h, wall)
        return self.beam(x0, x1, base + h, floor_h, floor)

    def roof(self, x0: float, x1: float, base: float, h: float, mat: str) -> float:
        self.d["blocks"].append({"shape": "tri", "material": mat,
                                 "pos": [round((x0 + x1) / 2, 3), round(base + h / 2, 3)],
                                 "size": [round(x1 - x0, 3), round(h, 3)]})
        return base + h

    def stack(self, x: float, base: float, w: float, h: float, n: int, mat: str) -> float:
        for _ in range(n):
            base = self.col(x, base, w, h, mat)
        return base

    def wall(self, x0: float, x1: float, base: float, h: float, mat: str, rows: int = 2, cols: int = 1) -> float:
        rh = h / rows
        cw = (x1 - x0) / cols
        for r in range(rows):
            off = (cw / 2) if (r % 2 and cols > 1) else 0.0
            xs = [x0 + c * cw for c in range(cols)]
            if off:
                xs = [x0] + [x0 + off + c * cw for c in range(cols - 1)] + [x1 - off]
                widths = [off] + [cw] * (cols - 1) + [off]
            else:
                widths = [cw] * cols
            x = x0
            for w in widths:
                self.rect(x + w / 2, base + rh * r + rh / 2, w, rh, mat)
                x += w
        return base + h

    def tower(self, x: float, base: float, w: float, levels: int, mat: str, floor: str, h: float = 1.6,
              wall_w: float = 0.35) -> float:
        for _ in range(levels):
            base = self.room(x - w / 2, x + w / 2, base, h, mat, floor, wall_w)
        return base

    # ----- people -----
    def put(self, kind: str, x: float, base: float, flip: bool = False) -> None:
        e = {"type": kind, "pos": [round(x, 3), round(base + ENEMY_HALF[kind], 3)]}
        if flip:
            e["flip"] = True
        self.d["enemies"].append(e)


# ======================================================== Greenmantle ===
def g01() -> L:
    # Kept as designed for the vertical slice (hand-written JSON).
    return None  # type: ignore[return-value]


def g02() -> L:
    l = L("greenmantle-02", "greenmantle", "A Taller Tower",
          "Lord Ashby's tower is taller than mine. Shorten it. From the top.", "morning").flat()
    top = l.tower(30, 0, 2.4, 3, "wood", "wood", 1.5)
    l.roof(28.6, 31.4, top, 1.0, "wood")
    l.put("king", 30, 1.8 + 1.8)
    return l


def g03() -> L:
    l = L("greenmantle-03", "greenmantle", "Two Thrones",
          "The Duke and Duchess of Fennick sit on matching thrones. Matching!", "noon").flat()
    for x, who in [(27.5, "king"), (33.5, "queen")]:
        top = l.room(x - 1.6, x + 1.6, 0, 1.7, "stone", "wood", 0.4)
        l.roof(x - 1.7, x + 1.7, top, 0.9, "wood")
        l.put(who, x, 0)
    l.col(30.5, 0, 0.6, 1.0, "stone")
    return l


def g04() -> L:
    l = L("greenmantle-04", "greenmantle", "Scattered Thoughts",
          "Sir Pellam's picnic was lovely. I wasn't invited. Scatter it.", "afternoon").flat()
    for i, who in enumerate(["king", "queen", "knight"]):
        x = 26 + i * 4.2
        top = l.room(x - 1.3, x + 1.3, 0, 1.6, "wood", "wood", 0.25, 0.25)
        l.roof(x - 1.4, x + 1.4, top, 0.8, "thatch")
        l.put(who, x, 0)
    return l


def g05() -> L:
    l = L("greenmantle-05", "greenmantle", "Tin Cans",
          "Baron Mudge hired knights. Real ones. With hats.", "morning").flat()
    l.wall(25.0, 25.8, 0, 1.6, "stone", rows=2)
    top = l.room(27, 31, 0, 1.6, "stone", "wood", 0.4)
    l.room(27.6, 30.4, top, 1.5, "wood", "wood", 0.3)
    l.put("knight", 28.2, 0)
    l.put("knight", 29.8, 0, True)
    l.put("king", 29, top)
    l.wall(32.2, 33.0, 0, 1.6, "stone", rows=2)
    return l


def g06() -> L:
    l = L("greenmantle-06", "greenmantle", "Thatch Me If You Can",
          "The Thane of Lowmoor thatched his roof in gold straw. Show-off.", "noon").flat()
    top = l.room(26, 31, 0, 1.7, "wood", "wood", 0.3)
    l.roof(25.8, 31.2, top, 1.4, "thatch")
    l.put("king", 27.6, 0)
    l.put("queen", 29.4, 0)
    top2 = l.room(32.5, 35.5, 0, 2.6, "stone", "wood", 0.4)
    l.roof(32.4, 35.6, top2, 1.2, "thatch")
    l.put("knight", 34, 0)
    return l


def g07() -> L:
    l = L("greenmantle-07", "greenmantle", "King of the Hill",
          "Earl Brask built on a hill so he could look down on me. Literally.", "afternoon", 56)
    l.ground((-24, 0), (20, 0), (26, 3.0), (40, 3.0), (46, 0.5), (90, 0.5))
    top = l.room(28.5, 33.5, 3.0, 1.8, "stone", "stone", 0.45, 0.4)
    top = l.room(29.2, 32.8, top, 1.6, "wood", "wood", 0.3)
    l.roof(29.0, 33.0, top, 1.0, "wood")
    l.put("king", 30.2, 3.0 + 1.8 + 0.4)
    l.put("knight", 31, 3.0)
    l.col(36.5, 3.0, 0.6, 1.4, "stone")
    l.put("queen", 38, 3.0)
    return l


def g08() -> L:
    l = L("greenmantle-08", "greenmantle", "Flying Colours",
          "Lady Vane's banners are brighter than mine. Make them flutter. Downwards.", "golden").flat()
    for x in (26.5, 29.5, 32.5):
        l.col(x, 0, 0.3, 3.6, "wood")
        l.rect(x + 0.55, 2.9, 0.8, 1.2, "cloth")
    top = l.beam(26.35, 32.65, 3.6, 0.3, "wood")
    l.roof(26.2, 32.8, top, 1.0, "cloth")
    l.put("king", 28, 0)
    l.put("queen", 31, 0)
    l.put("knight", 34.5, 0)
    l.col(35.5, 0, 0.5, 1.8, "stone")
    return l


def g09() -> L:
    l = L("greenmantle-09", "greenmantle", "Heavy Heart",
          "Count Orlo's palisade is so thick, he says nothing gets through. We'll see.", "dusk").flat()
    for i in range(6):
        l.col(25.2 + i * 0.5, 0, 0.5, 3.4, "wood")
    top = l.room(28.4, 32.6, 0, 1.8, "wood", "wood", 0.35)
    top = l.room(28.8, 32.2, top, 1.6, "wood", "wood", 0.3)
    l.roof(28.6, 32.4, top, 0.9, "wood")
    l.put("knight", 30.5, 0)
    l.put("king", 30.5, 1.8 + 0.3)
    return l


def g10() -> L:
    l = L("greenmantle-10", "greenmantle", "The Gatehouse",
          "Sir Tobble's gatehouse has a portcullis. Mine has a curtain.", "morning", 56).flat()
    l.stack(25, 0, 1.0, 0.8, 4, "stone")
    l.stack(29, 0, 1.0, 0.8, 4, "stone")
    top = l.beam(24.5, 29.5, 3.2, 0.5, "stone")
    l.room(25.5, 28.5, top, 1.5, "wood", "wood", 0.3)
    l.put("knight", 27, 0)
    l.put("king", 27, top)
    # The lord's house, well behind the gate.
    top = l.room(41, 45, 0, 1.8, "stone", "stone", 0.5, 0.4)
    l.roof(40.9, 45.1, top, 1.0, "thatch")
    l.put("queen", 43, 0)
    return l


def g11() -> L:
    l = L("greenmantle-11", "greenmantle", "Twin Keeps",
          "The Brothers Hale each built a keep. Two insults for the price of one.", "golden", 56).flat()
    for x in (24.5, 42.5):
        t = l.tower(x, 0, 2.6, 2, "stone", "wood", 1.6, 0.45)
        l.roof(x - 1.4, x + 1.4, t, 0.9, "thatch")
        l.put("knight", x, 0)
        l.put("king", x, 1.6 + 0.3)
    return l


def g12() -> L:
    l = L("greenmantle-12", "greenmantle", "Greenmantle Keep",
          "My cousin Wendel claims the Greenmantle crown. My crown. Flatten his keep.", "dusk", 58)
    l.ground((-24, 0), (20, 0), (23, 1.0), (62, 1.0), (90, 1.0))
    l.wall(24.5, 25.5, 1.0, 2.0, "stone", rows=3)
    base = 1.0
    t1 = l.room(27, 33, base, 1.8, "stone", "stone", 0.5, 0.4)
    t2 = l.room(27.5, 32.5, t1, 1.7, "stone", "wood", 0.45)
    t3 = l.room(28.3, 31.7, t2, 1.5, "wood", "wood", 0.3)
    l.roof(28, 32, t3, 1.1, "thatch")
    l.put("knight", 28.6, base)
    l.put("knight", 31.4, base, True)
    l.put("queen", 30, t1)
    l.put("king", 30, t2)
    # Wendel's own tower, out at the edge of the hill.
    t = l.tower(45, base, 2.2, 2, "stone", "wood", 1.6, 0.4)
    l.roof(43.8, 46.2, t, 1.0, "thatch")
    l.put("king", 45, base + 1.6 + 0.3)
    return l

# ============================================================ Saffron ===
def s01() -> L:
    l = L("saffron-01", "saffron", "Powder Day",
          "The Sultan of Saffron sent me sand in a box. Return the favour, with interest.", "noon").flat()
    top = l.room(27, 31.5, 0, 1.7, "stone", "stone", 0.6, 0.5)
    l.room(27.6, 30.9, top, 1.5, "stone", "stone", 0.5, 0.4)
    l.put("king", 29.25, 0)
    l.put("knight", 29.25, top)
    return l



def s02() -> L:
    l = L("saffron-02", "saffron", "Glass Houses",
          "The Vizier's glass palace sparkles at me every morning. Rude.", "afternoon").flat()
    for x, who in [(27, "queen"), (31.5, "king")]:
        top = l.room(x - 1.5, x + 1.5, 0, 1.8, "glass", "glass", 0.3, 0.3)
        l.roof(x - 1.6, x + 1.6, top, 0.9, "glass")
        l.put(who, x, 0)
    l.col(34.5, 0, 0.5, 2.4, "stone")
    l.put("knight", 35.6, 0)
    return l


def s03() -> L:
    l = L("saffron-03", "saffron", "Market Day",
          "Every stall at the Saffron market sells my portrait. Upside down.", "noon").flat()
    for i, who in enumerate(["king", "queen", "knight", "king"]):
        x = 25.5 + i * 3.4
        l.col(x - 1.2, 0, 0.25, 2.0, "wood")
        l.col(x + 1.2, 0, 0.25, 2.0, "wood")
        l.beam(x - 1.4, x + 1.4, 2.0, 0.15, "cloth")
        l.put(who, x, 0)
    return l


def s04() -> L:
    l = L("saffron-04", "saffron", "Mind the Guests",
          "Emir Qadir keeps my favourite baker hostage. Careful: I want my pastries.", "afternoon").flat()
    top = l.room(26, 30, 0, 1.7, "stone", "wood", 0.45)
    l.roof(25.9, 30.1, top, 0.9, "cloth")
    l.put("king", 27.2, 0)
    l.put("hostage", 28.8, 0)
    top = l.room(32, 35.4, 0, 1.7, "stone", "wood", 0.45)
    l.put("knight", 33.7, 0)
    l.put("queen", 33.7, top)
    return l


def s05() -> L:
    l = L("saffron-05", "saffron", "Fire Sale",
          "The timber baron of Saffron sells wood to my enemies. Light up his life.", "dusk").flat()
    t = l.tower(27.5, 0, 3.0, 3, "wood", "wood", 1.6, 0.3)
    l.roof(25.9, 29.1, t, 1.0, "thatch")
    l.put("king", 27.5, 1.9)
    l.put("queen", 27.5, 3.8)
    l.put("knight", 27.5, 0)
    l.put("hostage", 31.5, 0)
    return l


def s06() -> L:
    l = L("saffron-06", "saffron", "Sandstone Steps",
          "Pharaoh-ish Pteran built a pyramid. I didn't even know we had pyramids.", "golden").flat()
    widths = [7.0, 5.4, 3.8, 2.2]
    base = 0.0
    for i, w in enumerate(widths):
        x0 = 31 - w / 2
        n = max(1, int(round(w / 1.1)))
        cw = w / n
        for c in range(n):
            l.rect(x0 + cw * c + cw / 2, base + 0.4, cw, 0.8, "stone")
        base += 0.8
        if i == 1:
            l.put("knight", 31 - 2.0, base)
    l.put("king", 31, base)
    l.put("hostage", 31 + 1.7, 1.6)
    return l


def s07() -> L:
    l = L("saffron-07", "saffron", "Iron Gate",
          "The Gatekeeper of Qal'at put iron on his gate. I put iron on my lunch.", "noon", 56).flat()
    l.col(25, 0, 0.5, 2.2, "iron")
    l.col(26.2, 0, 0.5, 2.2, "iron")
    l.beam(24.75, 26.45, 2.2, 0.4, "iron")
    top = l.room(28, 32, 0, 1.8, "stone", "wood", 0.45)
    l.roof(27.9, 32.1, top, 0.9, "cloth")
    l.put("knight", 29.2, 0)
    l.put("hostage", 30.8, 0)
    l.wall(41, 42, 0, 2.4, "stone", rows=3)
    top = l.room(43, 46, 0, 1.8, "stone", "stone", 0.45, 0.4)
    l.put("king", 44.5, 0)
    return l


def s08() -> L:
    l = L("saffron-08", "saffron", "Lantern Row",
          "Prince Idris lights a thousand lanterns every night just to keep me awake.", "night").flat()
    # Stalls: two poles, a beam, a glass lantern on top, a cloth canopy.
    for i, who in enumerate(["king", "hostage", "queen", "knight"]):
        x = 26 + i * 3.2
        top = l.room(x - 1.3, x + 1.3, 0, 2.2, "wood", "wood", 0.25, 0.2)
        l.col(x - 0.7, top, 0.5, 0.5, "glass")
        l.roof(x - 0.2, x + 1.3, top, 0.6, "cloth")
        l.put(who, x, 0)
    return l


def s09() -> L:
    l = L("saffron-09", "saffron", "Chain Reaction",
          "The Silk Merchant's tower is held up by sheer silk. And pride.", "afternoon").flat()
    for x in (27, 28.8, 30.6, 32.4):
        l.col(x, 0, 0.25, 3.0, "wood")
    top = l.beam(26.8, 32.6, 3.0, 0.3, "wood")
    for x in (27.9, 29.7, 31.5):
        l.rect(x, 1.5, 1.5, 2.8, "cloth")
    t2 = l.room(27.5, 32, top, 1.6, "wood", "wood", 0.3)
    l.roof(27.4, 32.1, t2, 0.9, "cloth")
    l.put("king", 29.7, top)
    l.put("queen", 30.9, top)
    l.put("hostage", 34.5, 0)
    return l


def s10() -> L:
    l = L("saffron-10", "saffron", "The Oasis Palace",
          "The Caliph's oasis has fountains. My well has frogs.", "golden", 58)
    l.ground((-24, 0), (20, 0), (24, 2.5), (36, 2.5), (39, 0), (90, 0))
    top = l.room(26, 32, 2.5, 1.8, "stone", "stone", 0.5, 0.4)
    l.room(26.6, 31.4, top, 1.6, "glass", "wood", 0.3)
    l.put("king", 27.6, top)
    l.put("hostage", 29, 2.5)
    # The Caliph's summer tent by the water.
    l.col(43, 0, 0.3, 2.0, "wood")
    l.col(46, 0, 0.3, 2.0, "wood")
    l.roof(42.6, 46.4, 2.0, 1.0, "cloth")
    l.put("queen", 44.5, 0)
    l.col(41.5, 0, 0.6, 1.6, "stone")
    return l


def s11() -> L:
    l = L("saffron-11", "saffron", "Minarets",
          "The Twin Minarets of Zahir are so tall they shade my garden. At noon.", "dusk", 56).flat()
    for x, who in [(25, "king"), (44, "queen")]:
        t = l.stack(x, 0, 1.6, 1.0, 5, "stone")
        l.room(x - 0.8, x + 0.8, t, 1.4, "wood", "wood", 0.25, 0.25)
        l.put(who, x, t)
    top = l.room(33, 36, 0, 1.7, "stone", "cloth", 0.4, 0.2)
    l.put("hostage", 34.5, 0)
    l.put("knight", 34.5, top)
    return l


def s12() -> L:
    l = L("saffron-12", "saffron", "The Sultan's Fortress",
          "The Sultan of Saffron returned my sand. Lightly used. This means war.", "night", 60)
    l.ground((-24, 0), (21, 0), (24, 1.2), (64, 1.2), (90, 1.2))
    b = 1.2
    l.col(25, b, 0.6, 2.2, "iron")
    t1 = l.room(27, 34, b, 1.8, "stone", "stone", 0.55, 0.45)
    t2 = l.room(27.8, 33.2, t1, 1.7, "stone", "wood", 0.45)
    t3 = l.room(28.6, 32.4, t2, 1.5, "glass", "wood", 0.3)
    l.roof(28.4, 32.6, t3, 1.0, "cloth")
    l.put("knight", 28.2, b)
    l.put("hostage", 30.5, b)
    l.put("knight", 32.8, b, True)
    l.put("queen", 30.5, t1)
    l.put("king", 30.5, t2)
    t = l.tower(46, b, 2.0, 2, "stone", "wood", 1.6, 0.45)
    l.roof(44.9, 47.1, t, 0.9, "cloth")
    l.put("knight", 46, b)
    l.put("king", 46, b + 1.6 + 0.3)
    return l

# ========================================================== Frostfang ===
def f01() -> L:
    l = L("frostfang-01", "frostfang", "Cold Reception",
          "The Ice Margrave froze my envoy. Well, the envoy's soup. Same thing.", "dawn").flat()
    top = l.room(27, 31, 0, 1.8, "stone", "stone", 0.55, 0.45)
    l.room(27.6, 30.4, top, 1.5, "ice", "ice", 0.35)
    l.put("knight", 29, 0)
    l.put("king", 29, top)
    return l



def f02() -> L:
    l = L("frostfang-02", "frostfang", "Slippery Slope",
          "Jarl Ingmar's hall is built on ice. On purpose. Help him slide.", "morning").flat()
    for x in (26, 30, 34):
        top = l.room(x - 1.3, x + 1.3, 0, 1.6, "ice", "ice", 0.4, 0.35)
        l.roof(x - 1.4, x + 1.4, top, 0.8, "ice")
    l.put("king", 26, 0)
    l.put("hostage", 30, 0)
    l.put("queen", 34, 0)
    return l


def f03() -> L:
    l = L("frostfang-03", "frostfang", "Brittle Bones",
          "Old Lord Rime boasts his stone never breaks. Ice it, then break it.", "noon").flat()
    top = l.room(26.5, 32.5, 0, 1.9, "stone", "stone", 0.7, 0.6)
    l.room(27.4, 31.6, top, 1.6, "stone", "stone", 0.55, 0.5)
    l.put("knight", 28.2, 0)
    l.put("king", 30.8, 0)
    l.put("queen", 29.5, top)
    return l


def f04() -> L:
    l = L("frostfang-04", "frostfang", "Iron Will",
          "Baroness Steelbrow wears iron underwear. Allegedly. Find out.", "afternoon").flat()
    l.col(25.5, 0, 0.5, 2.0, "iron")
    top = l.room(27, 31.5, 0, 1.8, "iron", "iron", 0.4, 0.35)
    l.room(27.6, 30.9, top, 1.6, "wood", "wood", 0.3)
    l.put("knight", 28.4, 0)
    l.put("knight", 30.1, 0, True)
    l.put("queen", 29.25, top)
    l.put("hostage", 33.5, 0)
    return l


def f05() -> L:
    l = L("frostfang-05", "frostfang", "Overhang",
          "The Cliff Earl's balcony hangs over the void. Like his debts.", "dusk", 56)
    l.ground((-24, 0), (22, 0), (25, 3.0), (33, 3.0), (33.5, -6), (60, -6))
    l.col(28, 3.0, 0.6, 2.0, "stone")
    l.col(32.4, 3.0, 0.6, 2.0, "stone")
    top = l.beam(27.0, 35.5, 5.0, 0.4, "wood")
    l.room(32.0, 35.4, top, 1.6, "wood", "wood", 0.3)
    l.put("king", 33.7, top)
    l.put("knight", 30.2, 3.0)
    return l


def f06() -> L:
    l = L("frostfang-06", "frostfang", "Hall of Mirrors",
          "Princess Glimm's hall of mirrors reflects my face. Repeatedly. Stop it.", "night").flat()
    for x, who in [(26, "queen"), (30, "hostage"), (34, "king")]:
        top = l.room(x - 1.4, x + 1.4, 0, 1.7, "glass", "ice", 0.3, 0.3)
        l.roof(x - 1.5, x + 1.5, top, 0.8, "glass")
        l.put(who, x, 0)
    return l


def f07() -> L:
    l = L("frostfang-07", "frostfang", "Into the Void",
          "Grand Duke Varn's fortress is iron, stone and ego. Swallow it whole.", "dawn").flat()
    l.wall(25, 26, 0, 2.4, "iron", rows=3)
    top = l.room(27.5, 32.5, 0, 1.9, "stone", "iron", 0.6, 0.45)
    t2 = l.room(28.2, 31.8, top, 1.6, "stone", "stone", 0.5, 0.45)
    l.roof(28.0, 32.0, t2, 1.0, "stone")
    l.put("knight", 29, 0)
    l.put("king", 31, 0)
    l.put("queen", 30, top)
    l.wall(33.5, 34.5, 0, 2.4, "iron", rows=3)
    return l


def f08() -> L:
    l = L("frostfang-08", "frostfang", "Avalanche",
          "The Hermit King lives atop an icy crag and refuses to come down. Assist.", "morning", 56)
    l.ground((-24, 0), (22, 0), (27, 4.0), (35, 4.0), (40, 0.0), (90, 0))
    top = l.stack(29, 4.0, 2.0, 0.9, 3, "ice")
    top = l.room(28, 30, top, 1.5, "ice", "ice", 0.3, 0.3)
    l.put("king", 29, top - 0.3 - 1.5)
    l.col(32.5, 4.0, 0.5, 1.6, "stone")
    l.put("knight", 33.6, 4.0)
    return l


def f09() -> L:
    l = L("frostfang-09", "frostfang", "Mixed Blessings",
          "Countess Vey's castle uses every material. Every. Single. One.", "golden", 56).flat()
    t1 = l.room(25, 31, 0, 1.8, "stone", "iron", 0.5, 0.35)
    t2 = l.room(25.6, 30.4, t1, 1.6, "wood", "wood", 0.3)
    t3 = l.room(26.4, 29.6, t2, 1.5, "glass", "ice", 0.3, 0.3)
    l.roof(26.3, 29.7, t3, 0.9, "thatch")
    l.put("knight", 26.5, 0)
    l.put("hostage", 29.5, 0)
    l.put("king", 28, t2)
    top = l.room(42, 45.5, 0, 1.8, "ice", "iron", 0.4, 0.35)
    l.roof(41.9, 45.6, top, 0.9, "cloth")
    l.put("queen", 43.75, 0)
    return l


def f10() -> L:
    l = L("frostfang-10", "frostfang", "The Bridge",
          "The Bridge Lord charges me a toll. A toll! Me!", "dusk", 58)
    l.ground((-24, 0), (24, 0), (26, 2.0), (28, 2.0), (28.2, -8), (90, -8))
    l.ground((36.0, -8), (36.2, 2.0), (50, 2.0), (52, 0), (90, 0))
    top = l.beam(27.2, 37.0, 2.0, 0.4, "wood")
    l.room(30, 34, top, 1.6, "wood", "ice", 0.3)
    l.put("knight", 31, top)
    l.put("hostage", 33, top)
    top = l.room(44, 47.5, 2.0, 1.8, "stone", "stone", 0.45, 0.4)
    l.put("king", 45.75, 2.0)
    return l


def f11() -> L:
    l = L("frostfang-11", "frostfang", "Peak Watch",
          "Old Admiral Frost watches my kingdom from his tower. With a telescope.", "night", 56).flat()
    t = l.tower(27, 0, 2.2, 4, "stone", "wood", 1.6, 0.4)
    t = l.room(25.8, 28.2, t, 1.5, "ice", "ice", 0.3)
    l.roof(25.6, 28.4, t, 1.0, "iron")
    l.put("knight", 27, 0)
    l.put("hostage", 27, 1.6 + 0.3)
    l.put("king", 27, 4 * 1.9)
    top = l.room(43, 46, 0, 1.8, "stone", "stone", 0.45, 0.4)
    l.roof(42.9, 46.1, top, 0.9, "iron")
    l.put("queen", 44.5, 0)
    return l


def f12() -> L:
    l = L("frostfang-12", "frostfang", "The Frostfang Citadel",
          "The last of my rivals sits in the coldest castle of all. Warm him up. Then down.", "night", 62)
    l.ground((-24, 0), (21, 0), (24, 1.5), (64, 1.5), (90, 1.5))
    b = 1.5
    l.wall(24.5, 25.5, b, 2.4, "iron", rows=3)
    t1 = l.room(27, 35, b, 1.9, "stone", "iron", 0.6, 0.45)
    t2 = l.room(27.8, 34.2, t1, 1.7, "stone", "stone", 0.5, 0.45)
    t3 = l.room(28.8, 33.2, t2, 1.6, "ice", "wood", 0.35)
    l.roof(28.6, 33.4, t3, 1.1, "glass")
    l.put("knight", 28.3, b)
    l.put("hostage", 31, b)
    l.put("knight", 33.7, b, True)
    l.put("queen", 30, t1)
    l.put("king", 32, t1)
    l.put("king", 31, t2)
    t = l.tower(47, b, 2.0, 3, "stone", "iron", 1.5, 0.45)
    l.roof(45.9, 48.1, t, 0.9, "glass")
    l.put("knight", 47, b)
    l.put("hostage", 47, b + 1.5 + 0.3)
    l.put("king", 47, b + 2 * (1.5 + 0.3))
    return l

# ============================================================ Mirefen ===
# Bog pits (shallow drops), stilt houses, powder in the cellars, light wind.
def m01() -> L:
    l = L("mirefen-01", "mirefen", "Damp Squib",
          "Baron Bogg keeps his gunpowder under his throne. Someone should tell him why that's a bad idea.",
          "dawn").flat()
    t = l.room(26, 30.4, 0, 1.8, "stone", "stone", 0.4, 0.3)
    l.casks(26.6, 0, 4)
    l.room(26.6, 29.8, t, 1.6, "wood", "wood", 0.3)
    l.put("king", 28.2, t)
    top = l.room(37, 40, 0, 1.6, "wood", "wood", 0.3)
    l.roof(36.9, 40.1, top, 0.9, "thatch")
    l.put("knight", 38.5, 0)
    return l


def m02() -> L:
    l = L("mirefen-02", "mirefen", "On Stilts",
          "The Fen Reeve built his house on stilts so the frogs can't reach him. Neither can I. Yet.",
          "morning", wind=1.5)
    l.ground((-24, 0), (22, 0), (23, -2.5), (41, -2.5), (42, 0), (90, 0))
    for x, who in [(26, "king"), (32, "queen"), (38, "knight")]:
        l.col(x - 1.0, -2.5, 0.25, 3.5, "wood")
        l.col(x + 1.0, -2.5, 0.25, 3.5, "wood")
        t = l.beam(x - 1.2, x + 1.2, 1.0, 0.25, "wood")
        top = l.room(x - 1.1, x + 1.1, t, 1.5, "wood", "wood", 0.25, 0.25)
        l.roof(x - 1.2, x + 1.2, top, 0.8, "thatch")
        l.put(who, x, t)
    return l


def m03() -> L:
    l = L("mirefen-03", "mirefen", "Cellar Door",
          "Lord Mossgrave keeps powder in his cellar and his mother-in-law in the attic. Mind the attic.",
          "noon", wind=2.0).flat()
    l.wall(24.5, 25.5, 0, 2.4, "stone", rows=3)
    t1 = l.room(27, 32, 0, 1.8, "stone", "stone", 0.5, 0.4)
    l.casks(27.6, 0, 2)
    l.put("king", 30.6, 0)
    t2 = l.room(27.6, 31.4, t1, 1.6, "stone", "wood", 0.4)
    l.put("queen", 29.5, t1)
    t3 = l.room(28.2, 30.8, t2, 1.4, "wood", "wood", 0.25, 0.25)
    l.roof(28.0, 31.0, t3, 0.9, "thatch")
    l.put("hostage", 29.5, t2)
    l.room(39, 42, 0, 1.8, "stone", "stone", 0.45, 0.4)
    l.put("knight", 40.5, 0)
    return l


def m04() -> L:
    l = L("mirefen-04", "mirefen", "Reed Roofs",
          "The Reed Barons thatch everything. Roofs, boats, hats. Burn the lot, but spare the miller.",
          "afternoon", wind=-2.0).flat()
    for i, who in enumerate(["king", "knight", "hostage", "queen", "knight"]):
        x = 25 + i * 3.5
        top = l.room(x - 1.4, x + 1.4, 0, 1.6, "wood", "wood", 0.25, 0.25)
        l.roof(x - 1.5, x + 1.5, top, 0.9, "thatch")
        l.put(who, x, 0)
    return l


def m05() -> L:
    l = L("mirefen-05", "mirefen", "Bog Standard",
          "The Marsh Warden's fort stands on the only dry hill for miles. He charges rent for standing near it.",
          "dawn", wind=3.0)
    l.ground((-24, 0), (21, 0), (22, -2.5), (25, -2.5), (26, 1.5), (36, 1.5), (37, -2.5), (40, -2.5),
             (41, 0), (90, 0))
    b = 1.5
    l.wall(26.5, 27.3, b, 2.0, "stone", rows=2)
    t1 = l.room(28, 33, b, 1.8, "stone", "stone", 0.5, 0.4)
    t2 = l.room(28.6, 32.4, t1, 1.6, "stone", "wood", 0.4)
    l.roof(28.4, 32.6, t2, 0.9, "thatch")
    l.put("knight", 29.3, b)
    l.put("knight", 31.7, b, True)
    l.put("king", 30.5, t1)
    l.casks(33.2, b, 2)
    l.put("queen", 35.4, b)
    return l


def m06() -> L:
    l = L("mirefen-06", "mirefen", "Powder Monkeys",
          "Three powder huts, three royals, and not one fire bucket between them. I'm only helping.",
          "golden", wind=-1.0).flat()
    for x, who in [(25.5, "king"), (33, "queen"), (40.5, "king")]:
        t = l.room(x - 1.5, x + 1.5, 0, 1.8, "stone", "wood", 0.4)
        l.casks(x - 0.8, 0, 2)
        top = l.room(x - 1.2, x + 1.2, t, 1.6, "wood", "wood", 0.3)
        l.roof(x - 1.3, x + 1.3, top, 0.8, "thatch")
        l.put(who, x, t)
    return l


def m07() -> L:
    l = L("mirefen-07", "mirefen", "Heron's Nest",
          "Count Heron perches on stilts and looks down his beak at everyone. Bring him down to earth.",
          "morning", wind=-3.0)
    l.ground((-24, 0), (23.5, 0), (24.5, -2.5), (33.5, -2.5), (34.5, 0), (90, 0))
    l.col(27.9, -2.5, 0.3, 5.0, "wood")
    l.col(30.1, -2.5, 0.3, 5.0, "wood")
    t = l.beam(27.6, 30.4, 2.5, 0.3, "wood")
    top = l.room(27.8, 30.2, t, 1.6, "wood", "wood", 0.25)
    l.roof(27.7, 30.3, top, 0.9, "thatch")
    l.put("king", 29, t)
    l.wall(35.5, 36.3, 0, 2.0, "stone", rows=2)
    l.room(37, 40.5, 0, 1.6, "stone", "stone", 0.55, 0.5)
    l.put("knight", 38.2, 0)
    l.put("queen", 39.3, 0)
    return l


def m08() -> L:
    l = L("mirefen-08", "mirefen", "Sunken Chapel",
          "The Abbot built his chapel in a sinkhole to be nearer the frogs. Help him get nearer still.",
          "dusk", wind=2.0)
    l.ground((-24, 0), (26, 0), (26.2, -4), (33.8, -4), (34, 0), (90, 0))
    t1 = l.room(27, 33, -4, 2.0, "stone", "stone", 0.5, 0.4)
    t2 = l.room(28, 32, t1, 1.6, "stone", "wood", 0.4)
    l.roof(27.9, 32.1, t2, 1.0, "wood")
    l.put("knight", 28.3, -4)
    l.put("king", 31.6, -4)
    l.put("queen", 30, t1)
    l.put("hostage", 24.5, 0)
    l.col(36.5, 0, 0.6, 1.4, "stone")
    l.put("knight", 37.6, 0)
    return l


def m09() -> L:
    l = L("mirefen-09", "mirefen", "Fen Fort",
          "Sir Squelch's fort is mostly mud. The good parts are stone. The best parts are gunpowder.",
          "noon", wind=-2.0).flat()
    l.wall(24.5, 25.3, 0, 2.4, "stone", rows=3)
    l.col(27.3, 0, 0.6, 2.0, "stone")
    l.col(30.7, 0, 0.6, 2.0, "stone")
    t = l.beam(27.0, 31.0, 2.0, 0.4, "iron")
    l.put("knight", 29, 0)
    top = l.room(27.2, 30.8, t, 1.6, "wood", "wood", 0.3)
    l.roof(27.1, 30.9, top, 0.9, "thatch")
    l.put("queen", 29, t)
    l.casks(33.0, 0, 3)
    l.put("hostage", 36.2, 0)
    top = l.room(36.8, 39.6, 0, 1.8, "stone", "stone", 0.45, 0.4)
    l.roof(36.7, 39.7, top, 0.9, "thatch")
    l.put("king", 38.2, 0)
    return l


def m10() -> L:
    l = L("mirefen-10", "mirefen", "Plank Walk",
          "The Duke of Dampwick owns the only bridge over the bog and put a toll booth on it. My end.",
          "golden", 56, wind=2.0)
    l.ground((-24, 0), (23, 0), (24, -2.5), (38, -2.5), (39, 0), (90, 0))
    for x in (27, 31, 35):
        l.col(x, -2.5, 0.4, 2.5, "wood")
    t = l.beam(26.8, 35.2, 0, 0.3, "wood")
    top = l.room(29.8, 32.2, t, 1.6, "wood", "wood", 0.25, 0.25)
    l.roof(29.7, 32.3, top, 0.8, "thatch")
    l.put("king", 31, t)
    l.put("knight", 28.0, t)
    l.put("queen", 33.8, t)
    top = l.room(42, 45.5, 0, 1.8, "stone", "stone", 0.45, 0.4)
    l.roof(41.9, 45.6, top, 0.9, "thatch")
    l.put("knight", 43.75, 0)
    return l


def m11() -> L:
    l = L("mirefen-11", "mirefen", "Twin Mills",
          "The Mill Lords grind their flour finer than mine. Grind their mills finer still.",
          "afternoon", 58, wind=3.0).flat()
    for x, who in [(25, "king"), (45, "queen")]:
        t = l.stack(x, 0, 1.8, 1.0, 4, "stone")
        top = l.room(x - 0.9, x + 0.9, t, 1.5, "wood", "wood", 0.25, 0.25)
        l.roof(x - 1.0, x + 1.0, top, 0.9, "thatch")
        l.put(who, x, t)
    top = l.room(33.5, 37, 0, 1.8, "wood", "wood", 0.3)
    l.roof(33.4, 37.1, top, 1.0, "thatch")
    l.put("knight", 34.6, 0)
    l.put("hostage", 36.0, 0)
    return l


def m12() -> L:
    l = L("mirefen-12", "mirefen", "Mirefen Hall",
          "The Bog King says Mirefen Hall is unsinkable. It is built on a swamp. Test that.",
          "night", 58, wind=-2.0)
    l.ground((-24, 0), (21, 0), (22, 1.0), (34, 1.0), (35, -2.5), (39, -2.5), (40, 1.0), (90, 1.0))
    b = 1.0
    l.wall(23.0, 23.8, b, 2.4, "stone", rows=3)
    t1 = l.room(25, 32, b, 1.9, "stone", "stone", 0.55, 0.45)
    l.casks(25.7, b, 3)
    l.put("knight", 29.2, b)
    l.put("hostage", 30.7, b)
    t2 = l.room(25.6, 31.4, t1, 1.7, "stone", "wood", 0.45)
    l.put("queen", 27.5, t1)
    l.put("king", 29.5, t1)
    t3 = l.room(26.6, 30.4, t2, 1.5, "wood", "wood", 0.3)
    l.roof(26.4, 30.6, t3, 1.0, "thatch")
    l.put("knight", 28.5, t2)
    t = l.tower(44, b, 2.2, 2, "stone", "wood", 1.6, 0.4)
    l.roof(42.8, 45.2, t, 1.0, "thatch")
    l.put("knight", 44, b)
    l.put("king", 44, b + 1.6 + 0.3)
    return l


# ======================================================== Cinderreach ===
# Lava gorges (deep drops), stone and iron, powder magazines, steady wind.
def c01() -> L:
    l = L("cinderreach-01", "cinderreach", "Hot Welcome",
          "The Ember Margrave sent me a housewarming present. It was on fire. So was my house.",
          "dusk", wind=2.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (25.7, -8), (26, 1.0), (40, 1.0), (41, 0), (90, 0))
    b = 1.0
    t1 = l.room(27.5, 32.5, b, 1.8, "iron", "stone", 0.4, 0.4)
    l.casks(28.0, b, 2)
    l.put("king", 31.2, b)
    t2 = l.room(28, 32, t1, 1.6, "stone", "wood", 0.4)
    l.roof(27.9, 32.1, t2, 1.0, "stone")
    l.put("queen", 30, t1)
    l.col(34.5, b, 0.6, 1.6, "stone")
    l.put("knight", 36, b)
    return l


def c02() -> L:
    l = L("cinderreach-02", "cinderreach", "Ash Steps",
          "The Ash Pharaoh's steps lead up to his throne. Rearrange them so they lead down.",
          "afternoon", wind=-3.0).flat()
    base = 0.0
    for i, w in enumerate([9.0, 6.6, 4.2, 1.8]):
        n = max(1, int(round(w / 1.1)))
        cw = w / n
        x0 = 32 - w / 2
        for c in range(n):
            l.rect(x0 + cw * c + cw / 2, base + 0.45, cw, 0.9, "iron" if i == 3 else "stone")
        base += 0.9
    l.put("knight", 28.1, 0.9)
    l.put("knight", 35.9, 0.9, True)
    l.put("queen", 29.3, 1.8)
    l.put("hostage", 34.7, 1.8)
    l.put("king", 32, 3.6)
    return l


def c03() -> L:
    l = L("cinderreach-03", "cinderreach", "The Forge",
          "The Iron Duke forged himself a suit of armour. With my iron. Which I paid for. Collect.",
          "night", wind=3.0).flat()
    l.col(25.5, 0, 0.5, 2.2, "iron")
    t = l.room(27, 32, 0, 2.0, "iron", "iron", 0.4, 0.35)
    l.casks(27.6, 0, 2)
    l.put("king", 30.0, 0)
    l.put("knight", 31.1, 0, True)
    top = l.room(27.2, 29.8, t, 1.5, "wood", "wood", 0.3)
    l.roof(27.1, 29.9, top, 0.8, "stone")
    l.put("queen", 28.5, t)
    l.stack(30.8, t, 0.8, 0.8, 3, "stone")
    l.put("hostage", 33.5, 0)
    l.col(34.3, 0, 0.6, 0.5, "iron")
    return l


def c04() -> L:
    l = L("cinderreach-04", "cinderreach", "Over the Edge",
          "Lady Smoulder built her palace across a lava gorge to avoid my visits. Visit.",
          "golden", 60, wind=4.0)
    l.ground((-24, 0), (22, 0), (23, 1.5), (30, 1.5), (30.3, -8), (38.7, -8), (39, 1.5), (90, 1.5))
    b = 1.5
    l.room(25, 28, b, 1.7, "stone", "stone", 0.45, 0.4)
    l.put("knight", 26.5, b)
    t1 = l.room(41, 47, b, 1.9, "stone", "stone", 0.5, 0.45)
    t2 = l.room(41.8, 46.2, t1, 1.7, "glass", "wood", 0.3)
    l.roof(41.7, 46.3, t2, 1.0, "cloth")
    l.put("queen", 42.6, b)
    l.put("hostage", 44, b)
    l.put("knight", 45.4, b, True)
    l.put("king", 44, t1)
    return l


def c05() -> L:
    l = L("cinderreach-05", "cinderreach", "Magazine Row",
          "The Gunner General keeps his powder in a tidy row. Tidiness should be rewarded.",
          "noon", wind=-2.0).flat()
    t = 0.0
    for x0, who in [(24, "knight"), (27, "hostage"), (30, "knight")]:
        t = l.room(x0, x0 + 3, 0, 1.8, "stone", "stone", 0.4, 0.4)
        l.casks(x0 + 0.5, 0, 1)
        l.put(who, x0 + 2.0, 0)
    top = l.room(24.4, 32.6, t, 1.6, "wood", "wood", 0.3)
    l.roof(24.3, 32.7, top, 1.0, "cloth")
    l.put("king", 27, t)
    l.put("queen", 30, t)
    l.room(40, 43, 0, 1.8, "iron", "iron", 0.4, 0.35)
    l.put("knight", 41.5, 0)
    return l


def c06() -> L:
    l = L("cinderreach-06", "cinderreach", "Pillar of Fire",
          "The Fire Hermit lives on a pillar above the lava and throws pebbles at passing kings. I pass.",
          "dusk", 58, wind=3.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (27.7, -8), (28, 4.0), (32, 4.0), (32.3, -8), (39.7, -8),
             (40, 0.5), (90, 0.5))
    top = l.room(28.6, 31.4, 4.0, 1.6, "stone", "wood", 0.4)
    l.roof(28.5, 31.5, top, 0.9, "stone")
    l.put("king", 30, 4.0)
    b = 0.5
    l.wall(41, 41.8, b, 2.0, "stone", rows=2)
    l.room(43, 47, b, 1.8, "stone", "stone", 0.45, 0.4)
    l.put("knight", 44.1, b)
    l.put("queen", 45.9, b, True)
    l.casks(47.2, b, 2)
    return l


def c07() -> L:
    l = L("cinderreach-07", "cinderreach", "Iron Curtain",
          "Margrave Kettle hid behind an iron wall and said I'd never see him again. Promises, promises.",
          "night", wind=-4.0).flat()
    l.wall(25, 26, 0, 3.6, "iron", rows=3)
    t1 = l.room(28, 33, 0, 1.8, "stone", "stone", 0.5, 0.4)
    t2 = l.room(28.6, 32.4, t1, 1.6, "stone", "wood", 0.4)
    l.roof(28.5, 32.5, t2, 0.9, "iron")
    l.put("knight", 29.2, 0)
    l.put("knight", 31.8, 0, True)
    l.put("king", 30.5, t1)
    l.casks(33.2, 0, 2)
    l.room(36.2, 38.6, 0, 1.6, "iron", "iron", 0.35, 0.3)
    l.put("queen", 37.4, 0)
    return l


def c08() -> L:
    l = L("cinderreach-08", "cinderreach", "Cinder Bridge",
          "Baron Clinker's stone bridge crosses the lava river. He is very proud of it. Unduly.",
          "golden", 58, wind=2.0)
    l.ground((-24, 0), (22, 0), (23, 1.0), (27, 1.0), (27.3, -8), (40.7, -8), (41, 1.0), (90, 1.0))
    l.stack(31, -8, 1.0, 1.5, 6, "stone")
    l.stack(37, -8, 1.0, 1.5, 6, "stone")
    l.beam(25.5, 31.0, 1.0, 0.4, "stone")
    l.beam(31.0, 37.0, 1.0, 0.4, "stone")
    d = l.beam(37.0, 42.5, 1.0, 0.4, "stone")
    top = l.room(32, 36, d, 1.6, "wood", "wood", 0.3)
    l.roof(31.9, 36.1, top, 0.9, "cloth")
    l.put("king", 34, d)
    l.put("knight", 28.5, d)
    l.put("knight", 39.5, d, True)
    l.room(46, 49, 1.0, 1.7, "stone", "stone", 0.45, 0.4)
    l.put("queen", 47.5, 1.0)
    return l


def c09() -> L:
    l = L("cinderreach-09", "cinderreach", "Slag Heap",
          "The Slag Count piled his rubbish into a hill and built a castle on it. Take out the rubbish.",
          "afternoon", 60, wind=5.0)
    l.ground((-24, 0), (22, 0), (30, 4.0), (36, 4.0), (44, 0), (90, 0))
    b = 4.0
    t1 = l.room(30.5, 35.5, b, 1.8, "stone", "stone", 0.5, 0.4)
    t2 = l.room(31.2, 34.8, t1, 1.6, "wood", "wood", 0.3)
    l.roof(31.0, 35.0, t2, 1.0, "thatch")
    l.put("knight", 31.6, b)
    l.put("hostage", 33, b)
    l.put("knight", 34.4, b, True)
    l.put("queen", 33, t1)
    top = l.room(46, 50, 0, 1.8, "wood", "wood", 0.35)
    l.roof(45.9, 50.1, top, 1.0, "thatch")
    l.put("king", 48, 0)
    l.casks(50.2, 0, 2)
    return l


def c10() -> L:
    l = L("cinderreach-10", "cinderreach", "The Crucible",
          "Lord Cauldron lives in the crater of his own volcano. Who does that? He does. For now.",
          "night", wind=-3.0)
    l.ground((-24, 0), (22, 0), (25, 2.0), (27, 2.0), (27.3, -3.0), (36.7, -3.0), (37, 2.0), (40, 2.0),
             (43, 0), (90, 0))
    t1 = l.room(28.5, 35.5, -3.0, 1.8, "iron", "iron", 0.45, 0.4)
    l.casks(29.1, -3.0, 2)
    l.put("king", 31.8, -3.0)
    l.put("queen", 33.2, -3.0)
    l.put("knight", 34.4, -3.0, True)
    l.room(29.5, 34.5, t1, 1.6, "stone", "wood", 0.4)
    l.put("knight", 32, t1)
    l.put("knight", 26, 2.0)
    l.put("queen", 38.3, 2.0)
    l.col(39.4, 2.0, 0.6, 1.4, "stone")
    return l


def c11() -> L:
    l = L("cinderreach-11", "cinderreach", "Twin Calderas",
          "The Brothers Ashcroft live on two volcanoes and shout at each other across the lava. Settle it.",
          "dusk", 56, wind=-4.0)
    l.ground((-24, 0), (22, 0), (23, 3.0), (30, 3.0), (30.3, -8), (34.7, -8), (35, 3.0), (42, 3.0),
             (43, 0), (90, 0))
    b = 3.0
    t = l.tower(26.5, b, 2.4, 2, "stone", "wood", 1.6, 0.45)
    l.roof(25.2, 27.8, t, 1.0, "stone")
    l.put("knight", 26.5, b)
    l.put("king", 26.5, b + 1.9)
    l.casks(28.2, b, 2)
    t = l.tower(38.5, b, 2.4, 2, "iron", "stone", 1.6, 0.4)
    l.roof(37.2, 39.8, t, 1.0, "iron")
    l.put("knight", 38.5, b)
    l.put("king", 38.5, b + 1.9)
    l.put("hostage", 41.2, b)
    return l


def c12() -> L:
    l = L("cinderreach-12", "cinderreach", "Cinderreach Citadel",
          "The Ember Emperor's citadel has iron walls, stone towers and a magazine the size of a barn. "
          "One of those is a weakness.", "night", 62, wind=4.0)
    l.ground((-24, 0), (21, 0), (24, 1.5), (36, 1.5), (36.3, -8), (40.7, -8), (41, 1.5), (90, 1.5))
    b = 1.5
    l.wall(24.5, 25.5, b, 2.4, "iron", rows=3)
    t1 = l.room(27, 35, b, 1.9, "stone", "iron", 0.6, 0.45)
    t2 = l.room(27.8, 34.2, t1, 1.7, "stone", "stone", 0.5, 0.45)
    t3 = l.room(28.8, 33.2, t2, 1.6, "iron", "wood", 0.35)
    l.roof(28.6, 33.4, t3, 1.1, "iron")
    l.put("knight", 28.3, b)
    l.put("hostage", 29.6, b)
    l.put("knight", 30.9, b)
    l.casks(31.6, b, 3)
    l.put("queen", 30, t1)
    l.put("king", 32, t1)
    l.put("king", 31, t2)
    t = l.tower(46, b, 2.2, 3, "stone", "iron", 1.5, 0.45)
    l.roof(44.8, 47.2, t, 0.9, "stone")
    l.put("knight", 46, b)
    l.put("hostage", 46, b + 1.8)
    l.put("king", 46, b + 3.6)
    return l


# =========================================================== Skyreach ===
# Peaks over bottomless gorges, shelves bolted to cliffs, strong wind.
def k01() -> L:
    l = L("skyreach-01", "skyreach", "Thin Air",
          "The Sky Margrave says the air is thinner up there. So is his patience. So is mine.",
          "morning", wind=4.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (26.7, -8), (27, 3.0), (35, 3.0), (35.3, -8), (90, -8))
    b = 3.0
    t1 = l.room(28, 34, b, 1.8, "stone", "stone", 0.5, 0.4)
    t2 = l.room(28.8, 33.2, t1, 1.6, "wood", "wood", 0.3)
    l.roof(28.6, 33.4, t2, 1.0, "cloth")
    l.put("knight", 29.2, b)
    l.put("queen", 32.8, b, True)
    l.put("king", 31, t1)
    return l


def k02() -> L:
    l = L("skyreach-02", "skyreach", "Cliffhanger",
          "Lord Perch built his house hanging off a cliff. He calls it bold. I call it a head start.",
          "noon", wind=-4.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (29.7, -8), (30, 6.0), (40, 6.0), (40.3, -8), (90, -8))
    t = l.ledge(26.0, 29.95, 3.0)
    top = l.room(26.4, 29.4, t, 1.6, "wood", "wood", 0.3)
    l.roof(26.3, 29.5, top, 0.8, "thatch")
    l.put("king", 27.9, t)
    l.room(32, 36, 6.0, 1.8, "stone", "stone", 0.45, 0.4)
    l.put("knight", 33.2, 6.0)
    l.put("queen", 34.8, 6.0, True)
    return l


def k03() -> L:
    l = L("skyreach-03", "skyreach", "Gale Force",
          "The Storm Thanes live on three peaks and blow raspberries at me on the wind. I can hear them.",
          "afternoon", wind=-6.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (24.7, -8), (25, 2.0), (28, 2.0), (28.3, -8), (30.7, -8),
             (31, 3.5), (34, 3.5), (34.3, -8), (36.7, -8), (37, 5.0), (40, 5.0), (40.3, -8), (90, -8))
    for x0, top, who in [(25, 2.0, "king"), (31, 3.5, "queen"), (37, 5.0, "king")]:
        t = l.room(x0 + 0.3, x0 + 2.7, top, 1.6, "stone", "wood", 0.35)
        l.roof(x0 + 0.2, x0 + 2.8, t, 0.8, "cloth")
        l.put(who, x0 + 1.5, top)
    return l


def k04() -> L:
    l = L("skyreach-04", "skyreach", "Eyrie",
          "The Eagle Duke's eyrie is the highest castle in the world. That's a lot of falling to do.",
          "golden", 62, wind=6.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (29.7, -8), (30, 2.5), (33, 2.5), (33.3, -8), (43.7, -8),
             (44, 7.0), (50, 7.0), (50.3, -8), (90, -8))
    top = l.room(30.3, 32.7, 2.5, 1.6, "wood", "wood", 0.3)
    l.roof(30.2, 32.8, top, 0.8, "thatch")
    l.put("knight", 31.5, 2.5)
    t = l.tower(47, 7.0, 3.0, 2, "stone", "wood", 1.6, 0.4)
    l.roof(45.4, 48.6, t, 1.0, "thatch")
    l.put("knight", 47, 7.0)
    l.put("king", 47, 7.0 + 1.9)
    return l


def k05() -> L:
    l = L("skyreach-05", "skyreach", "Hanging Gardens",
          "Queen Trellis grows roses on shelves up a cliff. She threw one at me. Thorns first.",
          "dawn", 58, wind=4.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (37.7, -8), (38, 9.0), (90, 9.0))
    t = l.ledge(33.5, 37.95, 0.5)
    l.room(34, 37, t, 1.6, "wood", "wood", 0.3)
    l.put("queen", 35.5, t)
    t = l.ledge(33.0, 37.95, 3.7)
    l.room(34.2, 37.2, t, 1.6, "glass", "wood", 0.3)
    l.put("knight", 35.7, t)
    t = l.ledge(33.5, 37.95, 6.9)
    top = l.room(33.8, 37.4, t, 1.6, "wood", "wood", 0.3)
    l.roof(33.7, 37.5, top, 0.9, "cloth")
    l.put("king", 35.6, t)
    l.put("hostage", 40, 9.0)
    l.room(41.5, 44.5, 9.0, 1.7, "stone", "stone", 0.45, 0.4)
    l.put("knight", 43, 9.0)
    return l


def k06() -> L:
    l = L("skyreach-06", "skyreach", "Rope Bridge",
          "The Pass Warden strung a bridge between two peaks and charges a toll both ways. Both!",
          "afternoon", wind=-5.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (24.7, -8), (25, 3.0), (29, 3.0), (29.3, -8), (36.7, -8),
             (37, 3.0), (41, 3.0), (41.3, -8), (90, -8))
    d = l.beam(27.5, 38.5, 3.0, 0.25, "wood")
    l.room(31.8, 34.2, d, 1.6, "wood", "cloth", 0.25, 0.2)
    l.put("knight", 33, d)
    l.room(25.2, 27.4, 3.0, 1.6, "stone", "wood", 0.35)
    l.put("queen", 26.3, 3.0)
    l.room(38.6, 40.8, 3.0, 1.6, "stone", "wood", 0.35)
    l.put("king", 39.7, 3.0)
    return l


def k07() -> L:
    l = L("skyreach-07", "skyreach", "Storm Wall",
          "The Wind King built a wall to keep out the weather. And me. Mostly me.",
          "dusk", 64, wind=7.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (25.7, -8), (26, 4.0), (29, 4.0), (29.3, -8), (35.7, -8),
             (36, 2.0), (50, 2.0), (50.3, -8), (90, -8))
    top = l.wall(26.5, 28.5, 4.0, 4.0, "stone", rows=4, cols=2)
    l.put("knight", 27.5, top)
    b = 2.0
    t1 = l.room(38, 44, b, 1.8, "stone", "stone", 0.5, 0.4)
    t2 = l.room(38.8, 43.2, t1, 1.6, "stone", "wood", 0.4)
    l.roof(38.6, 43.4, t2, 1.0, "cloth")
    l.put("knight", 39.2, b)
    l.put("queen", 42.8, b, True)
    l.put("king", 41, t1)
    l.casks(44.6, b, 2)
    l.put("hostage", 47.5, b)
    return l


def k08() -> L:
    l = L("skyreach-08", "skyreach", "Kite Fort",
          "Prince Zephyr built his fort of glass and silk because it 'catches the light'. Catch this.",
          "noon", wind=-7.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (25.7, -8), (26, 1.0), (38, 1.0), (38.3, -8), (90, -8))
    b = 1.0
    t1 = l.room(27, 32, b, 1.8, "glass", "glass", 0.3, 0.3)
    t2 = l.room(27.6, 31.4, t1, 1.6, "glass", "cloth", 0.3, 0.2)
    l.roof(27.5, 31.5, t2, 1.0, "cloth")
    l.put("queen", 28.2, b)
    l.put("king", 30.8, b, True)
    l.put("knight", 29.5, t1)
    l.room(33.5, 36.5, b, 1.6, "glass", "glass", 0.3)
    l.put("hostage", 34.4, b)
    l.put("king", 35.5, b, True)
    return l


def k09() -> L:
    l = L("skyreach-09", "skyreach", "The Stair",
          "The Abbess of the Steps counts every stair on her way to bed. Help her count. Quickly.",
          "morning", 60, wind=4.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (41.7, -8), (42, 10.0), (90, 10.0))
    t = l.ledge(35.5, 41.95, 1.0)
    l.room(36, 38.6, t, 1.6, "wood", "wood", 0.3)
    l.put("king", 37.3, t)
    t = l.ledge(37.0, 41.95, 3.6)
    l.room(37.5, 40.1, t, 1.6, "stone", "wood", 0.35)
    l.put("queen", 38.8, t)
    t = l.ledge(38.5, 41.95, 6.2)
    l.room(38.8, 41.4, t, 1.6, "wood", "wood", 0.3)
    l.put("knight", 40.1, t)
    top = l.room(44, 47, 10.0, 1.8, "stone", "stone", 0.45, 0.4)
    l.roof(43.9, 47.1, top, 0.9, "cloth")
    l.put("king", 45.5, 10.0)
    return l


def k10() -> L:
    l = L("skyreach-10", "skyreach", "Thunderhead",
          "The Storm Baron keeps his powder dry in an iron keep on a mountain. Dry is relative.",
          "night", wind=-6.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (27.7, -8), (28, 2.5), (38, 2.5), (38.3, -8), (90, -8))
    b = 2.5
    t1 = l.room(29, 35, b, 1.9, "iron", "iron", 0.45, 0.4)
    l.casks(29.6, b, 2)
    l.put("king", 32.2, b)
    l.put("knight", 33.6, b, True)
    t2 = l.room(29.8, 34.2, t1, 1.7, "stone", "stone", 0.45, 0.4)
    l.roof(29.6, 34.4, t2, 1.0, "iron")
    l.put("queen", 32, t1)
    l.put("hostage", 36.2, b)
    l.col(37.2, b, 0.6, 1.4, "stone")
    return l


def k11() -> L:
    l = L("skyreach-11", "skyreach", "Twin Spires",
          "The Spire Sisters built the two tallest towers in Skyreach to look down on each other. And me.",
          "golden", 66, wind=8.0)
    l.ground((-24, 0), (22, 0), (22.3, -8), (25.7, -8), (26, 1.5), (30, 1.5), (30.3, -8), (45.7, -8),
             (46, 3.0), (51, 3.0), (51.3, -8), (90, -8))
    for x, b, who in [(28, 1.5, "queen"), (48.5, 3.0, "queen")]:
        t = l.stack(x, b, 1.6, 1.0, 5, "stone")
        top = l.room(x - 0.8, x + 0.8, t, 1.5, "wood", "wood", 0.25, 0.25)
        l.roof(x - 0.9, x + 0.9, top, 0.9, "cloth")
        l.put(who, x, t)
    l.put("knight", 29.4, 1.5)
    return l


def k12() -> L:
    l = L("skyreach-12", "skyreach", "The Skyreach Throne",
          "The High King of Skyreach sits on the roof of the world and says everything is beneath him. "
          "Correct him.", "dusk", 56, wind=-2.5)
    l.ground((-24, 0), (22, 0), (22.3, -8), (24.7, -8), (25, 2.0), (32, 2.0), (32.3, -8), (35.7, -8),
             (36, 4.0), (44, 4.0), (44.3, -8), (90, -8))
    b = 2.0
    l.wall(25.5, 26.5, b, 2.4, "stone", rows=3)
    t1 = l.room(27.5, 31.5, b, 1.8, "stone", "stone", 0.45, 0.4)
    l.put("knight", 28.6, b)
    l.put("hostage", 30.4, b)
    t2 = l.room(28.1, 30.9, t1, 1.6, "wood", "wood", 0.3)
    l.roof(27.9, 31.1, t2, 0.9, "cloth")
    l.put("queen", 29.5, t1)
    t = l.ledge(33.0, 36.05, 3.0)
    l.casks(33.4, t, 2)
    b = 4.0
    t1 = l.room(36.5, 43.5, b, 1.9, "stone", "iron", 0.55, 0.45)
    t2 = l.room(37.3, 42.7, t1, 1.7, "iron", "stone", 0.45, 0.45)
    t3 = l.room(38.3, 41.7, t2, 1.6, "stone", "wood", 0.4)
    l.roof(38.1, 41.9, t3, 1.2, "iron")
    l.put("knight", 37.6, b)
    l.put("king", 40, b)
    l.put("knight", 42.4, b, True)
    l.put("queen", 38.8, t1)
    l.put("king", 41.2, t1)
    l.put("king", 40, t2)
    return l


LEVELS = {
    "greenmantle": [g02, g03, g04, g05, g06, g07, g08, g09, g10, g11, g12],
    "saffron": [s01, s02, s03, s04, s05, s06, s07, s08, s09, s10, s11, s12],
    "frostfang": [f01, f02, f03, f04, f05, f06, f07, f08, f09, f10, f11, f12],
    "mirefen": [m01, m02, m03, m04, m05, m06, m07, m08, m09, m10, m11, m12],
    "cinderreach": [c01, c02, c03, c04, c05, c06, c07, c08, c09, c10, c11, c12],
    "skyreach": [k01, k02, k03, k04, k05, k06, k07, k08, k09, k10, k11, k12],
}
KEEP = ("par", "par_override", "solution", "solution_basic", "content_hash")


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if len(argv) >= 2 else 2
    game = Path(argv[1])
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    for realm, fns in LEVELS.items():
        ids = ["greenmantle-01"] if realm == "greenmantle" else []
        out_dir = game / "data" / "levels" / realm
        out_dir.mkdir(parents=True, exist_ok=True)
        for fn in fns:
            lvl = fn().d
            ids.append(lvl["id"])
            if only and lvl["id"] != only:
                continue
            path = out_dir / f"{lvl['id']}.json"
            if path.exists():
                old = json.loads(path.read_text())
                for k in KEEP:
                    if k in old:
                        lvl[k] = old[k]
            path.write_text(json.dumps(lvl, indent=2) + "\n")
        realm_path = game / "data" / "realms" / f"{realm}.json"
        rd = json.loads(realm_path.read_text())
        rd["levels"] = ids
        realm_path.write_text(json.dumps(rd, indent=2) + "\n")
    print("levels written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
