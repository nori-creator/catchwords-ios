import { DEFAULT_TARGET_LANGUAGE } from "./target-lang";
import { targetProfile } from "./target-profile";
/**
 * 例文を**どこから作るか**の指示。
 *
 * オーナー:
 * > 「例文は**現実世界の有名人や実際の出来事、ニュース、歴史、文化、流行**
 * >  などから制作する、または、**自分の過去の単語の一言感想や撮った画像、
 * >  日記から AI がユーザーの行動、感情を分析し、例文を作る。**」
 *
 * ## なぜ2系統なのか
 * どちらも「その文が**誰かの現実**である」ことを狙っている。教科書の
 * 「我是學生。」が記憶に残らないのは、正しいが誰の話でもないから。
 * 世界の側は共有された現実(有名人・出来事)、自分の側はその人の現実
 * (撮った物・書いた日記)を借りる。
 *
 * ## 世界の側で必ず縛ること
 * 実在の人物や出来事を出すと、**モデルが平気で嘘の事実を書く**。
 * 語学の例文として文が自然でも、事実が違えば学習者はそれを覚える。
 * だから「断定しない言い回し」を要求し、日付・数字・受賞歴のような
 * 検証が要る細部を禁じる。有名人の名前を出すこと自体は禁じない —
 * それを禁じたら、この指示は元の教科書文に戻る。
 *
 * ここには外の世界に触れるものを入れない(server から材料を渡す)。
 */

/** 例文の材料になる、その人自身のもの。無い項目は省いてよい。 */
export type PersonalMaterial = {
  /** その語をキャッチしたときに書いた一言。 */
  caption?: string | null;
  /** 撮った場所。 */
  place?: string | null;
  /** 撮った日(表示用の文字列のまま渡す)。 */
  takenAt?: string | null;
  /** 最近の日記の下書き(新しい順)。 */
  diaries?: readonly (string | null | undefined)[];
};

/** 日記は長い。1本あたりこの字数で切る。 */
export const DIARY_CHARS = 120;
/** 渡す日記の本数。多く渡しても例文2つには使いきれない。 */
export const DIARY_COUNT = 3;

function clean(s: string | null | undefined): string {
  return (s ?? "").replace(/\s+/g, " ").trim();
}

/** その人の材料が1つでもあるか。無ければ自分の側の指示は出さない。 */
export function hasPersonalMaterial(m: PersonalMaterial): boolean {
  if (clean(m.caption) || clean(m.place)) return true;
  return (m.diaries ?? []).some((d) => clean(d).length > 0);
}

/**
 * 世界の側の指示。
 * `nl` は解説の言語の呼び名(「日本語」/「英語」)。
 */
export function worldExampleRule(
  nl: string,
  target: string = DEFAULT_TARGET_LANGUAGE,
  now: Date = new Date(),
): string {
  // 生きた話題の出どころは言語の表から(前は台湾華語か英語圏かの2分岐で、
  // 日本語の例文に英語圏の話題を勧めていた)。
  const { exampleLocalTopics: local, exampleLocalPreference } = targetProfile(target).capture;
  const month = `${now.getFullYear()}年${now.getMonth() + 1}月`;
  // 優先の順（オーナー指示 2026-09-27「例文は、レベルに合わせて語彙・文法を限定。
  // ネイティブが最も頻繁に使う場面・シチュエーション・感情の例文。ニュース・
  // 世界の出来事・現在のトレンドなどで楽しい生きた例文（決まりきった退屈な
  // ものではない）。最重要はネイティブが使う最も自然な例文」）。
  // 2026-09-28 追記「一番重要なのはその単語をネイティブが使うときに最も自然で頻繁に
  // 使う例文にすること。無理やり固有名詞を入れた不自然な文を作らないで」— 現実の話題は
  // **自然に合う時だけ**の味付けに下げ、固有名詞は入れなくてよいと明記する。
  return [
    `例文の作り方（上ほど大事）:`,
    `\n1. **いちばん大事: ネイティブがその語を使う時に、最も自然で、最も頻繁に口にする一文。**`,
    `その語が実際にいちばんよく使われる言い回し・組み合わせ（よく一緒に出る語）で書く。`,
    `教科書の作文・直訳調・説明文は書かない。語順・語尾・口癖までネイティブの話し言葉のまま。`,
    `\n2. **学習者のレベルに合わせる**: 語彙と文型はそのレベルの範囲に収め、`,
    `新しく覚えるのは見出し語だけで済むようにする。`,
    `\n3. **いちばんよく出会う場面・状況・気持ち**で言う（誰に・どこで・どんな気持ちで）。`,
    `\n4. **生きた話題は、自然に合う時だけ**: ${local}、実在の人物、実際の出来事、ニュース、`,
    `歴史、流行、豆知識、季節の行事（今は${month}）などは、**その語をいちばん自然に使う文に`,
    `そのまま収まる時だけ**使う。**固有名詞を無理に入れない。** 入れると不自然になるなら、`,
    `固有名詞のない日常の一文でよい（その方がよい）。`,
    exampleLocalPreference,
    `決まりきった退屈な文・教科書的な無名の文(「我是學生。」)は書かない。`,
    `\n**ただし事実を作らない**: 日付・数字・順位・受賞歴・「〜年に〜した」のような`,
    `検証が要る細部は書かない。「〜が好きな人が多い」「〜でよく見る」のように、`,
    `間違いようのない書き方にする。流行は、長く続いていて外れようのないものだけ。`,
    `\nscene には、その文が出てくる現実の場面を${nl}で短く書く。`,
  ].join("");
}

/**
 * 自分の側の指示。材料が無ければ**空文字**を返す
 * (空の引用符だけが残った指示をモデルに渡さない)。
 */
export function personalExampleRule(m: PersonalMaterial, nl: string): string {
  if (!hasPersonalMaterial(m)) return "";
  const bits: string[] = [];
  const caption = clean(m.caption);
  const place = clean(m.place);
  const takenAt = clean(m.takenAt);
  if (caption) bits.push(`・この語を撮ったときの一言:「${caption}」`);
  if (place || takenAt)
    bits.push(`・撮った場所と日: ${[place, takenAt].filter(Boolean).join(" / ")}`);
  const diaries = (m.diaries ?? [])
    .map(clean)
    .filter(Boolean)
    .slice(0, DIARY_COUNT)
    .map((d) => (d.length > DIARY_CHARS ? `${d.slice(0, DIARY_CHARS)}…` : d));
  for (const d of diaries) bits.push(`・最近の日記:「${d}」`);

  return [
    `\nこの人自身の記録:\n${bits.join("\n")}\n`,
    `**例文のうち1つは、この人の記録から作る。** 何をして何を感じた人かを読み取り、`,
    `その人が実際に言いたくなる文にする。記録に無いことは足さない。`,
    `scene には「いつ・どんな気持ちで言うか」を${nl}で短く書く。`,
  ].join("");
}

/**
 * **共有の行に書く例文**の作り方の指示（監査 2026-10-03 H1）。
 *
 * 世界の側だけ。その人の記録（一言・場所・日記）は**受け取る口が無い** — 共有の語や
 * 読む人ごとの解説（`word_explanations`）は同じ語を持つ全員が見るので、そこに書く生成に
 * 個人の材料を入れると、その人の日記や居場所が他人のカードに出る。
 * 自分の側（`personalExampleRule`）は、書き先がその人だけの物になる道でだけ使う。
 */
export function sharedExampleSourceRule(
  nl: string,
  target: string = DEFAULT_TARGET_LANGUAGE,
): string {
  return worldExampleRule(nl, target);
}

/**
 * 2系統をまとめた、例文の作り方の指示。
 * **書き先がその人だけの物のときだけ**使う（共有の行には `sharedExampleSourceRule`）。
 */
export function exampleSourceRule(
  m: PersonalMaterial,
  nl: string,
  target: string = DEFAULT_TARGET_LANGUAGE,
): string {
  const personal = personalExampleRule(m, nl);
  const world = worldExampleRule(nl, target);
  return personal ? `${world}${personal}` : world;
}
