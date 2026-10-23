// node cues10.js '[["O10","2.4","",""],["O9f","2.4","","O9"]]' -> audio/cues10.json: every cue of the scan for each
// [name, AI wait (s from the shutter to the names), tapmin, concept (O10 default; O9 to compare)] — for the sound mix
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const cfg = JSON.parse(process.argv[2]);
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const out = {};
  for (const [name, ai, tapmin, concept] of cfg) {
    const c = concept || 'O10';
    const p = await b.newPage({ viewport: { width: 1080, height: 2340 } });
    await p.goto('http://127.0.0.1:8765/film10.html?c=' + c + '&t=0&ai=' + ai + (tapmin ? '&tapmin=' + tapmin : '') + (process.env.QS || '')); await p.evaluate(() => window.ready);
    out[name] = await p.evaluate((c) => {
      window.renderFrame(window.DUR[c] - .3, c);
      const o = JSON.parse(JSON.stringify(window.CUES[c]));
      o.shared = { T_PRESS, T_CAP, T_NAMES, T_TAP, T_VIS, LOOP, tags: TAGS.map(tg => ({ id: tg.id, x: tg.p[0], y: tg.p[1] })), dur: window.DUR };
      return o;
    }, c);
    out[name].ai = +ai; out[name].tapmin = tapmin ? +tapmin : null; out[name].concept = c;
    await p.close();
  }
  const file = process.env.CUES_OUT || '../audio/cues10.json', prev = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
  fs.writeFileSync(file, JSON.stringify(Object.assign(prev, out), null, 1));
  console.log(Object.entries(out).map(([k, v]) => `${k}: names ${v.names.toFixed(2)} close ${v.close.join('/')} tags ${v.tags.join('/')} end ${v.end}` + (v.catchUp ? ` K=${v.catchUp.k}` : '')).join('\n'));
  await b.close();
})();
