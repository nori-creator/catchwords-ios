// apptab.js — ?apptab=1: the app's own tab bar in place of the films' drawn one (owner 2026-10-23: 「アプリの下のバーの
// アイコン…が再現されてない。実際のアプリに準拠して」). The pictures are cut from the app's screen (the iOS check's
// tabbar previews, 1206 px wide: assets/apptab/<lang>-sel1.png 図鑑 chosen, -sel2.png カメラ chosen) and drawn at the
// films' scale (1080 / 1206), where the films put their bar. Without ?apptab=1 nothing changes.
(() => {
  const q = new URLSearchParams(location.search);
  if (q.get('apptab') !== '1') return;
  const lang = q.get('lang') === 'en' ? 'en' : 'ja';
  const imgs = {};
  const ready = Promise.all([1, 2].map(sel => new Promise(res => {
    const im = new Image(); im.onload = () => { imgs[sel] = im; res(); }; im.onerror = res; im.src = `assets/apptab/${lang}-sel${sel}.png`;
  })));
  const origLoad = load;
  window.load = () => Promise.all([origLoad(), ready]).then(r => r[0]);
  const origTab = tabBar, K = 1080 / 1206;
  window.tabBar = function (opts = {}) {
    const { sel = 2, alpha = 1, dy = 0 } = opts, im = imgs[sel];
    if (!im) return origTab(opts);
    if (alpha <= 0) return;
    const w = im.width * K, h = im.height * K, x = W / 2 - w / 2, y = TAB_Y + TAB_H / 2 - h / 2 + dy;
    ctx.save(); ctx.globalAlpha = alpha;
    ctx.shadowColor = 'rgba(15,30,60,0.14)'; ctx.shadowBlur = 36; ctx.shadowOffsetY = 10;
    ctx.drawImage(im, x, y, w, h);
    ctx.restore();
  };
})();
