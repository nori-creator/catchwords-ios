// concepts6.js — the v6 flow as one take: F = scan (P1 + lock-on brackets) → standard tags → tap → D (choose the way to
// say it, in the app's own white-and-blue) → the GET moment → into the 図鑑.  S = the slow case (?ai=11.5): the scan and
// the long wait only, to the tap.  Each concept publishes its key times (CUES) for the sound mix and the haptics.
const CUES = {};
const PICK_U = PICK.u;

function scrollAt(t, t0, t1, a, b) { const u = seg(t, t0, t1); const e = 1 - Math.pow(1 - E.inOutSine(Math.min(1, u * 1.15)), 2.2); return lerp(a, b, clamp(e)); }
function scrollVel(t, t0, t1, a, b) { return (scrollAt(t, t0, t1, a, b) - scrollAt(t - 1 / 60, t0, t1, a, b)); }
function flyTrail(stk, path, fly, s0, s1, r1, n = 3) {
  for (let k = n; k >= 1; k--) { const fk = clamp(fly - k * .05); if (fk <= 0) continue; const e = E.inCubic(fk); const p = path(e); placeTile(stk, p[0], p[1], lerp(s0, s1, e), r1 * e, .14 / k); }
}
const ARRIVE_S = 1.3 * (SLOT * .86) / CUP_CUT_H * (1184 / 1172);
const FX = (I, anticip, compact = false) => ({ I, anticip, compact, k0: 1.3, r0: -.12 });
const START = { F: 0, S: 0 };

// a four-point star (the sparkle of the app's sparkles icon), for the GET moment and the word page's reveal
function star4(x, y, r, rot, alpha, color = '#fff', c = ctx) {
  if (alpha <= 0 || r <= 0) return;
  c.save(); c.globalAlpha *= alpha; c.translate(x, y); c.rotate(rot); c.fillStyle = color; c.beginPath();
  c.moveTo(0, -r); c.quadraticCurveTo(r * .14, -r * .14, r, 0); c.quadraticCurveTo(r * .14, r * .14, 0, r); c.quadraticCurveTo(-r * .14, r * .14, -r, 0); c.quadraticCurveTo(-r * .14, -r * .14, 0, -r);
  c.fill(); c.restore();
}

// ===================================================================================================================
// D + GET. After the choice the word gets its own moment before it goes into the 図鑑: the cup becomes a sticker in the
// middle of the page, the voice says the word while its characters land one per syllable, the meaning follows, then
// 「新しいことばをキャッチ！」 with the catch jingle. It holds (~1.7 s with everything on screen) so the word can be read and
// heard; then it flies into its slot. In the app a tap anywhere skips ahead.
const D_POS = [540, 560], D_S = .34;
const D_CARD = { x: 40, y: 1150, w: W - 80 };
const GET_POS = [540, 1060], GET_S = .5;
function getTimes(C) {
  const P = C + 1.6, G = P + .62;
  // the voice (voice_zhennai_4): 珍 starts 0.08 s and 奶 0.27 s into the file; the mix places the file at G − 0.04.
  // 珍珠奶茶 (voice_zhenzhu, ?pick=0): 珍 0.08, 珠 0.33, 奶 0.52, 茶 0.72 s; the word is longer, so all after it is 0.45 s later.
  const long = PICK === VAR[0], d = long ? .45 : 0, ch = long ? [G + .04, G + .29, G + .48, G + .68] : [G + .04, G + .23];
  return { C, P, rise: P + .18, cut: P + .32, G, ch, mean: P + 1.15 + d, catchT: P + 1.32 + d,
    out: P + 2.9 + d, open: P + 3.0 + d, scroll0: P + 3.05 + d, scroll1: P + 3.6 + d, anticip: P + 3.3 + d, launch: P + 3.42 + d, I: P + 3.82 + d };
}
function wordPop(t, x, y, size, times) {                  // each character lands with its syllable (scale + blur → sharp, a glow)
  const { cell } = zyCell(size), total = zyWidth(PICK_U, size); let cx = x - total / 2;
  PICK_U.forEach((u, i) => {
    const t0 = times[Math.min(i, times.length - 1)] + Math.max(0, i - times.length + 1) * .12, p = seg(t, t0 - .02, t0 + .32);
    if (p > 0) {
      const g = seg(t, t0, t0 + .6);
      if (g < 1) { const gx = cx + size / 2, gy = y - size * .36, R = size * 1.1, gr = ctx.createRadialGradient(gx, gy, 0, gx, gy, R); gr.addColorStop(0, `rgba(42,155,255,${.28 * Math.sin(Math.PI * g)})`); gr.addColorStop(1, 'rgba(42,155,255,0)'); ctx.fillStyle = gr; ctx.fillRect(gx - R, gy - R, 2 * R, 2 * R); }
      const sc = lerp(1.38, 1, E.outBack(p, 1.9));
      ctx.save(); ctx.globalAlpha *= clamp(p * 3); const ox = cx + size / 2, oy = y - size * .36; ctx.translate(ox, oy); ctx.scale(sc, sc); ctx.translate(-ox, -oy);
      if (p < .35) ctx.filter = `blur(${(1 - p / .35) * 7}px)`;
      zyDraw([u], cx, y, size, { align: 'left', w: 800, color: INK, zcolor: MUTED });
      ctx.restore();
    }
    cx += cell;
  });
  return total;
}
// ---------- the GET backdrop (rebuilt from scratch, owner 2026-10-10: the sunburst looked cheap) ----------
// A lit stage for the catch, like a piece in a collection: a seamless backdrop (wall curving into a floor), one soft
// key light from above, a pool of light on the floor where the sticker floats, its soft shadow and a faint reflection,
// a few motes in the light. The thing's own colour (k-means on its cut-out — here the milk tea) warms the light round
// it and bounces on the floor, so each catch is lit in its own colour. The word sits in front like the label of the
// piece. The catch beat: the light swells, two rings run out across the floor, sparkles round the headline.
// SwiftUI: gradients + a Canvas (shadow, reflection = the sticker flipped with a mask, motes), TimelineView for drift.
let GETPAL = null;
const mixW = (c, k) => c.map(v => Math.round(v + (255 - v) * k));
function getPalette() {
  if (GETPAL) return GETPAL;
  const im = A.d_cup, w = 48, h = Math.round(48 * im.height / im.width), c = document.createElement('canvas'); c.width = w; c.height = h;
  const g = c.getContext('2d', { willReadFrequently: true }); g.drawImage(im, 0, 0, w, h); const d = g.getImageData(0, 0, w, h).data, px = [];
  for (let i = 0; i < d.length; i += 4) if (d[i + 3] > 200) px.push([d[i], d[i + 1], d[i + 2]]);
  // k-means (k = 4), seeded by lightness quantiles so it is deterministic
  const L = p => .299 * p[0] + .587 * p[1] + .114 * p[2], sorted = px.slice().sort((p, q) => L(p) - L(q));
  let cen = [.15, .4, .65, .9].map(f => sorted[Math.floor(f * (sorted.length - 1))].slice()), lab = new Array(px.length).fill(0);
  for (let it = 0; it < 12; it++) {
    px.forEach((p, i) => { let bi = 0, bd = 1e9; cen.forEach((q, j) => { const dd = (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 + (p[2] - q[2]) ** 2; if (dd < bd) { bd = dd; bi = j; } }); lab[i] = bi; });
    cen = cen.map((q, j) => { const m = px.filter((_, i) => lab[i] === j); return m.length ? [0, 1, 2].map(k => m.reduce((a, p) => a + p[k], 0) / m.length) : q; });
  }
  const cnt = cen.map((_, j) => lab.filter(l => l === j).length);
  const byL = cen.map((q, j) => ({ q, n: cnt[j], l: L(q) })).sort((p, q) => q.l - p.l);
  const light = byL[0].q, warm = byL.filter(c => c.l > 70 && c.l < 200).sort((p, q) => q.n - p.n)[0]?.q || byL[1].q;
  const hex = c => '#' + c.map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
  // the object's warm tone as light: same hue, lifted to a luminous pastel (HSL L 0.89, S ×1.6)
  const glow = hslAdj(warm, { l: .89, sMul: 1.6, sMax: .8 }), glow2 = hslAdj(light, { l: .93, sMul: 1.4, sMax: .7 });
  GETPAL = { glow, glow2, sky: [215, 232, 255], peri: [226, 224, 255], aqua: [211, 243, 255], white: [255, 255, 255], src: [hex(light), hex(warm)], out: [hex(glow), hex(glow2)] };
  return GETPAL;
}
function hslAdj([r, g, b], { l, sMul = 1, sMax = 1 }) {
  r /= 255; g /= 255; b /= 255; const mx = Math.max(r, g, b), mn = Math.min(r, g, b); let h = 0, s = 0; const L0 = (mx + mn) / 2;
  if (mx !== mn) { const d = mx - mn; s = L0 > .5 ? d / (2 - mx - mn) : d / (mx + mn); h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h /= 6; }
  s = Math.min(sMax, s * sMul);
  const q = l < .5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q, f = t => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < .5 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p; };
  return [f(h + 1 / 3), f(h), f(h - 1 / 3)].map(v => Math.round(v * 255));
}
const FLOOR_Y = 1388;                                    // where the floor meets the light under the sticker
let GRAIN = null;
function grainTile() {
  if (GRAIN) return GRAIN; GRAIN = document.createElement('canvas'); GRAIN.width = GRAIN.height = 256; const g = GRAIN.getContext('2d'), im = g.createImageData(256, 256);
  for (let i = 0; i < 256 * 256; i++) { const v = 128 + (rnd(i * 1.37) - .5) * 90; im.data[i * 4] = im.data[i * 4 + 1] = im.data[i * 4 + 2] = v; im.data[i * 4 + 3] = 255; }
  g.putImageData(im, 0, 0); return GRAIN;
}
const rgba = (c, a) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;
function getStage(t, T, a, cx) {
  if (a <= 0) return;
  const P = getPalette(), swell = Math.sin(Math.PI * seg(t, T.catchT - .05, T.catchT + .95));
  ctx.save(); ctx.globalAlpha = a;
  // the wall, curving into the floor (cool at the top, lit white behind the piece, a soft shade in the curve)
  const wall = ctx.createLinearGradient(0, 0, 0, H);
  [[0, '#E6EEFB'], [.22, '#F1F6FE'], [.42, '#FBFCFF'], [.54, '#F6F8FC'], [.585, '#E9EEF6'], [.62, '#EDF1F8'], [.8, '#E8EDF5'], [1, '#DFE6F0']].forEach(([o, c]) => wall.addColorStop(o, c));
  ctx.fillStyle = wall; ctx.fillRect(0, 0, W, H);
  // the key light on the wall behind the piece, warmed by the piece's own colour
  const kl = ctx.createRadialGradient(cx, 930, 0, cx, 930, 760); kl.addColorStop(0, `rgba(255,255,255,${.85 + .15 * swell})`); kl.addColorStop(.55, 'rgba(255,255,255,0.35)'); kl.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = kl; ctx.fillRect(0, 0, W, H);
  const au = ctx.createRadialGradient(cx, 1010, 0, cx, 1010, 520 + 60 * swell); au.addColorStop(0, rgba(P.glow, .5 + .2 * swell)); au.addColorStop(.6, rgba(P.glow2, .22)); au.addColorStop(1, rgba(P.glow2, 0));
  ctx.fillStyle = au; ctx.fillRect(0, 0, W, H);
  // the pool of light on the floor, with the piece's colour bouncing in it
  ctx.save(); ctx.translate(cx, FLOOR_Y + 10); ctx.scale(1, .2);
  let pl = ctx.createRadialGradient(0, 0, 0, 0, 0, 600 + 40 * swell); pl.addColorStop(0, `rgba(255,255,255,${.95})`); pl.addColorStop(.5, 'rgba(255,255,255,0.45)'); pl.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = pl; ctx.beginPath(); ctx.arc(0, 0, 640, 0, Math.PI * 2); ctx.fill();
  pl = ctx.createRadialGradient(0, 0, 0, 0, 0, 300); pl.addColorStop(0, rgba(P.glow, .45)); pl.addColorStop(1, rgba(P.glow, 0)); ctx.fillStyle = pl; ctx.beginPath(); ctx.arc(0, 0, 300, 0, Math.PI * 2); ctx.fill();
  ctx.restore();
  // the catch: two rings run out across the floor (ellipses in the floor's perspective)
  [[0, 1], [.14, .55]].forEach(([d, a0]) => {
    const u = seg(t, T.catchT + d, T.catchT + d + .95); if (u <= 0 || u >= 1) return;
    const e = E.outCubic(u), rx = lerp(170, 720, e); ctx.save(); ctx.globalAlpha *= a0 * (1 - u) ** 1.3;
    ctx.strokeStyle = 'rgba(255,255,255,0.95)'; ctx.lineWidth = lerp(4, 1.5, e); ctx.shadowColor = 'rgba(42,155,255,0.75)'; ctx.shadowBlur = 18;
    ctx.beginPath(); ctx.ellipse(cx, FLOOR_Y + 8, rx, rx * .19, 0, 0, Math.PI * 2); ctx.stroke(); ctx.restore();
  });
  // motes drifting in the light
  for (let i = 0; i < 16; i++) {
    const sp2 = 10 + 14 * rnd(i * 5.1), y0 = 260 + 1080 * rnd(i * 2.7), yy = ((y0 - t * sp2) % 1100 + 1100) % 1100 + 260, xx = cx + (rnd(i * 9.3) - .5) * 640 + 24 * Math.sin(t * .5 + i);
    const inLight = clamp(1 - Math.abs(xx - cx) / 360) * clamp((yy - 240) / 200) * clamp((1380 - yy) / 160), tw = .55 + .45 * Math.sin(t * (1.3 + rnd(i)) * 2 + i);
    const r = 2 + 2.5 * rnd(i * 1.9), al = .55 * inLight * tw * (1 + swell); if (al <= .02) continue;
    const g = ctx.createRadialGradient(xx, yy, 0, xx, yy, r * 3); g.addColorStop(0, `rgba(255,255,255,${al})`); g.addColorStop(.35, `rgba(255,255,255,${al * .5})`); g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g; ctx.fillRect(xx - r * 3, yy - r * 3, r * 6, r * 6);
  }
  // fine grain (keeps the soft gradients from banding in 8-bit video)
  ctx.globalAlpha = a * .045; ctx.globalCompositeOperation = 'overlay'; ctx.fillStyle = ctx.createPattern(grainTile(), 'repeat'); ctx.fillRect(0, 0, W, H);
  ctx.restore();
}
// the piece's own shadow and reflection on the stage floor (drawn under the sticker)
function stageFloor(stk, cx, cy, s, a, bob) {
  if (a <= 0) return;
  const c = M.cup, bottom = cy + (CUP_CUT_H / 2) * s, lift = Math.max(0, FLOOR_Y - bottom) + 6;
  const sa = a * clamp(1 - lift / 160) * .42;
  if (sa > .005) { ctx.save(); ctx.globalAlpha = sa; ctx.fillStyle = '#2B3A52'; ctx.filter = `blur(${10 + lift * .18}px)`;
    ctx.beginPath(); ctx.ellipse(cx, FLOOR_Y + 4, Math.max(1, 150 * s / .5 * (1 - lift / 600)), Math.max(1, 20 * s / .5), 0, 0, Math.PI * 2); ctx.fill(); ctx.filter = 'none'; ctx.restore(); }
  // reflection: the sticker mirrored about the floor, fading quickly
  if (lift >= 120) return;
  const RH = 190; if (!REFL.ctx) { REFL.c = document.createElement('canvas'); REFL.c.width = W; REFL.c.height = RH; REFL.ctx = REFL.c.getContext('2d'); }
  const rx = REFL.ctx; rx.setTransform(1, 0, 0, 1, 0, 0); rx.clearRect(0, 0, W, RH); rx.globalCompositeOperation = 'source-over';
  rx.save(); rx.translate(cx, FLOOR_Y - cy - 2); rx.scale(s, -s); rx.drawImage(stk, -c.tw / 2, -c.th / 2); rx.restore();
  rx.globalCompositeOperation = 'destination-in'; const g = rx.createLinearGradient(0, 0, 0, RH); g.addColorStop(0, 'rgba(0,0,0,0.9)'); g.addColorStop(1, 'rgba(0,0,0,0)'); rx.fillStyle = g; rx.fillRect(0, 0, W, RH);
  ctx.save(); ctx.globalAlpha = a * .16 * clamp(1 - lift / 120); ctx.filter = 'blur(1.5px)'; ctx.drawImage(REFL.c, 0, FLOOR_Y + 2); ctx.filter = 'none'; ctx.restore();
}
const REFL = {};
function getText(t, T, alpha) {                           // headline, chip, word, meaning, note
  if (alpha <= 0) return;
  ctx.save(); ctx.globalAlpha *= alpha;
  // 「新しいことばをキャッチ！」 (the app's own line) pops with the jingle, sparkles burst round it
  const hp = seg(t, T.catchT, T.catchT + .4);
  if (hp > 0) {
    const k = lerp(.6, 1, E.outBack(hp, 2.6)); ctx.save(); ctx.globalAlpha *= clamp(hp * 4); ctx.translate(540, 550); ctx.scale(k, k); ctx.translate(-540, -550);
    text('新しいことばをキャッチ！', 540, 570, { w: 900, size: 66, color: BLUE }); ctx.restore();
    const cp = E.outCubic(seg(t, T.catchT + .12, T.catchT + .42));
    ctx.save(); ctx.globalAlpha *= cp; ctx.translate(0, (1 - cp) * 14);
    const lab = 'No.001 · 飲み物', lw = measure(lab, 600, 30) + 120 + 16, lx = 540 - lw / 2;
    ctx.fillStyle = BLUE; rr(lx, 610, 120, 50, 25); ctx.fill(); text('NEW', lx + 60, 645, { w: 800, size: 26, f: FONT_UI, color: '#fff', ls: 2 });
    text(lab, lx + 136, 646, { w: 600, size: 30, color: MUTED, align: 'left' }); ctx.restore();
    [[-430, -40, 34, 0], [424, -70, 28, .05], [-392, 52, 20, .1], [452, 34, 30, .07], [-470, 6, 16, .14], [330, -112, 18, .12]].forEach(([dx, dy, r, d]) => {
      const u = seg(t, T.catchT + d, T.catchT + d + .9); if (u <= 0 || u >= 1) return;
      const s = E.outBack(seg(u, 0, .3), 3) * (1 - E.inCubic(seg(u, .55, 1))), tw = .75 + .25 * Math.sin(u * 20);
      star4(540 + dx * lerp(.86, 1.04, E.outCubic(u)), 550 + dy, r * s * tw, u * 1.2, 1, d % .1 ? '#64E0FF' : BLUE2);
    });
  }
  // the word, one character per syllable, the reading beside each; the speaker shows the voice
  const total = wordPop(t, 540 - 40, 1600, 150, T.ch);
  const sa = E.outCubic(seg(t, T.G - .1, T.G + .15)); if (sa > 0) speakerBtn(540 - 40 + total / 2 + 96, 1545, 46, t, T.G, { alpha: sa, blue: false });
  // register + meaning, then the note
  const ma = E.outCubic(seg(t, T.mean, T.mean + .3));
  if (ma > 0) {
    ctx.save(); ctx.globalAlpha *= ma; ctx.translate(0, (1 - ma) * 16);
    const chip = REG[PICK.reg], cw = measure(chip, 600, 28) + 36, mw = measure(PICK.mean, 500, 38), x0 = 540 - (cw + 20 + mw) / 2;
    ctx.fillStyle = '#EDF2F8'; rr(x0, 1665, cw, 50, 25); ctx.fill(); text(chip, x0 + cw / 2, 1700, { w: 600, size: 28, color: MUTED });
    text(PICK.mean, x0 + cw + 20, 1703, { w: 500, size: 38, color: MUTED, align: 'left' });
    text(PICK.note, 540, 1775, { w: 600, size: 30, color: '#0066CC', alpha: E.outCubic(seg(t, T.mean + .15, T.mean + .45)) });
    ctx.restore();
  }
  ctx.restore();
}
function dGet(t, T) {
  const { C, P, I } = T, cc = cupCenter();
  const melt = E.inOutCubic(seg(t, C + .05, C + .6)), toDex = E.inOutCubic(seg(t, T.open, T.open + .4));
  const pose = sp(t, C + .05, .62, .8), m = clamp(sp(t, T.rise, .55, .8), 0, 1.08);
  const bob = Math.sin((t - C) * 2.6) * 10 * seg(t, C + .6, C + 1) * (1 - toDex);
  const sx = lerp(D_POS[0], GET_POS[0], m), sy = lerp(D_POS[1], GET_POS[1], m), ss = lerp(D_S, GET_S, m);
  photoBase(t, { blur: 40 * melt, bright: 1 + .06 * melt, scale: 1 + .08 * melt, focus: cc });
  if (melt > 0) {
    bgx.save(); bgx.globalAlpha = melt; bgx.fillStyle = BG_APP; bgx.fillRect(0, 0, W, H);
    const R = lerp(620, 760, clamp(m)), r = bgx.createRadialGradient(sx, sy + 20, 0, sx, sy + 20, R);
    r.addColorStop(0, '#DDEEFF'); r.addColorStop(.55, 'rgba(234,244,255,0.75)'); r.addColorStop(1, 'rgba(234,244,255,0)');
    bgx.fillStyle = r; bgx.fillRect(0, 0, W, H); bgx.restore();
  }
  makeBlur(); ctx.drawImage(BG, 0, 0);
  tagsSettled(t, { otherAlpha: 1 - seg(t, C, C + .15), cupAlpha: 1 - seg(t, C, C + .15), cupPress: cupTagPress(t) });
  topPill(t, -1, C, '覚えたいことばをタップ', { icon: 'sparkles' });
  const textA = 1 - E.inOutCubic(seg(t, T.out, T.out + .25));
  const stageA = E.inOutCubic(seg(t, P + .14, P + .8)) * (1 - E.inOutCubic(seg(t, T.open + .1, T.open + .4)));
  getStage(t, T, stageA, sx);
  let slotXY = null;
  if (toDex > 0) slotXY = drawDexPage(t, { top: (1 - toDex) * 140, alpha: toDex, sy: scrollAt(t, T.scroll0, T.scroll1, scrollToCat(3), 0), vy: scrollVel(t, T.scroll0, T.scroll1, scrollToCat(3), 0), fx: FX(I, T.anticip) });
  // the card (the choice): white card, hairline border, blue selection, blue NEW chip (as D in v5)
  const out = E.inOutCubic(seg(t, P + .22, P + .5));
  if (t > C + .4 && out < 1) {
    ctx.save(); ctx.globalAlpha = 1 - out; ctx.translate(0, out * 60);
    const a1 = E.outCubic(seg(t, C + .45, C + .7)) * (1 - E.inOutCubic(seg(t, P + .02, P + .16))), rise = (1 - E.outCubic(seg(t, C + .45, C + .7))) * 30;
    ctx.save(); ctx.translate(0, rise); ctx.globalAlpha *= a1;
    ctx.fillStyle = BLUE; rr(64, 900, 120, 52, 26); ctx.fill(); text('NEW', 124, 936, { w: 800, size: 26, f: FONT_UI, color: '#fff', ls: 2 });
    text('No.001 · 飲み物', 206, 937, { w: 600, size: 30, color: MUTED, align: 'left' });
    text('覚える言い方を選ぶ', 64, 1050, { w: 800, size: 50, color: INK, align: 'left' });
    text('写っている物：タピオカミルクティー', 64, 1104, { w: 500, size: 30, color: MUTED, align: 'left' });
    ctx.restore();
    const sel = seg(t, P + .06, P + .26), press = seg(t, P, P + .06) * (1 - seg(t, P + .12, P + .24));
    const sizes = [84, 64, 64], hs = VAR.map((v, i) => pickRow(v, 0, 0, D_CARD.w, t, { size: sizes[i], alpha: 0 })), total = hs.reduce((a, b) => a + b, 0);
    const cardIn = E.outCubic(seg(t, C + .5, C + .82));
    ctx.save(); ctx.globalAlpha *= cardIn; ctx.translate(0, (1 - cardIn) * 40);
    ctx.save(); ctx.shadowColor = 'rgba(15,40,80,0.08)'; ctx.shadowBlur = 40; ctx.shadowOffsetY = 12; ctx.fillStyle = '#fff'; rr(D_CARD.x, D_CARD.y, D_CARD.w, total, 48); ctx.fill(); ctx.restore();
    ctx.strokeStyle = '#E0E5EB'; ctx.lineWidth = 2.5; rr(D_CARD.x, D_CARD.y, D_CARD.w, total, 48); ctx.stroke();
    let cy = D_CARD.y;
    VAR.forEach((v, i) => {
      const ri = E.outCubic(seg(t, C + .58 + i * .07, C + .9 + i * .07)), isPick = v === PICK;
      ctx.save(); ctx.translate(0, (1 - ri) * 18);
      pickRow(v, D_CARD.x, cy, D_CARD.w, t, { size: sizes[i], pal: PAL.light, alpha: ri * (isPick ? 1 : 1 - sel * .55), sel: isPick ? sel : 0, press: isPick ? press : 0 });
      ctx.restore();
      if (isPick) CUES.F.pickXY = [D_CARD.x + D_CARD.w * .4, cy + hs[i] / 2];
      if (i < 2) { ctx.save(); ctx.globalAlpha *= ri; ctx.fillStyle = '#E0E5EB'; ctx.fillRect(D_CARD.x + 30, cy + hs[i], D_CARD.w - 60, 2); ctx.restore(); }
      cy += hs[i];
    });
    ctx.restore();
    text('選ぶと、そのことばで図鑑に入ります', W / 2, cy + 70, { w: 500, size: 30, color: MUTED, alpha: E.outCubic(seg(t, C + .9, C + 1.1)) });
    ctx.restore();
  }
  // the cup → the sticker (die-cut border on the choice, holo sheen on the catch) → the slot
  if (t >= C && t < I) {
    let cx = lerp(cc[0], D_POS[0], clamp(pose)), cy = lerp(cc[1], D_POS[1], clamp(pose)) + bob, s = lerp(1, D_S, clamp(pose)), r = 0;
    if (t > T.rise) { cx = sx; cy = sy + bob; s = ss; }
    s *= 1 + .07 * Math.sin(Math.PI * seg(t, T.anticip - .1, T.launch)) - .05 * E.inOutCubic(seg(t, T.out, T.anticip));
    const fly = seg(t, T.launch, I), e = E.inCubic(fly), tgt = slotXY || [188, 622];
    const p0 = [cx, cy], path = u => bez2(p0, [p0[0] + 80, p0[1] - 320], tgt, u);
    const border = 20 * E.outCubic(seg(t, T.cut, T.cut + .3));
    const stk = sticker({ border, sheen: seg(t, C + .6, C + 1.1), holo: seg(t, T.catchT - .05, T.catchT + .85) });
    if (fly > 0) { flyTrail(stk, path, fly, s, ARRIVE_S, -.12); const p = path(e); cx = p[0]; cy = p[1]; s = lerp(s, ARRIVE_S, e); r = -.12 * e; }
    if (fly <= 0) { const k = s / D_S, sa = .2 * clamp(pose) * (1 - toDex); ctx.save(); ctx.globalAlpha = sa; ctx.fillStyle = '#0F2850'; ctx.filter = 'blur(16px)'; ctx.beginPath(); ctx.ellipse(cx, cy - bob + 236 * k - bob * .3, (112 - bob) * k, 18 * k, 0, 0, Math.PI * 2); ctx.fill(); ctx.filter = 'none'; ctx.restore(); }
    if (fly <= 0) stageFloor(stk, cx, cy, s, stageA, bob);
    const sh = clamp(m) * (1 - fly) * (1 - stageA); if (sh > 0) shadowTile(cx, cy, s, .42 * sh, 22);
    placeTile(stk, cx, cy, s, r, 1);
  }
  getText(t, T, textA);
  const tabIn = E.outCubic(seg(t, T.open + .15, T.open + .45));
  tabBar({ sel: t > T.open ? 1 : 2, alpha: t < C + .5 ? 1 - seg(t, C + .05, C + .3) : tabIn, dy: (1 - tabIn) * 100, t });
  goalToast(t, I + .85, 99);
  finger(tagFinger[0], tagFinger[1], t, T_TAP - .22, T_TAP);
  const pk = CUES.F.pickXY; if (pk) finger(pk[0], pk[1], t, P - .3, P);
  statusBar(melt > .5); homeIndicator(melt > .5);
}

// ===================================================================================================================
function conceptF(t) {
  const T = getTimes(C0);
  CUES.F = Object.assign(CUES.F || {}, scanCues(), { C: T.C, P: T.P, melt: T.C + .05, card: T.C + .45, rise: T.rise, cut: T.cut, voice: T.G, chars: T.ch, mean: T.mean,
    catch: T.catchT, out: T.out, open: T.open, scroll0: T.scroll0, scroll1: T.scroll1, anticip: T.anticip, launch: T.launch, I: T.I, end: T.I + 2.5 });
  if (t < T.C) { scanScene(t); return; }
  dGet(t, T);
}
// the slow case: load with ?ai=11.5 (the real 90th percentile)
function conceptS(t) {
  CUES.S = Object.assign(scanCues(), { end: T_TAP + .6 });
  scanScene(t);
}
