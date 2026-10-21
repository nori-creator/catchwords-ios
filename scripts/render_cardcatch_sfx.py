#!/usr/bin/env python3
"""Render the card-catch prototype's synthesized sounds to .m4a files (offline, numpy only).

Source of truth: docs/prototype/cardcatch-src.html — the `SFX` object and its helpers
`osc`, `nz`, `env`, `impulse` and the bus graph built in `ac()`:

    voice → AU.sfx (gain .7 = sfxLevel at vol "low") ─┬─────────────→ master (.9) → compressor → out
                                                      └→ srev (.35) → convolver(impulse 2.8 s, decay 2.2) → revOut (.55) ↗

WebAudio details reproduced here:
  * oscillators are band-limited (additive partials below Nyquist), detune in cents,
    `frequency.exponentialRampToValueAtTime(slide, t + dur)`
  * `env()`: 0 → linear ramp to peak in `a` → exponential ramp to 0.0001 over `rel`
  * BiquadFilter (Audio EQ cookbook as in the WebAudio spec: lowpass/highpass Q in dB, bandpass Q linear),
    with the exponential frequency ramp f0 → f1 over `dur`
  * ConvolverNode normalisation (spec `normalizationScale`: RMS power, GainCalibration 0.00125)
  * DynamicsCompressor threshold -14 dB, ratio 3, knee 30 dB, attack 3 ms, release 250 ms
Random parts (noise buffer, reverb impulse, twinkle notes) use a fixed seed so files are reproducible.

Loudness: every file is scaled by ONE common factor — the factor that brings the prototype's
`SFX.page(1)` ("bubble" pon) to the same peak as the shipped pon-bubble-open.m4a (-1.5 dBFS) — so the
sounds keep the prototype's loudness relative to each other and to the pon. A file that would clip at
that factor is turned down and the difference is reported, to be restored with its SFX gain in Swift.

Usage: python3 scripts/render_cardcatch_sfx.py [name …]   (writes ios/CatchWords/Resources/Sounds/cc-*.m4a;
       with names, only those files, e.g. `cc-land`)
"""
import math
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "ios", "CatchWords", "Resources", "Sounds")
PON_PEAK_DB = -1.5  # measured peak of pon-bubble-open.m4a
rng = np.random.default_rng(20261002)


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# ---------------------------------------------------------------- graph pieces

def env_curve(n, t, a, peak, rel, stop):
    """env(g,t,a,peak,0,rel): 0 at t, linear to peak at t+a, exponential to .0001 at t+a+rel."""
    tt = np.arange(n) / SR
    g = np.zeros(n)
    on = (tt >= t) & (tt < t + a)
    g[on] = peak * (tt[on] - t) / a
    dec = (tt >= t + a) & (tt < t + a + rel)
    g[dec] = peak * (0.0001 / peak) ** ((tt[dec] - (t + a)) / rel)
    tail = (tt >= t + a + rel) & (tt < stop)
    g[tail] = 0.0001
    return g


def freq_curve(n, f, t, dur, slide):
    tt = np.arange(n) / SR
    fr = np.full(n, float(f))
    if slide:
        seg = (tt >= t) & (tt < t + dur)
        fr[seg] = f * (slide / f) ** ((tt[seg] - t) / dur)
        fr[tt >= t + dur] = slide
    return fr


def partials(kind):
    """(harmonic numbers, amplitudes) of WebAudio's basic waveforms, normalised to peak 1."""
    if kind == "sine":
        return np.array([1]), np.array([1.0])
    ks = np.arange(1, 200)
    if kind == "square":
        amp = np.where(ks % 2 == 1, 4 / (np.pi * ks), 0.0)
    elif kind == "triangle":
        amp = np.where(ks % 2 == 1, 8 / (np.pi ** 2 * ks ** 2) * (-1.0) ** ((ks - 1) // 2), 0.0)
    elif kind == "sawtooth":
        amp = 2 / (np.pi * ks) * (-1.0) ** (ks + 1)
    else:
        raise ValueError(kind)
    ph = np.linspace(0, 2 * np.pi, 4096, endpoint=False)
    peak = np.max(np.abs(sum(a * np.sin(k * ph) for k, a in zip(ks[:40], amp[:40]))))
    return ks, amp / peak


def osc(buf, kind, f, t, dur, peak, a=0.005, rel=None, detune=0, slide=None):
    """The prototype's osc(type,f,t,dur,peak,dest,{a,rel,detune,slide})."""
    rel = dur if rel is None else rel
    stop = t + a + rel + 0.05
    n = len(buf)
    fr = freq_curve(n, f, t, dur, slide) * 2 ** (detune / 1200)
    phase = np.cumsum(2 * np.pi * fr / SR)
    s0 = int(t * SR)
    phase -= phase[min(s0, n - 1)]
    ks, amps = partials(kind)
    sig = np.zeros(n)
    for k, amp in zip(ks, amps):
        if amp == 0:
            continue
        ok = (k * fr) < SR / 2
        if not ok.any():
            break
        sig += np.where(ok, amp * np.sin(k * phase), 0.0)
    g = env_curve(n, t, a, peak, rel, stop)
    live = (np.arange(n) / SR >= t) & (np.arange(n) / SR < stop)
    buf += sig * g * live


NOISE = rng.uniform(-1, 1, SR * 2)


def biquad(x, kind, f_of_n, q):
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    block = 16
    for start in range(0, len(x), block):
        f = min(float(f_of_n[start]), SR / 2 - 1)
        w0 = 2 * math.pi * f / SR
        cw, sw = math.cos(w0), math.sin(w0)
        if kind == "bandpass":
            alpha = sw / (2 * q)
            b0, b1, b2 = alpha, 0.0, -alpha
        else:
            alpha = sw / (2 * 10 ** (q / 20))
            if kind == "lowpass":
                b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
            else:  # highpass
                b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
        b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
        for i in range(start, min(start + block, len(x))):
            xi = x[i]
            yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, xi, y1, yi
            y[i] = yi
    return y


def nz(buf, t, dur, kind="bandpass", f0=1000, f1=None, q=1, peak=0.2, a=0.005):
    """The prototype's nz(t,dur,{type,f0,f1,q,peak,a}) (white noise → biquad → env)."""
    n = len(buf)
    stop = t + dur + 0.1
    s0, s1 = int(t * SR), min(n, int(stop * SR))
    off = int(rng.uniform(0, 1) * SR)  # s.start(t, Math.random())
    src = np.zeros(n)
    seg = NOISE[off:off + (s1 - s0)]
    src[s0:s0 + len(seg)] = seg
    fr = freq_curve(n, f0, t, dur, f1)
    y = biquad(src, kind, fr, q)
    buf += y * env_curve(n, t, a, peak, dur, stop)


def impulse(sec=2.8, decay=2.2):
    n = int(SR * sec)
    i = np.arange(n)
    return [rng.uniform(-1, 1, n) * (1 - i / n) ** decay for _ in range(2)]


IR = impulse()


def convolver_scale(ir):
    power = math.sqrt(sum(float(np.sum(c * c)) for c in ir) / (len(ir) * len(ir[0])))
    power = max(power, 0.000125)
    return (1 / power) * 0.00125 * (44100 / SR)


IR_SCALE = convolver_scale(IR)


def fftconv(x, h):
    n = len(x) + len(h) - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(h, m), m)[:n]


def compressor(x, thr=-14.0, ratio=3.0, knee=30.0, attack=0.003, release=0.25):
    def curve(db):
        if db < thr:
            return db
        if db < thr + knee:
            return db + (1 / ratio - 1) * (db - thr) ** 2 / (2 * knee)
        top = thr + knee + (1 / ratio - 1) * knee / 2
        return top + (db - thr - knee) / ratio

    ga, gr = math.exp(-1 / (attack * SR)), math.exp(-1 / (release * SR))
    level = 0.0
    out = np.empty_like(x)
    for i, v in enumerate(x):
        a = abs(v)
        level = ga * level + (1 - ga) * a if a > level else gr * level + (1 - gr) * a
        db = 20 * math.log10(max(level, 1e-9))
        out[i] = v * 10 ** ((curve(db) - db) / 20)
    return out


def render(voices, seconds):
    """voices(buf) writes into the AU.sfx input; returns the mono master output."""
    n = int(SR * seconds)
    dry = np.zeros(n)
    voices(dry)
    sfx = dry * 0.7                       # AU.sfx = sfxLevel() (.7)
    send = sfx * 0.35                     # AU.srev
    wet = [fftconv(send, c)[:n] * IR_SCALE for c in IR]
    wet_mono = (wet[0] + wet[1]) / 2      # stereo convolver folded to mono like the pon files
    master = (sfx + wet_mono * 0.55) * 0.9  # revOut .55, master .9
    return compressor(master)


# ---------------------------------------------------------------- the prototype's SFX

def page_open(b):  # SFX.page(1), psfx "bubble" — the loudness reference (pon-bubble-open)
    osc(b, "sine", 420, 0, .09, .26, slide=1100, a=.002)
    osc(b, "sine", 1400, .03, .05, .05)


def shutter(b):
    nz(b, 0, .03, kind="highpass", f0=3000, peak=.5)
    nz(b, .055, .05, kind="bandpass", f0=2200, q=2, peak=.35)
    osc(b, "square", 160, 0, .04, .08)
    osc(b, "sine", 90, .05, .08, .12)


def shutter_light(b):  # owner 2026-10-20 「シャッター音の案」: no low thump — a two-stage "ka-sha" of bright clicks
    nz(b, 0, .018, kind="highpass", f0=4000, peak=.55)
    nz(b, .045, .03, kind="bandpass", f0=3200, q=1.5, peak=.4)
    osc(b, "triangle", 1400, 0, .025, .05)


def shutter_soft(b):  # a soft "pop" with a short click on top
    nz(b, 0, .015, kind="highpass", f0=3500, peak=.35)
    osc(b, "sine", 900, 0, .08, .16, slide=1700)


def shutter_digital(b):  # a short digital "pi-pip"
    osc(b, "sine", 2400, 0, .045, .1)
    osc(b, "sine", 3200, .06, .05, .08)


def tick(b):
    osc(b, "sine", 2100, 0, .05, .08)
    osc(b, "triangle", 1050, 0, .07, .05)


def scan_start(b):
    osc(b, "sine", 220, 0, 2.2, .06, a=.4, slide=880)
    osc(b, "sine", 330, 0, 2.2, .04, a=.6, slide=1320, detune=7)
    nz(b, 0, 2.4, kind="bandpass", f0=400, f1=5000, q=3, peak=.05, a=1.2)


def found(b):
    for i, m in enumerate([76, 83, 88]):
        osc(b, "sine", mtof(m), i * .06, .6, .07, rel=.9)


def pop(b):
    osc(b, "sine", 520, 0, .14, .2, slide=1200)
    osc(b, "sine", 1560, .02, .12, .05)


def cands(n):  # wsfx "trio" (the default branch): one note per candidate
    def v(b):
        for i in range(n):
            u, up = i * .09, 1.26 ** i
            osc(b, "sine", 420 * up, u, .09, .22, slide=1100 * up, a=.002)
            osc(b, "sine", 1400 * up, u + .03, .05, .04)
    return v


def charge(b):  # gsfx "harp" (the default branch)
    for i, m in enumerate([67, 69, 72, 74, 76, 79, 81, 84, 86, 88]):
        f = mtof(m)
        osc(b, "triangle", f, i * .06, .5, .06, a=.003, rel=.7)
        osc(b, "sine", f * 2, i * .06, .2, .015, a=.003)


def fly(b):  # gsfx "harp"
    osc(b, "sine", 900, 0, .5, .035, a=.08, slide=1800)
    for i, m in enumerate([100, 98, 103, 101]):
        osc(b, "sine", mtof(m), .08 + i * .09, .25, .025, rel=.4)


def reveal(b):
    nz(b, 0, .08, kind="lowpass", f0=800, peak=.4)
    osc(b, "sine", 55, 0, .6, .35, slide=40)
    for m in [60, 64, 67, 72, 76]:
        osc(b, "sawtooth", mtof(m), .02, 1.6, .035, a=.03, detune=-6)
        osc(b, "sawtooth", mtof(m), .02, 1.6, .035, a=.03, detune=6)
    for i, m in enumerate([84, 88, 91, 96, 100]):
        osc(b, "triangle", mtof(m), .12 + i * .07, 1.2, .06, rel=1.4)
    nz(b, .1, 1.4, kind="highpass", f0=8000, peak=.04, a=.2)


TWINKLE_NOTES = [96 + int(rng.uniform(0, 1) * 10) for _ in range(6)]  # Math.floor(Math.random()*10)


def twinkle(b):
    for i, m in enumerate(TWINKLE_NOTES):
        osc(b, "sine", mtof(m), i * .05, .2, .025, rel=.4)


def land(b):  # SFX.land: a word fills its dex slot
    osc(b, "sine", 140, 0, .25, .3, slide=60)
    nz(b, 0, .06, kind="lowpass", f0=1200, peak=.25)
    for i, m in enumerate([91, 95, 98, 103]):
        osc(b, "sine", mtof(m), .05 + i * .05, .5, .05, rel=.8)


SOUNDS = [
    ("cc-shutter", shutter, 1.6),
    ("cc-shutter-light", shutter_light, 1.2),
    ("cc-shutter-soft", shutter_soft, 1.2),
    ("cc-shutter-digital", shutter_digital, 1.2),
    ("cc-tick", tick, 1.4),
    ("cc-scan-start", scan_start, 4.0),
    ("cc-found", found, 2.6),
    ("cc-pop", pop, 1.6),
    ("cc-cands-1", cands(1), 1.6),
    ("cc-cands-2", cands(2), 1.7),
    ("cc-cands-3", cands(3), 1.8),
    ("cc-charge-harp", charge, 3.0),
    ("cc-fly-harp", fly, 2.4),
    ("cc-reveal", reveal, 4.0),
    ("cc-twinkle", twinkle, 2.0),
    ("cc-land", land, 2.4),
]


def trim(x, floor_db=-40.0):
    """Cut the reverb tail once it stays below `floor_db` under the file's peak (the shipped pon files end at
    about -40 dB, 0.6 s); 30 ms fade."""
    peak = np.max(np.abs(x))
    thr = peak * 10 ** (floor_db / 20)
    idx = np.nonzero(np.abs(x) > thr)[0]
    end = min(len(x), (idx[-1] if len(idx) else len(x)) + int(.02 * SR))
    y = x[:end].copy()
    fade = min(len(y), int(.03 * SR))
    y[-fade:] *= np.linspace(1, 0, fade)
    return y


def write_m4a(path, x):
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, "a.wav")
        pcm = np.clip(x, -1, 1)
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((pcm * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "96k",
                        "-movflags", "+faststart", path], check=True)


def main():
    ref = render(page_open, 1.2)
    common = 10 ** (PON_PEAK_DB / 20) / np.max(np.abs(ref))
    print(f"common gain {common:.3f} (page(1) peak {20 * math.log10(np.max(np.abs(ref))):.1f} dBFS before)")
    report = []
    only = set(sys.argv[1:])
    for name, voices, secs in SOUNDS:
        if only and name not in only:
            continue
        y = render(voices, secs) * common
        peak = float(np.max(np.abs(y)))
        extra = 1.0
        limit = 10 ** (PON_PEAK_DB / 20)
        if peak > limit:          # would clip: turn the file down, Swift restores it with the SFX gain
            extra = peak / limit
            y = y / extra
        y = trim(y)
        write_m4a(os.path.join(OUT_DIR, name + ".m4a"), y)
        report.append((name, len(y) / SR, 20 * math.log10(max(peak, 1e-9)), extra))
    print(f"{'file':18} {'sec':>5} {'peak dB at common gain':>24} {'gain x':>7}")
    for name, sec, pk, extra in report:
        print(f"{name:18} {sec:5.2f} {pk:24.1f} {extra:7.3f}")


if __name__ == "__main__":
    sys.exit(main())
