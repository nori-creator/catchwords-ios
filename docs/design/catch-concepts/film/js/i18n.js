// i18n.js — ?lang=en: the films' Japanese text in English, for the App Store preview's English version (owner
// 2026-10-22: no Japanese on the English page). Every string the films draw goes through the canvas' fillText and
// measureText, so those two translate whole strings; words in Mandarin (the headwords, the readings, the examples) are
// not in the table and stay as they are. The app's own English where it has one (ios/.../Localization/strings.json).
// Without ?lang=en nothing changes.
(() => {
  if (new URLSearchParams(location.search).get('lang') !== 'en') return;
  const EN = {
    'ホーム': 'Home', '図鑑': 'Collection', 'カメラ': 'Camera', '復習': 'Review', '設定': 'Settings',
    'タピオカミルクティー': 'bubble tea', 'バイク': 'scooter', '鉢植え': 'potted plant', '黒板': 'chalkboard',
    'AIが写真を見ています': 'AI is looking at the photo', '覚えたいことばをタップ': 'Tap a word to learn',
    '写真をスキャンしています': 'Scanning the photo', '名前を調べています': 'Looking up the names',
    '台湾でいちばん一般的な言い方': 'The most common way to say it in Taiwan',
    '珍珠奶茶の略。会話や注文でよく使う': 'Short for 珍珠奶茶. Used when chatting and ordering',
    '大粒タピオカのミルクティー': 'milk tea with large pearls',
    '粒の大きいタピオカのもの。店のメニューで見かける': 'With large pearls. Seen on shop menus',
    'ふだんの言い方': 'Everyday', '砕けた言い方': 'Casual', 'くわしい名前': 'Specific / technical name', '固有名詞': 'Proper noun',
    '覚える言い方を選ぶ': 'Choose the way to say it', '写っている物：タピオカミルクティー': 'In the photo: bubble tea',
    'この語で図鑑に入れる': 'Add this word to your collection', 'ほかの言い方': 'Other ways to say it',
    '飲み物': 'Drinks', '料理・屋台': 'Dishes & Street Food', '果物・野菜': 'Fruit & Vegetables', 'お菓子・パン': 'Sweets & Bread',
    '食器・台所': 'Tableware & Kitchen', '家具・インテリア': 'Furniture & Interior', '家電': 'Appliances',
    '枚・影 ': ' cards · shadows ', '飲み物の基本5語': 'Drinks · the basic 5', 'あと1語でコンプリート': '1 more to complete the set',
    '新しいことばをキャッチ！': 'New word caught!', 'No.001 · 飲み物': 'No.001 · Drinks',
    '選ぶと、そのことばで図鑑に入ります': 'The one you choose goes into your collection',
    '珍珠奶茶を1杯、甘さ半分・氷少なめで。': 'One bubble tea, half sugar, less ice.',
    'この店の珍珠奶茶はおいしい。': "This shop's bubble tea is great.",
    '珍奶を1杯、甘さ半分・氷少なめで。': 'One bubble tea, half sugar, less ice.',
    'この店の珍奶はおいしい。': "This shop's bubble tea is great.",
    '注文では「珍奶」だけで通じる。': 'When ordering, “珍奶” is enough.',
    '甘さは 全糖・半糖・微糖・無糖、': 'Sweetness: 全糖・半糖・微糖・無糖,',
    '氷は 正常冰・少冰・去冰 で伝える。': 'ice: 正常冰・少冰・去冰.',
    '1980年代に台湾で生まれた飲み物。': 'A drink born in Taiwan in the 1980s.',
    '台中と台南の店が元祖を名乗っている。': 'Shops in Taichung and Tainan both claim it.',
    '例文': 'Example', '使い方のコツ': 'Tips', '豆知識': 'Trivia', '似た言い方': 'Similar ways to say it', '大粒タピオカ': 'large pearls',
    '書き終わりました': 'Done', 'AIが例文と解説を書いています': 'AI is writing the examples and notes',
  };
  const T = s => {
    if (typeof s !== 'string') return s;
    if (s in EN) return EN[s];
    let m = s.match(/^ほか(\d+)$/); if (m) return '+' + m[1];
    m = s.match(/^(\d+)つ見つけました・名前を調べています$/); if (m) return `Found ${m[1]} · Looking up the names`;
    return s;
  };
  const P = CanvasRenderingContext2D.prototype, fill = P.fillText, meas = P.measureText, stroke = P.strokeText;
  P.fillText = function (s, ...a) { return fill.call(this, T(s), ...a); };
  P.strokeText = function (s, ...a) { return stroke.call(this, T(s), ...a); };
  P.measureText = function (s) { return meas.call(this, T(s)); };
  // wrapJP breaks by characters; English breaks between words (the measuring and drawing above translate the lines).
  if (typeof wrapJP === 'function') {
    window.wrapJP = function (s, w, size, maxW, f = FONT_JP) {
      const words = T(s).split(' '), out = []; let line = '';
      for (const wd of words) { const t = line ? line + ' ' + wd : wd; if (measure(t, w, size, f) > maxW && line) { out.push(line); line = wd; } else line = t; }
      if (line) out.push(line); return out;
    };
  }
})();
