/**
 * **AI の会社ごとに、いま使えるモデルの一覧**（オーナー指示 2026-09-28「使う AI の切り替え
 * 画面、複雑すぎる。直感的に簡単に AI を変更できるようにして。openrouter の使い方分からないし、
 * 今はそれぞれの AI を直接 api を取得し、lovable に貼り付けてる」）。
 *
 * モデルの名前を手で打つと、古い名前・綴りの間違いで機能が止まる（2026-07-27 の障害）。
 * そこで、**鍵が入っている会社にだけ**「いま使えるモデル」を聞き、その中から選ばせる。
 * ここは通信しない計算だけ（一覧の形の読み取り・並べ替え・速い/賢いの見分け）。
 */

export type ProviderModel = {
  id: string;
  /** 画面に出す名前（会社が教えてくれれば、それ）。 */
  label: string;
  /** 速い・安い物か、賢い物か（名前から見分ける目安）。 */
  kind: "fast" | "smart";
};

/** 会話・文章に使えないモデル（埋め込み・音声・画像・検閲 など）を外すための印。 */
const NOT_CHAT =
  /(embed|embedding|tts|whisper|transcribe|audio|realtime|dall-?e|image|imagen|veo|moderation|search|similarity|edit|babbage|davinci|aqa|learnlm|computer-use|live)/i;

/**
 * 名前から「速い・安い」物を見分ける（各社の命名の慣わし: flash / mini / haiku / lite / nano）。
 * **区切りの付いた語だけ**を見る — 「gemini」の中の「mini」で速い物と取り違えないように。
 */
const FAST = /(^|[-_/.:])(flash|mini|haiku|lite|nano|small|turbo|instant)([-_/.:]|$)|chat$/i;

/**
 * **画像を読めるモデルか**（スキャンは写真を読む。読めない物を選ぶとスキャンが丸ごと止まる —
 * 2026-09-22 の約束「スキャンは画像を読めるモデルだけ」）。各社の公開情報の系統で見分ける。
 * 分からない物は「読めない」側に倒す（選べないだけで、壊れはしない）。
 */
export function supportsVision(provider: string, id: string): boolean {
  const m = id.toLowerCase();
  switch (provider) {
    case "google":
      return m.includes("gemini");
    case "openai":
      return /(gpt-4o|gpt-4\.1|gpt-5|^o3|^o4)/.test(m);
    case "anthropic":
      return m.includes("claude");
    case "kimi":
      return m.includes("vision");
    case "openrouter":
      return /(gemini|gpt-4o|gpt-4\.1|gpt-5|claude|vision|-vl)/.test(m);
    default:
      return false;
  }
}

/**
 * 各社の `GET /models` の返事を読む。OpenAI 形式（`{data:[{id}]}`）と、Anthropic 形式
 * （`{data:[{id, display_name}]}`）の両方。Google の OpenAI 互換口は `models/…` と頭に付くので外す。
 */
export function parseModelList(json: unknown): ProviderModel[] {
  const data = (json as { data?: unknown })?.data;
  if (!Array.isArray(data)) return [];
  const out: ProviderModel[] = [];
  const seen = new Set<string>();
  for (const row of data) {
    const r = row as { id?: unknown; display_name?: unknown };
    if (typeof r.id !== "string") continue;
    const id = r.id.replace(/^models\//, "");
    if (!id || seen.has(id) || NOT_CHAT.test(id)) continue;
    seen.add(id);
    out.push({
      id,
      label: typeof r.display_name === "string" && r.display_name ? r.display_name : id,
      kind: FAST.test(id) ? "fast" : "smart",
    });
  }
  // 新しそうな物を上に（名前の数字が大きい順）→ 同じなら名前順。
  const ver = (id: string) => {
    const m = id.match(/(\d+(?:[.-]\d+)?)/);
    return m ? Number(m[1].replace("-", ".")) : 0;
  };
  return out.sort((a, b) => ver(b.id) - ver(a.id) || a.id.localeCompare(b.id));
}

/** 機能ごとに、どちらの種類をおすすめするか（スキャンは速さ、ほかは中身の質）。 */
export function recommendedKind(feature: string): "fast" | "smart" {
  return feature === "scan" || feature === "review" ? "fast" : "smart";
}

/** 保存の形 `会社:モデル` を分ける（モデル名だけの古い形は会社なし）。 */
export function splitSpec(spec: string | undefined | null): { provider: string; model: string } {
  if (!spec) return { provider: "", model: "" };
  const i = spec.indexOf(":");
  if (i < 0) return { provider: "", model: spec };
  return { provider: spec.slice(0, i), model: spec.slice(i + 1) };
}
