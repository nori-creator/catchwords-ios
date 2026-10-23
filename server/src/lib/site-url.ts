/**
 * このサイトの**正式な住所**を1箇所で決める所。
 *
 * ## なぜ要るか（オーナー指示 2026-08-31）
 * > 「ドメインも独自で取得したい。」
 *
 * いま `https://catchwords.lovable.app` が **7ファイル・16箇所**に
 * 直接書き込まれている。canonical・og:url・sitemap・JSON-LD — どれも
 * 「このページの本当の住所はここです」と検索エンジンに宣言する所なので、
 * **1つでも古いまま残ると、独自ドメインに移した日に検索の評価が
 * lovable.app 側へ流れ続ける**。しかも画面には何も出ないので気づけない。
 *
 * だから住所は**変数1つ**にする。移る日は `VITE_SITE_URL` を設定するだけ。
 *
 * ## いまは何も変わらない
 * 未設定のときは今の lovable.app を返す。**今日の出力はバイト単位で同じ**。
 * 設定した日に、16箇所すべてが同時に動く。取り残しが起きない。
 *
 * ## 読む場所が2つある理由
 * 画面（ブラウザ）は Vite がビルド時に `import.meta.env` を埋め込む。
 * サーバー側（sitemap.xml を組む所など）は `process.env` を読む。
 * どちらか一方だけを見ると、**サーバーだけ古い住所を返す**という
 * いちばん見つけにくい食い違いになる。両方見る。
 *
 * ここには外の世界に触れるものを入れないこと。
 */

/**
 * 未設定のときの住所。**今の本番の住所そのもの。**
 * 2026-09-29 に Lovable の公開 URL が `word-snap-journey.lovable.app` から
 * `catchwords.lovable.app` に変わった（旧 URL は「Project not found」になる）ので、ここも新 URL。
 *
 * ここを消してはいけない。消すと未設定時に `undefined` が canonical に
 * 入り、検索エンジンに壊れた宣言を出すことになる。
 */
export const FALLBACK_SITE_URL = "https://catchwords.lovable.app";

/** 末尾の `/` を落として、住所の形をそろえる。 */
export function normalizeSiteUrl(raw: string | null | undefined): string | null {
  const trimmed = (raw ?? "").trim();
  if (!trimmed) return null;
  return trimmed.replace(/\/+$/, "");
}

/**
 * 設定された住所を読む。画面側とサーバー側の**両方**を見る。
 *
 * 呼ぶ側から環境を渡せるようにしてあるのは、試験でここを差し替えるため。
 * 差し替えられないと、この関数の分岐は一度も試されないまま本番に出る。
 */
export function configuredSiteUrl(
  env: Record<string, string | undefined> = readEnv(),
): string | null {
  return normalizeSiteUrl(env.VITE_SITE_URL);
}

function readEnv(): Record<string, string | undefined> {
  const out: Record<string, string | undefined> = {};
  // 画面側（Vite がビルド時に埋め込む）。
  const viteEnv =
    typeof import.meta !== "undefined"
      ? (import.meta as unknown as { env?: Record<string, string | undefined> }).env
      : undefined;
  if (viteEnv?.VITE_SITE_URL) out.VITE_SITE_URL = viteEnv.VITE_SITE_URL;
  // サーバー側。画面側が空のときだけ見る（ビルド時の埋め込みを優先）。
  if (!out.VITE_SITE_URL && typeof process !== "undefined") {
    out.VITE_SITE_URL = process.env?.VITE_SITE_URL;
  }
  return out;
}

/** このサイトの住所（末尾に `/` は付かない）。 */
export function siteUrl(env?: Record<string, string | undefined>): string {
  return configuredSiteUrl(env) ?? FALLBACK_SITE_URL;
}

/**
 * ページの住所を組む。
 *
 * **`/` の重複と欠落の両方を防ぐ。** `siteUrl() + path` を呼ぶ側で
 * 素朴に繋ぐと、片方が `/post/1`、片方が `post/1` になった日に
 * `…app//post/1` と `…apppost/1` が混ざる。canonical が1文字でも
 * 違えば検索エンジンには別のページに見える。
 */
export function siteUrlFor(path: string, env?: Record<string, string | undefined>): string {
  const base = siteUrl(env);
  const clean = (path ?? "").trim();
  if (!clean || clean === "/") return base;
  return `${base}/${clean.replace(/^\/+/, "")}`;
}
