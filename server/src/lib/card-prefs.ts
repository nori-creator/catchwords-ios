import { SECTION_IDS, type SectionId } from "./card-sections";

/**
 * 単語の詳細に**どの節を、どの順で**出すか（端末ごとの好み）。
 *
 * ## 既定は8項目だけ（オーナー指示 2026-09-23）
 * > 取った場所と一言メモ / 意味と発音 / 頻度と使う場面 / 例文 / チャンク /
 * > 量詞 / 類義語・反義語・関連語 / 実際の使われ方
 * > 「デフォルトで表示するのは8個の項目にして。あとはユーザーが指定したら
 * >  表示する。その分単語の詳細を早く表示させたい。」
 *
 * 「取った場所と一言メモ」は札の上の段（`StickerSheet`）の持ち物で、節では
 * ない。「意味と発音」は見出しの行（発音）と `meaning`。残りの6つが節。
 * それ以外の節は**既定で隠す**。隠した節は裏でも作らない（`missing` は
 * 見えている節だけを数える）ので、その分だけ詳細が早くそろう。
 *
 * ## 以前から使っている人
 * 前の版（v4）は「隠す物なし」が既定だった。**自分で1つも隠していない人**
 * は既定のままと見なして、新しい既定を当てる。1つでも隠していた人は、
 * その人が選んだ形をそのまま引き継ぐ。並びはどちらも引き継ぐ。
 */
export const DEFAULT_VISIBLE: readonly SectionId[] = [
  "meaning",
  "example",
  "usage_chunks",
  "measure_words",
  "related_words",
  "real_usage",
];

export type CardPrefs = { order: SectionId[]; hidden: SectionId[] };

/**
 * v6（2026-09-23）: **既定で見せる項目を一覧のいちばん上へ**（オーナー指示
 * 「デフォルトの5つは一番上に並べて」）。v5 以前の並びは、既定の項目を上へ
 * 寄せてから引き継ぐ（それぞれの中の順は崩さない）。隠す／見せるはそのまま。
 */
export const CARD_PREF_KEY = "wordcard-prefs-v6";
const V5_KEY = "wordcard-prefs-v5";
const LEGACY_KEY = "wordcard-prefs-v4";
export const CARD_PREF_EVENT = "wordcard-prefs-changed";

export function defaultHidden(all: readonly SectionId[]): SectionId[] {
  return all.filter((id) => !DEFAULT_VISIBLE.includes(id));
}

/** 既定で見せる項目を先に（それぞれの中の順は渡された順のまま）。 */
export function defaultsFirst(order: readonly SectionId[]): SectionId[] {
  return [
    ...order.filter((id) => DEFAULT_VISIBLE.includes(id)),
    ...order.filter((id) => !DEFAULT_VISIBLE.includes(id)),
  ];
}

/**
 * 保存された好みを読む。`all` は並べ替えの一覧に出る節の全部
 * （知らない名前は落とし、足りない名前は後ろへ足す）。
 */
export function readCardPrefs(
  all: readonly SectionId[],
  storage: Pick<Storage, "getItem"> | null,
): CardPrefs {
  const fallback = { order: defaultsFirst(all), hidden: defaultHidden(all) };
  if (!storage) return fallback;
  const valid = (id: SectionId) => all.includes(id);
  const tidy = (p: Partial<CardPrefs>, hidden: SectionId[]): CardPrefs => {
    const order = (p.order ?? []).filter(valid);
    return {
      order: [...order, ...all.filter((id) => !order.includes(id))],
      hidden: hidden.filter(valid),
    };
  };
  try {
    const raw = storage.getItem(CARD_PREF_KEY);
    if (raw) {
      const p = JSON.parse(raw) as Partial<CardPrefs>;
      return tidy(p, p.hidden ?? []);
    }
    const v5 = storage.getItem(V5_KEY);
    if (v5) {
      const p = JSON.parse(v5) as Partial<CardPrefs>;
      const t = tidy(p, p.hidden ?? []);
      return { ...t, order: defaultsFirst(t.order) };
    }
    const legacy = storage.getItem(LEGACY_KEY);
    if (legacy) {
      const p = JSON.parse(legacy) as Partial<CardPrefs>;
      const chose = (p.hidden ?? []).length > 0;
      const t = tidy(p, chose ? (p.hidden ?? []) : defaultHidden(all));
      return { ...t, order: defaultsFirst(t.order) };
    }
  } catch {
    /* 壊れた値は既定へ */
  }
  return fallback;
}

/**
 * いま見えている節（並び順）。**生成を頼むときに渡す** — 見えない節の中身を
 * 書かせない分、返事が短く、早く届く。
 */
export function visibleSections(prefs: CardPrefs): SectionId[] {
  return prefs.order.filter((id) => !prefs.hidden.includes(id));
}

/** 画面の外（生成を頼む所）から、いまの好みで見えている節を読む。 */
export function visibleSectionsNow(all: readonly SectionId[]): SectionId[] {
  const storage = typeof window === "undefined" ? null : safeStorage();
  return visibleSections(readCardPrefs(all, storage));
}

function safeStorage(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

/**
 * カードの生成を頼む所が渡す「いま見えている節」（`generateCard` の `sections`）。
 * 並びは要らないので、節の全部の一覧から読む。
 */
export function cardSectionsNow(): SectionId[] {
  return visibleSectionsNow(SECTION_IDS);
}
