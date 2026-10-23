"""Film mixes v6. Times come from the films themselves (audio/cues6.json, exported by cues6.js).

Owner feedback this answers: the sound that ran round the outline in v5 P1 was unpleasant (an airy noise sweep with a
7 Hz vibrato on top, high up at 3.5-4.7 kHz), and the sounds should be designed as a set.

The set — one key (D major), one job per layer, nothing hissy:
  lock     カチャッ: two small mechanical transients 38 ms apart (filtered, nothing above 9 kHz) and a faint in-key
           ting — percussive, where the bracket locks, panned to the thing (+ Haptics.selection, as the old screen).
  trace    the light round the outline: a soft bowed-glass tone (two voices, fixed 4-cent detune — no vibrato, no
           noise) that swells with the light and rises one step while it travels; its pan follows the light's head.
  close    the loop closes: one soft bell, climbing per thing (D6, F#6, A6).
  wait     a steady low pad (D5 + A5, no LFO) while the names are looked up.
  tags     a tick + a bell per word (climbing), a soft chord when all are in (as v5).
  D        as v5 (melt, float, the ways to say, choose, voice). GET: the stage lights up (a warm chord), the voice says
           the word, the catch jingle (D6-F#6-A6-D7 bells over marimba, a sparkle), then the 図鑑 finale as v5.
  E        the page waits in quiet (music only). The reveal: two soft bells per line (start → end, panned with the
           light as it writes the line, climbing line by line) over a faint shimmer; a bell pair when all is written.
The removed v5 layers: the noise sweep + vibrato tone (trace), the lift whoosh and the sheen grains (they cluttered
the trace), the wobbling think-bed, E's grain sweeps and particle cloud.
Master: glue compression -> -16 LUFS -> limiter -1 dBTP.   usage: python3 mix6.py F|S|E out.wav
"""
import sys, os, json, numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from sfxlib import *
import pyloudnorm as pyln
from scipy import signal

HERE = os.path.dirname(__file__)
RAW = os.path.join(HERE, '..', 'raw')
ALL = json.load(open(os.environ.get('CUES') or os.path.join(HERE, '..', 'cues6.json')))   # CUES=: another film's cues
PENTA = ['D6', 'E6', 'F#6', 'A6', 'B6', 'D7', 'E7', 'F#7', 'A7', 'B7']

def pan_of(x): return float(np.clip((x - 540) / 540 * .8, -.8, .8))
def oneshot(name, length=0.12, pre=0.004, thresh=0.3):
    x = load(os.path.join(RAW, name + '.mp3')); m = np.abs(x).max(1)
    on = int(np.argmax(m > thresh * m.max())); a = max(0, on - int(pre * SR))
    return fade(x[a:a + int(length * SR)], 0.001, min(0.03, length / 3))
def clip(name, start=0, end=None): return fade(load(os.path.join(RAW, name + '.mp3'), start, end), 0.002, 0.03)

# ---------------------------------------------------------------- v6 voices
def lock_click(seed=0, pitch='A6'):
    """the bracket locking on (カチャッ): two soft mechanical transients 38 ms apart + a faint in-key ting"""
    rng = np.random.default_rng(seed); L = int(.5 * SR); y = np.zeros(L); t = np.arange(L) / SR
    for t0, tau, lo, hi, amp in [(0, .0012, 1200, 4800, .55), (.038, .002, 1500, 5200, .7)]:          # soft, band-limited (rounded, not a hiss)
        s = int(t0 * SR); n = int(.03 * SR); tt = np.arange(n) / SR
        y[s:s + n] += butter(rng.standard_normal(n), 'band', [lo, hi], 2) * np.exp(-tt / tau) * amp
    for t0, f, tau, a in [(0, 1500, .005, .45), (.038, 2350, .01, .3), (.038, 380, .008, .4)]:     # small resonances: a mechanism, not a crackle
        s = int(t0 * SR); tt = t[:L - s]; y[s:] += np.sin(2 * np.pi * f * tt) * np.exp(-tt / tau) * a
    y = butter(butter(y, 'low', 6000, 4), 'high', 220, 2); y = y / (np.abs(y).max() + 1e-9)
    ting = bell(NOTE[pitch], .5, index=.6, decay=8).mean(1); s = int(.042 * SR); y[s:s + len(ting)] += ting[:L - s] * .3
    return fade(y, .0005, .05)
def trace_tone(dur, f0, f1):
    """the light round the outline: a soft bowed-glass tone, swelling with the light, rising a step (no noise, no vibrato)"""
    t = t_axis(dur); x = t / dur; e = x * x * (3 - 2 * x); f = f0 * (f1 / f0) ** e
    y = np.zeros(len(t))
    for det, amp in ((0, 1.0), (4, .6)):
        ph = 2 * np.pi * np.cumsum(f * 2 ** (det / 1200)) / SR; y += amp * (np.sin(ph) + .22 * np.sin(2 * ph) + .07 * np.sin(3 * ph))
    y = butter(y * np.sin(np.pi * x) ** 1.5, 'low', 5000, 2)
    return y / (np.abs(y).max() + 1e-9)
def moving_pan(y, xs):
    p = np.interp(np.linspace(0, 1, len(y)), np.linspace(0, 1, len(xs)), [pan_of(x) for x in xs]); a = (p + 1) * np.pi / 4
    return np.stack([y * np.cos(a), y * np.sin(a)], 1)
def calm_pad(dur, notes=('D5', 'A5')):
    t = t_axis(dur); y = sum(np.sin(2 * np.pi * NOTE[n] * t) + .2 * np.sin(4 * np.pi * NOTE[n] * t) for n in notes)
    env = np.minimum(1, t / .9) * np.minimum(1, (dur - t) / .5) * np.linspace(.65, 1, len(t))
    y = butter(y * env, 'low', 2500, 2); return np.stack([y, np.roll(y, 41)], 1) / (np.abs(y).max() + 1e-9)
def catch_jingle():
    out = np.zeros((int(2.3 * SR), 2))
    for i, (b, m) in enumerate([('D6', 'D5'), ('F#6', 'F#5'), ('A6', 'A5'), ('D7', 'D6')]):
        s = int(i * .07 * SR); bb = bell(NOTE[b], 1.7, index=1.3) * (1 - .05 * i); mm = marimba(NOTE[m], .5, hardness=.5) * .5
        out[s:s + len(bb)] += bb; out[s:s + len(mm)] += mm
    g = grains(.9, [NOTE[n] for n in ('A7', 'D8', 'F#7', 'B7')], 30, glen=(.02, .05), pan_spread=.8); s = int(.2 * SR); out[s:s + len(g)] += g * .8
    return out / (np.abs(out).max() + 1e-9)
def chord_hit(notes, spread=.007, dur=1.8, index=1.6):
    n = int(dur * SR) + int(spread * len(notes) * SR) + 10; out = np.zeros((n, 2))
    for i, nm in enumerate(notes):
        b = bell(NOTE[nm], dur, index=index); s = int(i * spread * SR); out[s:s + len(b)] += b * (1 - i * .08)
    return out / (np.abs(out).max() + 1e-9)

class Mix:
    def __init__(self, dur, off=0.0):
        self.n = int(dur * SR); self.off = off
        self.bus = {k: np.zeros((self.n, 2)) for k in ('amb', 'music', 'sfx', 'send', 'voice')}; self.events = []; self.gaps = []
    def add(self, bus, x, t, gain=0.0, pan=None, send=0.0, label=None, haptic=None):
        t = t - self.off
        if x.ndim == 1: x = stereo(x, pan or 0)
        elif pan is not None: x = stereo(x.mean(1), pan)
        s = int(round(t * SR)); g = db(gain)
        if s < 0: x = x[-s:]; s = 0
        e = min(self.n, s + len(x))
        if e <= s: return
        self.bus[bus][s:e] += x[:e - s] * g
        if send: self.bus['send'][s:e] += x[:e - s] * g * send
        if label: self.events.append({'t': round(t, 3), 'cue': label, 'bus': bus, 'gain_db': gain, 'haptic': haptic})

def ambience(mx, sh, focus_at, gone_at=None):
    amb = load(os.path.join(RAW, 'amb_street.mp3')); amb = np.vstack([amb] * int(np.ceil(mx.n / len(amb) + 1)))[:mx.n]
    amb = peak_norm(butter(amb, 'high', 60), -1) * db(-27); lp = butter(amb, 'low', 900, 2)
    tt = np.arange(mx.n) / SR + mx.off; k = np.clip((tt - focus_at) / .35, 0, 1)[:, None]
    y = amb * (1 - k) + lp * k * db(-5)
    if gone_at is not None: y *= (1 - np.clip((tt - gone_at) / .55, 0, 1)[:, None]) ** 2
    mx.bus['amb'] += y
def opening(mx, sh, gone_at=None):
    ambience(mx, sh, sh['T_CAP'], gone_at)
    mx.add('sfx', oneshot('ui_tap', .09), sh['T_PRESS'], -20, 0, label='shutter press')
    mx.add('sfx', clip('shutter', 0, .22), sh['T_CAP'] - .01, -7, 0, send=.15, label='shutter', haptic='transient 0.8/0.6')
    mx.add('sfx', sub_thump(NOTE['D2'], .22, drop=1.2), sh['T_CAP'], -20)
def scan(mx, cu):
    """the lock-on brackets + P1's light, one thing at a time"""
    for j, id_ in enumerate(cu['scanIds']):
        p = pan_of(cu['clickX'][j]); f0, f1 = [(880.0, 987.77), (987.77, 1174.66), (1174.66, 1318.51)][j]
        mx.add('sfx', lock_click(10 + j, ['D6', 'F#6', 'A6'][j]), cu['click'][j] - .002, -20, p, label=f'bracket locks (カチャッ): {id_}', haptic='selection (UISelectionFeedbackGenerator, as the old screen)')
        mx.add('sfx', moving_pan(trace_tone(.62, f0, f1), cu['headX'][j]), cu['scans'][j], -29, send=.35, label=f'light runs round the outline: {id_} (pan follows the light)', haptic='continuous 0.12 600ms (sharpness 0.2)')
        mx.add('sfx', bell(NOTE[PENTA[2 * j]], 1.1, index=1.0, decay=2.6), cu['scans'][j] + .6, -27, p, send=.45, label=f'outline closes: {id_}', haptic='transient 0.25/0.6')
    a, b = max(cu['done']) + .1, min(cu['tags'])
    if b - a > .6: mx.add('sfx', calm_pad(b - a), a, -37, send=.25, label='waiting for the names (steady pad, no wobble)')
def tags_in(mx, sh, times):
    ids = [t['id'] for t in sh['tags']]; tx = {t['id']: t['x'] for t in sh['tags']}
    for k, tn in enumerate(times):
        p = pan_of(tx[ids[k]])
        mx.add('sfx', tick(NOTE[PENTA[k + 2]], 1), tn, -23, p, label=f'tag: {ids[k]}', haptic='transient 0.35/0.8')
        mx.add('sfx', bell(NOTE[PENTA[k]], 1.0, index=1.2), tn + .01, -22, p * .7, send=.35)
    mx.add('sfx', soft_pad([NOTE['D5'], NOTE['F#5'], NOTE['A5']], 1.2, attack=.08), max(times) + .08, -29, send=.3, label='all words in (resolve)')
def tap(mx, t):
    mx.add('sfx', oneshot('ui_tap', .09), t + .02, -15, 0, label='tap the word', haptic='transient 0.5/0.7')
    mx.add('sfx', tick(NOTE['A6'], 1), t + .02, -27)
PICK0 = os.environ.get('PICK') == '0'   # the film rendered with ?pick=0: 珍珠奶茶 is chosen (the App Store preview)
def voice(mx, t, gain=-3):
    f, w = ('voice_zhenzhu.mp3', '珍珠奶茶') if PICK0 else ('voice_zhennai_4.mp3', '珍奶')
    v = load(os.path.join(RAW, f)); v = peak_norm(butter(v, 'high', 90), -6)
    mx.add('voice', v, t - 0.04, gain, label=f'pronunciation {w} (zh-TW, prefetched — no wait)')
def music(mx, name, start, frm, gain, fin=.35, fout=.8, until=None):
    m = load(os.path.join(RAW, name + '.mp3'))[int(frm * SR):]; end = (until or mx.off + mx.n / SR) - start; m = m[:int(max(.1, end) * SR)]
    mx.add('music', fade(m, fin, fout), start, gain, label=f'music {name} from {frm}s')
def choose(mx, P):
    mx.add('sfx', oneshot('ui_tap', .09), P + .01, -14, label='choose 珍奶', haptic='transient 0.55/0.8')
    mx.add('sfx', marimba(NOTE['E6'], .3, hardness=.6), P + .06, -24, label='check'); mx.add('sfx', marimba(NOTE['A6'], .4, hardness=.6), P + .11, -23)
def finale(mx, cu):
    I = cu['I']
    mx.add('sfx', clip('sheet_slide', 0, .36), cu['open'], -16, label='図鑑 opens', haptic='transient 0.3/0.3')
    mx.add('sfx', whoosh(.4, 500, 1800, 1.1, peak=.5, seed=40), cu['open'], -24)
    sd = cu['scroll1'] - cu['scroll0']; mx.add('sfx', whoosh(sd + .1, 2600, 900, 1.2, peak=.25, seed=41, air=.4), cu['scroll0'], -27, label='scroll')
    R = load(os.path.join(RAW, 'riser_1.mp3')).mean(1); pk = int(np.argmax(np.abs(R))); L = int(max(.2, I - .07 - cu['anticip']) * SR)
    rs = fade(R[max(0, pk - L):pk], .05, .01); mx.add('sfx', rs, I - .07 - len(rs) / SR, -21, send=.2, label='anticipation riser', haptic='continuous 0.1→0.45')
    mx.gaps.append(I - mx.off)
    mx.add('sfx', chord_hit(['D5', 'F#5', 'A5', 'D6']), I, -15, send=.35, label='IMPACT: D major chord', haptic='transient 1.0/0.6 + continuous 0.5→0 150ms')
    mx.add('sfx', sub_thump(NOTE['D2'], .35), I, -14, label='impact weight')
    mx.add('sfx', pitch_shift(clip('impact_4', 0, 1.1), .55), I - .003, -19, send=.2, label='impact texture')
    mx.add('sfx', whoosh(.35, 4000, 1200, 1.0, peak=.15, seed=42, air=.6), I + .01, -26, label='shockwave air')
    mx.add('sfx', grains(.6, [NOTE[n] for n in ('A7', 'D8', 'F#7', 'B7')], 45, glen=(.02, .06), pan_spread=.9), I + .03, -24, send=.5, label='sparkle')
    mx.add('sfx', pitch_shift(oneshot('bubble_pop', .2), 5), I + .1, -24, label='NEW badge', haptic='transient 0.55/0.95')
    for k2, nm in enumerate(('D6', 'F#6')): mx.add('sfx', marimba(NOTE[nm], .35, hardness=.5), I + .16 + k2 * .07, -26)
    mx.add('sfx', tick(NOTE['E6'], .9), I + .3, -25, label='category 6→7 / 19'); mx.add('sfx', tick(NOTE['F#6'], .9), I + .42, -26, label='129→130枚'); mx.add('sfx', tick(NOTE['A6'], .9), I + .5, -26, label='影 37→38')
    tg = I + .85; mx.add('sfx', whoosh(.3, 900, 2200, 1, peak=.4, seed=43), tg, -28, label='goal toast')
    mx.add('sfx', bell(NOTE['E6'], 1.0, index=1.2), tg + .05, -22, send=.3, label='goal: E→A (one more to complete)'); mx.add('sfx', bell(NOTE['A6'], 1.4, index=1.2), tg + .17, -21, send=.35)
    mx.add('sfx', whoosh(I - cu['launch'] + .02, 2600, 700, 1.0, peak=.85, seed=32), cu['launch'], -18, label='flies into its slot')

# ---------------------------------------------------------------- the films
def concept_F(mx):
    cu = ALL['F']; sh = cu['shared']; C, P = cu['C'], cu['P']
    opening(mx, sh, gone_at=C + .05); scan(mx, cu); tags_in(mx, sh, cu['tags']); tap(mx, cu['tap'])
    # D (as v5)
    melt = clip('melt_swell', .1, .78); mx.add('sfx', melt, C + .62 - len(melt) / SR, -19, send=.3, label='photo clears into the page')
    mx.add('sfx', soft_pad([NOTE['D5'], NOTE['F#5'], NOTE['A5']], 1.4, attack=.35), C + .35, -27, send=.3, label='float')
    mx.add('sfx', marimba(NOTE['A6'], .4), cu['card'], -24, label='NEW chip')
    for i, nm in enumerate(('D6', 'E6', 'F#6')): mx.add('sfx', marimba(NOTE[nm], .4, hardness=.45), C + .58 + i * .07, -25, label='ways to say it' if not i else None)
    choose(mx, P)
    mx.add('sfx', whoosh(.4, 600, 1800, 1, peak=.4, seed=31), P + .24, -26, label='card folds away')
    # GET
    mx.add('sfx', soft_pad([NOTE['D5'], NOTE['F#5'], NOTE['A5'], NOTE['D6']], 1.6, attack=.5, release=.8), P + .14, -29, send=.35, label='the stage lights up (warm chord)')
    mx.add('sfx', whoosh(.45, 300, 900, 1.2, peak=.55, seed=33), cu['rise'], -32, label='the cup glides onto the stage')
    voice(mx, cu['voice'])
    mx.add('sfx', catch_jingle(), cu['catch'] - .01, -17, send=.35, label='CATCH: 新しいことばをキャッチ！ (D6–F#6–A6–D7)', haptic='success (UINotificationFeedbackGenerator)')
    finale(mx, cu)
    music(mx, 'music_D1', C + .4, 0.0, -18, fin=.5)
def concept_S(mx):
    cu = ALL['S']; sh = cu['shared']
    opening(mx, sh); scan(mx, cu); tags_in(mx, sh, cu['tags']); tap(mx, cu['tap'])
def concept_E(mx):
    cu = ALL['E']
    mx.add('sfx', oneshot('ui_tap', .09), cu['tap'], -15, label='tap the new word', haptic='transient 0.5/0.7')
    mx.add('sfx', whoosh(cu['detail'] - cu['open'] + .1, 500, 1600, 1, peak=.5, seed=60), cu['open'], -24, label='page zooms out of the slot')
    voice(mx, cu['voice'])
    P = ['D6', 'E6', 'F#6', 'A6', 'B6', 'D7', 'E7']; seen = {}
    for l in cu['lines']:
        k = seen.get(l['sec'], 0); seen[l['sec']] = k + 1; i = l['sec'] + k
        mx.add('sfx', bell(NOTE[P[min(i, 6)]], .8, index=.9, decay=4.5), l['t0'] + .02, -29, pan_of(l['x0']), send=.4, label=f"line written (section {l['sec'] + 1})" if k == 0 else None, haptic='transient 0.2/0.7' if k == 0 else None)
        mx.add('sfx', bell(NOTE[P[min(i + 2, 6)]], .9, index=.9, decay=4.0), l['t0'] + l['dur'] * .85, -30, pan_of(l['x1']), send=.4)
        sh = grains(l['dur'] + .1, [NOTE[n] for n in ('A7', 'D8', 'F#7')], 36, glen=(.004, .01), pan_spread=.05)
        mx.add('sfx', moving_pan(sh.mean(1), [l['x0'], l['x1']]), l['t0'], -35)
    mx.add('sfx', bell(NOTE['A6'], 1.2, index=1.3), cu['finish'] + .05, -19, send=.3, label='all written: A→D (resolve)', haptic='success')
    mx.add('sfx', bell(NOTE['D7'], 1.6, index=1.2), cu['finish'] + .13, -18, send=.35)
    music(mx, 'music_D2', cu['detail'], 0.0, -17, fin=.6, fout=.7)

def master(mx):
    B = mx.bus; n = mx.n
    wet = reverb(B['send'], 1.15, damp=6000) * db(-6); vroom = reverb(B['voice'], .35, .008, damp=7000) * db(-20)
    env = envelope_follower(B['voice'], .01, .3); env = env / (env.max() + 1e-9); k = np.clip(env * 1.4, 0, 1)
    duck, sduck = 1 - .75 * k, 1 - .5 * k
    gap = np.ones(n)
    for I in mx.gaps:
        a, b = int((I - .075) * SR), int(I * SR); r = int(.012 * SR)
        if a < 0 or b > n: continue
        gap[a:b] = db(-18); gap[a:a + r] = np.linspace(1, db(-18), r); gap[b - int(.004 * SR):b] = np.linspace(db(-18), 1, int(.004 * SR))
    mixd = (B['amb'] * (1 - .5 * k)[:, None] + B['music'] * duck[:, None] + wet * sduck[:, None] + B['sfx'] * sduck[:, None]) * gap[:, None] + B['voice'] + vroom
    mixd = butter(mixd, 'high', 30)
    e = envelope_follower(mixd, .005, .12); thr = db(-20)
    gr = np.where(e > thr, (thr * (e / thr) ** .5) / np.maximum(e, 1e-9), 1.0); mixd *= gr[:, None]
    meter = pyln.Meter(SR)
    for _ in range(3): lufs = meter.integrated_loudness(mixd); mixd = limiter(mixd * db(-16 - lufs), -1.0)
    return mixd, meter.integrated_loudness(mixd)

if __name__ == '__main__':
    c, out = sys.argv[1], sys.argv[2]
    sh = ALL[c]['shared']
    mx = Mix(sh['dur'][c], sh['start'].get(c, 0) or 0)
    globals()['concept_' + c](mx)
    y, lufs = master(mx)
    import wave
    pcm = (np.clip(y, -1, 1) * 32767).astype('<i2')
    with wave.open(out, 'wb') as w: w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    tp = 20 * np.log10(np.abs(signal.resample_poly(y, 4, 1, axis=0)).max() + 1e-12)
    json.dump(sorted(mx.events, key=lambda e: e['t']), open(out.replace('.wav', '_cues.json'), 'w'), ensure_ascii=False, indent=1)
    print(c, f'LUFS {lufs:.1f}  truepeak {tp:.2f} dBTP  dur {len(y) / SR:.2f}s  cues {len(mx.events)}')
