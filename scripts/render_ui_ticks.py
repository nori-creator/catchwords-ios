#!/usr/bin/env python3
"""Render the small UI ticks of the Collection map timeline and the Settings pickers (owner 2026-10-15, three
alternatives each so they can be compared on the device from 設定 › 開発者 › 開発者の試し).

Made the same way as the v6 kit (docs/design/catch-concepts/audio/tools/kit3.py: the `sfxlib` voices, every file
loudness-matched to its role with pyloudnorm, written as 48 kHz 16-bit PCM .caf through ffmpeg so AVAudioPlayer has no
encoder delay on a 60 ms sound). Role: `ui` = −26 LUFS, the quietest role of the kit (frequent sounds never tire the
ear); the app's sound level (控えめ 0.45 / しっかり 0.8) scales them down further.

    python3 scripts/render_ui_ticks.py          # writes ios/CatchWords/Resources/Sounds/cc6-{scroll,pick}-tick-{1,2,3}.caf

Prints one line per file (duration, peak, loudness) for the pull request.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, "..", "docs", "design", "catch-concepts", "audio", "tools")
RAW = os.path.join(HERE, "..", "docs", "design", "catch-concepts", "audio", "raw")
OUT = os.path.join(HERE, "..", "ios", "CatchWords", "Resources", "Sounds")
sys.path.insert(0, TOOLS)
from sfxlib import SR, NOTE, butter, db, fade, glass_drop, load, marimba, pitch_shift, stereo, t_axis, tick, whoosh  # noqa: E402

import pyloudnorm as pyln  # noqa: E402

UI_LUFS = -26.0
meter = pyln.Meter(SR, block_size=0.2)


def mixdown(parts, dur):
    out = np.zeros((int(dur * SR), 2))
    for x, t, gain_db in parts:
        if x.ndim == 1:
            x = stereo(x)
        s = int(t * SR)
        e = min(len(out), s + len(x))
        out[s:e] += x[: e - s] * db(gain_db)
    return out


def click(dur=0.004, lo=1800, hi=6500, seed=5):
    """A 4 ms burst of band-passed noise: the mechanical part of a dial detent."""
    rng = np.random.default_rng(seed)
    n = rng.standard_normal(int(0.03 * SR))
    n = butter(butter(n, "high", lo), "low", hi)
    env = np.exp(-t_axis(0.03) / dur)
    return stereo(n * env * 0.8)


def write(name, x, note):
    x = np.asarray(x, float)
    if x.ndim == 1:
        x = stereo(x)
    x = fade(x, 0.001, 0.02)
    padded = np.vstack([x, np.zeros((int(0.25 * SR), 2))])
    try:
        loud = meter.integrated_loudness(padded)
    except Exception:
        loud = -40.0
    if not np.isfinite(loud):
        loud = -40.0
    x = x * db(UI_LUFS - loud)
    x = x * min(1.0, db(-1.0) / (np.abs(x).max() + 1e-9))
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        pcm = (np.clip(x, -1, 1) * 8388607).astype("<i4")
        raw = b"".join(int(v).to_bytes(4, "little", signed=True)[:3] for v in pcm.reshape(-1))
        with wave.open(wav, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(3)
            w.setframerate(SR)
            w.writeframes(raw)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "pcm_s16le", "-f", "caf",
                        os.path.join(OUT, name + ".caf")], check=True)
    try:
        final = meter.integrated_loudness(np.vstack([x, np.zeros((int(0.25 * SR), 2))]))
    except Exception:
        final = float("nan")
    peak = 20 * np.log10(np.abs(x).max() + 1e-12)
    print(f"{name}.caf  {len(x) / SR * 1000:5.0f} ms  peak {peak:5.1f} dBFS  {final:6.1f} LUFS  — {note}")


def main():
    os.makedirs(OUT, exist_ok=True)
    # --- the Collection map timeline: one tick per word that passes the reading line while scrolling ---
    write("cc6-scroll-tick-1",
          mixdown([(tick(NOTE["A6"], 0.9), 0, 0), (marimba(NOTE["A6"], 0.09, hardness=0.4), 0.002, -6)], 0.1),
          "wood detent: a dry, round click (A6) with a touch of wooden body — the kit's scroll_detent, recommended")
    write("cc6-scroll-tick-2",
          mixdown([(whoosh(0.08, 1500, 4200, 0.9, peak=0.3, seed=21, air=0.1), 0, -4), (tick(NOTE["D7"], 0.35), 0.004, -8)], 0.09),
          "paper flick: a tiny airy brush of noise, like a page edge, with a faint high tick")
    write("cc6-scroll-tick-3", glass_drop(NOTE["E6"], 0.18), "glass drop: a bright musical blip (E6), the kit's discovery sound, shorter")
    # --- the Settings pickers: a pill chosen, a wheel passing a value ---
    write("cc6-pick-tick-1", marimba(NOTE["E6"], 0.14, hardness=0.5), "soft marimba: a round wooden tap (E6), recommended")
    write("cc6-pick-tick-2",
          mixdown([(click(seed=7), 0, 0), (tick(NOTE["F#7"], 0.5), 0.001, -6)], 0.05),
          "dial click: a crisp mechanical detent, 4 ms of noise and a high tick (F#7)")
    pop = load(os.path.join(RAW, "bubble_pop.mp3"))
    start = max(0, int(np.argmax(np.abs(pop).max(1) > 0.05)) - int(0.002 * SR))
    pop = pop[start:start + int(0.2 * SR)]
    write("cc6-pick-tick-3", pitch_shift(pop, 3), "bubble: the app's bubble pop a little higher — the same family as the tab bar's pon")


if __name__ == "__main__":
    main()
