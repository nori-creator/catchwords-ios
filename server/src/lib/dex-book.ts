/**
 * **図鑑の升目の組み立て**（iOS 版 `Models/DexBook.swift` の写し）。
 *
 * - 1つの言葉は1マス（`groupDexWords`）。同じ見出し語を文字で2回検索すると札が2枚できることが
 *   あり、図鑑に「貓」が2つ並んでいた（オーナー報告 2026-10-08「文字検索したら同じ単語でも
 *   同じものとしてカウントされてない」）。札の数ではなく**言葉の数**で並べ、数える。
 * - 番号（`assignDexNumbers`）: 基本の100は No.001〜100。それ以外の言葉は、捕まえた順に
 *   No.101, 102, … を**その人・その学習言語ごとに端末に覚えて**振る（一度付いた番号は動かない）。
 * - カテゴリーの節（`dexSections`）: 捕まえた言葉（番号順）、続けてまだ捕まえていない影を5つ。
 */
import {
  DEX_CATEGORIES,
  DEX_OTHER_KEY,
  DEX_SHADOW_COUNT,
  dexCatalogCategory,
  dexCategoryForKey,
  dexCategoryKey,
  dexItemFor,
  normDexHeadword,
  type DexItem,
} from "./dex-catalog";
import { isBuiltinCategory } from "./user-category";
import { wordCategoryKey } from "./category";

/** 升目に並べる札に要る物だけ（`StickerWithWord` の一部）。 */
export type DexGroupable = {
  id: string;
  taken_at: string;
  created_at?: string;
  encounter_count?: number | null;
  shelf_key?: string | null;
  word: { headword: string; language?: string | null; category_key?: string | null };
};

/** 1つの言葉のマス。`rep` が表に出る札（いちばん新しい札、着地の札があればそれ）。 */
export type DexWordGroup<T extends DexGroupable> = {
  key: string;
  rep: T;
  /** 同じ言葉の札。古い順。 */
  members: T[];
  /** 出会った回数: 札の枚数 + 再会の回数（写真なしの再会も1回）。 */
  captures: number;
};

const time = (s: DexGroupable) => Date.parse(s.taken_at || s.created_at || "") || 0;

/** 古い順（同じ時刻なら id の順）。iOS の番号を振る順と同じ。 */
function byOldest(a: DexGroupable, b: DexGroupable) {
  return time(a) - time(b) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}

/** 言葉を見分ける鍵。見出し語が空なら札ごとに別のマス。 */
export function dexWordKey(s: DexGroupable, lang: string | null | undefined): string {
  const h = normDexHeadword(s.word.headword, s.word.language ?? lang);
  return h ? h : `id:${s.id}`;
}

/**
 * 札を言葉ごとにまとめる。並びは**入ってきた順の、その言葉の最初の札の位置**（図鑑の今の
 * 並びを崩さない）。表に出す札は、`preferId`（いま着地する札）があればそれ、無ければ
 * いちばん新しい札 — 着地の目印 `dex-cell-<id>` がいつもいま捕まえた札の id になる。
 */
export function groupDexWords<T extends DexGroupable>(
  stickers: readonly T[],
  lang: string | null | undefined,
  preferId?: string | null,
): DexWordGroup<T>[] {
  const order: string[] = [];
  const byKey = new Map<string, T[]>();
  for (const s of stickers) {
    const k = dexWordKey(s, lang);
    const list = byKey.get(k);
    if (list) list.push(s);
    else {
      byKey.set(k, [s]);
      order.push(k);
    }
  }
  return order.map((key) => {
    const members = [...byKey.get(key)!].sort(byOldest);
    const preferred = preferId ? members.find((m) => m.id === preferId) : undefined;
    const rep = preferred ?? members[members.length - 1];
    const captures = members.reduce((n, m) => n + 1 + Math.max(0, m.encounter_count ?? 0), 0);
    return { key, rep, members, captures };
  });
}

/** 言葉の数（同じ言葉の札は1つと数える）。 */
export function countDexWords(stickers: readonly DexGroupable[], lang?: string | null): number {
  return new Set(stickers.map((s) => dexWordKey(s, lang))).size;
}

/** 番号を覚えておく所（Web は localStorage。試験では手元の入れ物）。 */
export type DexNumberStore = {
  load(): Record<string, number>;
  save(numbers: Record<string, number>): void;
};

/** 端末に覚える鍵（iOS `DexNumbering.storeKey` と同じ形）。 */
export function dexNumberStoreKey(uid: string | null | undefined, lang: string): string {
  return `dex.numbers.${uid || "guest"}.${lang}`;
}

/** localStorage の入れ物。読めない・書けない時（プライベートの窓など）は覚えずに振る。 */
export function localDexNumberStore(uid: string | null | undefined, lang: string): DexNumberStore {
  const key = dexNumberStoreKey(uid, lang);
  return {
    load() {
      try {
        const raw = typeof localStorage === "undefined" ? null : localStorage.getItem(key);
        const v = raw ? (JSON.parse(raw) as unknown) : null;
        if (!v || typeof v !== "object" || Array.isArray(v)) return {};
        const out: Record<string, number> = {};
        for (const [k, n] of Object.entries(v as Record<string, unknown>))
          if (typeof n === "number" && Number.isFinite(n)) out[k] = n;
        return out;
      } catch {
        return {};
      }
    },
    save(numbers) {
      try {
        localStorage.setItem(key, JSON.stringify(numbers));
      } catch {
        // 覚えられなくても番号は出す（次に開いた時に同じ順で振り直す）。
      }
    },
  };
}

/**
 * 札の id → 番号（iOS `DexNumbering.assign`）。古い札から順に、基本の100はその番号、
 * それ以外は覚えてある番号、無ければ次の番号（101 から）を振って覚える。
 */
export function assignDexNumbers(
  stickers: readonly DexGroupable[],
  lang: string | null | undefined,
  store: DexNumberStore,
  /**
   * 新しく振った番号を覚えるか。**札をまだ全部読んでいない間は false**（図鑑は最初の
   * ページだけ先に出し、残りを裏で読み足す）。途中で覚えると、まだ届いていない古い札より
   * 先に新しい札が 101 から番号を取り、捕まえた順の番号がずれたまま残る。
   * 覚えない間も番号は出す（読み終えた時に、捕まえた順で振り直して覚える）。
   */
  persist = true,
): Map<string, number> {
  const saved = store.load();
  let next = Math.max(100, ...Object.values(saved)) + 1;
  let changed = false;
  const out = new Map<string, number>();
  for (const s of [...stickers].sort(byOldest)) {
    const base = dexItemFor(s.word.headword, s.word.language ?? lang)?.baseNo;
    if (base != null) {
      out.set(s.id, base);
      continue;
    }
    const k = dexWordKey(s, lang);
    const n = saved[k];
    if (n != null) out.set(s.id, n);
    else {
      saved[k] = next;
      out.set(s.id, next);
      next += 1;
      changed = true;
    }
  }
  if (changed && persist) store.save(saved);
  return out;
}

/**
 * 番号の表示（iOS `"No.%03d"`）。番号がまだ無い物（基本の100の外の影 — 番号は捕まえた順に
 * 付く）は `No.???`。前は `No.---` で、オーナーから「作りかけに見える」（2026-10-08）。
 * 「まだ分からない番号」を、図鑑のなぞとしてはっきり見せる。
 */
export function formatDexNo(no: number | null | undefined): string {
  return no == null ? DEX_NO_UNKNOWN : `No.${String(no).padStart(3, "0")}`;
}

/** まだ番号の無い物の表示。 */
export const DEX_NO_UNKNOWN = "No.???";

/** 升目の1マス: 捕まえた言葉か、まだの影か。 */
export type DexSlot<T extends DexGroupable> =
  | { kind: "caught"; id: string; no: number | null; group: DexWordGroup<T> }
  | { kind: "shadow"; id: string; no: number | null; item: DexItem };

/** 1つのカテゴリーの節。 */
export type DexSection<T extends DexGroupable> = {
  /** 節の鍵（`data-dex-cat`）。図鑑の20は代表の分類の鍵、その人のカテゴリーはその鍵。 */
  key: string;
  /** 図鑑のカテゴリー（1〜20）。その人が作ったカテゴリーと「その他」の節は null。 */
  dexNo: number | null;
  slots: DexSlot<T>[];
  caughtCount: number;
};

/**
 * 入れ替わる写真のうち、**描く物**（図鑑の升目）。表の1枚と、次に浮かべる1枚だけ —
 * 何枚撮っていても、1マスに読み込む写真は最大2枚。動かさない時・画面の外は表の1枚だけ
 * （`withNext` が偽）。
 */
export function dexCycleFrames(
  count: number,
  shown: number,
  withNext: boolean,
): Array<{ k: number; role: "current" | "next" }> {
  if (count <= 0) return [];
  const current = ((shown % count) + count) % count;
  if (!withNext || count < 2) return [{ k: current, role: "current" }];
  return [
    { k: current, role: "current" },
    { k: (current + 1) % count, role: "next" },
  ];
}

/**
 * 広告を挟む数え方の、節ごとの大きさ。**捕まえた札のマスだけ**を数える。
 * 広告は捕まえた札の後ろにしか挟めない（影の後ろには出さない）。影まで数えると、
 * 広告の番号が影に当たって消えたり、何枚目の後に出すかの間隔がずれたりする。
 * 節の中は捕まえた札 → 影の順なので、0..caughtCount-1 がそのまま札の番号になる。
 */
export function dexAdGroupSizes(sections: ReadonlyArray<{ caughtCount: number }>): number[] {
  return sections.map((sec) => sec.caughtCount);
}

/**
 * 言葉の図鑑のカテゴリー。その人が移した先（`shelf_key`）があればそれが勝つ — 既定の鍵なら
 * その鍵のカテゴリー、その人のカテゴリーなら節そのもの（文字列で返す）。無ければ iOS と同じく
 * 表の物のカテゴリー（見出し語 → 言い方の揺れ）、表に無ければ語の分類から。
 *
 * **どれにも当たらない語（分類が other・知らない鍵）は「その他」の節（`DEX_OTHER_KEY`）**。
 * 前は 10（洗面・日用品）へ黙って寄せていて、札は「その他」なのに図鑑では蘑菇・小豬が
 * 日用品に並んでいた（オーナー報告 2026-10-09）。
 */
export function dexPlaceOf(
  s: DexGroupable,
  lang: string | null | undefined,
  userKeys: ReadonlySet<string>,
): number | string {
  const override = (s.shelf_key ?? "").trim();
  if (override) {
    if (isBuiltinCategory(override)) return dexCategoryForKey(override) ?? DEX_OTHER_KEY;
    if (userKeys.has(override)) return override;
  }
  const fromCatalog = dexCatalogCategory(s.word.headword, s.word.language ?? lang);
  if (fromCatalog != null) return fromCatalog;
  // 表に無い語は、見出し語で直した分類から（燒仙草が「〜草」で植物・花に入っていた）。
  return dexCategoryForKey(wordCategoryKey(s.word)) ?? DEX_OTHER_KEY;
}

/**
 * 図鑑の節（iOS `DexBook.sections`）。20 のカテゴリーをこの順に、続けてその人が作った
 * カテゴリー。`shadows` が false（絞り込み・検索の最中）なら影を出さず、空の節も出さない。
 */
export function dexSections<T extends DexGroupable>(
  stickers: readonly T[],
  opts: {
    lang: string | null | undefined;
    numbers: ReadonlyMap<string, number>;
    userKeys?: ReadonlySet<string>;
    shadows: boolean;
    preferId?: string | null;
    /** その人のカテゴリーの並び（無ければ出てきた順）。 */
    userOrder?: readonly string[];
  },
): DexSection<T>[] {
  const userKeys = opts.userKeys ?? new Set<string>();
  const groups = groupDexWords(stickers, opts.lang, opts.preferId);
  const byPlace = new Map<number | string, DexWordGroup<T>[]>();
  const caughtItems = new Set<string>();
  for (const g of groups) {
    const place = dexPlaceOf(g.rep, opts.lang, userKeys);
    const list = byPlace.get(place);
    if (list) list.push(g);
    else byPlace.set(place, [g]);
    const item = dexItemFor(g.rep.word.headword, g.rep.word.language ?? opts.lang);
    if (item) caughtItems.add(item.id);
  }
  const noOf = (g: DexWordGroup<T>) => opts.numbers.get(g.rep.id) ?? null;
  const caughtSlots = (list: DexWordGroup<T>[] | undefined): DexSlot<T>[] =>
    [...(list ?? [])]
      .sort((a, b) => {
        const na = noOf(a) ?? Number.MAX_SAFE_INTEGER;
        const nb = noOf(b) ?? Number.MAX_SAFE_INTEGER;
        return na - nb || time(a.rep) - time(b.rep);
      })
      .map((g) => ({ kind: "caught", id: g.rep.id, no: noOf(g), group: g }));

  const out: DexSection<T>[] = [];
  for (const c of DEX_CATEGORIES) {
    const caught = caughtSlots(byPlace.get(c.no));
    const shadows: DexSlot<T>[] = opts.shadows
      ? c.items
          .filter((it) => !caughtItems.has(it.id))
          .slice(0, DEX_SHADOW_COUNT)
          .map((it) => ({ kind: "shadow", id: `i:${it.id}`, no: it.baseNo, item: it }))
      : [];
    if (caught.length === 0 && shadows.length === 0) continue;
    if (!opts.shadows && caught.length === 0) continue;
    out.push({
      key: dexCategoryKey(c.no),
      dexNo: c.no,
      slots: [...caught, ...shadows],
      caughtCount: caught.length,
    });
  }
  const custom = [...byPlace.keys()].filter((k): k is string => typeof k === "string");
  const rank = (k: string) => {
    const i = opts.userOrder?.indexOf(k) ?? -1;
    return i < 0 ? Number.MAX_SAFE_INTEGER : i;
  };
  // 「その他」の節は、その人のカテゴリーよりも後ろ（いちばん最後）。
  custom.sort(
    (a, b) => Number(a === DEX_OTHER_KEY) - Number(b === DEX_OTHER_KEY) || rank(a) - rank(b),
  );
  for (const key of custom) {
    const caught = caughtSlots(byPlace.get(key));
    out.push({ key, dexNo: null, slots: caught, caughtCount: caught.length });
  }
  return out;
}
