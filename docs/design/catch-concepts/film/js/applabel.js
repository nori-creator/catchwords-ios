// applabel.js — ?applabel=1: the word tags as the app draws them now (owner 2026-10-23: 「実際のアプリには表示言語で
// しかつかない」; CandidatePickerView, owner 2026-10-14 「表示するのは母語にして」): one white capsule per thing, a blue dot
// and the thing's name in the reader's language, nothing else (no Mandarin, no meaning line, no NEW, no 「ほか」), sitting
// on the thing (no anchor dot or stem). Sizes from the app's screen (the iOS check's picker4 preview) at the films'
// scale. Without ?applabel=1 nothing changes.
(() => {
  if (new URLSearchParams(location.search).get('applabel') !== '1') return;
  const H = 78, SIZE = 38, DOT = 12, PADL = 26, GAP = 18, PADR = 32;
  window.tagGeom = function (tag) {
    const w = PADL + DOT * 2 + GAP + measure(tag.ja, 800, SIZE) + PADR;
    return { w, h: H, x: tag.p[0] - w / 2, y: tag.p[1] - H / 2, hint: 0 };
  };
  window.tagAnchor = function () {};
  window.newBadge = function () {};
  window.drawTag = function (tag, t, { alpha = 1, press = 0, done = 0, reveal = 1, w = null, h = null, cx = null, cy = null, textAlpha = null } = {}) {
    const ta = textAlpha == null ? alpha : textAlpha;
    if (alpha <= 0 && (ta <= 0 || reveal <= 0)) return;
    const g = tagGeom(tag), gw = w == null ? g.w : w, gh = h == null ? g.h : h;
    const X = cx == null ? tag.p[0] : cx, Y = cy == null ? g.y + g.h / 2 : cy, x = X - gw / 2, y = Y - gh / 2, r = gh / 2;
    const s = 1 - press * .07;
    ctx.save(); ctx.translate(X, Y); ctx.scale(s, s); ctx.translate(-X, -Y);
    if (alpha > 0) {
      ctx.save(); ctx.globalAlpha *= alpha; ctx.shadowColor = 'rgba(0,0,0,0.22)'; ctx.shadowBlur = 22; ctx.shadowOffsetY = 6;
      rr(x, y, gw, gh, r); ctx.fillStyle = done > 0 ? `rgba(${Math.round(255 - 255 * done)},${Math.round(255 - 86 * done)},${Math.round(255 - 163 * done)},1)` : '#FFFFFF'; ctx.fill(); ctx.restore();
    }
    if (reveal > 0 && ta > 0) {
      ctx.save(); ctx.globalAlpha *= ta; rr(x, y, gw, gh, r); ctx.clip();
      const x0 = X - g.w / 2;
      const dp = E.outBack(clamp(reveal * 3), 2.2);
      if (dp > 0) { ctx.fillStyle = done > .5 ? '#fff' : BLUE2; ctx.beginPath(); ctx.arc(x0 + PADL + DOT, Y, DOT * dp, 0, Math.PI * 2); ctx.fill(); }
      const p = E.outCubic(clamp(reveal * 1.6 - .2));
      text(tag.ja, x0 + PADL + DOT * 2 + GAP, Y + SIZE * .36 + (1 - p) * 14, { w: 800, size: SIZE, color: done > .5 ? '#fff' : INK, align: 'left', alpha: clamp(p * 1.3) });
      ctx.restore();
    }
    ctx.restore();
  };
})();
