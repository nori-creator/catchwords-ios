// picker.js — choosing which way of saying it to learn (the web CandidatePicker, stage 2): the usual word largest,
// then 「ほかの言い方」 with a register chip, the short meaning and one line on when it is used. No AI wait: the
// variants come with the candidates, and their audio is fetched in the background as soon as the picker opens.
const VAR = [
  { h: '珍珠奶茶', zy: 'ㄓㄣ ㄓㄨ ㄋㄞˇ ㄔㄚˊ', reg: 'common', mean: 'タピオカミルクティー', note: '台湾でいちばん一般的な言い方' },
  { h: '珍奶', zy: 'ㄓㄣ ㄋㄞˇ', reg: 'casual', mean: 'タピオカミルクティー', note: '珍珠奶茶の略。会話や注文でよく使う' },
  { h: '波霸奶茶', zy: 'ㄅㄛ ㄅㄚˋ ㄋㄞˇ ㄔㄚˊ', reg: 'specific', mean: '大粒タピオカのミルクティー', note: '粒の大きいタピオカのもの。店のメニューで見かける' },
];
VAR.forEach(v => v.u = Z(v.h, v.zy));
// the user chooses 珍奶 (the word they hear when ordering); ?pick=0 chooses 珍珠奶茶 (the App Store preview, owner 2026-10-23)
const PICK = VAR[Q.get('pick') === '0' ? 0 : 1];
const REG = { common: 'ふだんの言い方', casual: '砕けた言い方', specific: 'くわしい名前', proper: '固有名詞' };   // common: the chip on GET / the word page when 珍珠奶茶 is chosen (the choose screen shows none for it)
const PAL = {
  light: { ink: INK, muted: MUTED, note: '#0066CC', chipBg: '#EEF1F5', chipInk: MUTED, card: '#FFFFFF', line: '#E6ECF3', sel: 'rgba(0,131,255,0.08)', selRing: BLUE },
  warm: { ink: '#2B1D12', muted: '#7A5F47', note: '#A0522D', chipBg: 'rgba(120,85,50,0.10)', chipInk: '#6B5038', card: 'rgba(255,255,255,0.72)', line: 'rgba(120,85,50,0.14)', sel: 'rgba(160,82,45,0.10)', selRing: '#A0522D' },
};

// one candidate row; returns its height. `sel` 0..1 = chosen highlight, `press` 0..1
function pickRow(v, x, y, w, t, { size = 64, pal = PAL.light, sel = 0, press = 0, alpha = 1, chip = true, note = true, speaker = true, tVoice = -9, compact = false } = {}) {
  const pad = compact ? 22 : 30, chipH = 40;
  let h = pad; const hasChip = chip && v.reg !== 'common';
  if (hasChip) h += chipH + 12;
  h += size * 1.18;
  h += compact ? 0 : 42;            // meaning
  if (note) h += compact ? 36 : 40;
  h += pad;
  if (alpha <= 0) return h;
  ctx.save(); ctx.globalAlpha *= alpha;
  const k = 1 - press * .025; ctx.translate(x + w / 2, y + h / 2); ctx.scale(k, k); ctx.translate(-(x + w / 2), -(y + h / 2));
  if (sel > 0) { ctx.save(); ctx.globalAlpha *= sel; ctx.fillStyle = pal.sel; rr(x + 8, y + 6, w - 16, h - 12, 28); ctx.fill(); ctx.strokeStyle = pal.selRing; ctx.lineWidth = 4; ctx.stroke(); ctx.restore(); }
  let cy = y + pad;
  if (hasChip) { const cw = measure(REG[v.reg], 600, 24) + 32; ctx.fillStyle = pal.chipBg; rr(x + pad, cy, cw, chipH, 20); ctx.fill(); text(REG[v.reg], x + pad + cw / 2, cy + 28, { w: 600, size: 24, color: pal.chipInk }); cy += chipH + 12; }
  zyDraw(v.u, x + pad, cy + size * .92, size, { align: 'left', color: pal.ink, zcolor: pal.muted, w: compact ? 700 : 600 });
  cy += size * 1.18;
  if (!compact) { text(v.mean, x + pad, cy + 32, { w: 500, size: 30, color: pal.muted, align: 'left' }); cy += 42; }
  if (note) { text(v.note, x + pad, cy + (compact ? 28 : 30), { w: 600, size: compact ? 25 : 27, color: pal.note, align: 'left' }); }
  // right side: pronounce button, or the check once chosen
  const bx = x + w - pad - 44, by = y + h / 2;
  if (speaker && sel < .5) speakerBtn(bx, by, compact ? 30 : 36, t, tVoice, { alpha: 1 - sel * 2, blue: false });
  if (sel > 0) { const s = E.outBack(clamp(sel * 1.2), 2.2); ctx.save(); ctx.translate(bx, by); ctx.scale(s, s); ctx.fillStyle = pal.selRing; ctx.beginPath(); ctx.arc(0, 0, 34, 0, Math.PI * 2); ctx.fill(); icon('check', 0, 1, 44, '#fff', 8); ctx.restore(); }
  ctx.restore();
  return h;
}

// --- B: the sheet (web stage 2 as an iOS sheet) ---------------------------------------------------------------
// t0: sheet starts up, tPick: the finger lands on 珍奶, tOut: sheet goes down. Returns the 珍奶 row centre.
const SHEET_Y = 960;
function pickerSheet(t, t0, tPick, tOut) {
  const up = sp(t, t0, .48, .86), down = E.inCubic(seg(t, tOut, tOut + .3));
  const y0 = lerp(H + 40, SHEET_Y, clamp(up)) + down * (H - SHEET_Y + 80);
  if (y0 >= H) return null;
  const x = 0, w = W, pal = PAL.light;
  ctx.save(); ctx.shadowColor = 'rgba(0,0,0,0.28)'; ctx.shadowBlur = 70; ctx.fillStyle = '#F9FCFF'; rr(x, y0, w, H - y0 + 80, 56); ctx.fill(); ctx.restore();
  ctx.fillStyle = 'rgba(60,66,80,0.22)'; rr(W / 2 - 60, y0 + 20, 120, 14, 7); ctx.fill();
  // header: what is being named (its cut-out), and the question
  const im = A.d_cup, th = 120, tw = im.width / im.height * th;
  ctx.save(); ctx.shadowColor = 'rgba(0,30,70,0.22)'; ctx.shadowBlur = 10; ctx.shadowOffsetY = 6; ctx.drawImage(im, 64, y0 + 62, tw, th); ctx.restore();
  text('覚える言い方を選ぶ', 64 + tw + 28, y0 + 118, { w: 800, size: 44, align: 'left' });
  text('写っている物：タピオカミルクティー', 64 + tw + 28, y0 + 166, { w: 500, size: 28, color: MUTED, align: 'left' });
  // hero card
  const cx = 48, cw = W - 96; let cy = y0 + 214;
  const sel = seg(t, tPick + .06, tPick + .26);
  const heroH = 400;
  ctx.save(); ctx.shadowColor = 'rgba(15,40,80,0.07)'; ctx.shadowBlur = 24; ctx.shadowOffsetY = 8; ctx.fillStyle = '#fff'; rr(cx, cy, cw, heroH, 48); ctx.fill(); ctx.restore();
  ctx.strokeStyle = pal.line; ctx.lineWidth = 2; rr(cx, cy, cw, heroH, 48); ctx.stroke();
  const hv = VAR[0];
  zyDraw(hv.u, cx + 44, cy + 122, 92, { align: 'left', w: 600 });
  text(hv.mean, cx + 44, cy + 186, { w: 500, size: 32, color: MUTED, align: 'left' });
  text(hv.note, cx + 44, cy + 232, { w: 600, size: 29, color: pal.note, align: 'left' });
  speakerBtn(cx + cw - 84, cy + 104, 46, t, -9, { blue: false });
  ctx.fillStyle = BLUE; rr(cx + 36, cy + heroH - 124, cw - 72, 96, 48); ctx.fill();
  text('この語で図鑑に入れる', cx + cw / 2, cy + heroH - 62, { w: 700, size: 34, color: '#fff' });
  cy += heroH + 34;
  text('ほかの言い方', cx + 12, cy + 30, { w: 600, size: 28, color: MUTED, align: 'left' });
  cy += 52;
  // list card
  const rows = [VAR[1], VAR[2]]; let hs = rows.map(v => pickRow(v, 0, 0, cw, t, { size: 62, alpha: 0 })); const listH = hs[0] + hs[1];
  ctx.save(); ctx.fillStyle = '#fff'; rr(cx, cy, cw, listH, 40); ctx.fill(); ctx.strokeStyle = pal.line; ctx.lineWidth = 2; ctx.stroke(); ctx.restore();
  const press = seg(t, tPick, tPick + .06) * (1 - seg(t, tPick + .12, tPick + .24));
  pickRow(VAR[1], cx, cy, cw, t, { size: 62, sel, press });
  ctx.fillStyle = pal.line; ctx.fillRect(cx + 30, cy + hs[0], cw - 60, 2);
  pickRow(VAR[2], cx, cy + hs[0], cw, t, { size: 62, alpha: 1 - sel * .45 });
  return [cx + cw * .42, cy + hs[0] / 2];
}

// --- A: a glass list under the floating sticker -------------------------------------------------------------
function pickerGlass(t, t0, tPick, y, { out = 0 } = {}) {
  const x = 60, w = W - 120;
  const sel = seg(t, tPick + .06, tPick + .26), press = seg(t, tPick, tPick + .06) * (1 - seg(t, tPick + .12, tPick + .24));
  const rowsH = VAR.map((v, i) => pickRow(v, 0, 0, w, t, { size: i ? 60 : 78, alpha: 0, note: true }));
  const total = rowsH.reduce((a, b) => a + b, 0);
  const a = E.outCubic(seg(t, t0, t0 + .3)) * (1 - out);
  if (a <= 0) return null;
  text('覚える言い方を選ぶ', W / 2, y - 26, { w: 700, size: 34, color: 'rgba(255,255,255,0.95)', alpha: a });
  glass(x, y, w, total, 48, { alpha: a, tint: 'rgba(255,255,255,0.84)' });
  let cy = y, res = null;
  VAR.forEach((v, i) => {
    const ri = E.outCubic(seg(t, t0 + .06 * i, t0 + .06 * i + .32));
    const isPick = v === PICK;
    const al = a * ri * (isPick ? 1 : 1 - sel * .5);
    ctx.save(); ctx.translate(0, (1 - ri) * 24);
    pickRow(v, x, cy, w, t, { size: i ? 60 : 78, alpha: al, sel: isPick ? sel : 0, press: isPick ? press : 0 });
    ctx.restore();
    if (i < VAR.length - 1) { ctx.save(); ctx.globalAlpha = a * .6; ctx.fillStyle = 'rgba(11,18,26,0.08)'; ctx.fillRect(x + 30, cy + rowsH[i], w - 60, 2); ctx.restore(); }
    if (isPick) res = [x + w * .4, cy + rowsH[i] / 2];
    cy += rowsH[i];
  });
  return res;
}

// --- C: a compact popover anchored to the tag ----------------------------------------------------------------
function pickerPopover(t, t0, tPick, tag) {
  const g = tagGeom(tag), w = 820, x = clamp(tag.p[0] - w / 2, 40, W - 40 - w);
  const open = sp(t, t0, .36, .78), close = E.inCubic(seg(t, tPick + .2, tPick + .38));
  const a = clamp(open) * (1 - close); if (a <= 0) return null;
  const sel = seg(t, tPick + .04, tPick + .2), press = seg(t, tPick, tPick + .06) * (1 - seg(t, tPick + .12, tPick + .24));
  const rowsH = VAR.map(v => pickRow(v, 0, 0, w, t, { size: 52, alpha: 0, compact: true }));
  const total = rowsH.reduce((p, q) => p + q, 0) + 20, y = g.y - 26 - total;
  // grows out of the tag (scale from the tag's top centre)
  const k = lerp(.6, 1, clamp(open));
  ctx.save(); ctx.translate(tag.p[0], g.y); ctx.scale(k, k); ctx.translate(-tag.p[0], -g.y);
  glass(x, y, w, total, 44, { alpha: a, tint: 'rgba(255,255,255,0.86)' });
  ctx.save(); ctx.globalAlpha *= a; ctx.fillStyle = 'rgba(255,255,255,0.86)'; ctx.beginPath(); ctx.moveTo(tag.p[0] - 22, y + total - 1); ctx.lineTo(tag.p[0], y + total + 22); ctx.lineTo(tag.p[0] + 22, y + total - 1); ctx.fill(); ctx.restore();
  let cy = y + 10, res = null;
  VAR.forEach((v, i) => {
    const isPick = v === PICK;
    pickRow(v, x, cy, w, t, { size: 52, alpha: a * (isPick ? 1 : 1 - sel * .5), sel: isPick ? sel : 0, press: isPick ? press : 0, compact: true, speaker: true });
    if (i < VAR.length - 1) { ctx.save(); ctx.globalAlpha = a * .6; ctx.fillStyle = 'rgba(11,18,26,0.08)'; ctx.fillRect(x + 24, cy + rowsH[i], w - 48, 2); ctx.restore(); }
    if (isPick) res = [x + w * .38, cy + rowsH[i] / 2];
    cy += rowsH[i];
  });
  ctx.restore();
  return res;
}
