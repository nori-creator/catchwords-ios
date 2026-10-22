// node render_overlay.js spec.json outdir — the preview's background (bg.png) and its 30 fps overlay frames
// (fg/000000.png …, transparent) from overlay.html, served at http://127.0.0.1:8766/ (compose.py starts the server).
const { chromium } = require('playwright'); const fs = require('fs'); const path = require('path');
(async () => {
  const [specFile, out] = process.argv.slice(2);
  const spec = JSON.parse(fs.readFileSync(specFile, 'utf8')); const FPS = 30, N = Math.round(spec.duration * FPS);
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 886, height: 1920 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('http://127.0.0.1:8766/overlay.html?icon=icon.png'); await p.evaluate(() => window.ready);
  const shot = async (t, s, file) => {
    const data = await p.evaluate(([t, s]) => { window.renderFrame(t, s); return document.getElementById('c').toDataURL('image/png'); }, [t, s]);
    fs.writeFileSync(file, Buffer.from(data.split(',')[1], 'base64'));
  };
  fs.mkdirSync(path.join(out, 'fg'), { recursive: true });
  await shot(0, { ...spec, mode: 'bg' }, path.join(out, 'bg.png'));
  for (let i = 0; i < N; i++) await shot(i / FPS, { ...spec, mode: 'fg' }, path.join(out, 'fg', String(i).padStart(6, '0') + '.png'));
  console.log('overlay', N, 'frames', 'errors', errs.length ? errs : 'none');
  await b.close();
})();
