// node cues6.js -> audio/cues6.json: every cue of the v6 films (for the sound mix and haptics). F and E at the median
// AI wait (6.0 s), S with ?ai=11.5 (the 90th percentile).
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const out = {};
  for (const [ai, list] of [[null, ['F', 'E']], ['11.5', ['S']]]) {
    const p = await b.newPage({ viewport: { width: 1080, height: 2340 } });
    await p.goto('http://127.0.0.1:8765/film6.html?c=F&t=0' + (ai ? '&ai=' + ai : '') + (process.env.QS || '')); await p.evaluate(() => window.ready);
    const r = await p.evaluate(list => {
      for (const c of list) window.renderFrame((window.START[c] || 0) + window.DUR[c] - .3, c);
      const o = {}; for (const c of list) o[c] = JSON.parse(JSON.stringify(window.CUES[c]));
      o._shared = { T_PRESS, T_CAP, T_NAMES, T_TAP, T_VIS, tags: TAGS.map(tg => ({ id: tg.id, x: tg.p[0], y: tg.p[1] })), dur: window.DUR, start: window.START };
      return o;
    }, list);
    for (const c of list) { out[c] = r[c]; out[c].shared = r._shared; }
    await p.close();
  }
  fs.writeFileSync((process.env.CUES_OUT || '../audio/cues6.json'), JSON.stringify(out, null, 1));
  console.log('F end', out.F.end, 'S end', out.S.end, 'E end', out.E.end, 'F dur', out.F.shared.dur.F, 'S dur', out.S.shared.dur.S);
  await b.close();
})();
