/**
 * **アプリの中で AI を使う機能の一覧と、その切り替えの値の形**（オーナー決定 2026-10-09）。
 *
 * - 既定: スキャンは最新の Gemini Flash-Lite（`latest-flash-lite`）、ほかの機能は全部
 *   最新の Gemini Flash（`latest-flash`）。
 * - **全部の AI 機能**を、開発者の設定（Web・iOS の両方）から別の会社・モデルへ切り替えられる。
 *   保存先は `app_config.key='ai_models'` の `features[機能の id]` だけ（唯一の正）。
 *   値は `"auto"`（= 既定）か `"会社:モデル"`（例 `"anthropic:claude-sonnet-4-5"`）。
 *
 * ここは表と純粋な関数だけ（画面からも試験からも読める。鍵には触らない）。
 * 実際の振り分けは `ai-provider.server.ts` の `getAiFor`、管理の口は `admin-ai.server.ts`。
 */

/** モデルの段。スキャンだけ速い方（Flash-Lite）、ほかは丁寧な方（Flash）。 */
export type AiTier = "flash" | "flash-lite";

/** モデルを割り当てられる機能の単位。 */
export const AI_FEATURE_IDS = [
  "scan",
  "card",
  "review",
  "journal",
  "audit",
  "reading_check",
  "lexicon",
] as const;
export type AiFeature = (typeof AI_FEATURE_IDS)[number];

export type AiFeatureInfo = {
  id: AiFeature;
  tier: AiTier;
  /** 写真を読む機能（画像を読めるモデルしか選べない）。 */
  needsVision: boolean;
  /** 画面の名前（`i18n.tsx` のキー）。説明は `labelKey` の末尾を `Desc` にしたキー。 */
  labelKey: string;
  descKey: string;
};

/**
 * 機能の表。**新しく AI を呼ぶ所を書いたら、どれかの機能に入れる**（`getAiFor(id, 用途)`。
 * 用途は `ai-call-log.ts` の `AI_TASKS` — 開発者の画面の速さと正確さの表の1行になる）。
 *
 * - scan: 写真の物・文字の検出、単語の候補、チュートリアルの写真、単語帳の頁の読み取り
 * - card: 単語カード・フレーズカードの生成、項目の作り直し、読む人の言語での意味
 * - review: 復習のスピーキング添削・ヒント
 * - journal: 日記の添削・書き出しの質問（iOS の自由文の窓口も）
 * - audit: 自己改善の点検（報告された項目の特定・作り直しの判定）
 * - reading_check: 読み・品詞の突き合わせの2人目（1人目は audit。別の AI にすると独立に確かめられる）
 * - lexicon: 辞書の点検・利用者の報告の検証・生きた例文の生成（毎日の裏方）
 */
export const AI_FEATURES: readonly AiFeatureInfo[] = AI_FEATURE_IDS.map((id) => ({
  id,
  tier: id === "scan" ? "flash-lite" : "flash",
  needsVision: id === "scan",
  labelKey: `aiSet.feature.${id}`,
  descKey: `aiSet.featureDesc.${id}`,
}));

export function isAiFeature(id: unknown): id is AiFeature {
  return typeof id === "string" && (AI_FEATURE_IDS as readonly string[]).includes(id);
}

export function featureTier(feature: AiFeature): AiTier {
  return feature === "scan" ? "flash-lite" : "flash";
}

/** その段の「いつも最新」の合言葉（Google の時だけ版付きの ID に置き換わる）。 */
export function tierKeyword(tier: AiTier): "latest-flash-lite" | "latest-flash" {
  return tier === "flash-lite" ? "latest-flash-lite" : "latest-flash";
}

export const AUTO = "auto";

/** モデル名・会社名に使ってよい字（DB にも入るので絞る）。 */
const SAFE_PROVIDER = /^[a-z][a-z0-9-]{0,30}$/;
const SAFE_MODEL = /^[A-Za-z0-9._/:@+-]{1,160}$/;

export type FeatureSpec = { provider: string; model: string };

/**
 * 保存されている値を読む。`"auto"`・空・未設定は null（= 既定）。
 * `"会社:モデル"` は会社とモデルへ。**古い形の「モデル名だけ」**は会社なし（`provider: ""`）。
 */
export function parseFeatureValue(value: unknown): FeatureSpec | null {
  if (typeof value !== "string") return null;
  const v = value.trim();
  if (!v || v.toLowerCase() === AUTO) return null;
  const i = v.indexOf(":");
  if (i < 0) return { provider: "", model: v };
  const provider = v.slice(0, i).trim();
  const model = v.slice(i + 1).trim();
  if (!model) return null;
  return { provider, model };
}

/**
 * 管理の口が受け取る値の形を確かめる（鍵の有無は別に見る）。
 * 返すのは保存する正規の形（`"auto"` か `"会社:モデル"`）。形が違えば投げる。
 */
export function normalizeFeatureValue(value: unknown): string {
  if (typeof value !== "string") throw new Error('value は文字列です（"auto" か "会社:モデル"）');
  const v = value.trim();
  if (!v || v.toLowerCase() === AUTO) return AUTO;
  const spec = parseFeatureValue(v);
  if (!spec || !spec.provider)
    throw new Error('value は "auto" か "会社:モデル"（例 openai:gpt-5-mini）です');
  if (!SAFE_PROVIDER.test(spec.provider)) throw new Error(`会社の名前が不正です: ${spec.provider}`);
  if (!SAFE_MODEL.test(spec.model)) throw new Error(`モデルの名前が不正です: ${spec.model}`);
  return `${spec.provider}:${spec.model}`;
}
