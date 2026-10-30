#!/usr/bin/env python3
"""Render the diary book's page turn (2026-10-25, the book on iPhone Duo's inner display: `BookSpreadView`).

A sheet of paper turned over, in three parts, all from noise (no pitched note, so it sits under any earcon):
  1. the lift — a tiny dry crinkle as the edge leaves the page under the finger;
  2. the swish — airy band-passed noise gliding up as the sheet goes over, moving right to left in the stereo field
     (the page travels that way), with a quick flutter in it;
  3. the landing — a soft, low flap as the sheet settles on the other page.

Made like the other UI sounds (scripts/render_ui_ticks.py: the `sfxlib` voices, loudness-matched with pyloudnorm, written
as 48 kHz 16-bit PCM .caf through ffmpeg so AVAudioPlayer has no encoder delay). Role: `motion` = −24 LUFS (a sound
made by something moving across the screen; the kit's ticks are −26). The app's sound level scales it further, and a
riffle's quick flicks play it at 0.55.

    pip install numpy scipy pyloudnorm
    python3 scripts/render_page_turn.py      # writes ios/CatchWords/Resources/Sounds/cc6-page-turn.caf
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "..", "docs", "design", "catch-concepts", "audio", "tools")
OUT = os.path.join(HERE, "..", "ios", "CatchWords", "Resources", "Sounds")
sys.path.insert(0, TOOLS)
from sfxlib import SR, butter, db, fade, stereo, t_axis, whoosh  # noqa: E402

import pyloudnorm as pyln  # noqa: E402

MOTION_LUFS = -24.0
meter = pyln.Meter(SR, block_size=0.2)


def place(out, x, t, gain_db=0.0):
    if x.ndim == 1:
        x = stereo(x)
    s = int(t * SR)
    e = min(len(out), s + len(x))
    out[s:e] += x[: e - s] * db(gain_db)


def crinkle(dur=0.05, seed=11, density=260):
    """Sparse micro-clicks of bright noise: paper fibres giving way."""
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    y = np.zeros(n)
    for _ in range(int(density * dur)):
        at = rng.integers(0, max(1, n - 200))
        ln = rng.integers(40, 160)
        burst = rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln / 4)) * rng.uniform(0.3, 1.0)
        y[at:at + ln] += burst
    y = butter(butter(y, "high", 2600), "low", 9000)
    return y / (np.abs(y).max() + 1e-9)


def flap(seed=13):
    """The sheet settling: a short, dark puff of noise and a faint low body."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.12)
    puff = butter(rng.standard_normal(len(t)), "low", 1100) * np.exp(-t / 0.028)
    body = np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.035) * 0.35
    y = puff / (np.abs(puff).max() + 1e-9) + body
    return y / (np.abs(y).max() + 1e-9)


def page_turn():
    dur = 0.62
    out = np.zeros((int(dur * SR), 2))
    # 1. The lift.
    place(out, crinkle(0.045, seed=3) * 0.6, 0.0, -10)
    # 2. The swish, right to left, with a flutter (the sheet's quick wobble as it goes over).
    sw = whoosh(0.44, 1100, 3600, bw_oct=1.5, amp=1.0, peak=0.42, pan0=0.55, pan1=-0.55, seed=29, air=0.35)
    t = t_axis(len(sw) / SR)
    flutter = 1 + 0.28 * np.sin(2 * np.pi * 17 * t + 0.8) * np.exp(-t / 0.3)
    sw = sw * flutter[:, None]
    place(out, sw, 0.02, 0)
    place(out, crinkle(0.2, seed=5, density=90) * 0.5, 0.08, -16)
    # 3. The landing.
    place(out, flap(), 0.43, -7)
    return out


def write(name, x, note):
    x = fade(np.asarray(x, float), 0.001, 0.03)
    padded = np.vstack([x, np.zeros((int(0.25 * SR), 2))])
    loud = meter.integrated_loudness(padded)
    x = x * db(MOTION_LUFS - loud)
    x = x * min(1.0, db(-1.0) / (np.abs(x).max() + 1e-9))
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
        with wave.open(wav, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "pcm_s16le", "-f", "caf",
                        os.path.join(OUT, name + ".caf")], check=True)
    final = meter.integrated_loudness(np.vstack([x, np.zeros((int(0.25 * SR), 2))]))
    peak = 20 * np.log10(np.abs(x).max() + 1e-12)
    print(f"{name}.caf  {len(x) / SR * 1000:5.0f} ms  peak {peak:5.1f} dBFS  {final:6.1f} LUFS  — {note}")


def main():
    os.makedirs(OUT, exist_ok=True)
    write("cc6-page-turn", page_turn(), "a sheet turned over: lift, right-to-left swish with a flutter, soft landing")


if __name__ == "__main__":
    main()
