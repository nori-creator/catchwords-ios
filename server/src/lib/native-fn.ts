/**
 * **iOS 版から Web 版のサーバ関数をそのまま呼ぶための一覧**（`/api/native-fn`）。
 *
 * iOS 版が候補の出し方・カードの作り方・保存・発音・復習の採点を Swift で
 * 書き直すと、Lovable で決めた細かい約束（辞書での照合、レベル、台湾での
 * 使われ方、1日の上限、保存の手順…）が必ずずれていく。そこで iOS 版は
 * **Web 版と同じ関数を同じ入力で呼ぶ**。Web 版で直せば iOS 版も直る。
 *
 * - ここに載っている関数だけを呼べる。
 * - 本人確認は各関数の `requireSupabaseAuth` がそのまま行う（iOS は
 *   `Authorization: Bearer <Supabase のアクセストークン>` を付けて呼ぶ）。
 * - **管理者向けは `admin` で始まる名前の物だけ**（開発者の「AI の設定」。オーナー決定
 *   2026-10-09「全部の AI を Web と iOS の開発者設定から切り替えられるように」）。
 *   どれも関数の中で `has_role(admin)` を確かめ、管理者でなければ読み取りは
 *   `{ isAdmin: false }`、書き込みは 403。鍵の値は返さない。約束は `docs/admin-ai-api.md`。
 * - 開発者の「利用者と分析」（`/admin/users`・`/admin/metrics`・`/admin/beta` と同じ数字。
 *   オーナー決定 2026-10-11「開発者の私だけ設定の開発者設定から web 版と同じように、
 *   利用者やアプリの詳しい情報、分析が見えるように」）も `admin` で始まる別名で載せる。
 *   どれも読むだけで、管理者でなければ 403（`Forbidden: admin role required`）。
 *   メールアドレス・正確な位置・写真・日記の本文は、Web の管理画面と同じく返さない。
 * - ここに載せる関数は、Web の画面からもすでに同じ本人確認で呼べる物だけ。
 *   新しく外へ開く入口は増えない。
 */

type ServerFn = (opts: { data?: unknown }) => Promise<unknown>;
type Loader = () => Promise<ServerFn>;

const ai = () => import("./ai.functions");
const scan = () => import("./scan.functions");
const stickers = () => import("./stickers.functions");
const encounters = () => import("./encounters.functions");
const tts = () => import("./tts.functions");
const reviews = () => import("./reviews.functions");
const profile = () => import("./profile.functions");
const explanation = () => import("./word-explanation.functions");
const categories = () => import("./categories.functions");
const album = () => import("./album-hidden.functions");
const journal = () => import("./journal.functions");
const stats = () => import("./stats.functions");
const jev = () => import("./jev.functions");
const wordbook = () => import("./wordbook.functions");
const images = () => import("./images.functions");
const consent = () => import("./ai-consent.functions");
const appleToken = () => import("./apple-token.functions");
const adminAi = () => import("./admin-ai.functions");
const candidatePick = () => import("./candidate-pick.functions");
const adminUsers = () => import("./admin-users.functions");
const metrics = () => import("./metrics.functions");
const betaMetrics = () => import("./beta-metrics.functions");
const reports = () => import("./reports.functions");
const sentenceReadings = () => import("./sentence-readings.functions");
const standing = () => import("./standing.functions");

function from<M>(mod: () => Promise<M>, name: keyof M & string): Loader {
  return async () => (await mod())[name] as unknown as ServerFn;
}

export const NATIVE_FNS: Record<string, Loader> = {
  // 候補・カード
  suggestWords: from(ai, "suggestWords"),
  // カメラを開いた時の下準備（AI は呼ばない・枠は数えない）
  warmUpCapture: from(ai, "warmUpCapture"),
  suggestWordCandidates: from(ai, "suggestWordCandidates"),
  // 候補の何番目を選んだか（モデルごとの候補の当たり。`candidate-pick.functions.ts`）
  logCandidatePick: from(candidatePick, "logCandidatePick"),
  generateCard: from(ai, "generateCard"),
  generatePhraseCard: from(ai, "generatePhraseCard"),
  // 例文の字ごとの読み（AI は呼ばない。`sentence-readings.functions.ts`）
  readSentences: from(sentenceReadings, "readSentences"),
  regenerateCardSection: from(ai, "regenerateCardSection"),
  reportAndFixSection: from(ai, "reportAndFixSection"),
  // スキャン
  detectScan: from(scan, "detectScan"),
  detectParts: from(scan, "detectParts"),
  lookupHeadwords: from(scan, "lookupHeadwords"),
  getScanContext: from(scan, "getScanContext"),
  markScanTap: from(scan, "markScanTap"),
  markScanCaught: from(scan, "markScanCaught"),
  rankScanCandidates: from(jev, "rankScanCandidates"),
  extractWordbook: from(wordbook, "extractWordbook"),
  // 保存・図鑑
  saveSticker: from(stickers, "saveSticker"),
  getSticker: from(stickers, "getSticker"),
  listMyStickers: from(stickers, "listMyStickers"),
  listMyShelves: from(stickers, "listMyShelves"),
  deleteSticker: from(stickers, "deleteSticker"),
  attachStickerCutout: from(stickers, "attachStickerCutout"),
  attachStickerSelfie: from(stickers, "attachStickerSelfie"),
  replaceStickerPhoto: from(stickers, "replaceStickerPhoto"),
  setStickerHeadword: from(stickers, "setStickerHeadword"),
  setStickerHeroRole: from(stickers, "setStickerHeroRole"),
  // 写真の無い札の見出し・「ネットの画像」の節（画像は iOS が直に取りに行く）
  searchImageCandidates: from(images, "searchImageCandidates"),
  setStickerPlaceholder: from(stickers, "setStickerPlaceholder"),
  updateStickerCaption: from(stickers, "updateStickerCaption"),
  updateWordExtras: from(stickers, "updateWordExtras"),
  reportWordIssue: from(stickers, "reportWordIssue"),
  checkOwnedWord: from(encounters, "checkOwnedWord"),
  recordEncounter: from(encounters, "recordEncounter"),
  listStickerPhotos: from(encounters, "listStickerPhotos"),
  // 発音
  synthesizeSpeech: from(tts, "synthesizeSpeech"),
  getTtsVoiceTags: from(tts, "getTtsVoiceTags"),
  // 復習
  getDueReviews: from(reviews, "getDueReviews"),
  gradeReview: from(reviews, "gradeReview"),
  getMemoryOverview: from(reviews, "getMemoryOverview"),
  getOverallMemoryStats: from(reviews, "getOverallMemoryStats"),
  getReviewCapState: from(reviews, "getReviewCapState"),
  getStickerMemoryHistory: from(reviews, "getStickerMemoryHistory"),
  getUpcomingDueTimes: from(reviews, "getUpcomingDueTimes"),
  // 棚（自分の棚・語の置き場所）
  setStickerCategory: from(categories, "setStickerCategory"),
  setStickersCategory: from(categories, "setStickersCategory"),
  saveMyCategory: from(categories, "saveMyCategory"),
  deleteMyCategory: from(categories, "deleteMyCategory"),
  // ホームのアルバム（外す・戻す・並べ方）
  listAlbumHidden: from(album, "listAlbumHidden"),
  setAlbumHidden: from(album, "setAlbumHidden"),
  saveAlbumLayout: from(stickers, "saveAlbumLayout"),
  // 日記（添削・書き出しの質問・過去の日記・本人の文の保存）
  listJournal: from(journal, "listJournal"),
  correctMyJournal: from(journal, "correctMyJournal"),
  getJournalPrompts: from(journal, "getJournalPrompts"),
  saveMyDiary: from(journal, "saveMyDiary"),
  listMyDiaryMonth: from(journal, "listMyDiaryMonth"),
  // 利用者
  getMyStats: from(stats, "getMyStats"),
  // 全利用者の中での位置（iOS の「ほめる演出」。数と順位だけ返す。`standing.functions.ts`）
  getMyStanding: from(standing, "getMyStanding"),
  getMyProfile: from(profile, "getMyProfile"),
  updateMyProfile: from(profile, "updateMyProfile"),
  deleteMyAccount: from(profile, "deleteMyAccount"),
  getWordExplanation: from(explanation, "getWordExplanation"),
  getReaderMeanings: from(explanation, "getReaderMeanings"),
  // 外部の AI へ送る同意（`docs/ios-spec/23-ai-consent.md`）
  getAiConsent: from(consent, "getAiConsent"),
  recordAiConsent: from(consent, "recordAiConsent"),
  // 「Apple でサインイン」の code を預ける（退会で Apple の許可を取り消すため。Guideline 5.1.1(v)）
  storeAppleAuthCode: from(appleToken, "storeAppleAuthCode"),
  // 開発者の「AI の設定」（管理者だけ。`docs/admin-ai-api.md`）
  adminGetAiSettings: from(adminAi, "adminGetAiSettings"),
  adminSetAiFeature: from(adminAi, "adminSetAiFeature"),
  // 用途ごとの AI と控え・費用（2026-10-14〜）
  adminSetAiTask: from(adminAi, "adminSetAiTask"),
  adminGetAiCosts: from(adminAi, "adminGetAiCosts"),
  adminSetAiPrice: from(adminAi, "adminSetAiPrice"),
  // 保存済みの語のチャンクの点検し直し（20 語ずつ）
  adminSetImageConfig: from(adminAi, "adminSetImageConfig"),
  adminSetTtsVoice: from(adminAi, "adminSetTtsVoice"),
  adminTestImage: from(images, "adminTestImage"),
  adminPreviewTtsVoice: from(tts, "previewTtsVoice"),
  adminDiagnoseGeminiTts: from(tts, "diagnoseGeminiTts"),
  // 機能ごと・モデルごとの AI の速さと正確さ・固定の写真で試す（`ai-model-stats.ts`）
  adminGetAiStats: from(adminAi, "adminGetAiStats"),
  adminGetAiTestPhotos: from(adminAi, "adminGetAiTestPhotos"),
  adminTestPhotoCandidates: from(ai, "adminTestPhotoCandidates"),
  // 開発者の「利用者と分析」（管理者だけ・読むだけ。Web の管理画面と同じ関数）
  adminListUsers: from(adminUsers, "listAdminUsers"),
  adminGetUserDetail: from(adminUsers, "getAdminUserDetail"),
  adminGetOverview: from(adminUsers, "getAdminOverview"),
  adminGetDashboard: from(metrics, "getAdminDashboard"),
  adminGetBetaMetrics: from(betaMetrics, "getBetaMetrics"),
  // 開発者の「エラー報告」（管理者だけ。利用者の「内容の誤りを報告」の一覧と、状態の変更。2026-10-15）
  // 入力 { status?: "open" | "all", limit?: number } → [{ id, headword, kind, item, note, status, outcome,
  // reporter_lang, word_id, created_at, outcome_at }]。status は open / fixed / needs_review / resolved / dismissed。
  adminListEntryReports: from(reports, "listEntryReports"),
  // 入力 { id, status: "open" | "resolved" | "dismissed" } → { ok: true }
  adminSetEntryReportStatus: from(reports, "resolveEntryReport"),
};

/** 管理者だけが使える口（名前は必ず `admin` で始める）。試験が一覧と突き合わせる。 */
export const NATIVE_ADMIN_FNS = [
  "adminGetAiSettings",
  "adminSetAiFeature",
  "adminSetAiTask",
  "adminGetAiCosts",
  "adminSetAiPrice",
  "adminSetImageConfig",
  "adminSetTtsVoice",
  "adminTestImage",
  "adminPreviewTtsVoice",
  "adminDiagnoseGeminiTts",
  "adminGetAiStats",
  "adminGetAiTestPhotos",
  "adminTestPhotoCandidates",
  "adminListUsers",
  "adminGetUserDetail",
  "adminGetOverview",
  "adminGetDashboard",
  "adminGetBetaMetrics",
  "adminListEntryReports",
  "adminSetEntryReportStatus",
] as const;

/** 失敗の中身から、iOS に返す状態コードを決める。 */
export function statusForError(e: unknown): number {
  const name = (e as { name?: string })?.name ?? "";
  const msg = e instanceof Error ? e.message : String(e ?? "");
  if (msg.startsWith("Unauthorized")) return 401;
  // 管理者だけの口を、管理者でない人が呼んだ（`admin-ai.server.ts` の ADMIN_ONLY_MESSAGE）。
  if (msg.startsWith("Forbidden")) return 403;
  // 外部の AI へ送る同意が無い（`ai-consent.ts`）。iOS は同意の画面を出す。
  if (msg.includes("AI_CONSENT_REQUIRED")) return 403;
  if (msg.includes("AI_CONSENT_CHECK_FAILED")) return 503;
  // 開発者の「固定の写真で試す」の1日の上限（`ai-test.server.ts`）。
  if (msg.includes("AI_TEST_DAILY_LIMIT")) return 429;
  // 送った写真が、名前の写真と違う（`adminTestPhotoCandidates`。古い写真を覚えた端末など）。
  if (msg.includes("AI_TEST_PHOTO_MISMATCH")) return 400;
  if (
    msg.includes("1日の利用上限") ||
    msg.includes("AI_DAILY_CAP") ||
    msg.includes("AI_GLOBAL_CAP")
  )
    return 429;
  // 利用回数を数えられない（閉じる側に倒した）— 少し待てば通る。
  if (msg.includes("AI_USAGE_CHECK_FAILED")) return 503;
  if (name === "ZodError") return 400;
  // 送った値が使えない（`admin-ai.server.ts` の BadRequestError。知らない会社・鍵の無い会社 等）。
  if (name === "BadRequestError") return 400;
  // いま保存できない（DB に届かない等。`review-grade-guard.ts` の GradeSaveError）— 少し待てば通る。
  if (name === "ServiceUnavailableError") return 503;
  return 500;
}

/** 利用者に見せてよい長さに丸める（スタックや長い JSON をそのまま返さない）。 */
export function publicMessage(e: unknown): string {
  const name = (e as { name?: string })?.name ?? "";
  if (name === "ZodError") return "送った内容の形が違います。アプリを最新にしてください。";
  const msg = e instanceof Error ? e.message : String(e ?? "");
  return msg.slice(0, 300) || "サーバで失敗しました。";
}
