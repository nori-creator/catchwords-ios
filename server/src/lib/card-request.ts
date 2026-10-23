import { NOT_GENERATED_SECTIONS, type SectionId } from "./card-sections";

/**
 * カードを作るときに**どの節の中身まで書かせるか**。
 *
 * （オーナー指示 2026-09-23「デフォルトで表示するのは8個の項目にして。
 *  あとはユーザーが指定したら表示する。その分単語の詳細を早く表示させたい」）
 *
 * `generateCard` は1回の呼び出しで全部の欄を書かせていた。語源・覚え方・
 * 追加の例文・発音のコツは、既定では画面に出ない。**出さない欄を書かせる
 * 分だけ返事が長くなり、待ち時間が延びる。** 画面が「いま見えている節」を
 * 渡し、見えない節の欄は頼まない。
 *
 * 語は利用者の間で共有される（`words` の行）。頼まなかった欄は
 * 空のまま残るが、その節を表示にした人が開けば、節ごとの作り直し
 * （`regenerateCardSection` の `only_if_empty`）が埋める。
 *
 * **ここに無い節は常に頼む**（意味・例文・使う場面・頻度など）。ほかの
 * 機能（棚・場面・級）もそれらを使うので、見えていなくても省かない。
 */
export const OPTIONAL_EXTRA_KEYS: Partial<Record<SectionId, readonly string[]>> = {
  usage_chunks: ["usage_chunks"],
  examples_extra: ["examples_extra"],
  related_words: ["related_words"],
  measure_words: ["measure_words"],
  pronunciation_tips: ["pronunciation_tips"],
  taiwan_note: ["taiwan_note"],
  culture_note: ["culture_note"],
  etymology: ["etymology", "etymology_relatives", "radicals", "etymology_diagram"],
  mnemonic: ["mnemonic"],
  // 日本語のカードの節(2026-10-01)。既定では見えない物もあるので、見えない節は頼まない。
  kanji_breakdown: ["kanji_breakdown"],
  pitch_accent: ["pitch_accent"],
  conjugation: ["conjugation"],
  politeness: ["politeness"],
  counters: ["counters"],
  word_origin: ["word_origin"],
  japan_note: ["japan_note"],
};

/** その節の欄を書かせるか。`sections` が無ければ（古い呼び出し）全部書かせる。 */
export function wantsSection(
  sections: readonly string[] | null | undefined,
  id: SectionId,
): boolean {
  if (!sections) return true;
  if (!(id in OPTIONAL_EXTRA_KEYS)) return true;
  return sections.includes(id);
}

/**
 * 頼まなかった節の欄を**返事から落とす**。
 *
 * 頼まなくても、モデルが空の欄（`"etymology": ""`）を付けて返すことがある。
 * 保存は既存の中身に重ねて書く（`updateWordExtras`）ので、空の欄が残ると
 * **ほかの人のために作ってあった語源を空で上書きする**。
 */
export function stripUnrequested<T extends Record<string, unknown>>(
  extras: T,
  sections: readonly string[] | null | undefined,
): T {
  if (!sections) return extras;
  const out: Record<string, unknown> = { ...extras };
  for (const [id, keys] of Object.entries(OPTIONAL_EXTRA_KEYS)) {
    if (sections.includes(id)) continue;
    for (const k of keys ?? []) delete out[k];
  }
  return out as T;
}

/**
 * **サーバがもう作らない節の欄を返事から落とす**（発音のコツ・覚え方、2026-10-15 `NOT_GENERATED_SECTIONS`）。
 * 指示から外してもモデルが書いてくることがあるので、返す前に鍵ごと消す（空で上書きもしない —
 * 保存済みのカードの中身はそのまま）。
 */
export function stripNotGenerated<T extends Record<string, unknown>>(extras: T): T {
  const out: Record<string, unknown> = { ...extras };
  for (const id of NOT_GENERATED_SECTIONS) {
    for (const k of OPTIONAL_EXTRA_KEYS[id] ?? []) delete out[k];
  }
  return out as T;
}
