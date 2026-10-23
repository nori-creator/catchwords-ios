"""Film mix v10 — v9's sounds on the v10 picture (the pen catches up once the names arrive, owner 2026-10-11 「⑧そうして」).
The ticks come where the bracket clicks on the catching-up pen; nothing else changes. v9's notes follow.
Film mix v9 — the same sounds as v8 (owner 2026-10-10 on v9: 「音はそのままでいい」), placed on the v9 picture.
v8's notes follow. Film mix v8 — the shot-to-tags phase with the old version's own sounds (owner 2026-10-10: "iosの前のバージョンの
ようにものを認識して（効果音も再現して）"). The sounds are the files the iOS app already ships,
ios/CatchWords/Resources/Sounds/cc-*.m4a, rendered from the card-catch prototype's synthesized SFX
(docs/prototype/cardcatch-src.html → scripts/render_cardcatch_sfx.py), at the app's own gains (SoundService.swift:
cc-shutter 0.9 × 2.803, the others 0.9), each placed where the prototype plays it:
  shutter     SFX.shutter()    the shot                                      (shoot)
  scan start  SFX.scanStart()  260 ms later, as the analysis starts          (analyze)
  tick        SFX.tick()       each time the bracket locks onto a thing      (anaFocus)
  found       SFX.found()      when the things are named                     (analyze, after the scan)
  pop         SFX.pop()        each tag, 140 ms + 130 ms apart               (showPick)
Nothing is added for the wait: the prototype has no waiting sound (the points of light carry the wait). The tap on a
tag keeps the approved flow's tap. The street ambience is the film's (the app plays none).
Times come from the films (audio/cues9.json, exported by cues9.js), one entry per wait rendered.
Master: glue compression -> -16 LUFS -> limiter -1 dBTP.   usage: python3 mix10.py <name in cues10.json> out.wav
"""
import sys, os, json, numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from sfxlib import *
import pyloudnorm as pyln
from scipy import signal

HERE = os.path.dirname(__file__)
RAW = os.path.join(HERE, '..', 'raw')
CC = os.environ.get('CC_SOUNDS') or os.path.join(HERE, '..', '..', '..', '..', '..', 'ios', 'CatchWords', 'Resources', 'Sounds')   # the repo's own files
ALL = json.load(open(os.environ.get('CUES') or os.path.join(HERE, '..', 'cues10.json')))   # CUES=: another film's cues
APP_GAIN = {'cc-shutter': .9 * 2.803, 'cc-scan-start': .9, 'cc-tick': .9, 'cc-found': .9, 'cc-pop': .9}   # SoundService.swift
BASE = -11.0                                              # one common trim for all the app's sounds against the ambience

def oneshot(name, length=0.12, pre=0.004, thresh=0.3):
    x = load(os.path.join(RAW, name + '.mp3')); m = np.abs(x).max(1)
    on = int(np.argmax(m > thresh * m.max())); a = max(0, on - int(pre * SR))
    return fade(x[a:a + int(length * SR)], 0.001, min(0.03, length / 3))
# The app's shutter is now B, cc-shutter-light (owner 2026-10-21), at its own gain (SoundService: 0.9 × 2.610).
SHUTTER_NOW = {'cc-shutter': ('cc-shutter-light', .9 * 2.610)}
def cc(name):
    f, g = name, APP_GAIN[name]
    if not os.path.exists(os.path.join(CC, f + '.m4a')) and name in SHUTTER_NOW: f, g = SHUTTER_NOW[name]
    return fade(load(os.path.join(CC, f + '.m4a')) * g, 0.0005, 0.02)

class Mix:
    def __init__(self, dur):
        self.n = int(dur * SR); self.bus = {k: np.zeros((self.n, 2)) for k in ('amb', 'sfx')}; self.events = []
    def add(self, bus, x, t, gain=0.0, label=None, haptic=None):
        if x.ndim == 1: x = stereo(x, 0)
        s = int(round(t * SR)); g = db(gain)
        if s < 0: x = x[-s:]; s = 0
        e = min(self.n, s + len(x))
        if e <= s: return
        self.bus[bus][s:e] += x[:e - s] * g
        if label: self.events.append({'t': round(t, 3), 'cue': label, 'bus': bus, 'gain_db': gain, 'haptic': haptic})

def concept_O9(mx, cu):
    sh = cu['shared']; T_CAP = sh['T_CAP']
    amb = load(os.path.join(RAW, 'amb_street.mp3')); amb = np.vstack([amb] * int(np.ceil(mx.n / len(amb) + 1)))[:mx.n]
    amb = peak_norm(butter(amb, 'high', 60), -1) * db(-27); lp = butter(amb, 'low', 900, 2)
    tt = np.arange(mx.n) / SR; k = np.clip((tt - T_CAP) / .35, 0, 1)[:, None]; mx.bus['amb'] += amb * (1 - k) + lp * k * db(-5)
    mx.add('sfx', cc('cc-shutter'), T_CAP - .01, BASE, label='shutter (cc-shutter)', haptic='transient 0.8/0.6')
    mx.add('sfx', cc('cc-scan-start'), cu['bracketIn'], BASE, label='analysis starts, the bracket appears (cc-scan-start)')
    for t, tid in zip(cu['lock'], cu['lockIds']):
        mx.add('sfx', cc('cc-tick'), t, BASE, label=f'bracket locks: {tid} (cc-tick)', haptic='selection')
    mx.add('sfx', cc('cc-found'), cu['found'], BASE, label='names arrive (cc-found)')
    ids = [tg['id'] for tg in sh['tags']]
    for tid, t in zip(ids, cu['tags']):
        mx.add('sfx', cc('cc-pop'), t, BASE, label=f'tag: {tid} (cc-pop)', haptic='impact light')
    mx.add('sfx', oneshot('ui_tap', .09), cu['tap'] + .02, -15, label='tap the word (as the approved flow)', haptic='transient 0.5/0.7')

def master(mx):
    mixd = butter(mx.bus['amb'] + mx.bus['sfx'], 'high', 30)
    e = envelope_follower(mixd, .005, .12); thr = db(-20)
    gr = np.where(e > thr, (thr * (e / thr) ** .5) / np.maximum(e, 1e-9), 1.0); mixd *= gr[:, None]
    meter = pyln.Meter(SR)
    for _ in range(3): lufs = meter.integrated_loudness(mixd); mixd = limiter(mixd * db(-16 - lufs), -1.0)
    return mixd, meter.integrated_loudness(mixd)

if __name__ == '__main__':
    c, out = sys.argv[1], sys.argv[2]
    cu = ALL[c]; mx = Mix(cu['end'])
    concept_O9(mx, cu)
    y, lufs = master(mx)
    import wave
    pcm = (np.clip(y, -1, 1) * 32767).astype('<i2')
    with wave.open(out, 'wb') as w: w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    tp = 20 * np.log10(np.abs(signal.resample_poly(y, 4, 1, axis=0)).max() + 1e-12)
    json.dump(sorted(mx.events, key=lambda e: e['t']), open(out.replace('.wav', '_cues.json'), 'w'), ensure_ascii=False, indent=1)
    print(c, f'LUFS {lufs:.1f}  truepeak {tp:.2f} dBTP  dur {len(y) / SR:.2f}s  cues {len(mx.events)}')
