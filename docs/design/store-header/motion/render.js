// node render.js ja out.mp4 [first last] — header.html を 1 コマずつ描いて、3840×1646・30fps の H.264 にする（音なし）。
// 先に motion/ を http://127.0.0.1:8766/ で配る（python3 -m http.server 8766 --bind 127.0.0.1）。
// frames/（Blender の絵）と data/（outlines.json・points.json）は README の手順で作る。
const { chromium } = require('playwright'); const { spawn } = require('child_process');
(async () => {
  const [lang, out, first = '0', last = '299'] = process.argv.slice(2);
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 3840, height: 1646 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto(`http://127.0.0.1:8766/header.html?lang=${lang}`); await p.evaluate(() => window.ready);
  const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', '30', '-c:v', 'png', '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '14', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '5.2',
    '-r', '30', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const t0 = Date.now();
  for (let f = +first; f <= +last; f++) {
    const data = await p.evaluate(async f => { await window.renderFrame(f); return document.getElementById('c').toDataURL('image/png'); }, f);
    const buf = Buffer.from(data.split(',')[1], 'base64');
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (f % 30 === 0) process.stderr.write(`${lang} ${f} ${((Date.now() - t0) / 1000).toFixed(0)}s\n`);
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r));
  console.log(lang, 'done', ((Date.now() - t0) / 1000).toFixed(0) + 's', 'errors', errs.length ? errs : 'none');
  await b.close();
})();
