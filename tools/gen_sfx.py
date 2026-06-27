#!/usr/bin/env python3
"""Win/lose stinger generator for do-fu-sui-kyo (synthesized, stdlib only).

Two short SFX, no external assets or dependencies:
  win.wav   bright ascending major arpeggio (C5-E5-G5-C6) + a high sparkle ring
  lose.wav  descending notes ending in a drooping pitch-bend (sad-trombone "aww")
  draw.wav  two equal flat beeps -- neutral, neither rising nor falling

Writes 16-bit mono PCM WAV into art/ (alongside the card-face pngs). After running,
let Godot import them once -- open the editor, or `godot --headless --import` -- exactly
like the sprites; that creates the .import sidecars the game loads through.

The "satisfying" feel is a calibration knob, not a fixed number: tune the note lists,
durations, and harmonic weights below until it sounds right in-headset.

  python tools/gen_sfx.py           # write art/win.wav + art/lose.wav
  python tools/gen_sfx.py selftest  # assert the render is sane (ponytail's one check)
"""

from __future__ import annotations

import math
import struct
import sys
import wave
from pathlib import Path

RATE = 44100  # Hz, 16-bit mono
ART = Path(__file__).resolve().parent.parent / "art"

# Timbres = additive harmonic weights (fundamental, 2nd, 3rd, ...).
BELL = (1.0, 0.5, 0.28, 0.12)  # bright, ringing -> triumphant
SOFT = (1.0, 0.0, 0.22, 0.0, 0.08)  # odd harmonics only -> mellow, reedy, sad
MILD = (1.0, 0.25, 0.1)  # in between -> a plain, neutral "boop"


def midi(n: int) -> float:
    """MIDI note number -> frequency in Hz (equal temperament, A4=440)."""
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def tone(
    freq: float,
    dur: float,
    harmonics=(1.0,),
    attack: float = 0.005,
    decay: float = 3.0,
    bend: float = 1.0,
    vib: float = 0.0,
    vib_hz: float = 6.0,
    release: float = 0.03,
) -> list[float]:
    """One note: additive sines with phase accumulation (so pitch bend/vibrato stay clean),
    a fast attack, exponential decay, and a short release fade to zero so the buffer never
    hard-stops mid-amplitude (that truncation clicks). `bend` is the end/start frequency
    ratio, applied EXPONENTIALLY so the glide is even in pitch (Hz-linear ramps waver);
    `vib` is vibrato depth as a fraction of the frequency."""
    n = max(1, int(dur * RATE))
    rel_t = min(release, dur * 0.3)  # cap so short notes stay crisp
    phases = [0.0] * len(harmonics)
    out = [0.0] * n
    for i in range(n):
        t = i / RATE
        f = freq * bend ** (i / n)
        if vib:
            f *= 1.0 + vib * math.sin(2.0 * math.pi * vib_hz * t)
        s = 0.0
        for k, w in enumerate(harmonics):
            phases[k] += 2.0 * math.pi * f * (k + 1) / RATE
            s += w * math.sin(phases[k])
        rfade = 1.0 if dur - t >= rel_t else max(0.0, (dur - t) / rel_t)
        env = min(1.0, t / attack) * math.exp(-decay * t) * rfade
        out[i] = s * env
    return out


def overlay(base: list[float], ins: list[float], start: int, gain: float) -> None:
    """Mix `ins` into `base` in place, starting at sample `start`."""
    for i, s in enumerate(ins):
        if 0 <= start + i < len(base):
            base[start + i] += gain * s


def build_win() -> list[float]:
    out: list[float] = []
    for m in (72, 76, 79):  # C5 E5 G5 -- quick ascending steps
        out += tone(midi(m), 0.11, BELL, attack=0.004, decay=6.0)
    out += tone(midi(84), 0.55, BELL, attack=0.004, decay=3.0)  # land + ring on C6
    spark = tone(midi(96), 0.45, (0.0, 1.0, 0.0, 0.6), decay=4.0, vib=0.01)  # high C7 shimmer
    overlay(out, spark, len(out) - len(spark), 0.22)
    return out


def build_lose() -> list[float]:
    out: list[float] = []
    for m in (64, 62, 60):  # E4 D4 C4 -- three descending steps (the "1,2,3")
        out += tone(midi(m), 0.17, SOFT, attack=0.01, decay=2.5)
    # The droop: land on Bb3 and slide a clean minor-third down to settle -> the "aww".
    # One note (no re-articulated Bb3), exponential glide, release fade -> no warble/click.
    out += tone(midi(58), 0.55, SOFT, attack=0.01, decay=1.8, bend=0.84)
    return out


def build_draw() -> list[float]:
    # Neutral: two equal beeps on one pitch -- no rise (win) nor fall (lose), just "even".
    out: list[float] = []
    for _ in range(2):
        out += tone(midi(62), 0.13, MILD, attack=0.005, decay=4.0)  # D4, D4
    return out


def write_wav(path: Path, samples: list[float]) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    gain = 0.9 / peak  # normalize to -0.9 dBFS-ish, leave a little headroom
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767)) for s in samples
    )
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


def selftest() -> None:
    sounds = {"win": build_win(), "lose": build_lose(), "draw": build_draw()}
    for name, buf in sounds.items():
        assert 0.2 * RATE < len(buf) < 2.0 * RATE, f"{name}: {len(buf) / RATE:.2f}s out of range"
        assert max(abs(s) for s in buf) > 0.1, f"{name}: silent"
    print("ok: " + ", ".join(f"{n} {len(b) / RATE:.2f}s" for n, b in sounds.items()))


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "selftest":
        selftest()
        return
    ART.mkdir(exist_ok=True)
    write_wav(ART / "win.wav", build_win())
    write_wav(ART / "lose.wav", build_lose())
    write_wav(ART / "draw.wav", build_draw())
    print(f"wrote win.wav, lose.wav, draw.wav into {ART}")


if __name__ == "__main__":
    main()
