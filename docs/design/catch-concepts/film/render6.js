// node render6.js F out.mp4 audio.wav — steps the film frame by frame at 60 fps and encodes H.264 + AAC. The slow case: AI=11.5 node render6.js S …
const { chromium } = require('playwright'); const { spawn } = require('child_process');
(async () => {
  const [c, out, wav] = process.argv.slice(2); const FPS = +(process.env.FPS || 60);   // FPS=30: the App Store preview (30 fps at most)
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1080, height: 2340 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('http://127.0.0.1:8765/film6.html?c=' + c + '&t=0' + (process.env.QS || '') + (process.env.AI ? '&ai=' + process.env.AI : '')); await p.evaluate(() => window.ready);
  const { dur, start } = await p.evaluate(c => ({ dur: window.DUR[c], start: window.START[c] || 0 }), c); const N = Math.round(dur * FPS);
  const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-', '-i', wav,
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-tune', 'animation',
    '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart', '-shortest', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const t0 = Date.now();
  for (let i = 0; i < N; i++) {
    const data = await p.evaluate(([t, c]) => { window.renderFrame(t, c); return document.getElementById('c').toDataURL('image/png'); }, [start + i / FPS, c]);
    const buf = Buffer.from(data.split(',')[1], 'base64');
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (i % 60 === 0) process.stderr.write(`${c} ${i}/${N} ${((Date.now() - t0) / 1000).toFixed(0)}s\n`);
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r));
  console.log(c, 'done', N, 'frames', ((Date.now() - t0) / 1000).toFixed(0) + 's', 'errors', errs.length ? errs : 'none');
  await b.close();
})();
