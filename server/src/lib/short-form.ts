import { normalizeTargetLanguage } from "./target-lang";

/**
 * **見出し語の短い形**（オーナー 2026-11-21「1.2 それでいい」）。
 *
 * 台湾の人（オーナーの彼女）に、雨傘 の使い方の型「帶雨傘・撐雨傘・收雨傘」は文法は合っていてもあまり見かけない、
 * 「帶傘・撐傘・收傘」と言う方が自然と言われた。見出し語より短い形がネイティブにとって最も自然な型では、その短い形を
 * 使ってよい。ただし**見出し語の字の連続した一部**（雨傘 → 傘）の時だけ — 意味の変わる略し方（腳踏車 → 車 は自動車も
 * 指す、手機 → 手）は AI への指示で止め、ここでは形だけを確かめる。
 *
 * 外の世界に触れない（純粋）。試験は `short-form.test.ts`。
 */

type PartLike = { text?: string | null };
type ChunkWithShort = { parts?: ReadonlyArray<PartLike | null | undefined> | null; short_form?: string | null };

const HAN_ONLY = /^\p{Script=Han}+$/u;

/**
 * 短い形として受け取ってよいか。台湾華語だけ。見出し語と違い、見出し語の字の連続した一部で、漢字だけ。
 * 受け取れる時はその字（前後の空白を除いた物）、受け取れない時は null。
 */
export function validShortForm(
  headword: string | null | undefined,
  short: string | null | undefined,
  language?: string | null,
): string | null {
  if (!normalizeTargetLanguage(language).startsWith("zh")) return null;
  const head = (headword ?? "").trim();
  const s = (short ?? "").trim();
  if (!head || !s || s === head) return null;
  if (!HAN_ONLY.test(s) || !HAN_ONLY.test(head)) return null;
  if ([...s].length >= [...head].length) return null;
  return head.includes(s) ? s : null;
}

/**
 * その型の中で見出し語の役をしている字: 見出し語そのものが1つのパーツなら見出し語、そうでなく、受け取れる短い形が
 * 1つのパーツなら短い形。どちらも無ければ null（見出し語の入っていない型）。
 */
export function chunkHeadForm(
  chunk: ChunkWithShort | null | undefined,
  headword: string,
  language?: string | null,
): string | null {
  const head = (headword ?? "").trim();
  const texts = (chunk?.parts ?? []).map((p) => (p?.text ?? "").trim());
  if (head && texts.includes(head)) return head;
  const short = validShortForm(head, chunk?.short_form, language);
  return short && texts.includes(short) ? short : null;
}

/** その型が短い形を使っているか（`chunkHeadForm` が見出し語と違う字を返す）。 */
export function usesShortForm(
  chunk: ChunkWithShort | null | undefined,
  headword: string,
  language?: string | null,
): boolean {
  const form = chunkHeadForm(chunk, headword, language);
  return form !== null && form !== (headword ?? "").trim();
}

/**
 * **AI への指示: 短い形を使ってよい時**（使い方の型を作る指示の両方 — カードの生成と ↻ — が通す）。台湾華語だけ。
 * 形（見出し語の字の連続した一部）はサーバが確かめるが、**意味が変わらないか**は字の形からは分からないので、
 * ここで禁止の例を挙げ、使う前に自分で確かめさせる。
 */
export function chunkShortFormRule(headword: string, language?: string | null): string {
  if (!normalizeTargetLanguage(language).startsWith("zh")) return "";
  const head = (headword ?? "").trim();
  if ([...head].length < 2) return "";
  return [
    `**見出し語の短い形（「${head}」を1つのパーツとして入れる決まりの、ただ1つの例外）**: 台湾のネイティブがその型では` +
      `「${head}」より短い形で言うのが**最も自然な**時だけ（例: 雨傘 → 帶傘・撐傘・收傘。帶雨傘・撐雨傘 は文法は合っていても会話ではあまり言わない）、` +
      `その短い形を1つのパーツにし、その型に "short_form": "傘" のように短い形を書く。`,
    `- 短い形は「${head}」の字の**連続した一部**に限る（雨傘 → 傘）。それ以外の字を足した形・言い換えは使わない。`,
    `- **意味が変わる・別の物を指す略し方は禁止**（✗ 腳踏車 → 車 — 自動車も指す / ✗ 手機 → 手 / ✗ 冰淇淋 → 冰 — 氷 / ✗ 雨傘 → 雨）。`,
    `- 使う前に自分で確かめる: 短い形だけを聞いた台湾のネイティブが、その型の中で「${head}」と同じ物を思い浮かべるか。` +
      `少しでも別の物に聞こえるなら、見出し語のままの型にする（short_form を付けない）。`,
    `- 見出し語のままでも同じくらい自然なら見出し語を使う。迷ったら short_form を付けない。`,
  ].join("\n");
}
