// detail6.js — E v6: the word page while the AI writes, then the reveal.
// Owner (2026-10-10): nothing in the explanation fields while the AI is writing — no dots; when it is done, the
// explanation should appear like magic.
//   • What is already known (the word, reading, meaning, the other ways to say it) is clean from the first frame.
//   • The AI sections (例文 / 使い方のコツ / 豆知識) open with their titles and their final height (no jump later), bodies
//     empty. Their borders carry a slow light (the same blue as the scan's brackets): "being written here". The status
//     in the 例文 header says what is happening.
//   • The moment the text arrives, a light runs along each line, left to right, line after line, section after section;
//     where it passes, sparks of light gather onto the strokes and the text appears under them (no grains of ink left
//     behind — the owner asked for no dots). A chime runs with it.
// Wait (real data, web app ai_runs, last 7 days): a freshly generated word card takes 11.2 s (median) from the choice.
// If generation starts at the choice, ~5.9 s of that pass in the GET moment, the 図鑑 and the tap, so this page waits
// ~5.3 s. (Already generated: 0.27 s — the page then opens with the text in place.)
const T_OPEN_E = .62, T_DETAIL = 1.05, T_DONE = T_DETAIL + 5.3;
const EX = [
  ...(PICK === VAR[0] ? [
    { zh: Z('我要一杯珍珠奶茶，半糖少冰。', 'ㄨㄛˇ ㄧㄠˋ ㄧˋ ㄅㄟ ㄓㄣ ㄓㄨ ㄋㄞˇ ㄔㄚˊ ㄅㄢˋ ㄊㄤˊ ㄕㄠˇ ㄅㄧㄥ'), ja: '珍珠奶茶を1杯、甘さ半分・氷少なめで。' },
    { zh: Z('這家的珍珠奶茶很好喝。', 'ㄓㄜˋ ㄐㄧㄚ ˙ㄉㄜ ㄓㄣ ㄓㄨ ㄋㄞˇ ㄔㄚˊ ㄏㄣˇ ㄏㄠˇ ㄏㄜ'), ja: 'この店の珍珠奶茶はおいしい。' },
  ] : [
  { zh: Z('我要一杯珍奶，半糖少冰。', 'ㄨㄛˇ ㄧㄠˋ ㄧˋ ㄅㄟ ㄓㄣ ㄋㄞˇ ㄅㄢˋ ㄊㄤˊ ㄕㄠˇ ㄅㄧㄥ'), ja: '珍奶を1杯、甘さ半分・氷少なめで。' },
  { zh: Z('這家的珍奶很好喝。', 'ㄓㄜˋ ㄐㄧㄚ ˙ㄉㄜ ㄓㄣ ㄋㄞˇ ㄏㄣˇ ㄏㄠˇ ㄏㄜ'), ja: 'この店の珍奶はおいしい。' },
  ]),
];
const TIPS = ['注文では「珍奶」だけで通じる。', '甘さは 全糖・半糖・微糖・無糖、', '氷は 正常冰・少冰・去冰 で伝える。'];
const TRIVIA = ['1980年代に台湾で生まれた飲み物。', '台中と台南の店が元祖を名乗っている。'];
const DET = { x: 48, w: W - 96, sim: 960, ex: 1222, tips: 1694, triv: 1996 };
const SEC = [{ y: DET.ex, h: 450, title: '例文' }, { y: DET.tips, h: 280, title: '使い方のコツ' }, { y: DET.triv, h: 250, title: '豆知識' }];
const T_REV = s => T_DONE + .26 * s;                   // each section's reveal starts
const LINE_GAP = .09;
const INK_RGB = '11,18,26', MUTED_RGB = '92,100,111';

let DLINES = null;
function detLines() {
  if (DLINES) return DLINES;
  const L = [];
  EX.forEach((e, i) => {
    const y = DET.ex + 124 + i * 172, x = DET.x + 76;
    L.push({ sec: 0, k: 2 * i, x, y, w: zyWidth(e.zh, 46), top: y - 52, bot: y + 12, rgb: INK_RGB, draw: c => zyDraw(e.zh, x, y, 46, { align: 'left', w: 600, c }) });
    L.push({ sec: 0, k: 2 * i + 1, x, y: y + 52, w: measure(e.ja, 500, 30), top: y + 52 - 30, bot: y + 52 + 9, rgb: MUTED_RGB, draw: c => text(e.ja, x, y + 52, { w: 500, size: 30, color: MUTED, align: 'left', c }) });
  });
  [[TIPS, 1, DET.tips], [TRIVIA, 2, DET.triv]].forEach(([list, s, y0]) => list.forEach((str, i) => {
    const x = DET.x + 44, y = y0 + 112 + i * 58;
    L.push({ sec: s, k: i, x, y, w: measure(str, 500, 32), top: y - 32, bot: y + 10, rgb: INK_RGB, draw: c => text(str, x, y, { w: 500, size: 32, color: INK, align: 'left', c }) });
  }));
  L.forEach(l => { l.t0 = T_REV(l.sec) + LINE_GAP * l.k; l.dur = .34 + .24 * Math.min(1, l.w / 900); l.mid = (l.top + l.bot) / 2; });
  return DLINES = L;
}
// the light's position along a line, and the inverse (when it passes x)
const headX = (l, t) => l.x - 24 + (l.w + 48) * E.inOutSine(seg(t, l.t0, l.t0 + l.dur));
const passT = (l, x) => { const y = clamp((x - l.x + 24) / (l.w + 48)); return l.t0 + l.dur * Math.acos(1 - 2 * y) / Math.PI; };

// ---------- the targets: one spark per dithered 3 px cell of the final text ----------
const DSTEP = 3;
let DOTS = null;
const OFF = document.createElement('canvas'); OFF.width = W; OFF.height = H; const ofx = OFF.getContext('2d', { willReadFrequently: true });
function buildDots() {
  if (DOTS) return DOTS;
  const lines = detLines();
  lines.forEach((l, li) => {
    ofx.clearRect(0, 0, W, H); l.draw(ofx);
    const x0 = Math.floor(l.x - 6), x1 = Math.ceil(l.x + l.w + 6), y0 = Math.floor(l.top), y1 = Math.ceil(l.bot), ww = x1 - x0;
    const data = ofx.getImageData(x0, y0, ww, y1 - y0).data, tg = [];
    for (let y = 0; y + DSTEP <= y1 - y0; y += DSTEP) for (let x = 0; x + DSTEP <= ww; x += DSTEP) {
      let a = 0; for (let yy = 0; yy < DSTEP; yy++) for (let xx = 0; xx < DSTEP; xx++) a += data[((y + yy) * ww + x + xx) * 4 + 3];
      a /= DSTEP * DSTEP * 255;
      const seed = li * 9173 + x * 3.17 + y * 11.3;
      if (a > .05 && a > rnd(seed) * .9 && rnd(seed + 9) < .55) {
        const tx = x0 + x + 1.5, ty = y0 + y + 1.5, ang = rnd(seed + 3) * Math.PI * 2, rad = 18 + 30 * rnd(seed + 4);
        tg.push({ x: tx, y: ty, a: Math.min(1, .5 + a * .6), sx: tx - 10 - 16 * rnd(seed + 5) + Math.cos(ang) * rad * .4, sy: ty + Math.sin(ang) * rad, tp: 0, d: .2 + .12 * rnd(seed + 6) });
      }
    }
    tg.forEach(p => p.tp = passT(l, p.x) - .03);
    l.tg = tg;
    const cc = document.createElement('canvas'); cc.width = ww; cc.height = y1 - y0; const cx = cc.getContext('2d'); cx.translate(-x0, -y0); l.draw(cx);
    l.crisp = { c: cc, x: x0, y: y0 };
    l.tw = [0, 1, 2].map(i => ({ x: l.x + l.w * (.18 + .3 * i + .1 * rnd(li * 7 + i)), dy: (rnd(li * 13 + i) - .5) * 30, r: 13 + 9 * rnd(li * 3 + i) }));
  });
  return DOTS = lines;
}

// ---------- the page ----------
function sectionCard(y, h, title, { alpha = 1, lift = 0 } = {}) {
  ctx.save(); ctx.globalAlpha *= alpha;
  ctx.save(); ctx.shadowColor = `rgba(15,40,80,${.06 + .06 * lift})`; ctx.shadowBlur = 24 + 20 * lift; ctx.shadowOffsetY = 8 + 6 * lift; ctx.fillStyle = '#fff'; rr(DET.x, y, DET.w, h, 44); ctx.fill(); ctx.restore();
  ctx.strokeStyle = '#E0E5EB'; ctx.lineWidth = 2.5; rr(DET.x, y, DET.w, h, 44); ctx.stroke();
  text(title, DET.x + 44, y + 64, { w: 800, size: 34, align: 'left' });
  ctx.restore();
}
// the border light of a section being written: a slow conic sweep in the scan's blue
function edgeLight(s, t) {
  const S = SEC[s], tr = T_REV(s);
  const a = seg(t, T_DETAIL + .35, T_DETAIL + .9) * (1 - E.inOutCubic(seg(t, tr + .15, tr + .75))), bump = Math.sin(Math.PI * seg(t, tr - .12, tr + .32));
  const k = clamp(a * (.62 + .38 * bump) + bump * .4 * (t > tr - .12 ? 1 : 0)); if (k <= .01) return;
  const cx = DET.x + DET.w / 2, cy = S.y + S.h / 2, g = ctx.createConicGradient(t * 2 * Math.PI / 3.4 + s * 1.3, cx, cy);
  [[0, 'rgba(100,224,255,0)'], [.12, 'rgba(100,224,255,0.95)'], [.24, 'rgba(0,131,255,0.9)'], [.36, 'rgba(191,239,255,0)'], [.58, 'rgba(100,224,255,0)'], [.7, 'rgba(42,155,255,0.8)'], [.8, 'rgba(191,239,255,0)'], [1, 'rgba(100,224,255,0)']].forEach(([o, c]) => g.addColorStop(o, c));
  ctx.save(); ctx.globalAlpha *= k; ctx.strokeStyle = g;
  ctx.save(); ctx.filter = 'blur(9px)'; ctx.lineWidth = 12; ctx.globalAlpha *= .55; rr(DET.x, S.y, DET.w, S.h, 44); ctx.stroke(); ctx.restore();
  ctx.lineWidth = 3.5; rr(DET.x + .5, S.y + .5, DET.w - 1, S.h - 1, 44); ctx.stroke();
  ctx.restore();
}
function drawDetail(t) {
  const zoom = E.inOutQuart(seg(t, T_OPEN_E, T_DETAIL));
  if (zoom < 1) drawDexPage(t, { fx: FX(-10, -11) });
  const ts = targetSlot(), sx = ts.x, sy = ts.y;
  const x0 = lerp(sx, 0, zoom), y0 = lerp(sy, 0, zoom), w0 = lerp(SLOT, W, zoom), h0 = lerp(SLOT, H, zoom), r0 = lerp(44, 0, zoom);
  if (zoom > 0) {
    ctx.save(); ctx.fillStyle = BG_APP; ctx.shadowColor = 'rgba(0,0,0,0.2)'; ctx.shadowBlur = 60 * (1 - zoom); rr(x0, y0, w0, h0, r0); ctx.fill(); ctx.restore();
    ctx.save(); rr(x0, y0, w0, h0, r0); ctx.clip(); ctx.globalAlpha = seg(zoom, .55, 1); detailContent(t); ctx.restore();
  }
  const hx = lerp(ts.cx, 540, zoom), hy = lerp(ts.cy, 440, zoom), hk = lerp(SLOT * .86, 380, zoom);
  const im = A.d_cup, f = hk / im.height;
  ctx.save(); ctx.shadowColor = 'rgba(0,30,70,0.25)'; ctx.shadowBlur = 12; ctx.shadowOffsetY = 10; ctx.drawImage(im, hx - im.width * f / 2, hy - im.height * f / 2, im.width * f, im.height * f); ctx.restore();
  finger(ts.cx + 20, ts.cy + 30, t, .3, .52);
  statusBar(true); homeIndicator(true);
}
function detailContent(t) {
  const g = ctx.createRadialGradient(540, 440, 0, 540, 440, 400); g.addColorStop(0, '#EAF4FF'); g.addColorStop(1, 'rgba(234,244,255,0)'); ctx.fillStyle = g; ctx.fillRect(0, 150, W, 700);
  ctx.save(); ctx.fillStyle = '#EDF2F8'; ctx.beginPath(); ctx.arc(96, 220, 44, 0, Math.PI * 2); ctx.fill(); icon('chevL', 92, 220, 40, INK, 8); ctx.restore();
  text('図鑑', 160, 232, { w: 600, size: 34, color: MUTED, align: 'left' });
  zyDraw(PICK_U, 500, 770, 132, {});
  speakerBtn(820, 722, 50, t, T_DETAIL + .12, {});
  const chip = REG[PICK.reg], cw = measure(chip, 600, 26) + 34; ctx.fillStyle = '#EDF2F8'; rr(W / 2 - 300, 812, cw, 46, 23); ctx.fill(); text(chip, W / 2 - 300 + cw / 2, 844, { w: 600, size: 26, color: MUTED });
  text(PICK.mean, W / 2 - 300 + cw + 22, 846, { w: 500, size: 34, color: MUTED, align: 'left' });
  text(PICK.note, W / 2, 906, { w: 600, size: 30, color: '#0066CC' });
  sectionCard(DET.sim, 240, '似た言い方');
  [PICK === VAR[0] ? [VAR[1], '砕けた言い方'] : [VAR[0], 'ふだんの言い方'], [VAR[2], '大粒タピオカ']].forEach(([v, s], i) => {
    const y = DET.sim + 140 + i * 66; zyDraw(v.u, DET.x + 44, y, 46, { align: 'left', w: 600 });
    text(s, DET.x + DET.w - 44, y - 4, { w: 500, size: 30, color: MUTED, align: 'right' });
  });
  const lift = E.outCubic(seg(t, T_DONE + 1.0, T_DONE + 1.3)) * (1 - seg(t, T_DONE + 1.5, T_DONE + 2.1));
  SEC.forEach((s, i) => { sectionCard(s.y, s.h, s.title, { lift }); edgeLight(i, t); });
  // the example bubbles come with their text (nothing is drawn in the fields before the answer)
  [0, 1].forEach(i => {
    const by = DET.ex + 84 + i * 172, bh = 136, bw = DET.w - 88, bx = DET.x + 44, tb = T_REV(0) + LINE_GAP * 2 * i - .08;
    const ba = E.outCubic(seg(t, tb, tb + .25)); if (ba <= 0) return;
    ctx.save(); ctx.globalAlpha *= ba; ctx.fillStyle = '#F4F8FD'; ctx.strokeStyle = '#E3ECF6'; ctx.lineWidth = 2; rr(bx, by, bw, bh, 34); ctx.fill(); ctx.stroke(); ctx.restore();
    const sa = E.outBack(seg(t, T_REV(0) + .7 + i * .09, T_REV(0) + 1.0 + i * .09), 2);
    if (sa > 0) { ctx.save(); const cx = bx + bw - 54, cy = by + bh / 2; ctx.translate(cx, cy); ctx.scale(sa, sa); ctx.translate(-cx, -cy); speakerBtn(cx, cy, 32, t, -9, { blue: false }); ctx.restore(); }
  });
  aiStatus6(t);
  drawReveal(t);
}

// ---------- the reveal: a light along each line; sparks land on the strokes and become ink; the crisp text follows ----------
const DLV = 6;
function drawReveal(t) {
  if (t < T_DONE - .05) return;
  const lines = buildDots();
  const ink = { [INK_RGB]: Array.from({ length: DLV }, () => new Path2D()), [MUTED_RGB]: Array.from({ length: DLV }, () => new Path2D()) };
  const light = Array.from({ length: DLV }, () => new Path2D()), glow = Array.from({ length: DLV }, () => new Path2D());
  const put = (P, x, y, a, s) => { if (a <= .02) return; P[Math.min(DLV - 1, Math.floor(a * DLV))].rect(x - s / 2, y - s / 2, s, s); };
  const heads = [];
  for (const l of lines) {
    if (t < l.t0 - .02) continue;
    const hx = headX(l, t), crispFront = headX(l, t - .05) - 6;
    if (crispFront > l.x - 30) crispLine(l, crispFront);
    for (const p of l.tg) {
      if (t < p.tp) continue;
      const u = seg(t, p.tp, p.tp + p.d), e = E.outCubic(u);
      if (u >= 1) continue;
      const x = lerp(p.sx, p.x, e), y = lerp(p.sy, p.y, e), la = clamp(u * 5) * (1 - e) ** 1.2;
      if (la > .02) { put(glow, x, y, la * .5, 7); put(light, x, y, la, 2.6); }   // a spark of light that settles into the stroke as the text appears under it
    }
    if (t < l.t0 + l.dur + .05) heads.push([hx, l.mid, Math.sin(Math.PI * seg(t, l.t0 - .02, l.t0 + l.dur + .05)), l]);
    l.tw.forEach((w, i) => {                                       // a few twinkles left behind the light
      const tp = passT(l, w.x) + .02, u = seg(t, tp, tp + .62); if (u <= 0 || u >= 1) return;
      const s = E.outBack(seg(u, 0, .3), 3) * (1 - E.inCubic(seg(u, .45, 1)));
      star4(w.x, l.mid + w.dy, w.r * s, u * 1.6 + i, .9, i % 2 ? '#64E0FF' : BLUE2);
    });
  }
  for (let lv = 0; lv < DLV; lv++) { ctx.fillStyle = `rgba(100,200,255,${(lv + .5) / DLV * .5})`; ctx.fill(glow[lv]); ctx.fillStyle = `rgba(30,140,255,${(lv + .5) / DLV})`; ctx.fill(light[lv]); }
  for (const rgb of [INK_RGB, MUTED_RGB]) for (let lv = 0; lv < DLV; lv++) { ctx.fillStyle = `rgba(${rgb},${(lv + .5) / DLV})`; ctx.fill(ink[rgb][lv]); }
  // the light itself: a soft blue glow with a bright star at its tip
  heads.forEach(([x, y, a, l]) => {
    if (a <= 0) return; const R = 46, g = ctx.createRadialGradient(x, y, 0, x, y, R);
    g.addColorStop(0, `rgba(100,200,255,${.55 * a})`); g.addColorStop(.4, `rgba(42,155,255,${.22 * a})`); g.addColorStop(1, 'rgba(42,155,255,0)');
    ctx.fillStyle = g; ctx.fillRect(x - R, y - R, 2 * R, 2 * R);
    star4(x, y, 16 + 4 * Math.sin(t * 30 + l.k), t * 3, a, '#fff');
    star4(x, y, 9, t * 3 + .8, a * .9, BLUE2);
  });
}
const CR = document.createElement('canvas'); CR.width = W; CR.height = 120; const crx = CR.getContext('2d');
function crispLine(l, front) {
  const { c, x, y } = l.crisp;
  if (front >= x + c.width + 40) { ctx.drawImage(c, x, y); return; }
  if (CR.width < c.width || CR.height < c.height) { CR.width = Math.max(CR.width, c.width); CR.height = Math.max(CR.height, c.height); }
  crx.clearRect(0, 0, CR.width, CR.height); crx.globalCompositeOperation = 'source-over'; crx.drawImage(c, 0, 0);
  crx.globalCompositeOperation = 'destination-in'; const fx = front - x, g = crx.createLinearGradient(fx - 40, 0, fx, 0); g.addColorStop(0, 'rgba(0,0,0,1)'); g.addColorStop(1, 'rgba(0,0,0,0)');
  crx.fillStyle = g; crx.fillRect(0, 0, c.width, c.height); crx.globalCompositeOperation = 'source-over';
  ctx.drawImage(CR, 0, 0, c.width, c.height, x, y, c.width, c.height);
}
// status in the 例文 header: what the AI is doing; a check the moment it is done
function aiStatus6(t) {
  const a = seg(t, T_DETAIL + .2, T_DETAIL + .45), gone = seg(t, T_DONE + 1.9, T_DONE + 2.3); if (a <= 0 || gone >= 1) return;
  const done = t >= T_DONE, fin = seg(t, T_DONE, T_DONE + .22), xr = DET.x + DET.w - 40, y = DET.ex + 62;
  const s = done ? '書き終わりました' : 'AIが例文と解説を書いています', w = measure(s, 600, 25) + 70;
  ctx.save(); ctx.globalAlpha *= a * (1 - gone);
  ctx.fillStyle = done ? 'rgba(0,169,92,0.10)' : 'rgba(0,131,255,0.08)'; rr(xr - w, y - 34, w, 48, 24); ctx.fill();
  if (!done) {
    ctx.save(); ctx.translate(xr - w + 30, y - 10); const tw = 1 + .14 * Math.sin(t * 8); ctx.scale(tw, tw); icon('sparkles', 0, 0, 30, BLUE, 6); ctx.restore();
    ctx.save(); font(600, 25); ctx.textAlign = 'right'; const gx = xr - 18 - measure(s, 600, 25), gw = measure(s, 600, 25), ph = ((t - T_DETAIL) * .55) % 1.4 - .2;
    const gr = ctx.createLinearGradient(gx, 0, gx + gw, 0); gr.addColorStop(clamp(ph - .18), BLUE); gr.addColorStop(clamp(ph), '#9FD2FF'); gr.addColorStop(clamp(ph + .18), BLUE);
    ctx.fillStyle = gr; ctx.fillText(s, xr - 18, y); ctx.restore();
  } else {
    const s2 = E.outBack(fin, 2.5); ctx.save(); ctx.translate(xr - w + 30, y - 10); ctx.scale(s2, s2); ctx.fillStyle = '#00A95C'; ctx.beginPath(); ctx.arc(0, 0, 15, 0, Math.PI * 2); ctx.fill(); icon('check', 0, 1, 19, '#fff', 9); ctx.restore();
    text(s, xr - 18, y, { w: 600, size: 25, color: '#00A95C', align: 'right', alpha: fin });
  }
  ctx.restore();
}
function conceptE(t) {
  const lines = detLines();
  CUES.E = { tap: .52, open: T_OPEN_E, detail: T_DETAIL, voice: T_DETAIL + .12, done: T_DONE, rev: [0, 1, 2].map(T_REV),
    lines: lines.map(l => ({ sec: l.sec, t0: +l.t0.toFixed(3), dur: +l.dur.toFixed(3), x0: Math.round(l.x), x1: Math.round(l.x + l.w) })),
    finish: Math.max(...lines.map(l => l.t0 + l.dur)), end: T_DONE + 2.6 };
  drawDetail(t);
}
