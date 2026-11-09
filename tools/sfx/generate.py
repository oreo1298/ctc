#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
"""Procedural sound effects for the game (Python standard library only).

Every sound is synthesised from noise, filters, envelopes, inharmonic
partials and Karplus-Strong strings, with several seeded variations, and
written as 44.1 kHz 16-bit mono WAV files to game/audio/sfx/<name>_<n>.wav.
The output is original work (CC-BY-SA-4.0); this script is MIT.

Usage: generate.py OUT_DIR [--only NAME]
"""
from __future__ import annotations

import math
import random
import struct
import sys
import wave
from pathlib import Path
from typing import Callable

SR = 44100
Buf = list[float]


# ------------------------------------------------------------- building ---
def silence(seconds: float) -> Buf:
    return [0.0] * int(seconds * SR)


def mix(dst: Buf, src: Buf, at: float = 0.0, gain: float = 1.0) -> Buf:
    start = int(at * SR)
    need = start + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, v in enumerate(src):
        dst[start + i] += v * gain
    return dst


def noise(seconds: float, rng: random.Random) -> Buf:
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * SR))]


def env_exp(buf: Buf, decay: float, attack: float = 0.002) -> Buf:
    """Fast attack, exponential decay (decay = time to -60 dB)."""
    k = math.log(1000.0) / max(decay, 1e-4)
    a = max(1, int(attack * SR))
    out = []
    for i, v in enumerate(buf):
        t = i / SR
        g = min(1.0, i / a) * math.exp(-k * t)
        out.append(v * g)
    return out


def env_bell(buf: Buf, peak: float = 0.3) -> Buf:
    """Smooth rise then fall; peak is the fraction of the length."""
    n = len(buf)
    out = []
    for i, v in enumerate(buf):
        x = i / max(1, n - 1)
        g = math.sin(math.pi * min(1.0, x / (2 * peak))) if x < peak else math.cos(
            math.pi * 0.5 * (x - peak) / max(1e-6, 1 - peak)
        )
        out.append(v * max(0.0, g))
    return out


def lowpass(buf: Buf, cutoff: float | Callable[[float], float]) -> Buf:
    out, y = [], 0.0
    for i, v in enumerate(buf):
        c = cutoff(i / SR) if callable(cutoff) else cutoff
        a = 1.0 - math.exp(-2.0 * math.pi * c / SR)
        y += a * (v - y)
        out.append(y)
    return out


def highpass(buf: Buf, cutoff: float) -> Buf:
    lp = lowpass(buf, cutoff)
    return [v - l for v, l in zip(buf, lp)]


def bandpass(buf: Buf, freq: float | Callable[[float], float], q: float = 2.0) -> Buf:
    """RBJ biquad band-pass (constant 0 dB peak); freq may vary over time."""
    out = []
    x1 = x2 = y1 = y2 = 0.0
    for i, x in enumerate(buf):
        f = freq(i / SR) if callable(freq) else freq
        w = 2 * math.pi * min(f, SR * 0.45) / SR
        alpha = math.sin(w) / (2 * q)
        b0, b1, b2 = alpha, 0.0, -alpha
        a0, a1, a2 = 1 + alpha, -2 * math.cos(w), 1 - alpha
        y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


def sine_sweep(f0: float, f1: float, seconds: float, curve: float = 3.0) -> Buf:
    out, ph = [], 0.0
    n = int(seconds * SR)
    for i in range(n):
        t = i / max(1, n - 1)
        f = f1 + (f0 - f1) * math.exp(-curve * t)
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph))
    return out


def partials(freqs: list[float], decays: list[float], seconds: float, rng: random.Random) -> Buf:
    out = [0.0] * int(seconds * SR)
    for f, d in zip(freqs, decays):
        ph = rng.uniform(0, 2 * math.pi)
        k = math.log(1000.0) / d
        amp = 1.0 / (1.0 + 0.0004 * f)
        for i in range(len(out)):
            t = i / SR
            out[i] += amp * math.sin(ph + 2 * math.pi * f * t) * math.exp(-k * t)
    return out


def pluck(freq: float, seconds: float, rng: random.Random, damp: float = 0.996) -> Buf:
    """Karplus-Strong string."""
    period = max(2, int(SR / freq))
    ring = [rng.uniform(-1, 1) for _ in range(period)]
    out = []
    for i in range(int(seconds * SR)):
        v = ring[i % period]
        nxt = ring[(i + 1) % period]
        ring[i % period] = damp * 0.5 * (v + nxt)
        out.append(v)
    return out


def grains(seconds: float, rate: Callable[[float], float], make: Callable[[random.Random], Buf], rng: random.Random) -> Buf:
    out = silence(seconds)
    t = 0.0
    while t < seconds:
        mix(out, make(rng), t, rng.uniform(0.4, 1.0))
        t += rng.expovariate(max(1e-3, rate(t)))
    return out


def normalize(buf: Buf, peak_db: float = -1.0) -> Buf:
    m = max((abs(v) for v in buf), default=0.0)
    if m <= 0:
        return buf
    g = 10 ** (peak_db / 20) / m
    return [v * g for v in buf]


def fade_head(buf: Buf, seconds: float = 0.003) -> Buf:
    n = min(len(buf), int(seconds * SR))
    for i in range(n):
        buf[i] *= i / n
    return buf


def fade_tail(buf: Buf, seconds: float = 0.01) -> Buf:
    n = min(len(buf), int(seconds * SR))
    for i in range(n):
        buf[len(buf) - n + i] *= 1 - i / n
    return buf


# --------------------------------------------------------------- sounds ---
def click(rng: random.Random, f: float = 3000.0, length: float = 0.006) -> Buf:
    return env_exp(bandpass(noise(length * 3, rng), f * rng.uniform(0.7, 1.3), 1.5), length)


def wood_hit(rng: random.Random) -> Buf:
    body = env_exp(sine_sweep(rng.uniform(150, 190), 95, 0.25), 0.18)
    modes = env_exp(partials([rng.uniform(380, 460), rng.uniform(820, 980), 1650], [0.12, 0.08, 0.05], 0.2, rng), 0.15)
    knock = env_exp(bandpass(noise(0.05, rng), 1400, 1.2), 0.03)
    return mix(mix(body, modes, 0, 0.5), knock, 0, 0.8)


def wood_crack(rng: random.Random) -> Buf:
    out = grains(0.22, lambda t: 70 * math.exp(-t * 8), lambda r: click(r, r.uniform(1800, 5000), 0.004), rng)
    creak = env_bell(bandpass(saw_pulse(rng.uniform(70, 110), 0.18, rng), 600, 3.0), 0.2)
    return mix(out, creak, 0.02, 0.6)


def saw_pulse(freq: float, seconds: float, rng: random.Random) -> Buf:
    out, ph = [], 0.0
    for i in range(int(seconds * SR)):
        ph += freq * (1 + 0.3 * math.sin(i / SR * 37)) * (1 + rng.uniform(-0.05, 0.05)) / SR
        out.append(2 * (ph % 1.0) - 1)
    return out


def wood_break(rng: random.Random) -> Buf:
    out = wood_crack(rng)
    mix(out, wood_hit(rng), 0.01, 0.9)
    mix(out, grains(0.6, lambda t: 40 * math.exp(-t * 5), lambda r: wood_tick(r), rng), 0.06, 0.5)
    return out


def wood_tick(rng: random.Random) -> Buf:
    return env_exp(partials([rng.uniform(500, 1400)], [0.05], 0.06, rng), 0.05)


def stone_hit(rng: random.Random) -> Buf:
    thud = env_exp(sine_sweep(rng.uniform(85, 110), 48, 0.35, 4), 0.3)
    dirt = env_exp(lowpass(noise(0.3, rng), 500), 0.22)
    grit = env_exp(bandpass(noise(0.1, rng), 2500, 1.0), 0.05)
    return mix(mix(thud, dirt, 0, 0.9), grit, 0, 0.35)


def stone_crack(rng: random.Random) -> Buf:
    return grains(0.25, lambda t: 120 * math.exp(-t * 9), lambda r: env_exp(bandpass(noise(0.02, r), r.uniform(900, 3200), 1.0), 0.015), rng)


def stone_break(rng: random.Random) -> Buf:
    out = stone_hit(rng)
    mix(out, grains(0.9, lambda t: 90 * math.exp(-t * 3.5), lambda r: pebble(r), rng), 0.03, 0.6)
    mix(out, rumble(rng, 0.9), 0.0, 0.5)
    return out


def pebble(rng: random.Random) -> Buf:
    return env_exp(mix(bandpass(noise(0.03, rng), rng.uniform(700, 2400), 2.0), partials([rng.uniform(900, 2500)], [0.03], 0.03, rng), 0, 0.3), 0.025)


def glass_hit(rng: random.Random) -> Buf:
    f = rng.uniform(1900, 2600)
    tone = partials([f, f * 1.63, f * 2.71, f * 3.95], [0.5, 0.35, 0.22, 0.15], 0.6, rng)
    return mix(env_exp(tone, 0.55, 0.0005), click(rng, 6000, 0.004), 0, 0.6)


def glass_break(rng: random.Random) -> Buf:
    crack = env_exp(highpass(noise(0.12, rng), 2500), 0.08)
    shards = grains(0.8, lambda t: 70 * math.exp(-t * 4), lambda r: env_exp(partials([r.uniform(3000, 9000)], [r.uniform(0.03, 0.12)], 0.12, r), 0.1, 0.0003), rng)
    return mix(mix(crack, shards, 0.005, 0.7), glass_hit(rng), 0, 0.5)


def ice_hit(rng: random.Random) -> Buf:
    f = rng.uniform(1100, 1600)
    tone = env_exp(partials([f, f * 1.9, f * 3.3], [0.25, 0.15, 0.08], 0.3, rng), 0.28)
    crunch = env_exp(bandpass(noise(0.1, rng), 3500, 1.0), 0.06)
    return mix(tone, crunch, 0, 0.7)


def ice_crack(rng: random.Random) -> Buf:
    return grains(0.3, lambda t: 90 * math.exp(-t * 7), lambda r: click(r, r.uniform(2500, 7000), 0.005), rng)


def ice_break(rng: random.Random) -> Buf:
    out = ice_crack(rng)
    mix(out, glass_break(rng), 0.0, 0.6)
    return mix(out, ice_hit(rng), 0, 0.6)


def iron_hit(rng: random.Random) -> Buf:
    f = rng.uniform(280, 460)
    ratios = [1.0, 2.76, 5.40, 8.93, 13.34]
    tone = partials([f * r * rng.uniform(0.99, 1.01) for r in ratios], [1.2, 0.9, 0.6, 0.4, 0.25], 1.3, rng)
    return mix(env_exp(tone, 1.2, 0.0005), click(rng, 4000, 0.004), 0, 0.5)


def iron_crack(rng: random.Random) -> Buf:
    f = rng.uniform(600, 900)
    return env_exp(partials([f, f * 2.76, f * 5.4], [0.5, 0.3, 0.2], 0.5, rng), 0.45, 0.0005)


def iron_break(rng: random.Random) -> Buf:
    out = iron_hit(rng)
    mix(out, grains(0.6, lambda t: 25 * math.exp(-t * 4), lambda r: env_exp(iron_crack(r), 0.15), rng), 0.05, 0.35)
    return mix(out, stone_hit(rng), 0, 0.4)


def thatch_hit(rng: random.Random) -> Buf:
    return env_bell(lowpass(bandpass(noise(0.25, rng), 1800, 0.8), 3500), 0.15)


def thatch_break(rng: random.Random) -> Buf:
    rustle = env_bell(bandpass(noise(0.6, rng), lambda t: 1500 + 800 * math.sin(t * 9), 0.7), 0.2)
    whump = env_exp(sine_sweep(120, 60, 0.3), 0.25)
    return mix(rustle, whump, 0, 0.6)


def cloth_hit(rng: random.Random) -> Buf:
    return env_exp(lowpass(noise(0.18, rng), lambda t: 2500 * math.exp(-t * 20) + 300), 0.15)


def cloth_break(rng: random.Random) -> Buf:
    n = noise(0.45, rng)
    jitter = [0.4 + 0.6 * abs(math.sin(i / SR * rng.uniform(140, 220))) for i in range(len(n))]
    torn = [v * j for v, j in zip(n, jitter)]
    return env_bell(bandpass(torn, lambda t: 900 + 3000 * t, 1.2), 0.1)


def thud(rng: random.Random) -> Buf:
    boom = env_exp(sine_sweep(rng.uniform(70, 90), 38, 0.45, 5), 0.4)
    dirt = env_exp(lowpass(noise(0.4, rng), 350), 0.3)
    return mix(boom, dirt, 0, 0.8)


def rumble(rng: random.Random, seconds: float = 1.6) -> Buf:
    return env_bell(lowpass(lowpass(noise(seconds, rng), 140), 140), 0.25)


def poof(rng: random.Random) -> Buf:
    pop = env_exp(sine_sweep(rng.uniform(800, 1000), 180, 0.12, 6), 0.1)
    puff = env_bell(lowpass(noise(0.35, rng), lambda t: 4000 * math.exp(-t * 6) + 400), 0.12)
    return mix(pop, puff, 0, 0.6)


def squash(rng: random.Random) -> Buf:
    out, ph = [], 0.0
    n = int(0.32 * SR)
    for i in range(n):
        t = i / n
        f = 420 * (1 - t) + 110 * t + 18 * math.sin(i / SR * 2 * math.pi * 14)
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) + 0.3 * math.sin(2 * ph))
    return env_exp(out, 0.3)


def crown_ding(rng: random.Random) -> Buf:
    f = rng.uniform(1500, 1800)
    return env_exp(partials([f, f * 2.0, f * 3.01, f * 4.2], [0.9, 0.6, 0.4, 0.25], 1.0, rng), 0.9, 0.0005)


def treb_creak(rng: random.Random) -> Buf:
    return env_bell(bandpass(saw_pulse(rng.uniform(55, 80), 0.7, rng), lambda t: 500 + 300 * t, 4.0), 0.4)


def treb_whoosh(rng: random.Random) -> Buf:
    return env_bell(bandpass(noise(0.5, rng), lambda t: 300 + 2200 * math.sin(math.pi * min(1.0, t / 0.5)), 1.4), 0.45)


def treb_thunk(rng: random.Random) -> Buf:
    return mix(wood_hit(rng), thud(rng), 0, 0.5)


def fire_start(rng: random.Random) -> Buf:
    whoosh = env_bell(lowpass(noise(0.7, rng), lambda t: 600 + 3000 * t), 0.3)
    crackle = grains(0.7, lambda t: 30, lambda r: click(r, r.uniform(2000, 6000), 0.003), rng)
    return mix(whoosh, crackle, 0, 0.4)


def ui_click(rng: random.Random) -> Buf:
    return env_exp(partials([rng.uniform(1800, 2100), 3600], [0.05, 0.03], 0.06, rng), 0.05, 0.0005)


def ui_stamp(rng: random.Random) -> Buf:
    return mix(env_exp(sine_sweep(160, 70, 0.25), 0.2), env_exp(lowpass(noise(0.15, rng), 900), 0.1), 0, 0.7)


def jingle(rng: random.Random, notes: list[float], step: float = 0.12) -> Buf:
    out = silence(step * len(notes) + 1.2)
    for k, f in enumerate(notes):
        tone = pluck(f, 1.2, rng, 0.997)
        mix(out, lowpass(tone, 4000), k * step, 0.6)
        mix(out, lowpass(pluck(f * 2, 0.8, rng, 0.995), 5000), k * step + 0.004, 0.25)
    return out


def win_jingle(rng: random.Random) -> Buf:
    # D major-ish lute arpeggio: D4 F#4 A4 D5 A4 D5
    return jingle(rng, [293.66, 369.99, 440.0, 587.33, 440.0, 587.33])


def medal_gold(rng: random.Random) -> Buf:
    return mix(crown_ding(rng), jingle(rng, [587.33, 739.99, 880.0], 0.08), 0, 0.6)


def boom(rng: random.Random) -> Buf:
    blast = env_exp(lowpass(noise(1.4, rng), lambda t: 3000 * math.exp(-t * 7) + 120), 1.2, 0.001)
    sub = env_exp(sine_sweep(70, 30, 1.0, 3), 0.9)
    crack = env_exp(highpass(noise(0.08, rng), 1500), 0.05)
    out = mix(mix(blast, sub, 0, 0.9), crack, 0, 0.7)
    return mix(out, grains(1.0, lambda t: 40 * math.exp(-t * 3), lambda r: pebble(r), rng), 0.1, 0.3)


def burst(rng: random.Random) -> Buf:
    pop = env_exp(bandpass(noise(0.1, rng), 900, 0.8), 0.08)
    return mix(pop, cloth_break(rng), 0, 0.4)


def flask_shatter(rng: random.Random) -> Buf:
    return mix(glass_break(rng), env_exp(bandpass(noise(0.08, rng), 1800, 1.0), 0.06), 0, 0.5)


def frost_burst(rng: random.Random) -> Buf:
    hiss = env_bell(bandpass(noise(0.9, rng), lambda t: 6000 - 3000 * t, 2.0), 0.15)
    return mix(hiss, ice_crack(rng), 0.05, 0.6)


def void_hum(rng: random.Random) -> Buf:
    out, ph = [], 0.0
    n = int(1.6 * SR)
    for i in range(n):
        t = i / SR
        f = 55 + 25 * t + 6 * math.sin(t * 2 * math.pi * 5)
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) + 0.4 * math.sin(2.01 * ph) + 0.2 * math.sin(3.03 * ph))
    swirl = bandpass(noise(1.6, rng), lambda t: 400 + 1200 * t, 3.0)
    return env_bell(mix(out, swirl, 0, 0.5), 0.6)


def void_pop(rng: random.Random) -> Buf:
    return mix(env_exp(sine_sweep(120, 900, 0.18, 6), 0.15), poof(rng), 0.05, 0.8)


SOUNDS: dict[str, tuple[Callable[[random.Random], Buf], int]] = {
    "wood_hit": (wood_hit, 4),
    "wood_crack": (wood_crack, 3),
    "wood_break": (wood_break, 3),
    "stone_hit": (stone_hit, 4),
    "stone_crack": (stone_crack, 3),
    "stone_break": (stone_break, 3),
    "glass_hit": (glass_hit, 3),
    "glass_crack": (glass_hit, 2),
    "glass_break": (glass_break, 3),
    "ice_hit": (ice_hit, 3),
    "ice_crack": (ice_crack, 2),
    "ice_break": (ice_break, 2),
    "iron_hit": (iron_hit, 3),
    "iron_crack": (iron_crack, 2),
    "iron_break": (iron_break, 2),
    "thatch_hit": (thatch_hit, 2),
    "thatch_break": (thatch_break, 2),
    "cloth_hit": (cloth_hit, 2),
    "cloth_break": (cloth_break, 3),
    "thud": (thud, 3),
    "rumble": (rumble, 2),
    "poof": (poof, 3),
    "squash": (squash, 2),
    "crown_ding": (crown_ding, 2),
    "treb_creak": (treb_creak, 2),
    "treb_whoosh": (treb_whoosh, 3),
    "treb_thunk": (treb_thunk, 2),
    "fire_start": (fire_start, 2),
    "ui_click": (ui_click, 2),
    "ui_stamp": (ui_stamp, 1),
    "win_jingle": (win_jingle, 1),
    "medal_gold": (medal_gold, 1),
    "boom": (boom, 3),
    "burst": (burst, 2),
    "flask_shatter": (flask_shatter, 2),
    "frost_burst": (frost_burst, 2),
    "void_hum": (void_hum, 1),
    "void_pop": (void_pop, 2),
}


def write_wav(path: Path, buf: Buf) -> None:
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in buf)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if len(argv) >= 2 else 2
    out = Path(argv[1])
    out.mkdir(parents=True, exist_ok=True)
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    count = 0
    for name, (fn, variations) in SOUNDS.items():
        if only and name != only:
            continue
        for v in range(variations):
            rng = random.Random(f"{name}:{v}")
            buf = fade_head(fade_tail(normalize(fn(rng))))
            write_wav(out / f"{name}_{v}.wav", buf)
            count += 1
    print(f"wrote {count} files to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
