/**
 * 「この札は、どの絵で見せるか」を決める唯一の場所。
 *
 * ## なぜ要るか — 同じ札が画面ごとに違う写真で出ていた
 * 数えたら、選び方が**7通り**あった:
 *
 * | 画面 | 順番 |
 * |---|---|
 * | ホーム | 自撮り → 元写真 → 切り抜き → ネット画像 |
 * | 図鑑の格子 | 元写真 → 切り抜き → ネット画像 |
 * | 図鑑の棚 | 切り抜き(立てる) / 元写真 → ネット画像(額) |
 * | 札の詳細 | 切り抜き → 元写真 → ネット画像 |
 * | 札のシート | 元写真 → 切り抜き → ネット画像 |
 * | 復習 | 切り抜き → ネット画像(**元写真も自撮りも見ない**) |
 * | 近くの札 | 元写真 → 切り抜き → ネット画像 |
 *
 * 切り抜きだけ在って元写真が無い札は図鑑では切り抜きで出るのに、
 * 近くの札では別の絵になる。**同じ物なのに画面をまたぐと別物に見える。**
 *
 * 要望 #16「表示画像(切り抜き/元画像/自撮り)を設定から選べる」と
 * #17「写真ごとに長押しで表示画像を変更」は、この上には建てられない —
 * 「選んだ」を書き込む先が7箇所に散らばっているから。
 * だから**先に集約する**。この周では見た目を変えない。
 *
 * ## 画面ごとの好みは残す
 * 全部を1つの順番に潰すのは行き過ぎ。棚が切り抜きを先に見るのは
 * 「棚に立てる」という**意図**であって事故ではないし、ホームの
 * アルバムが自撮りを先に見るのも同じ。
 * だから「何を先に見るか」だけを画面が言い、**その後の落ち方は共通**にする。
 */

/** 絵の役どころ。 */
export type PhotoRole = "object" | "cutout" | "selfie" | "placeholder";

/** 先に見る役が指定されなかったときの落ち方。 */
const FALLBACK: readonly PhotoRole[] = ["object", "cutout", "selfie", "placeholder"];

const ROLES: readonly PhotoRole[] = FALLBACK;

/**
 * 札が持ちうる絵。**全部あることのほうが珍しい。**
 * 文字キャッチの札には元写真も切り抜きも無く、ネット画像しか無い。
 */
export type PhotoSources = {
  object_url?: string | null;
  object_thumb_url?: string | null;
  cutout_url?: string | null;
  cutout_thumb_url?: string | null;
  selfie_url?: string | null;
  placeholder_url?: string | null;
};

export type PickedPhoto = {
  url: string;
  /** どの役が選ばれたか。**棚は切り抜きかどうかで置き方を変える。** */
  role: PhotoRole;
  /** 縮小版が使えたか。使えなければ原寸を返している。 */
  thumb: boolean;
};

export type PickOptions = {
  /**
   * その画面が**先に見たい**役。知らない値・null は無視して既定の順に落ちる
   * (設定から来る値をそのまま渡せるようにしてある)。
   */
  prefer?: PhotoRole | string | null;
  /** 一覧のように小さく出す所では縮小版を先に使う。 */
  thumb?: boolean;
  /**
   * その画面では**使わない**役。
   *
   * ホームのアルバムが `placeholder` を外す(オーナー指摘 2026-08-21
   * 「文字入力した単語はホームのアルバムに単語の文字だけ書いて」)。
   * アルバムは**自分が出会って撮った物の記録**なので、ネットから来た絵を
   * 貼ると、撮った日の思い出と借り物が同じ紙の上で見分けられなくなる。
   * 単語の詳細では逆に、その絵が見出しになる — だから
   * 「無かったことにする」のではなく、**画面ごとに外す**。
   */
  exclude?: readonly PhotoRole[];
};

/** 署名URLの期限部分を除き、同じ保存物を指しているか判定する。 */
export function samePhotoAsset(
  a: string | null | undefined,
  b: string | null | undefined,
): boolean {
  if (!a || !b) return false;
  if (a === b) return true;
  try {
    const left = new URL(a, "https://local.invalid");
    const right = new URL(b, "https://local.invalid");
    return left.pathname === right.pathname;
  } catch {
    return false;
  }
}

/** 役の名前として通るか。**判定は1箇所**(画面ごとの選択も同じ物を読む)。 */
export function isPhotoRole(v: unknown): v is PhotoRole {
  return typeof v === "string" && (ROLES as readonly string[]).includes(v);
}
const isRole = isPhotoRole;

/** その役の絵を1つ取り出す。縮小版が要るときは縮小版を先に見る。 */
function urlFor(s: PhotoSources, role: PhotoRole, wantThumb: boolean): PickedPhoto | null {
  const pair =
    role === "object"
      ? [s.object_thumb_url, s.object_url]
      : role === "cutout"
        ? [s.cutout_thumb_url, s.cutout_url]
        : role === "selfie"
          ? [null, s.selfie_url]
          : [null, s.placeholder_url];
  const [thumb, full] = pair;
  if (
    role === "cutout" &&
    (samePhotoAsset(full, s.object_url) || samePhotoAsset(thumb, s.object_thumb_url))
  ) {
    return null;
  }
  if (wantThumb && thumb) return { url: thumb, role, thumb: true };
  if (full) return { url: full, role, thumb: false };
  // 縮小版しか無い回もある(原寸の掃除が済んだ札)。**取りこぼさない。**
  if (thumb) return { url: thumb, role, thumb: true };
  return null;
}

/**
 * 見せる絵を1つ選ぶ。1枚も無ければ null。
 *
 * **`prefer` を信じきらない。** 設定やDBから来た文字列をそのまま渡せる —
 * 知らない値は既定の順に落ちるだけで、例外にはしない
 * (`Number(null) === 0` で中立を既定にしてしまった件と同じ気の緩みを避ける)。
 */
export function pickStickerPhoto(
  sources: PhotoSources | null | undefined,
  options: PickOptions = {},
): PickedPhoto | null {
  if (!sources) return null;
  const wantThumb = options.thumb === true;
  const base: PhotoRole[] = isRole(options.prefer)
    ? [options.prefer, ...FALLBACK.filter((r) => r !== options.prefer)]
    : [...FALLBACK];
  // **外す役は `prefer` より強い。** 画面が「これは載せない」と言った物を、
  // 設定の好みが押し戻せてしまうと、外した意味が無くなる。
  const excluded = options.exclude ?? [];
  const order = base.filter((r) => !excluded.includes(r));
  for (const role of order) {
    const hit = urlFor(sources, role, wantThumb);
    if (hit) return hit;
  }
  return null;
}

/** URL だけ要る所の近道。 */
export function stickerPhotoUrl(
  sources: PhotoSources | null | undefined,
  options: PickOptions = {},
): string | null {
  return pickStickerPhoto(sources, options)?.url ?? null;
}

/**
 * 試す順に並べた絵の URL（重複なし）。**1枚目が読めなかったときの次**が要る所
 * （図鑑の地図のピン）で使う。縮小版 → 原寸 → 別の役の順。
 *
 * （オーナー報告 2026-09-23「地図上で丸いバブルの画像が表示されてない」—
 *  縮小版が保存に無い札・署名の切れた札で、ピンが白い丸のまま残っていた）
 */
export function photoCandidates(
  sources: PhotoSources | null | undefined,
  options: Omit<PickOptions, "thumb"> = {},
): string[] {
  if (!sources) return [];
  const out: string[] = [];
  const add = (u: string | null | undefined) => {
    if (u && !out.includes(u)) out.push(u);
  };
  add(stickerPhotoUrl(sources, { ...options, thumb: true }));
  add(stickerPhotoUrl(sources, { ...options, thumb: false }));
  for (const role of FALLBACK) {
    if ((options.exclude ?? []).includes(role)) continue;
    add(urlFor(sources, role, true)?.url);
    add(urlFor(sources, role, false)?.url);
  }
  return out;
}

/** その札が**自分で撮った絵**を持っているか(ネット画像しか無い札と区別する)。 */
export function hasOwnPhoto(sources: PhotoSources | null | undefined): boolean {
  if (!sources) return false;
  return !!(
    sources.object_url ||
    sources.object_thumb_url ||
    sources.cutout_url ||
    sources.cutout_thumb_url ||
    sources.selfie_url
  );
}
