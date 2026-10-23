// node render.js ja out.mp4 [search] — header.html を 1 コマずつ描いて、30fps・12 秒の H.264 にする（音なし）。
// ヘッダーは 3840×1646。3 つ目に search を付けると検索結果用（3:2、2880×1920）。
// 先に docs/design/store-header を http://127.0.0.1:8767/ で配る（python3 -m http.server 8767 --bind 127.0.0.1）。
const { chromium } = require('playwright'); const { spawn } = require('child_process');
(async () => {
  const [lang, out, fmt = 'header'] = process.argv.slice(2), [vw, vh] = fmt === 'search' ? [2880, 1920] : [3840, 1646];
  const b = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: vw, height: vh } });
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto(`http://127.0.0.1:8767/motion/header.html?lang=${lang}&fmt=${fmt}`); await p.evaluate(() => window.ready);
  const N = await p.evaluate(() => N);
  const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', '30', '-c:v', 'png', '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-level', '5.2',
    '-r', '30', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const t0 = Date.now();
  for (let f = 0; f < N; f++) {
    const data = await p.evaluate(f => { window.renderFrame(f); return document.getElementById('c').toDataURL('image/png'); }, f);
    const buf = Buffer.from(data.split(',')[1], 'base64');
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (f % 60 === 0) process.stderr.write(`${lang} ${f}/${N} ${((Date.now() - t0) / 1000).toFixed(0)}s\n`);
  }
  ff.stdin.end(); await new Promise(r => ff.on('close', r));
  console.log(lang, 'done', ((Date.now() - t0) / 1000).toFixed(0) + 's', 'errors', errs.length ? errs : 'none');
  await b.close();
})();
