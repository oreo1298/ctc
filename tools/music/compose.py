#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
"""Compose and render the game's music: one gentle, seamless loop per realm
plus the menu theme. Pure standard-library Python, deterministic (seeded),
so `make music` always writes the same files.

Each piece is a chord progression with a few voices (pad, bass, plucked
arpeggio, a lead melody, percussion or wind where the realm wants it), a
small Schroeder reverb, and a loop seam made by wrapping everything that
rings past the end of the loop back onto its start.

Usage: compose.py OUT_DIR [NAME ...]   (default: all pieces)
"""
from __future__ import annotations

import math
import random
import struct
import sys
import wave
from dataclasses import dataclass, field
from pathlib import Path

SR = 22050
TABLE_N = 2048
Buf = list[float]


def midi_hz(n: float) -> float:
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def _table(harmonics: list[tuple[int, float]]) -> list[float]:
    t = [0.0] * TABLE_N
    for h, a in harmonics:
        for i in range(TABLE_N):
            t[i] += a * math.sin(2 * math.pi * h * i / TABLE_N)
    m = max(abs(v) for v in t)
    return [v / m for v in t]


SINE = _table([(1, 1.0)])
WARM = _table([(1, 1.0), (2, 0.28), (3, 0.12), (4, 0.05)])
REED = _table([(1, 1.0), (2, 0.5), (3, 0.35), (4, 0.2), (5, 0.12), (6, 0.06)])


# ---------------------------------------------------------------- voices ---
def osc(table: list[float], freq: float, seconds: float, vib_hz: float = 0.0,
        vib_depth: float = 0.0, phase: float = 0.0) -> Buf:
    n = int(seconds * SR)
    out = [0.0] * n
    pos = phase * TABLE_N
    base = freq * TABLE_N / SR
    tn = TABLE_N
    if vib_depth <= 0.0:
        for i in range(n):
            out[i] = table[int(pos) % tn]
            pos += base
        return out
    step = base
    for i in range(n):
        if i % 64 == 0:
            step = base * (1.0 + vib_depth * math.sin(2 * math.pi * vib_hz * i / SR))
        out[i] = table[int(pos) % tn]
        pos += step
    return out


def envelope(buf: Buf, attack: float, release: float, hold: float | None = None,
             curve: float = 1.0) -> Buf:
    """Linear attack, sustain until `hold` seconds, then an exponential-ish
    release to silence at the end of the buffer."""
    n = len(buf)
    a = max(1, int(attack * SR))
    h = int((hold if hold is not None else n / SR - release) * SR)
    r = max(1, n - h)
    for i in range(n):
        if i < a:
            g = i / a
        elif i < h:
            g = 1.0
        else:
            g = max(0.0, 1.0 - (i - h) / r) ** (2.0 * curve)
        buf[i] *= g
    return buf


def decay(buf: Buf, seconds: float, attack: float = 0.004) -> Buf:
    k = math.log(1000.0) / max(seconds, 1e-3)
    a = max(1, int(attack * SR))
    for i in range(len(buf)):
        buf[i] *= min(1.0, i / a) * math.exp(-k * i / SR)
    return buf


def lowpass(buf: Buf, cutoff: float) -> Buf:
    x = math.exp(-2 * math.pi * cutoff / SR)
    y = 0.0
    for i in range(len(buf)):
        y = (1 - x) * buf[i] + x * y
        buf[i] = y
    return buf


def pluck(freq: float, seconds: float, rng: random.Random, damp: float = 0.996,
          bright: float = 1.0) -> Buf:
    """Karplus-Strong string; `bright` < 1 softens the attack."""
    period = max(2, int(SR / freq))
    ring = [rng.uniform(-1, 1) for _ in range(period)]
    # A zero-mean excitation: otherwise every note adds a slowly decaying DC
    # step (a sub-audible thump that eats headroom).
    mean = sum(ring) / period
    ring = [v - mean for v in ring]
    if bright < 1.0:
        prev = 0.0
        for i in range(period):
            prev = bright * ring[i] + (1 - bright) * prev
            ring[i] = prev
    out = [0.0] * int(seconds * SR)
    for i in range(len(out)):
        j = i % period
        v = ring[j]
        ring[j] = damp * 0.5 * (v + ring[(j + 1) % period])
        out[i] = v
    return decay(out, seconds * 1.1, 0.002)


def bell(freq: float, seconds: float, rng: random.Random) -> Buf:
    n = int(seconds * SR)
    out = [0.0] * n
    for ratio, amp, dec in ((1.0, 1.0, 1.0), (2.76, 0.45, 0.55), (5.4, 0.25, 0.3),
                            (8.93, 0.12, 0.18)):
        f = freq * ratio
        if f > SR * 0.45:
            continue
        k = math.log(1000.0) / (seconds * dec)
        ph = rng.uniform(0, 1) * TABLE_N
        step = f * TABLE_N / SR
        for i in range(n):
            out[i] += amp * SINE[int(ph) % TABLE_N] * math.exp(-k * i / SR)
            ph += step
    return out


def flute(freq: float, seconds: float, rng: random.Random) -> Buf:
    tone = osc(WARM, freq, seconds, vib_hz=5.0, vib_depth=0.004, phase=rng.random())
    breath = lowpass([rng.uniform(-1, 1) * 0.06 for _ in range(len(tone))], 2500.0)
    out = [t + b for t, b in zip(tone, breath)]
    return envelope(out, 0.07, min(0.25, seconds * 0.4))


def drum_dum(rng: random.Random) -> Buf:
    n = int(0.5 * SR)
    out = [0.0] * n
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 55.0 + 70.0 * math.exp(-t * 18.0)
        ph += f / SR
        out[i] = math.sin(2 * math.pi * ph) * math.exp(-t * 7.0)
    return out


def drum_tek(rng: random.Random) -> Buf:
    n = int(0.09 * SR)
    out = [rng.uniform(-1, 1) for _ in range(n)]
    # Crude band-pass: high-pass by differencing, then a gentle low-pass.
    prev = 0.0
    for i in range(n):
        v = out[i]
        out[i] = v - prev
        prev = v
    lowpass(out, 5000.0)
    return decay(out, 0.09, 0.001)


def wind(seconds: float, rng: random.Random) -> Buf:
    """Filtered noise whose colour drifts slowly (a state-variable band-pass)."""
    n = int(seconds * SR)
    out = [0.0] * n
    low = band = 0.0
    q = 0.35
    for i in range(n):
        t = i / SR
        f = 380.0 + 260.0 * math.sin(2 * math.pi * t / 11.0) + 120.0 * math.sin(2 * math.pi * t / 4.3)
        fc = 2.0 * math.sin(math.pi * f / SR)
        x = rng.uniform(-1, 1)
        high = x - low - q * band
        band += fc * high
        low += fc * band
        out[i] = band * (0.55 + 0.45 * math.sin(2 * math.pi * t / 7.7))
    return out


# ---------------------------------------------------------------- reverb ---
def reverb(buf: Buf, wet: float, size: float = 1.0) -> Buf:
    combs = [int(d * size * SR / 44100) for d in (1116, 1188, 1277, 1356)]
    alls = [int(d * SR / 44100) for d in (556, 441)]
    n = len(buf)
    acc = [0.0] * n
    for d in combs:
        line = [0.0] * d
        fb, damp = 0.82, 0.25
        store = 0.0
        j = 0
        for i in range(n):
            y = line[j]
            store = y * (1 - damp) + store * damp
            line[j] = buf[i] + store * fb
            acc[i] += y
            j += 1
            if j == d:
                j = 0
    for d in alls:
        line = [0.0] * d
        j = 0
        for i in range(n):
            y = line[j]
            x = acc[i]
            line[j] = x + y * 0.5
            acc[i] = y - x * 0.5
            j += 1
            if j == d:
                j = 0
    return [d + a * wet * 0.25 for d, a in zip(buf, acc)]


# ------------------------------------------------------------- composing ---
@dataclass
class Piece:
    name: str
    bpm: float
    root: int  # MIDI note of the key's tonic (octave 4)
    scale: list[int]  # semitones above the root
    progression: list[list[int]]  # per bar: chord tones as scale degrees (0-based)
    seed: int
    lead: str = "flute"  # flute | pluck | bell | none
    arp: str = "pluck"  # pluck | bell | none
    pad: float = 0.4
    drums: bool = False
    drone: bool = False
    wind: float = 0.0
    arp_density: float = 0.8
    lead_rest: float = 0.25
    layers: dict[str, float] = field(default_factory=dict)

    @property
    def beat(self) -> float:
        return 60.0 / self.bpm

    @property
    def bar(self) -> float:
        return 4 * self.beat

    @property
    def length(self) -> float:
        return len(self.progression) * self.bar

    def note(self, degree: int, octave: int = 0) -> int:
        """MIDI note for a scale degree (may exceed the scale: wraps octaves)."""
        k = len(self.scale)
        o, d = divmod(degree, k)
        return self.root + self.scale[d] + 12 * (o + octave)


def add(dst: Buf, src: Buf, at: float, gain: float) -> None:
    start = int(at * SR)
    end = min(len(dst), start + len(src))
    for i in range(start, end):
        dst[i] += src[i - start] * gain


def render(p: Piece) -> Buf:
    rng = random.Random(p.seed)
    tail = 5.0
    total = p.length + tail
    voices: dict[str, Buf] = {k: [0.0] * int(total * SR) for k in
                               ("pad", "bass", "arp", "lead", "perc", "air")}
    bar = p.bar
    beat = p.beat

    for b, chord in enumerate(p.progression):
        t0 = b * bar
        # Pad: chord tones around octave 3-4, slow swell into the next bar.
        for k, deg in enumerate(chord):
            f = midi_hz(p.note(deg, -1 if k == 0 else 0))
            tone = osc(WARM, f, bar + 1.2, vib_hz=0.3 + 0.1 * k, vib_depth=0.002,
                       phase=rng.random())
            lowpass(tone, 1400.0)
            add(voices["pad"], envelope(tone, 0.9, 1.0), t0, 0.16)
        # Bass on beat one (and a softer one on beat three).
        root = midi_hz(p.note(chord[0], -2))
        add(voices["bass"], decay(osc(SINE, root, bar * 0.9), bar * 0.9, 0.02), t0, 0.5)
        if rng.random() < 0.5:
            add(voices["bass"], decay(osc(SINE, root, beat * 1.8), beat * 1.6, 0.02),
                t0 + 2 * beat, 0.3)
        # Arpeggio: eighth notes walking up and down the chord.
        if p.arp != "none":
            # An octave above the pad, so the arpeggio sparkles over it.
            tones = sorted(p.note(d, 1) for d in chord) + [p.note(chord[0], 2)]
            up = rng.random() < 0.5
            for s in range(8):
                if rng.random() > p.arp_density:
                    continue
                idx = s % len(tones) if up else (len(tones) - 1 - s % len(tones))
                f = midi_hz(tones[idx])
                vel = rng.uniform(0.55, 1.0) * (1.0 if s % 2 == 0 else 0.75)
                if p.arp == "bell":
                    snd = bell(f, 2.2, rng)
                    gain = 0.16
                else:
                    snd = pluck(f, 1.6, rng, damp=0.995, bright=0.6)
                    gain = 0.3
                add(voices["arp"], snd, t0 + s * beat / 2, gain * vel)
        # Percussion: a frame-drum dum-tek figure.
        if p.drums:
            for s, kind in enumerate(("D", "", "t", "t", "D", "t", "", "t")):
                if kind == "D":
                    add(voices["perc"], drum_dum(rng), t0 + s * beat / 2, 0.38)
                elif kind == "t" and rng.random() < 0.85:
                    add(voices["perc"], drum_tek(rng), t0 + s * beat / 2,
                        rng.uniform(0.15, 0.3))

    # Lead melody: two-bar phrases, A A' B A'' over each 8 bars.
    if p.lead != "none":
        rhythms = [
            [1, 1, 1, 1, 2, 2],
            [1.5, 0.5, 1, 1, 3, 1],
            [2, 1, 1, 2, 2],
            [0.5, 0.5, 1, 2, 1, 1, 2],
        ]
        phrases: dict[str, list[tuple[float, float, int]]] = {}

        def phrase(start_bar: int, key: str) -> list[tuple[float, float, int]]:
            if key in phrases:
                return phrases[key]
            r = rng.choice(rhythms)
            deg = rng.choice(p.progression[start_bar % len(p.progression)])
            out = []
            t = 0.0
            for i, d in enumerate(r):
                last = i == len(r) - 1
                chord = p.progression[(start_bar + int(t // 4)) % len(p.progression)]
                if last:
                    deg = min(chord, key=lambda c: abs(c - deg))  # land on the chord
                else:
                    deg += rng.choice((-2, -1, -1, 1, 1, 2, 0))
                    deg = max(-1, min(9, deg))
                rest = rng.random() < p.lead_rest and not last and i > 0
                if not rest:
                    out.append((t, d, deg))
                t += d
            phrases[key] = out
            return out

        bars = len(p.progression)
        plan = ["A", "A2", "B", "A3"]
        for k in range(0, bars, 2):
            key = plan[(k // 2) % len(plan)]
            ph = phrase(k, key.rstrip("23"))
            for when, dur, deg in ph:
                # A' and A'' vary the last notes a little.
                if key != "A" and key != "B" and when >= 4 and rng.random() < 0.5:
                    deg += rng.choice((-1, 1))
                f = midi_hz(p.note(deg, 0 if p.lead == "pluck" else 1))
                start = k * bar + when * beat
                seconds = dur * beat
                if p.lead == "flute":
                    add(voices["lead"], flute(f, seconds * 1.05, rng), start, 0.28)
                elif p.lead == "pluck":
                    add(voices["lead"], pluck(f, max(1.0, seconds * 1.5), rng, 0.993, 0.8),
                        start, 0.42)
                elif p.lead == "bell":
                    add(voices["lead"], bell(f, 3.0, rng), start, 0.2)

    if p.drone:
        for deg, g in ((0, 0.04), (4, 0.022)):
            tone = osc(REED, midi_hz(p.note(deg, -1)), total, vib_hz=0.2, vib_depth=0.003)
            lowpass(tone, 900.0)
            add(voices["air"], tone, 0.0, g)
    if p.wind > 0.0:
        add(voices["air"], wind(total, rng), 0.0, p.wind)

    gains = {"pad": p.pad, "bass": 0.45, "arp": 0.8, "lead": 0.9, "perc": 0.7, "air": 1.0}
    gains.update(p.layers)
    n = int(total * SR)
    mixbuf = [0.0] * n
    for name, buf in voices.items():
        g = gains[name]
        for i in range(n):
            mixbuf[i] += buf[i] * g
    mixbuf = reverb(mixbuf, wet=0.9, size=1.05)

    # Seamless loop: everything ringing past the end wraps onto the start.
    loop = int(p.length * SR)
    out = mixbuf[:loop]
    for i in range(loop, n):
        out[i - loop] += mixbuf[i]
    # High-pass at 35 Hz to clear DC and sub-bass. The filter runs over the
    # loop twice and keeps the second pass, so its state at the start equals
    # its state at the end: the loop stays seamless.
    a = math.exp(-2 * math.pi * 35.0 / SR)
    prev_x = prev_y = 0.0
    for pass_no in range(2):
        for i in range(len(out)):
            x = out[i]
            y = a * (prev_y + x - prev_x)
            prev_x, prev_y = x, y
            if pass_no == 1:
                out[i] = y
    # Level every piece to the same loudness (-15 dBFS RMS), with a soft
    # limiter so peaks stay under -1 dBFS.
    rms = math.sqrt(sum(v * v for v in out) / len(out)) or 1.0
    g = 10 ** (-15 / 20) / rms
    ceiling = 10 ** (-1 / 20)
    return [ceiling * math.tanh(v * g / ceiling) for v in out]


def write_wav(path: Path, buf: Buf) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))
                               for v in buf))


# ---------------------------------------------------------------- pieces ---
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]
PHRYGIAN_DOMINANT = [0, 1, 4, 5, 7, 8, 10]


def triad(d: int) -> list[int]:
    return [d, d + 2, d + 4]


PIECES = [
    # Title and menus: warm, unhurried, G major (I vi IV V).
    Piece("menu", 84, 67, MAJOR,
          [triad(0), triad(5), triad(3), triad(4)] * 3, seed=11, lead="flute",
          arp_density=0.7),
    # Greenmantle: pastoral D major with lute and a flute-like lead.
    Piece("greenmantle", 96, 62, MAJOR,
          [triad(0), triad(3), triad(0), triad(4), triad(5), triad(3), triad(0), triad(4)] * 2,
          seed=23, lead="flute", arp_density=0.85),
    # Saffron Reach: D Phrygian dominant over a drone, oud-like plucks, frame drum.
    Piece("saffron", 88, 62, PHRYGIAN_DOMINANT,
          [triad(0), triad(1), triad(0), triad(3), triad(0), triad(1), triad(6), triad(0)] * 2,
          seed=37, lead="pluck", arp="pluck", pad=0.25, drums=True, drone=True,
          arp_density=0.55, lead_rest=0.15, layers={"bass": 0.22, "perc": 0.5}),
    # Frostfang Peaks: A minor (i VI III VII), bells, a cold pad and wind.
    Piece("frostfang", 66, 69, MINOR,
          [triad(0), triad(5), triad(2), triad(6)] * 3, seed=41, lead="bell", arp="bell",
          pad=0.5, wind=0.05, arp_density=0.45, lead_rest=0.35),
]


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) >= 2 else 2
    out_dir = Path(argv[1])
    wanted = set(argv[2:])
    for p in PIECES:
        if wanted and p.name not in wanted:
            continue
        buf = render(p)
        write_wav(out_dir / f"{p.name}.wav", buf)
        print(f"{p.name}: {len(buf) / SR:.1f} s loop, {len(p.progression)} bars at {p.bpm:g} BPM")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
