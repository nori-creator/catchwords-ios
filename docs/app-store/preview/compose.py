"""The App Store preview from the app's own screen recordings or the v6/v10 films (README.md): the cuts of edl-<lang>.json, framed on the
stage ("枠あり"), with the captions, the tap rings and the end card of overlay.html over them, and the app's own sounds
at the moments the app played them (the "sfx" lines of each recording's trace, SoundService.trace).

usage: python3 compose.py edl-ja.json FOOTAGE_DIR out.mp4
  FOOTAGE_DIR: ci-previews runs/store-preview/ (<scene>-<lang>.mp4, .trace.txt, .start) or the phone's recordings.
  Needs ffmpeg, numpy, node with playwright, and @fontsource/noto-sans-jp + @fontsource/inter (FONTSOURCE=<their
  node_modules/@fontsource>).
Output: 886 × 1920, 30 fps, H.264 High, AAC 256 kbps 48 kHz stereo (Apple: App preview specifications).
"""
import json, os, re, subprocess, sys, tempfile, shutil, http.server, threading, functools
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
SOUNDS = os.path.join(REPO, 'ios', 'CatchWords', 'Resources', 'Sounds')
ICON = os.path.join(REPO, 'ios', 'CatchWords', 'Assets.xcassets', 'AppIcon.appiconset', 'icon.png')
SR, FPS = 48000, 30
FRAME = dict(x=93, y=360, w=700, h=1522, r=56)   # overlay.html FRAME


def run(*cmd):
    subprocess.run(cmd, check=True)


def decode(path):
    """A sound file as float stereo at SR."""
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2)


def sound_file(name):
    for ext in ('m4a', 'caf', 'mp3'):
        p = os.path.join(SOUNDS, f'{name}.{ext}')
        if os.path.exists(p):
            return p
    return None


def trace_events(base):
    """(seconds into the recording, name, volume) for each sound the app asked for."""
    tf, sf = base + '.trace.txt', base + '.start'
    if not (os.path.exists(tf) and os.path.exists(sf)):
        return []
    start = float(open(sf).read())
    out = []
    for line in open(tf, encoding='utf-8'):
        m = re.search(r' sfx (\d+\.\d+) (\S+) (\d+\.\d+)', line)
        if m:
            out.append((float(m.group(1)) - start, m.group(2), float(m.group(3))))
    return out


def main(edl_file, footage, out):
    edl = json.load(open(edl_file))
    lang, segs = edl['lang'], edl['segments']
    seglen = lambda s: s['out'] - s['in'] + s.get('hold', 0)
    duration = sum(seglen(s) for s in segs)
    assert 15 <= duration <= 30, f'{duration:.2f} s: App previews are 15–30 s'
    work = tempfile.mkdtemp(prefix='preview-')
    try:
        # 1. The overlay frames (served: the page loads its fonts and the icon over http).
        shutil.copy(os.path.join(HERE, 'overlay.html'), work)
        shutil.copy(ICON, os.path.join(work, 'icon.png'))
        fs = os.environ.get('FONTSOURCE', '')
        css = []
        for fam, weights in (('noto-sans-jp', (600, 700, 800)), ('inter', (600, 700, 800))):
            src = os.path.join(fs, fam)
            os.symlink(os.path.join(src, 'files'), os.path.join(work, fam))
            for w in weights:
                css.append(open(os.path.join(src, f'{w}.css')).read().replace('./files/', f'./{fam}/'))
        open(os.path.join(work, 'fonts.css'), 'w').write('\n'.join(css))
        spec = dict(lang=lang, duration=duration, captions=edl['captions'], taps=edl.get('taps', []),
                    src=edl.get('src', dict(w=1206, h=2622)),
                    end=dict(t0=duration - edl['end']['length'], subtitle=edl['end']['subtitle']))
        json.dump(spec, open(os.path.join(work, 'spec.json'), 'w'))
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=work)
        handler.log_message = lambda *a: None
        srv = http.server.ThreadingHTTPServer(('127.0.0.1', 8766), handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            run('node', os.path.join(HERE, 'render_overlay.js'), os.path.join(work, 'spec.json'), work)
        finally:
            srv.shutdown()

        # 2. The footage: each cut at 30 fps, scaled into the frame; the end card's last seconds blurred.
        parts = []
        for i, s in enumerate(segs):
            p = os.path.join(work, f'cut{i}.mp4')
            run('ffmpeg', '-v', 'error', '-y', '-ss', str(s['in']), '-to', str(s['out']), '-i', os.path.join(footage, s['src'] + '.mp4'),
                '-vf', f"fps={FPS},scale={FRAME['w']}:{FRAME['h']}:flags=lanczos,setsar=1"
                       + (f",tpad=stop_mode=clone:stop_duration={s['hold']}" if s.get('hold') else ''), '-an', '-c:v', 'libx264', '-crf', '12', '-preset', 'fast', p)
            parts.append(p)
        open(os.path.join(work, 'cuts.txt'), 'w').write(''.join(f"file '{p}'\n" for p in parts))
        footage_mp4 = os.path.join(work, 'footage.mp4')
        run('ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', os.path.join(work, 'cuts.txt'), '-c', 'copy', footage_mp4)
        # Rounded corners: a white rounded rectangle as the footage's alpha.
        mask = os.path.join(work, 'mask.png')
        from PIL import Image, ImageDraw
        m = Image.new('L', (FRAME['w'], FRAME['h']), 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, FRAME['w'] - 1, FRAME['h'] - 1), FRAME['r'], fill=255)
        m.save(mask)

        # 3. The sound: the app's files at the traced moments, mapped through the cuts.
        mix = np.zeros((int(duration * SR) + SR, 2), dtype=np.float32)
        cache, t_out, loops = {}, 0.0, []
        for s in segs:
            if s.get('audio') == 'embedded':
                # A film with its own mix (the v6/v10 films, docs/design/catch-concepts): its sound for the cut.
                raw = subprocess.run(['ffmpeg', '-v', 'error', '-ss', str(s['in']), '-to', str(s['out']),
                                      '-i', os.path.join(footage, s['src'] + '.mp4'), '-vn', '-f', 'f32le', '-ac', '2',
                                      '-ar', str(SR), '-'], check=True, capture_output=True).stdout
                x = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2)
                a = int(t_out * SR); n = min(len(x), len(mix) - a)
                if n > 0:
                    mix[a:a + n] += x[:n]
                t_out += seglen(s)
                continue
            # Recording start → its first frame (seconds): differs per recording, set by matching a sound to its frame.
            calib = s.get('sound_offset', edl.get('sound_offset', 0.0))
            events = [(t - calib, n, v) for (t, n, v) in trace_events(os.path.join(footage, s['src']))]
            # Sounds the trace missed (the first scan's scan-start comes before the sound engine is up), in video time.
            events += [(e['t'], e['name'], e.get('volume', 0.405)) for e in s.get('extra_sounds', [])]
            for (t, name, vol) in events:
                if not (s['in'] <= t < s['out']):
                    continue
                at = t_out + (t - s['in'])
                if name in ('speak',):
                    continue                # the simulator speaks nothing; the phone's recording carries the voice
                if name.startswith('analyze-loop'):
                    loops.append((at, name))
                    continue
                f = sound_file(name)
                if not f or vol <= 0:
                    continue
                x = cache.get(f)
                if x is None:
                    x = cache[f] = decode(f)
                a = int(at * SR); n = min(len(x), len(mix) - a)
                if n > 0:
                    mix[a:a + n] += x[:n] * vol
            t_out += seglen(s)
        loop = sound_file('el-analyze-loop')
        if loop:
            x = decode(loop)
            starts = [a for a, n in loops if n.endswith('start')]
            for a0 in starts:
                stops = [a for a, n in loops if n.endswith('stop') and a > a0]
                a1 = stops[0] if stops else duration
                i0, i1 = int(a0 * SR), int(min(a1 + .3, duration) * SR)
                need = i1 - i0
                tiled = np.tile(x, (need // len(x) + 1, 1))[:need].copy()
                env = np.ones(need, dtype=np.float32)
                fi = min(need, int(.6 * SR)); env[:fi] = np.linspace(0, 1, fi)
                fo = min(need, int(.3 * SR)); env[-fo:] *= np.linspace(1, 0, fo)
                mix[i0:i1] += tiled * env[:, None] * .5
        mix = mix[:int(duration * SR)]
        peak = float(np.abs(mix).max() or 1)
        mix *= 0.71 / peak                  # the whole mix to a -3 dBFS peak: the sounds keep the app's balance
        wav = os.path.join(work, 'mix.wav')
        import wave
        with wave.open(wav, 'wb') as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes((np.clip(mix, -1, 1) * 32767).astype('<i2').tobytes())

        # 4. Together: stage + framed footage + overlay (captions, taps, the end card on white) + sound.
        fc = (f"[1:v]format=rgba[v];[2:v]format=gray[m];[v][m]alphamerge[vf];"
              f"[0:v][vf]overlay={FRAME['x']}:{FRAME['y']}:shortest=1[bv];[bv][3:v]overlay=0:0:shortest=1,format=yuv420p[out]")
        run('ffmpeg', '-v', 'error', '-y',
            '-loop', '1', '-framerate', str(FPS), '-i', os.path.join(work, 'bg.png'),
            '-i', footage_mp4,
            '-loop', '1', '-framerate', str(FPS), '-i', mask,
            '-framerate', str(FPS), '-i', os.path.join(work, 'fg', '%06d.png'),
            '-i', wav,
            '-filter_complex', fc, '-map', '[out]', '-map', '4:a',
            '-t', f'{duration:.3f}', '-r', str(FPS),
            '-c:v', 'libx264', '-profile:v', 'high', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p',
            '-c:a', 'aac', '-b:a', '256k', '-ar', str(SR), '-ac', '2', '-movflags', '+faststart', out)
        print(out, f'{duration:.2f} s')
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main(*sys.argv[1:4])
