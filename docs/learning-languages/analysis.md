# 学習言語を増やすための分析（日本語・英語・スペイン語）

最終確認: 2026-11-08 ／ 対象: オーナー（コードを書かない人）と、作業する AI・開発者
調べた物: `ios/`（アプリ）、`server/src/lib`（サーバの関数）、`supabase/migrations`（DB）、`docs/`。
コードは変えていない。この文書だけを足した。

---

## 0. 要点

1. **英語（en）と日本語（ja）は、もう半分ある。** サーバの言語の表（`server/src/lib/target-profile.ts`）、単語の頁の
   英語・日本語の項目、読み（ふりがな）、級（CEFR・JLPT）、図鑑の英語・日本語の見出しは書いてある。画面で
   選べないように隠しているだけ（`ProfileStore.offeredTargets = ["zh-TW"]`）。ただし品質の確かめはしていない。
2. **スペイン語（es）は学習言語としては何も無い。** 表示言語・母語としてはある。
3. **いちばん大きな問題は「知らない言語は台湾華語として扱う」作り。** サーバの `normalizeTargetLanguage`
   （`server/src/lib/target-lang.ts:77`）と、アプリの `switch … default:`（約95行・27ファイル）が、`es` を黙って
   台湾華語にする。エラーは出ない。スペイン語の単語に注音の設定が出る、例文が全部消える、英語の声で読む、が起きる。
4. **英語とスペイン語は同じアルファベット。** 今のアプリは「アルファベットなら英語」と決めている所がある
   （読み上げ・リンク・単語の言語の付け替え）。スペイン語の単語が英語の単語として扱われる。
5. 提案: 表示言語の一覧（`ios/Localization/languages.json`）と同じ形の**学習言語の一覧**を1つ作り、
   アプリ（Swift）とサーバ（TypeScript）の両方をそこから作る。一覧に無い言語は「台湾華語」ではなく「無い」として止める。
6. 順番: ①土台（見た目を変えずに一覧へ移す）→ ②日本語 → ③英語 → ④スペイン語。1言語ずつ、画面の写真と
   ネイティブの目で確かめてから出す。

---

## 1. 用語

| 言葉 | 意味 |
|---|---|
| 学習言語 | 学んでいる言語。DB の `profiles.target_language`。コードでは `targetLanguage` / `target` |
| 表示言語 | アプリの画面の言語。AI が書く解説の言語でもある（`ios/Localization/languages.json`） |
| 母語（L1） | 学習者の母語。解説を「つまずき」に合わせるのに使う（`server/src/lib/l1.ts`） |
| 学習言語パック | この文書の提案。1つの学習言語について、アプリとサーバが知るべきことを1か所に書いた物 |
| 一覧ファイル | JSON の形の表。人も機械も読める |
| 生成 | 一覧ファイルから Swift と TypeScript のコードを機械で作ること。手で書き写さない |
| 分岐 | 「もし英語なら…、日本語なら…、それ以外なら…」と書いたコード（`if` / `switch`） |
| フォールバック | 知らない値が来た時に代わりに使う値。今は台湾華語 |
| 見出し語 | 単語の頁の一番上の語（椅子・chair・silla） |
| 読み | 注音（ㄅㄆㄇ）・ピンイン・ふりがな・ローマ字・IPA（発音記号） |
| 級の目盛り | TOCFL・JLPT・CEFR。どれも6段に揃えてある（`server/src/lib/level-scale.ts`） |
| 帯 | 級を2つずつまとめた A・B・C。例文とチャンクの共有に使う（`docs/sharing-rules.md`） |
| チャンク | 「跟＋朋友＋見面」のような使い方の型（`docs/chunk-rules.md`） |
| 指示文 | AI への頼み方の文（プロンプト）。サーバだけが持つ |
| TTS | 文字を声で読む仕組み（読み上げ） |
| 書く文字 | かな・漢字・ハングル・アルファベットの区別 |
| 分かち書き | 語と語の間に空白を入れる書き方。英語・スペイン語はする、中文・日本語はしない |
| 形態素解析 | 日本語の文を語に切り、読みを決める道具。日本語の例文にふりがなを付けるのに要る |
| 移行（マイグレーション） | DB の表の形を変える手順のファイル（`supabase/migrations`） |
| CI | GitHub が変更ごとに自動で試験・画面の写真を撮る仕組み |
| 画面の写真 | CI がアプリの見本の画面を撮った物（`.github/workflows/ios-check.yml` の一覧） |
| PR | 変更の提案書。見てから取り込む |
| 門 | 決まりを破ると CI を赤くする検査 |

---

## 2. いまの状態

### 2.1 もう言語ごとになっている所（そのまま使える土台）

| 何 | 場所 | 状態 |
|---|---|---|
| 学習言語の表（サーバ） | `server/src/lib/target-profile.ts:150`（型）、`:452` 台湾華語、`:620` 英語、`:829` 日本語 | 項目・読み・級・指示文の言い回し・4択の受け皿・チャンクの決まりを言語ごとに持つ。**今のパックに一番近い物**。ただし TypeScript だけで、アプリは手で写している |
| 級の目盛り | `server/src/lib/level-scale.ts`（TOCFL・CEFR・JLPT、どれも6段） | 一般化済み。帯 A/B/C もそのまま使える |
| 単語の行の分け方 | DB `words` の鍵 `(language, headword)`（`…part2…sql:260`）、`word_explanations`・`generated_cards`・`dictionary_entries` も言語ごと | 言語ごとに別の行になる。同じ綴り（taxi）が英語とスペイン語で別の行になれる |
| 図鑑・復習・アルバムの絞り込み | `server/src/lib/language-filter.ts:36-62`、iOS `Models.swift:55-58`、`ReviewStore`（R18） | 学習言語で分けている。言語が空の古い行は台湾華語 |
| 単語の頁の英語・日本語の項目 | iOS `Models/CardSection.swift:51-64`、描き方 `Views/WordDetailView.swift:1531-1542`・`:1955-2120` | 活用・数え方と冠詞・句動詞・強く読む所・漢字の内訳・助数詞・高低アクセント・語種・日本メモを描ける |
| 読みの描き分け | iOS `Views/ZhuyinWordView.swift:152-158` | 英語は読み無し、日本語はふりがな/ローマ字、それ以外は注音/ピンイン |
| 図鑑の見出し | iOS `Models/DexCatalog.swift:21-38`（379件 × 中・英・日の3列）、サーバ `dex-catalog.ts`（同じ表） | 英語・日本語の列はある |
| 4択の受け皿 | iOS `Models/QuizPool.swift:25-30` | 中・英・日の3組 |
| 声 | サーバ `tts-voice.ts:47-82`、`tts-providers.ts:58-61` | 中・英・日の声 |
| 実際の使われ方のリンク | iOS `WordDetailView.swift:2160-2190` | 中・英・日のサイト |
| 言語の混ざりの規則 | `docs/language-rules.md` R8・R15〜R19 | 学習言語ごとの規則は書いてある（中・英・日） |
| 試験 | `ios/LanguageRules/cases.json`（209件、学習言語の欄 `target` あり: zh-TW 72・en 23・ja 18） | 学習言語ごとの判定の試験を足せる形 |
| CI の画面の写真 | `.github/workflows/ios-check.yml:184` に `jadetail-en`・`jaquiz-en`・`japicker-en`・`endetail-ja`・`enanswer-ja`・`enpicker-ja` など | 日本語・英語を学ぶ画面の写真の仕組みはある |

### 2.2 隠しているだけの所（オーナーの決定で隠した）

| 場所 | 中身 |
|---|---|
| iOS `ViewModels/ProfileStore.swift:48-55` | 選べる学習言語は `offeredTargets = ["zh-TW"]`。英語・日本語はコードに残してある（2026-10-11 の決定） |
| iOS `Views/OnboardingView.swift:69-78` | 学習言語の質問を出さない（`showsTargetStep = false`）。全員 `fixedTarget = "zh-TW"` |
| iOS `Views/SettingsView.swift:192-199` | 学習言語の欄は、選べる言語が2つ以上になると自動で出る |
| サーバ `target-lang.ts:56` | Web の選択肢は `["zh-TW","en"]`（Web は本物ではない） |

`CLAUDE.md` の「学習言語は台湾華語（zh-TW）だけ（2026-10-21）」と「新しい機能は足さない（2026-10-28）」は、
今回のオーナーの指示で改める必要がある。**CLAUDE.md の書き換えはオーナーに確かめてから**（この文書では変えていない）。

### 2.3 根本の問題: 知らない言語は台湾華語になる

新しい言語コード（`es`）を1つ足すと、次の所が**黙って台湾華語として動く**。エラーにも試験の失敗にもならない。

| 種類 | 場所 | 数 |
|---|---|---|
| サーバの入口 | `server/src/lib/target-lang.ts:77` `normalizeTargetLanguage`（一覧に無い値 → `zh-TW`） | 19ファイルが呼ぶ（48か所） |
| サーバの表 | `target-profile.ts:988` `targetProfile`、`tts-voice.ts:81` `ttsVoiceFor`、`generic-chunks.ts:148` `listFor` | 知らない値 → 台湾華語の表 |
| サーバの「中文なら」 | `startsWith("zh")` 28か所・15ファイル（`chunk-readings.server.ts`・`chunk-grammar.ts`・`chunk-quality.ts`・`tts-cache.ts` など） | 中文だけの処理。これ自体は正しいが、`es` が `zh-TW` に直された後に通ると中文の処理を受ける |
| サーバの「英語なら空白」 | `=== "en"` / `=== "ja"` 約46行（一部は表示言語の比較） | `extras.ts:945`・`reviews.functions.ts:140` など。スペイン語は空白なしで継がれる |
| アプリの入口 | `ProfileStore.swift:17-19`（`en`・`ja` 以外は `zh-TW` に直す） | 1か所で全部が台湾華語になる |
| アプリの分岐 | `case "en": … case "ja": … default: 台湾華語` の形 | 約95行・27ファイル（`UIPreview`・見本のデータを除く） |
| DB の既定値 | `profiles.target_language`・`words.language`・`stickers.language`・`dictionary_entries.language` の既定 `'zh-TW'`、`level_goal` の既定 `'TOCFL-2'` | 言語を渡し忘れた書き込みは台湾華語になる |

---

## 3. 洗い出し（台湾華語を前提にしている所）

表の読み方: 「いま」= 今の前提。「ja / en / es」= その言語で何が要るか。
「済」= 今のコードでその言語は動く形がある（品質は未確認）。「**止まる**」= その言語を出すと壊れる所。

### A. 言語の一覧・入口

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| `server/src/lib/target-lang.ts:41` `TARGET_LANGUAGES` | `["zh-TW","en","ja"]` | 済 | 済 | **止まる**: 無い。`es` は全部 `zh-TW` に直される |
| `target-lang.ts:77-82` `normalizeTargetLanguage` | 知らない値 → `zh-TW` | — | — | 一覧から作る。知らない値は台湾華語にしない（空・null だけ古い行として台湾華語） |
| `target-lang.ts:90-121` `speechLangOf` / `sttLangOf` | 中・英・日の表 | 済 | 済 | `es-ES` か `es-MX` など（地域はオーナーの決定 D2） |
| `target-lang.ts:140-142` `CHINESE_EXPLANATION_LANGUAGE` / `MAP_DISPLAY_LANGUAGE` | `zh-TW` | 地図の言語は学習言語ではない。iOS の場所の名前は `LocationService` が別に決める（R24）。このサーバ定数を iOS が通るかは要確認 | 同左 | 同左 |
| `target-profile.ts:976-990` `PROFILES` / `targetProfile` | 3言語、知らない値 → 台湾華語 | 済 | 済 | **止まる**: 表が無い |
| iOS `ViewModels/ProfileStore.swift:17-19` | `en`・`ja` 以外は `zh-TW` に直す | 済 | 済 | **止まる**: `es` を保存しても端末は台湾華語で動く |
| `ProfileStore.swift:48-55` `allTargetOptions` / `offeredTargets` | 中・英・日、出すのは中だけ | 出す時に足す | 同左 | 行を足す |
| `ProfileStore.swift:129` | プロフィールに値が無ければ `zh-TW` | 古いアカウントのため残す | 同左 | 同左 |
| iOS `Services/NativeAPI.swift:14` | 端末の最初の値は `zh-TW` | 残してよい | 同左 | 同左 |
| `NativeAPI.swift:18-24` `targetName`、`:26-35` `sample`、`:39-45` `defaultPos`、`:48-54` `speechLanguage` | `switch` の `default` が台湾華語 | 済 | 済 | **止まる**: 名前が「台湾華語」、見本が「椅子」、品詞が `N`、声が `zh-TW` |
| iOS `Views/OnboardingView.swift:69-71` `targets` | 中・英・日の3行 | 済 | 済 | 行を足す |
| `OnboardingView.swift:95-99` `targetChoices(ui:)` | 表示言語と同じ学習言語は外す（ほかが無い時は残す） | 日本語を表示する人に日本語を出さない | 同左 | 同左。オーナーの決定 D5 |
| iOS `Utilities/LanguageRules.swift:361-368` `resolveWordLanguage` | `["zh-TW","en","ja"]` 以外は `zh-TW`。見出しが合わなければ英語か台湾華語に付け替える | 済 | 済 | **止まる**: `es` の語「manzana」は**英語の語**として扱われる（単語の頁 `WordDetailView.swift:1379`、答え `AnswerPanel.swift:109`、画像検索 `WebImages.swift:52`） |
| iOS `Models/Models.swift:55-58` | 言語が空の行は台湾華語 | 残す（古い行） | 同左 | 同左 |
| DB `…part1…sql:180-181` `profiles.target_language` 既定 `'zh-TW'`・`level_goal` 既定 `'TOCFL-2'` | 新しいアカウントは台湾華語 | 学習言語を必ず書く道ならそのまま。級の既定は言語で違う（`JLPT-N4` など） | 同左（`A2`） | 同左（`A2`） |
| DB `…part2…sql:118` `words.language`、`:7` `stickers.language`、`…part1…sql:505` `dictionary_entries.language` 既定 `'zh-TW'` | 書き忘れは台湾華語 | 書き込みの道すべてで言語を渡すことを試験で確かめる | 同左 | 同左 |
| iOS アプリは `profiles` を直接書く（`ProfileStore.swift:166-170`） | サーバの確かめを通らない | `target_language` に一覧に無い値を書けないよう、DB で縛る案（§6 P7） | 同左 | 同左 |

### B. 見出し語と「学習言語の文か」の判定

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| iOS `LanguageRules.swift:161-180` `isIn`（例文が学習言語か、R8） | `default` は「漢字があれば中文」 | 済（かな・短い漢字） | 済（漢字・かな無し） | **止まる**: スペイン語の例文は漢字が無いので**全部消える**。英語の文との見分け（R22 の印の語）も要る |
| `LanguageRules.swift:194-230` `mentionsHeadword`（チャンクに学ぶ語があるか、R20） | 英語は語尾の変化、日本語は語幹、それ以外は字の一致 | 済 | 済 | 複数形（manzana → manzanas、lápiz → lápices）・冠詞・アクセント記号を見る規則が要る |
| `LanguageRules.swift:265-283` `headwordOk` | 英語は**A〜Z だけ**（café が通らない）。`default` は漢字だけ | 済 | アクセント付きの字を通す（サーバ `target-profile.ts` の `EN_HEADWORD` は通す。食い違い） | **止まる**: スペイン語は全部通らない |
| `LanguageRules.swift:298-330` `headwordSaveable`（保存してよい見出しか、R21） | 英語は A〜Z とアクセント付き・数字・& | 済 | 済 | **止まる**: `default`（台湾華語）でアルファベットを落とすので、**スペイン語の単語は1つも保存できない** |
| サーバ `target-profile.ts` 各言語の `headwordOk`（`:452`〜、`:620`〜、`:829`〜） | 言語ごと | 済 | 済 | 足す: アルファベット＋á é í ó ú ü ñ、冠詞（el/la/los/las/un/una）を外した形 |
| サーバ `target-language.ts:80-89` `isTargetHeadword` | 一覧に無い言語は「空でなければ何でも通す」 | — | — | 今の `es` は**サーバの保存の門を素通り**し、ほかの所では台湾華語に直される。食い違い。一覧に入れて門を付ける |
| サーバ `text-language.ts:45-77` `looksLikeTargetLanguage` | 中・英・日。それ以外は台湾華語の規則 | 済 | 済 | **止まる**: スペイン語の例文を「中文でない」として落とす。英語の文を落とす規則も要る |
| サーバ `text-query-lang.ts:39-55` `detectQueryLang`（打った語が母語か学習言語か） | 中文以外は「かな・漢字なら母語、見出しとして通れば学習言語」 | 済 | 表示言語がスペイン語の人が「manzana」と打つと**英語の見出し**と見なされる（今の隠れた英語にもある穴） | 表示言語が英語の人の「apple」をスペイン語と見なす。英語とスペイン語の印の語で見分ける規則が要る |
| サーバ `kanji-forms.ts`（日本だけの字） | 台湾華語の門で使う | 逆向き（台湾だけの字を日本語で落とす）は `text-query-lang.ts:22` の `TW_ONLY` にある | — | — |
| （作業中・未コミット）`server/src/lib/dictionary-lookup.ts`「しらべる」 | 拼音・注音で引く・字ごとの意味（2026-11-08 の新しい指示） | パックを読むように作る | 同左 | 同左 |

### C. 読み（注音・ピンイン・ふりがな・IPA）

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| iOS `Views/ZhuyinWordView.swift:128-165`（見出しの読みを描く、アプリ中で使う） | `en` は読み無し、`ja` はふりがな、`default` は注音/ピンイン | 済 | 済 | 読み無し（綴りどおりに読める）。今は `default` に落ちる。読みが空なら字だけ出るので見た目は崩れにくいが、意味は台湾華語の道 |
| iOS `Views/CardCatch/CCZhuyin.swift:24` `isMandarin` | 英語・日本語でなければ中文 | 済 | 済 | **止まる**: スペイン語が「中文」になる |
| iOS `Views/CatchCelebrationView.swift:472` | 英語・日本語でなければ字ごとに注音 | 済 | 済 | 同上 |
| iOS `Views/SettingsView.swift:183, 210-216`（設定 › 発音表記） | 日本語はふりがな/ローマ字、**英語以外は注音/ピンイン** | 済 | 済（欄を出さない） | **止まる**: スペイン語の人に「ㄅㄆㄇ 注音 / abc ピンイン」が出る |
| iOS `OnboardingView.swift:491-500` | 同上 | 済 | 済 | 同上 |
| iOS `Views/WordExampleCards.swift:69`、`Views/ChunkLineView.swift:63, 76, 305, 317` | 中文だけ読みを付ける（`hasPrefix("zh")`） | 済（例文・チャンクにふりがなは無い） | 済 | 済 |
| iOS `ViewModels/ReviewStore.swift:27` | 4択の読みを注音からピンインに直す（全言語で試す） | 直せず nil になるだけ（害は小さい） | 同左 | 同左 |
| DB の列の名前 `words.reading_zhuyin`・`pinyin`（`…part2…sql:120-121`） | 台湾華語の名前のまま、日本語はかな/ローマ字、英語は IPA 米/英を入れている（`target-profile.ts:83-90` の注） | 済 | 済（画面には出さない。2026-09-30・10-02 の決定） | 何も入れないか IPA。決定 D7 |
| サーバ `tw-reading.server.ts`・`sentence-readings.server.ts`・`chunk-readings.server.ts:32,59,74,119` | 中文だけ。辞書 `pinyin-pro`・`opencc-js` | 日本語の例文のふりがなは**無い**。付けるなら形態素解析の道具が要る（新しい機能、決定 D6） | 不要 | 不要 |
| iOS `Views/WelcomeView.swift:549-556` | 登録画面のステッカーが 咖啡・植物・麵包 と注音 | 見本の語を言語ごとに | 同左 | 同左 |

### D. 級（レベル）

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| サーバ `level-scale.ts` | TOCFL・CEFR・JLPT（6段） | 済（N5〜N1、6段目 N1+） | 済（A1〜C2） | CEFR の形は使える。ただし下の理由で**別の目盛りの名前**（例 `CEFR-es`）が要る |
| サーバ `level-instruction.ts:53-81, 86, 100, 192` | 帯の説明・文法の範囲を `scale.id` で引く。CEFR は **CEFR-J（英語の文法表）** | 済 | 済 | **止まる**: スペイン語に CEFR を使うと、AI に英語の文法項目が渡る。スペイン語の段の説明（Instituto Cervantes の Plan curricular など、出典は要確認）が要る |
| iOS `ProfileStore.swift:71-77` `levels(for:)`、`:80-85` `remap` | `default` は TOCFL | 済 | 済 | 足す |
| iOS `OnboardingView.swift:188`「TOCFLのレベルを教えてください」、`:575-576`（`"TOCFL-n"` を写す）、`:609-700` `OnboardingLevels`・`TOCFLLevel`（TOCFL の公式の説明） | TOCFL だけ | JLPT の質問と段の説明 | CEFR の質問と説明 | CEFR（DELE）の質問と説明 |
| `OnboardingView.swift:281`（目的「試験対策」の下の小さな字） | 英語 TOEFL·IELTS、日本語 JLPT、それ以外 TOCFL | 済 | 済 | 「DELE · SIELE」など |
| サーバ `ai.functions.ts:211`、`shared-word-guard.ts:440` | 級の既定 `"TOCFL-2"` | 言語の目盛りの2段目に | 同左 | 同左 |
| `docs/sharing-rules.md` S1〜S8 | 文は「TOCFL の帯」 | 仕組みは目盛りに依らない（`level-content.ts`）。文を「その言語の級」に直す | 同左 | 同左 |
| `docs/language-rules.md` R25（共通の表記） | TOCFL・CEFR・JLPT | 済 | 済 | DELE を足すか決める |

### E. 単語の頁の項目

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| iOS `Models/CardSection.swift:51-64` `sections(for:)`、`:145-151` `defaultVisible`、`:153-156` | `en`・`ja`・`default`（台湾華語） | 済 | 済 | **止まる**: 量詞・台湾メモの頁になる |
| `CardSection.swift:175`（並びの保存の鍵）、`:190, 195, 201` | 台湾華語だけの古い並びの直し | 影響なし | 同左 | 同左 |
| サーバ `card-sections.ts:30-60` `SECTION_IDS`、`card-request.ts:21-39` | 中・英・日の項目 | 済 | 済 | スペイン語の新しい項目（§4.4）を足す |
| iOS `WordDetailView.swift:1456` | 台湾メモは `zh-TW` の時だけ | 日本メモは別の項目で済 | 文化の一言で済 | スペイン語のメモ（地域差）を決める |
| `WordDetailView.swift:427`（見出しを直す入力欄の見本） | 英語・日本語・それ以外は「繁体字で入力」 | 済 | 済 | 足す |
| `WordDetailView.swift:1547-1555` `tooLong`（チャンクの長さ） | 英語4語/28字、日本語12字、**それ以外は8字** | 済 | 済 | **止まる**: 「dar un paseo」は12字なので、ほとんどのスペイン語のチャンクが消える |
| `WordDetailView.swift:1942-1950` `relatedWord` | 中文は字ごとの読み、それ以外は `ZhuyinWordView` | 済 | 済 | 済（読み無し） |
| `WordDetailView.swift:2144-2151` `linkLanguage` | 言語が空の古い行は字で決める。**アルファベットは英語** | 済 | 済 | 言語の欄がある行は問題なし。空の行は無いはず（新しい言語に古い行は無い） |
| `WordDetailView.swift:2160-2190` リンク | 中・英・日のサイト | 済 | 済 | 足す: YouTube（gl=ES/MX）、Google（hl=es）、YouGlish（spanish）、RAE の辞書（dle.rae.es）、WordReference、SpanishDict など |
| iOS `Views/TourGuide.swift:106-116` `sectionPoint` | 台湾華語の項目だけ一言。それ以外は共通の文 | 項目ごとの一言を書くか決める | 同左 | 同左 |
| iOS `Views/SectionsPanel.swift:164-170` | 学習言語の名前、`default` 台湾華語 | 済 | 済 | 一覧の名前を読む |
| サーバ `ai.functions.ts:1464` `wantMeasure` | 項目の一覧を渡さない呼び出しでは、助数詞を持たない言語にも**量詞を頼む** | 済（助数詞があるので頼まない） | **今も英語のカードに量詞を頼んでいる**: iOS の `generateCard`（`DexStore.swift:1367`）は項目の一覧を渡さない | 同左 |

### F. チャンク（使い方の型）

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| iOS `Utilities/ChunkRules.swift:27` `UsageChunk.text` | 札を空白なしで継ぐ | 済 | 英語は空白が要る（ほかの所で別に継いでいる） | 空白が要る |
| `ChunkRules.swift:484, 497, 509`（例文の中の型を探す・読み上げる） | **英語だけ**空白で継ぎ、大文字小文字を区別しない | 済 | 済 | **止まる**: スペイン語は「darunpaseo」と継がれ、例文の中で見つからない（2026-10-01 の CH12 と同じ形の不具合） |
| `ChunkRules.swift:603-604` `exampleHit`（例文の番号と色、C19） | 英語は番号・色を付けない | 済 | 英語の例文はチャンクの番号が付かない（今の欠け） | 同左。語の境目で探す形が要る |
| `ChunkRules.swift:213-217, 440` 程度の語・つなぎの語 | 中文の語（很・的…） | 日本語の助詞は品詞で見ている（`isGluePos`） | 同左 | 同左。前置詞・冠詞の品詞名を確かめる |
| `ChunkRules.swift:237-243, 300-330, 378-384` | 中文だけの直し（名詞の合体・程度の語の補い・崩れた型） | 済 | 済 | 済（中文だけの処理なので触らない） |
| `ios/Localization/languages.json` の `degreeGlosses`（表示言語の一覧に、很・超… の訳） | **学習言語（中文）のデータが表示言語の一覧に入っている** | — | — | パックに移す（学習言語 × 表示言語の表） |
| サーバ `ai.functions.ts:2506-2531` `chunkHardRules` | 「8字以内」「台湾のネイティブ」、例が全部中文。**全言語に渡している** | 日本語のカードに中文の例と「8字」が渡る | 英語のカードに同じ | 言語ごとの決まりにする（パックの指示文） |
| `ai.functions.ts:2545-2551` `chunkReadingRule` | 中文だけ | 済 | 済 | 済 |
| サーバ `extras.ts:627, 648, 657` 長さの上限、`:777, 891, 945` 英語だけ空白 | 中8字・英4語・日12字 | 済 | 済 | **止まる**: 8字で測られる。語の数で測る |
| サーバ `reviews.functions.ts:140` | 英語だけ空白 | 済 | 済 | 同上 |
| サーバ `generic-chunks.ts:40-141`（どの語にも付く型）、`:212` `WEAK_PARTNERS` | 前者は中・英・日、後者は**中文だけ** | 弱い相手（食べる・飲む…）の表が無い | 同左 | 両方足す |
| `target-profile.ts` の `chunkPrompt`・`chunkRoles` | 中・英・日 | 済 | 済 | 足す |
| `docs/chunk-rules.md` C7〜C10・C15 | 中文の決まりが中心 | 日本語の型の決まり（助詞込み）を足す | 英語 | スペイン語（冠詞・前置詞込み、性の一致） |

### G. 例文

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| サーバ `example-patterns.ts:176-242`（量詞と見出しの重なり、隻/支の書き違い） | 中文の規則 | 中文の字で動くので日本語の漢字の文に掛かるかは要確認 | 影響なし | 影響なし |
| `target-profile.ts` の `exampleLocalTopics` | 台湾の人物・文化 | 済（日本） | 済（英語圏） | スペイン・中南米（地域の決定 D2 に従う） |
| 例文は2行以内・16pt 以上（CLAUDE.md） | 言語に依らない | 済 | 長い単語の折り返しを画面の写真で確かめる | 同左 |
| 例文の読み（10-22・10-25 の決定） | 中文: ピンインの時だけ字の上 | ふりがなを付けるか決める（D6） | 無し | 無し |

### H. 復習（4択）

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| iOS `Models/QuizPool.swift:25-30` `words(for:)` | `default` は台湾華語の池 | 済 | 済 | **止まる**: スペイン語の4択に中文の語が並ぶ（R3 と同じ事故） |
| `QuizPool.swift:48-51` `kindWords`、`:59-83` `alsoFits` | 「複合語の**最後**の語がその種類」（珍珠奶茶 は 茶） | 済（お/ご の扱いもある） | 済 | スペイン語は**最初**の語が種類（zumo de naranja は zumo）。言語ごとの向きが要る |
| iOS `ReviewStore.swift:102` `fallback(for:)` | 上の池 | 済 | 済 | 同上 |
| サーバ `quiz-choices.ts:43-56` | 台湾の受け皿の語（`target-profile.ts` と重複） | iOS は使っていない（Web 用）。要確認 | 同左 | 同左 |
| サーバ `reviews.functions.ts:603-605` | 先に作る音声を `zh-TW` の声で作る | Web の復習の道。iOS が通るかは要確認 | 同左 | 同左 |
| 選択肢の見せ方 | 見出し＋読み | ふりがな | 字だけ | 冠詞を付けて出すか決める（D8） |

### I. 図鑑・カテゴリー・タグの名前

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| iOS `Models/DexCatalog.swift:21-38, 638-665`、サーバ `dex-catalog.ts:21-60, 153-156, 721` | 379件 × 中・英・日。「台湾で毎日出会う物」の並び | 列はある。日本の暮らしに合うか要確認 | 列はある | **列が無い**。379件にスペイン語を足す。並び（番号）は全言語で同じなので、台湾らしい物（便當 など）がスペイン語の図鑑にも影で出る（決定 D9） |
| `DexCatalog.swift:638-650` `norm` | 日本語はカタカナをひらがなへ、英語は a/an/the を外す | 済 | 済 | el/la/los/las/un/una を外す |
| iOS `Models/CategoryRules.swift`、サーバ `category.ts:101-402` | 中文の語の表でカテゴリーを決め直す | 日本語の漢字の語に中文の規則が当たる恐れ（例: 「馬」を含む語）。要確認 | 当たらない（AI の答えのまま） | 同左 |
| サーバ `basic-level.ts:99, 306` | 「いちばんふつうの名前」の表は中文だけ（2026-10-15 の決定） | 表が無い → 写真のタグが細かすぎる名前になり得る | 同左 | 同左 |

### J. 読み上げ（声）

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| iOS `Services/SoundService.swift:136-141` `language(of:)` | 文の字で決める: かな → 日本語、**アルファベットだけ → 英語**、漢字 → 学習言語 | 済 | 済 | **止まる**: スペイン語の語・例文を**英語の声**で読む |
| `SoundService.swift:143-149` `bcp47` | `default` は `zh-TW` | 済 | 済 | 足す |
| サーバ `tts-voice.ts:47-82` `VOICES`（Google の声）、`:81` | 知らない言語 → 台湾の声 | 済 | 済 | 足す（`es-ES-…` か `es-US-…`。D2） |
| サーバ `tts-providers.ts:58-61, 120-128`（Azure・Gemini の声） | 台湾の声の決まった表あり | 済 | 済 | 足す |
| iOS `Views/AdminAiSettingsView.swift:669, 774, 793`（開発者の声の設定） | 言語ごと、名前は中・英・日 | 済 | 済 | 足す |

### K. 撮る・候補・スキャン

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| サーバ `ai.functions.ts:593-620, 1136-1226`（写真の候補・打った語の候補） | 言語の表から組み立てる | 済 | 済 | 表が要る |
| サーバ `target-profile.ts:644` 英語の `coach` | **台湾華語の言い回しのまま**（「繁体字」「台湾のネイティブ」）。iOS の `detectScan`（スキャン）が通る | 済（日本語用がある） | **今の欠け**: 英語を学ぶ人のスキャンで繁体字を頼んでいる | 作る |
| `target-profile.ts:738` 英語の `taiwanTermCheck: true` | 英語の語に「台湾の言い方か」を聞いている | 済（false） | false にする | false |
| iOS `ViewModels/CaptureViewModel.swift:365-370`、`Services/DexStore.swift:1695-1696` | 「○○の単語が見つかりませんでした」を言語ごとに別の文で持つ | 済 | 済 | 1つの文（「{1}の単語が…」）に一覧の名前を入れる形に |
| サーバ `first-catch-ai.server.ts:243-247` | 表示言語の名前が ja・en・zh-TW だけ（es・ko・vi の人は空になる） | 学習言語とは別の、表示言語の穴。ついでに見つけた。iOS が通るかは要確認 | — | — |

### L. ホーム・見本・ウィジェット・案内

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| iOS `Views/CollageAlbum.swift:502`（アルバムの名前の札の字の大きさ） | 英語15、それ以外20 | 済 | 済 | 20 では長い語がはみ出る恐れ。一覧に持たせる |
| iOS `Services/SampleSticker.swift:137`、`DexStore.swift:1262`（見本の珍珠奶茶） | 台湾華語の時だけ入る | 見本の語を作るか決める（D10） | 同左 | 同左 |
| iOS `CatchWordsWidgets/WidgetSupport.swift:96-98` | ウィジェットの見本は「雨傘」 | 言語ごとの見本 | 同左 | 同左 |
| iOS `Views/UserStatsPanel.swift:51` | 「○○を学習中」を3つの文で | 済 | 済 | 1つの文に |
| iOS `Views/PlaceEditSheet.swift:29` | 場所の無い写真の地図は台北から | 学習言語ではなく利用者の場所の話。端末の位置か地域で決める案 | 同左 | 同左 |
| 翻訳表 `ios/CatchWords/Resources/Localization/strings.json`（1,626件） | 23件が台湾・注音・TOCFL を含む（例:「街で見つけた物が、台湾華語になる。」「この単語にまつわる、台湾の豆知識…」「TOCFLのレベルを教えてください」） | 言語の名前を差し込む形にするか、言語ごとの文を足す | 同左 | 同左 |
| サーバ `taipei-day.ts`、DB `…part1…sql:492, 586`（`Asia/Taipei`） | アプリの「今日」は台湾時間 | 学習言語ではないが、スペインの人は夕方17時に日付が変わる。決定 D11 | 同左 | 同左 |

### M. AI の指示文（サーバ）

| 場所 | いま | ja | en | es |
|---|---|---|---|---|
| `l1.ts:120-598` `L1_TABLE` | 母語ごとの「台湾華語のつまずき」 | — | — | — |
| `l1.ts:764-768` `RULE_LABELS`、`:789-872` `TARGET_L1_CONTENT` | 日本語を学ぶ時の本文は母語 en・zh-TW の2つだけ | ko・vi・es の母語の本文が無い（一般の一文だけ） | **英語を学ぶ時の本文が無い**。`ai-provider.server.ts:1026-1029` は英語の時に学習言語を渡さないので、**台湾華語のつまずき**（声調・有気音）が英語の解説の指示に入る | 全部作る（母語 ja・en・zh-TW・ko・vi） |
| `level-instruction.ts` | 上の D を参照 | 済 | 済 | 作る |
| `ai.functions.ts:1587` 量詞の指示 | 中文の量詞 | `wantMeasure` で止まる | 上の E を参照 | 同左 |
| `ai.functions.ts:2506-2531` チャンクの絶対ルール | 中文 | 上の F を参照 | 同左 | 同左 |
| `journal.functions.ts`・`correction-judge.ts`（日記・添削） | 言語の表の `coach` | 日記は出していない（`DiaryFeature.enabled = false`） | 同左 | 同左 |

### N. ストア・文書

| 場所 | いま |
|---|---|
| `ios/metadata/app-info/en-US.json`・`ja.json`、`ios/metadata/version/1.0.4/*.json` | 名前・説明が「Taiwanese Mandarin」「台湾華語」 |
| `ios/StoreShots/` | 台湾華語の画面だけ |
| `CLAUDE.md` | 「学習言語は台湾華語だけ」（2026-10-21） |
| `docs/word-detail-design.md` | 題が「単語の詳細（台湾華語）— 版25」。版25 の形は台湾華語で決めた物 |
| `docs/language-rules.md` R16・R17 | 中・英・日の項目と読みは書いてある。スペイン語は無い |

---

## 4. 言語ごとの画面の設計（コードが持つべき物だけ）

### 4.1 前提

- **アプリの単語は名詞**（オーナー 2026-10-20「このアプリ内の単語はすべて名詞だから」）。写真から撮る物の名前なので、
  動詞の活用・句動詞の項目は、名詞にはほぼ空になる。既定では隠し、チャンクの中の動詞だけで扱う。
- 版25 の並び（意味 → チャンク → 例文 → 言語ごとの項目 → 関連語 → メモ → 実際の使われ方）は全言語で同じにする。
  違うのは「言語ごとの項目」と「メモ」と「読み」だけ。
- 品詞は出さない（2026-10-20）。チャンクの品詞の色は出す（2026-11-03 の 6A）。

### 4.2 日本語（ja）

| 部分 | 中身 | コードの状態 |
|---|---|---|
| 見出し | 漢字かな交じり。上にふりがな（設定でローマ字） | ある（`ZhuyinWordView` の `japaneseWord`） |
| 意味 | 表示言語で | ある |
| チャンク | 助詞を入れた型（傘＋を＋さす）。12字まで | ある。サーバの絶対ルールを日本語用にする |
| 例文 | 2行以内。**漢字にふりがなを付けるか**（台湾華語の 10-22 の決定と揃えるなら付ける）は決定 D6。付けるなら形態素解析の道具（kuromoji など）をサーバに置く。関数の大きさ・速さは要確認 | 無い |
| 漢字の内訳 | 字ごとの意味と音読み・訓読み | ある |
| 助数詞 | 一本・一枚・一匹と音の変わり方（いっぽん） | ある |
| 高低アクセント | 東京式の型 | ある（AI の文）。**正しさの出どころ**（辞書のデータ）が無い。データの使用許可は要確認 |
| 語種 | 和語・漢語・外来語 | ある |
| 丁寧さ | 名詞では「お茶・ご飯」の美化語が中心 | ある（既定で隠す） |
| 活用 | 名詞には無い（する名詞だけ） | ある（既定で隠す） |
| 日本メモ | 日本ならではの一言 | ある |
| 級 | JLPT N5〜N1（6段目 N1+）。2010年から公式の語彙表は無い（`level-instruction.ts:63-68` の注）。級は例文とチャンクの難しさにだけ使うので概数でよい | ある |
| 声 | ja-JP | ある |
| リンク | YouTube・YouGlish・X・知恵袋・Google・Weblio・コトバンク・Jisho | ある |

### 4.3 英語（en）

| 部分 | 中身 | コードの状態 |
|---|---|---|
| 見出し | 小文字の原形（固有名詞は大文字）。読みは出さない（2026-09-30・10-02 の決定）。IPA は列に保存してある | ある |
| チャンク | 冠詞・前置詞込み（put on + socks）、4語まで | ある。例文の中の番号・色（C19）が英語では付かない（`ChunkRules.swift:603-604`） |
| 数え方と冠詞 | 可算/不可算・a/an/the・単複 | ある |
| 語形 | 複数形（不規則: mouse → mice）。動詞の形は名詞には空 | ある（`forms`） |
| 強く読む所 | 強勢の位置 | ある |
| 句動詞 | 動詞だけ（既定で隠す） | ある |
| 文化の一言 | 米英の言い方の違い（elevator / lift）を含む | ある |
| 級 | CEFR A1〜C2（CEFR-J の語彙・文法） | ある |
| 声 | en-US（アメリカ英語が既定、2026-08-24） | ある |
| 直す所 | 指示文の `coach`・母語のつまずき・`taiwanTermCheck`・量詞を頼む・アプリの `headwordOk` のアクセント | §3 K・M・E・B |

### 4.4 スペイン語（es）

| 部分 | 中身 | コードの状態 |
|---|---|---|
| 見出し | 冠詞を外した単数の形（manzana）を保存する。画面では**冠詞を添えて**（la manzana）出す。性で色を付けるかは決定 D8 | 無い |
| 読み | 無し（綴りどおりに読める）。強勢は綴りのアクセント記号で分かる | 無い（「読み無し」の描き方は英語と同じ） |
| 性と冠詞（新しい項目 `gender`） | 男性/女性、el/la・un/una、例外（el agua・la mano）、男女で形が変わる語（el/la estudiante） | 無い。サーバの欄・指示文・アプリの描き方を足す |
| 複数形 | -s / -es / -z → -ces、強勢の記号の移り（canción → canciones） | `forms` の複数形の行を使える（英語用の他の行は空） |
| チャンク | 冠詞・前置詞込み（tomar + un café）、語の数で測る（4〜5語、要確認）。空白で継ぐ。性・数の一致を崩さない | 無い |
| 例文 | 2行以内。地域（D2）の言い方に揃える（vosotros を使うか） | 無い |
| 地域の言い方（メモ） | スペインと中南米で違う語（zumo/jugo、coche/carro、ordenador/computadora）。`culture_note` を使うか、新しい項目にするかは D2 次第 | 無い |
| 関連語 | 同じ語根の語、縮小辞（-ito）は頻度が高い時だけ | 関連語の項目で足りる |
| 級 | CEFR A1〜C2（DELE と同じ段の名前）。段の説明はスペイン語用に別に作る | 無い |
| 声 | es-ES か es-MX/es-US（D2） | 無い |
| リンク | YouTube・Google（スペイン語）・YouGlish（spanish）・RAE（dle.rae.es）・WordReference・SpanishDict | 無い |
| 4択 | 冠詞を付けて出すか（D8）。複合語の種類は先頭の語 | 無い |
| 図鑑 | 379件にスペイン語の列 | 無い |

### 4.5 ほかの画面（全言語で、言語ごとに変わる所）

| 画面 | 変わる所 | 一覧に持たせる物 |
|---|---|---|
| オンボード | 級の質問（TOCFL / JLPT / CEFR）と段の説明、読みの選択 | `levels`、`readings` |
| 設定 | 発音表記の選択肢（無い言語は欄を出さない）、級のホイール | 同上 |
| ホームの札（`WordTag`） | 読みの描き方、字の大きさ | `readings.style`、`tagTextSize` |
| 撮った直後（GET・候補） | 読みの描き方、言語の名前 | 同上、`names` |
| 図鑑 | 見出しの列、`norm` で外す冠詞 | `dex.column`、`headword.articles` |
| 復習 | 受け皿の池、種類の語、複合語の向き、冠詞 | `quiz` |
| 案内（チュートリアル） | 項目の一言、メモの名前 | `sections` と翻訳表の鍵 |
| 見本の語（珍珠奶茶）・ウィジェット・登録画面のステッカー | 言語ごとの見本 | `samples` |

---

## 5. 学習言語パックの設計

### 5.1 方針

1. **一覧は1つ。** `ios/Localization/learning-languages.json`（表示言語の一覧の隣）。アプリとサーバの「事実」はここだけに書く。
2. **生成する。** `scripts/learning_languages.py` が `ios/Shared/LearningLanguages.swift` と
   `server/src/lib/learning-languages.generated.ts` を作る。手で書き換えない。CI が「一覧から作った物と同じか」を確かめる
   （`scripts/l10n_languages.py --check` と同じ形）。
3. **知らない言語で動かさない。** 一覧に無いコードは「台湾華語」にしない。空・null の古い行だけを台湾華語として読む。
   それ以外は記録を残して止める（サーバは `UNKNOWN_TARGET_LANGUAGE` の印、アプリは `DevLog` と「この言語には対応していません」）。
4. **言語のコードで分岐しない。性質で分岐する。** `if lang == "en"` ではなく `pack.spaced`（分かち書きか）、
   `pack.readings.style`（読みの描き方）、`pack.chunks.unit`（字で数えるか語で数えるか）を見る。
   こうすると、スペイン語は英語と同じ性質を宣言するだけで、英語の道を通る。
5. **長い指示文は TypeScript に残す。** 日本語で書いた AI への指示文（`target-profile.ts` の `capture`・`coach`・
   `chunkPrompt` など）は JSON に向かない。言語ごとのファイル（`server/src/lib/learning/ja.ts` など）に分け、
   型で「一覧のどのコードにも指示文がある」ことを強制する（`Record<TargetLanguage, …>`）。
6. **段階を持つ。** `status`: `hidden`（コードはある・選べない）→ `beta`（開発者・招待だけ選べる）→ `offered`（全員）。
   今の `offeredTargets` の代わり。

### 5.2 項目

| 項目 | 意味 | zh-TW | ja | en | es |
|---|---|---|---|---|---|
| `code` | 言語コード | `zh-TW` | `ja` | `en` | `es` |
| `status` | 出す段階 | `offered` | `hidden` | `hidden` | `hidden` |
| `names.autonym` / `names.nameJa` / `names.promptName` | 自称・日本語の名前（翻訳表で訳す）・指示文の中の呼び名 | 繁體字（台灣）/ 台湾華語 / 台湾華語(繁体字) | 日本語 / 日本語 / 日本語(現代の標準語) | English / 英語 / 英語(アメリカ英語) | Español / スペイン語 / スペイン語(D2 の地域) |
| `flag` | 旗 | 🇹🇼 | 🇯🇵 | 🇺🇸 | D2 で決める |
| `script.letters` | 見出しに使う字 | `han` | `kana`,`han` | `latin` | `latin` |
| `script.spaced` | 分かち書き | false | false | true | true |
| `script.caseFold` | 大文字小文字を同じに見る | false | false | true | true |
| `script.htmlLang` | 字形を決める `lang` | `zh-Hant` | `ja` | `en` | `es` |
| `headword.extraLetters` | 見出しに許す追加の字 | 漢字にくっつく大文字1〜3字（T恤） | 頭の大文字1〜2字＋カタカナ（Tシャツ） | á é ñ など・数字・& | á é í ó ú ü ñ・数字 |
| `headword.rejectKanji` | 落とす字 | 日本だけの字（`kanji-forms.ts`） | 台湾だけの字（`TW_ONLY`） | — | — |
| `headword.articles` | 見出しから外す冠詞 | — | — | a, an, the | el, la, los, las, un, una |
| `mixing.markerWords` / `markerLetters` | 同じ字の別の言語の文を見分ける印（R22） | — | — | 英語の印（表示言語の一覧と共有） | スペイン語の印（同） |
| `readings.kinds` | 保存する読み（列 `reading_zhuyin` / `pinyin` に入る物） | zhuyin, pinyin | kana, romaji | ipa-us, ipa-uk | （無し。D7） |
| `readings.style` | 読みの描き方 | `zhuyin-side`（字の右）/ `pinyin-above` | `ruby-above` | `none` | `none` |
| `readings.choices` / `settingKey` | 設定の選択肢と保存の鍵 | 注音/ピンイン・`reading.pref` | ふりがな/ローマ字・`reading.ja` | 無し | 無し |
| `readings.sentences` | 例文に読みを付けるか | `pinyin-when-chosen` | D6 | none | none |
| `levels.scale` | 級の目盛り | TOCFL | JLPT | CEFR（CEFR-J） | CEFR-es（新しい表） |
| `levels.default` | 既定の今・目標 | 1 / 2 | N5 / N4 | A1 / A2 | A1 / A2 |
| `levels.examTag` | 「試験対策」の下の小さな字 | TOCFL | JLPT | TOEFL · IELTS | DELE · SIELE（要確認） |
| `sections.all` / `defaultVisible` | 単語の頁の項目と既定の並び | 今の `CardSection.sections(for:)` | 同 | 同 | §4.4 |
| `sections.note` | メモの項目 | taiwan_note | japan_note | culture_note | culture_note か新しい項目（D2） |
| `chunks.unit` / `max` / `maxParts` | 長さの数え方と上限 | chars / 8 / 4 | chars / 12 / 4 | words / 4（28字）/ 4 | words / 5（要確認）/ 4 |
| `chunks.degreeWords` / `frameWords` / `fixedDegree` | 程度・つなぎの語 | 很・超… / 的・了… / 很 | — | — | — |
| `chunks.degreeGlosses` | 程度の語の訳（表示言語ごと） | 今は `languages.json` にある | — | — | — |
| `speech.bcp47` / `google` / `azure` / `ios` | 声 | zh-TW / cmn-TW-Wavenet-A / … | ja-JP / … | en-US / … | D2 |
| `quiz.fallback` | 4択の受け皿（語・読み・カテゴリー） | 今の `QuizPool.zhTW` | 今の `ja` | 今の `en` | 新しく |
| `quiz.kindWords` / `compoundHead` | 種類の語・複合語の向き | 水果… / last | 果物… / last | fruit… / last | fruta… / first |
| `dex.column` | 図鑑の見出しの列 | zh | ja | en | es |
| `samples` | 入力欄の見本・見本のステッカー・ウィジェット | 椅子 / 芒果 / 珍珠奶茶 | 椅子 / マンゴー | chair / mango | silla / mango |
| `pos.default` / `pos.phrase` | 仮の品詞 | N / 片語 | 名詞 / フレーズ | noun / phrase | sustantivo / frase（要確認） |
| `links` | 実際の使われ方のリンク | 今の表 | 今の表 | 今の表 | §4.4 |
| `ui.tagTextSize` | アルバムの札の字 | 20 | 20 | 15 | 15 |

### 5.3 一覧の書き方（見本、一部）

```json
{
  "_readme": "学習言語の一覧。scripts/learning_languages.py が Swift と TS を作る。手で生成物を直さない。",
  "legacyDefault": "zh-TW",
  "languages": [
    {
      "code": "es",
      "status": "hidden",
      "names": { "autonym": "Español", "nameJa": "スペイン語", "promptName": "スペイン語(○○の標準)" },
      "script": { "letters": ["latin"], "spaced": true, "caseFold": true, "htmlLang": "es" },
      "headword": { "extraLetters": "áéíóúüñÁÉÍÓÚÜÑ0-9", "articles": ["el", "la", "los", "las", "un", "una"] },
      "readings": { "kinds": [], "style": "none", "choices": [], "sentences": "none" },
      "levels": { "scale": "CEFR-es", "default": { "current": 1, "goal": 2 }, "examTag": "DELE · SIELE" },
      "sections": {
        "all": ["meaning", "usage_chunks", "example", "gender", "forms", "related_words", "culture_note", "real_usage"],
        "defaultVisible": ["meaning", "usage_chunks", "example", "gender", "related_words", "culture_note", "real_usage"],
        "note": "culture_note"
      },
      "chunks": { "unit": "words", "max": 5, "maxParts": 4 },
      "speech": { "bcp47": "es-ES", "google": "es-ES-Wavenet-?", "azure": ["es-ES-ElviraNeural"], "ios": "es-ES" },
      "quiz": { "compoundHead": "first", "kindWords": ["fruta", "flor", "árbol", "pájaro", "libro", "té", "zumo"] },
      "dex": { "column": "es" },
      "samples": { "word": "silla", "search": "mango" }
    }
  ]
}
```

（声の名前・語の数の上限・試験の名前は、作る時に確かめる。上は形の見本。）

### 5.4 今のコードがどう読むようになるか

| 今 | パックを読む形 |
|---|---|
| `ProfileStore.swift:17-19` `["en","ja"].contains(…) ? … : "zh-TW"` | `LearningLanguages.find(code) != nil ? code : 記録して元の言語のまま`。空だけ `legacyDefault` |
| `ProfileStore.swift:52` `offeredTargets = ["zh-TW"]` | `LearningLanguages.all.filter { $0.status == .offered }`（開発者は `beta` も） |
| `NativeAPI.swift:18-54` 4つの `switch` | `L10n.text(pack.names.nameJa)`、`pack.samples.word`、`pack.pos.default`、`pack.speech.bcp47` |
| `CardSection.swift:51-64` `sections(for:)` | `pack.sections.all.compactMap(CardSection.init(rawValue:))`。生成の時に「一覧の項目名がすべて `CardSection` にある」ことを確かめる |
| `ZhuyinWordView.swift:152` `switch lang` | `switch pack.readings.style { case .zhuyinSide, .pinyinAbove: …; case .rubyAbove: …; case .none: … }` |
| `SettingsView.swift:210-216` | `ForEach(pack.readings.choices)`。空なら欄を出さない |
| `OnboardingView.swift:188, 575, 696` | 質問の文は「{1}のレベルを教えてください」（{1}= `levels.scale` の名前、R25 の共通表記）。段の説明は翻訳表の鍵 `level.<scale>.<n>` |
| `ChunkRules.swift:484, 497, 509` `target == "en" ? " " : ""` | `pack.script.spaced ? " " : ""`、大文字小文字は `pack.script.caseFold` |
| `WordDetailView.swift:1547-1555` `tooLong` | `pack.chunks.unit == .words ? 語の数 > max : 字の数 > max`。サーバ `extras.ts:627-657` も同じ値を読む |
| `SoundService.swift:136-141` | 文の字が学習言語の `script.letters` に合えば学習言語の声。アルファベットで学習言語もアルファベットなら学習言語（スペイン語を英語の声で読まない）。合わなければ表示言語 |
| `LanguageRules.swift:161, 265, 298` | 字の規則は `pack.script` と `pack.headword` から。台湾華語・日本語だけの特別な規則（日本だけの字・T恤）は宣言した名前で呼ぶ |
| `LanguageRules.swift:361-368` `resolveWordLanguage` | 候補は一覧の全言語。**アルファベットの言語が2つ以上ある時は付け替えない**（どちらか決まらない） |
| `QuizPool.swift:25-30`、`DexCatalog.swift:32-38` | `pack.quiz`、`pack.dex.column`。図鑑の379件は Swift から JSON（`ios/CatchWords/Resources/dex-catalog.json`）へ移し、サーバの写し（`__fixtures__/ios-dex-catalog.json`）と同じ物を読む |
| サーバ `target-lang.ts:41, 77, 90-121` | `TARGET_LANGUAGES` と声のコードを生成物から。`normalizeTargetLanguage` は知らない値で印を投げる |
| サーバ `target-profile.ts:976` `PROFILES` | `Record<TargetLanguage, TargetProfile>`。生成物にコードを足すと、指示文のファイルが無い限り型の検査で落ちる |
| サーバ `level-instruction.ts:80, 86` `BANDS[scale.id] ?? TOCFL_BANDS` | `BANDS` も `Record<スケール, …>`。無いと型で落ちる |
| サーバ `tts-voice.ts:47` `VOICES` | 生成物から |

### 5.5 CI の門

| 門 | 何を確かめるか | どこに置くか |
|---|---|---|
| 生成物が最新か | JSON から作った Swift・TS と、置いてある物が同じか | `scripts/learning_languages.py --check`（`ios-check.yml`・`server.yml`） |
| 一覧の形 | 必要な項目がそろう、項目名が既知、`status` が正しい値 | 同上 |
| 指示文がそろう | 一覧の全コードに指示文のファイル・級の説明・声がある | サーバの型検査（`npm run typecheck`）と試験 `learning-languages.test.ts` |
| 台湾華語の指示文が変わらない | 移す前と後で台湾華語の指示文が1文字も変わらない（`l1.test.ts` の `__fixtures__/l1-prompts.zh-TW.json` と同じやり方） | サーバの試験 |
| 判定の試験の数 | `beta`・`offered` の言語は、`cases.json` に `headwordOk`・`isIn`・`mentionsHeadword`・`tidyChunk`・`chunkSpan` が各 N 件以上 | `ios/LanguageRules` の試験 |
| 言語の組の混ざり | 表示言語 × 学習言語の組（同じ組は除く）ごとに、R22 の見分けの試験がある。特に en × es、zh-TW × ja | 同上 |
| 図鑑・4択の中身 | `offered` の言語は図鑑の379件の列が全部埋まる、受け皿が30語以上 | `learning_languages.py --check` |
| 翻訳 | 級の説明・言語の名前などの文がすべての表示言語にある | `scripts/check_l10n.py` |
| 言語の決め打ちを増やさない | `== "en"`・`case "ja":`・`hasPrefix("zh")`・`"zh-TW"` の新しい行を、生成物と許可の一覧の外で見つけたら赤 | 新しい `scripts/check_language_literals.py`。許可の一覧は減らす一方 |
| 画面の写真 | `beta`・`offered` の言語ごとに、単語の頁・チャンク・例文・4択・答え・候補・設定・オンボードの写真が、表示言語の数だけある | `ios-check.yml` の一覧（`jadetail-en` の形を全言語へ） |

### 5.6 足す手順（パックができた後の形）

表示言語の `docs/adding-a-display-language.md` と同じ形の手順書を、土台ができた時に書く（今は書いていない）。流れは:
一覧に1行（`hidden`）→ 生成 → 赤くなった門を1つずつ埋める（指示文・級・声・図鑑・4択・試験・画面の写真）→
ネイティブの目 → `beta` → 数を見て `offered`。

---

## 6. 実装の順番（1つの PR で収まる大きさ）

### 段階0: オーナーが決めること（作る前）

| # | 決めること | なぜ要るか |
|---|---|---|
| D1 | 出す順番（日本語 → 英語 → スペイン語でよいか） | 既にある量で日本語・英語が先。英語は既に台湾向けに作った跡（`target-lang.ts` の注「英語を学ぶ台湾人向けの版」）がある |
| D2 | スペイン語の地域（スペイン / 中南米 / メキシコ）。英語はアメリカ（2026-08-24 に決定済み） | 声・語（zumo/jugo）・vosotros・例文の話題・旗が変わる。同じ `es` の中で混ぜると、共有の行（例文・チャンク）に別の地域の言い方が入る |
| D3 | 学習言語の数だけ App Store の名前・説明・写真を変えるか、別のアプリにするか | 今の名前・説明は「Taiwanese Mandarin」。審査は書いてある機能と中身が合っていることを見る |
| D4 | 学習言語を替えた人の扱い（今は替えると図鑑・アルバム・復習が言語ごとに分かれる、R18・L1） | 2つの言語を同時に学ぶ人の見え方 |
| D5 | 表示言語と同じ学習言語を許すか（台湾華語は許している、2026-10-20） | 日本語の画面で日本語を学ぶ人に、解説を誰の言語で書くか |
| D6 | 日本語の例文の漢字にふりがなを付けるか | 台湾華語の 10-22 の決定と揃えるなら付ける。新しい道具（形態素解析）が要る |
| D7 | 英語・スペイン語に発音記号を出すか（英語は 2026-09-30・10-02 に消した） | 列に入れるかどうか |
| D8 | スペイン語の見出し・4択に冠詞を付けて出すか、性で色を分けるか | 画面の見た目と復習の中身 |
| D9 | 図鑑の379件（台湾の暮らしの物）を全言語で同じにするか | 番号は全言語で同じ前提。台湾らしい物がスペイン語の図鑑の影に出る |
| D10 | 見本の語（珍珠奶茶）を言語ごとに用意するか | チュートリアルの説明に使っている |
| D11 | アプリの「今日」を台湾時間のままにするか（`taipei-day.ts`） | スペインでは夕方に日付が変わる |
| D12 | `CLAUDE.md` の「学習言語は台湾華語だけ」「新機能は足さない」を改める | 作業する AI がこれに従って直しを断る |

### 段階1: 土台（台湾華語の見た目・動きは1つも変えない）

| PR | 中身 | 確かめ方 |
|---|---|---|
| P1 一覧と生成器 | `learning-languages.json`（zh-TW・en・ja の今の値をそのまま写す、es は書かない）、`scripts/learning_languages.py`、生成物、CI の「最新か」の門。まだ誰も読まない | 生成物の試験。CI が緑 |
| P2 サーバを一覧へ | `target-lang.ts`（コード・声のコード）、`tts-voice.ts`、`extras.ts` の長さと空白、`reviews.functions.ts:140`、`level-instruction.ts` の表の型。`normalizeTargetLanguage` を「空だけ台湾華語、知らない値は印」に | `npm test`・`npm run typecheck`。台湾華語の指示文の写しの試験（新しく足す）が同じ。既存の `target-lang.test.ts`・`target-profile.test.ts` |
| P3 サーバの指示文を言語ごとのファイルへ | `target-profile.ts` を `learning/zh-TW.ts`・`en.ts`・`ja.ts` に分ける。`PROFILES` を `Record<TargetLanguage,…>` に。`chunkHardRules`（`ai.functions.ts:2506`）の中文の例と「8字」を台湾華語のファイルへ（英語・日本語は今は同じ文のまま、直すのは段階2・3） | 同上。台湾華語の指示文が1文字も変わらない |
| P4 アプリの入口を一覧へ | `ProfileStore`・`NativeAPI`・`SoundService.bcp47`・`CardSection`・`QuizPool`・`DexCatalog.headword(for:)`・`SectionsPanel`・`UserStatsPanel`・`CaptureViewModel`・`DexStore` の文 | `CatchWordsTests`（`WordCardPrefsTests`・`QuizPoolTests` など）。CI の画面の写真が前と同じ（台湾華語の全画面） |
| P5 アプリの判定を一覧へ | `LanguageRules`（`isIn`・`mentionsHeadword`・`headwordOk`・`headwordSaveable`・`resolveWordLanguage`）、`ChunkRules` の空白・大文字小文字、`WordDetailView.tooLong`・`linkLanguage`、`SoundService.language(of:)` | `ios/LanguageRules` の試験（今の209件が全部通る）。新しい試験: 「一覧に無い言語は台湾華語にならない」 |
| P6 読みの描き方を一覧へ | `ZhuyinWordView`（名前も `ReadingWordView` に）・`CCZhuyin.isMandarin`・`CatchCelebrationView`・`CollageAlbum` の字の大きさ・設定とオンボードの読みの選択・級の質問の文 | 画面の写真（`readings`・`readings-pinyin`・`word25-*`・`settings-*`・`oblevel*`）が前と同じ |
| P7 決め打ちの門と DB | `check_language_literals.py`（今ある行を許可の一覧に入れて、増やさない）。DB: `profiles.target_language` を一覧のコードだけに縛る（小さな表 `learning_languages(code)` と外部キー、または CHECK）。足すだけの移行 | CI。移行は本番の前に試験の DB で当てる（`docs/backend`） |

### 段階2: 日本語

| PR | 中身 | 確かめ方 |
|---|---|---|
| J1 サーバの日本語 | チャンクの絶対ルールを日本語用に、`WEAK_PARTNERS`・いちばんふつうの名前の表（`basic-level.ts`）の日本語、母語 ko・vi・es の日本語のつまずき（`l1.ts`）、カテゴリーの中文の規則が日本語の語に当たらないように | サーバの試験。決まった語の一覧（30〜50語、図鑑の基本の100から選ぶ）でカードを作り、自動の門（見出し・例文の言語・チャンクに語がある・解説の言語）を通す試験を足す |
| J2 アプリの日本語の頁 | 版25 の形で日本語の項目を並べる（漢字の内訳・助数詞・アクセント・語種・日本メモ）。既定で隠す項目（活用・丁寧さ）。案内の一言。D6 で付けると決めたら例文のふりがな（サーバの道具を別の PR で先に） | 画面の写真 `jadetail-*`・`word25-*` の日本語版を、表示言語 en・zh-TW・es・ko・vi で |
| J3 日本語の入口 | オンボードの JLPT の質問と段の説明（6言語）、設定、見本の語・ウィジェット・登録画面のステッカー（D10）、図鑑の日本語の列と4択の池の見直し | `check_l10n.py`。画面の写真 `oblevel-*`・`jaquiz-*`・`japicker-*` |
| J4 品質の確かめ | 日本語のネイティブが、写真の画面とカード30語以上を読む。直した点を `cases.json` と `docs/language-rules.md` の事例に足す | 人の目。事例が試験に入っている |
| J5 ベータで出す | `status: beta`。開発者・招待の人だけ選べる。分析（`AdminAnalyticsView`）で学習言語ごとの数を見る | TestFlight |

### 段階3: 英語

| PR | 中身 | 確かめ方 |
|---|---|---|
| E1 サーバの英語の欠け | `coach` を英語用に（スキャン）、`taiwanTermCheck: false`、母語ごとの英語のつまずき（ja・zh-TW・es・ko・vi）、量詞を頼まない（iOS から項目の一覧を渡すか、言語の項目に無い節は頼まない） | サーバの試験。英語の決まった語の一覧で J1 と同じ自動の門 |
| E2 アプリの英語の欠け | `headwordOk` のアクセント、例文の中のチャンクの番号と色（C19、語の境目で探す）、名前の札の大きさ、リンク | `cases.json`（en）。画面の写真 `endetail-*`・`enanswer-*`・`enpicker-*`、`word25-*` の英語版 |
| E3 入口 | CEFR の質問と説明、見本 | `check_l10n.py`、写真 |
| E4 品質の確かめ・ベータ | J4・J5 と同じ | 人の目、TestFlight |

### 段階4: スペイン語

| PR | 中身 | 確かめ方 |
|---|---|---|
| S1 一覧に1行（`hidden`） | D2 を反映した値。この時点で門が赤くなる所が「やることの一覧」になる | 赤い門の数を数える |
| S2 サーバの指示文 | `learning/es.ts`（撮る・候補・カード・チャンク・メモ）、`CEFR-es` の段の説明、母語ごとのつまずき、`generic-chunks.ts` の表 | サーバの試験。スペイン語の決まった語の一覧で自動の門 |
| S3 新しい項目「性と冠詞」 | サーバの欄（`extras.ts` の型）・指示文・`card-sections.ts`・アプリの描き方（`WordDetailView`）。複数形は `forms` を使う | サーバの試験、アプリの単体試験、画面の写真 |
| S4 判定と声 | `LanguageRules` の es（見出しの字・冠詞・複数形・英語との見分け）、`SoundService` の声、サーバの声（`tts-voice.ts`・`tts-providers.ts`） | `cases.json`（es と、en × es の組の見分け） |
| S5 図鑑・4択・見本・リンク | 図鑑の379件のスペイン語の列（D9）、受け皿の池、見本、リンク | `learning_languages.py --check` の数の門、写真 |
| S6 入口 | オンボード・設定の CEFR（DELE）の質問と説明 | `check_l10n.py`、写真 |
| S7 品質の確かめ・ベータ | スペイン語のネイティブ（D2 の地域の人）の目 | 人の目、TestFlight |

### どの段階でも続けること

- 1言語を `offered` にする前に、App Store の名前・説明・写真を決める（D3）。`ios/metadata` と `ios-store-metadata.yml`。
- `CLAUDE.md`・`docs/language-rules.md`（R16・R17 にスペイン語）・`docs/sharing-rules.md`（「TOCFL」を「その言語の級」に）・
  `docs/chunk-rules.md`（言語ごとの長さ）・`docs/word-detail-design.md`（題）を、オーナーの確認の後に直す。

---

## 7. 危険と対策

| 危険 | 何が起きるか | 対策 |
|---|---|---|
| 知らない言語が台湾華語として動く | スペイン語の頁に量詞・注音、例文が消える、エラーは出ない | §5.1 の 3。P2・P4・P5。決め打ちの門（P7） |
| アルファベットの言語が2つ | スペイン語の語が英語として付け替えられる、英語の声で読まれる、打った英語がスペイン語の見出しになる | 字ではなく言語の欄で決める（R23 と同じ考え）。字で決めるしかない所は印の語（R22）。en × es の試験 |
| DB の既定値 `'zh-TW'` と「空なら台湾華語」 | 言語を渡し忘れた書き込みが台湾華語の行になる | 書き込みの道ごとに言語を渡す試験。新しい列の既定は付けない。`profiles.target_language` を縛る（P7） |
| 列の名前が台湾華語のまま（`reading_zhuyin`・`pinyin`・`meaning_ja`・`tocfl_level`・`taiwan_usage`） | 列の名前を信じたコードが、日本語のかなを注音として描く | 名前は変えない（変えると古いアプリが壊れる）。中身の意味は一覧の `readings.kinds` が決めると書き、注音として扱うコードは `readings.style` を見てから |
| 共有の単語の行 `(language, headword)` | 見出しの表記揺れで同じ語が2行になる（Manzana / manzana / la manzana、colour / color） | 保存の前に揃える規則を一覧に（`caseFold`・`articles`・地域の綴り）。サーバの `upsertWord` の門で |
| 地域の言い方の混ざり | 同じ `es` の行の例文に、スペインと中南米の言い方が混ざる | D2 で1つに決める。2つ要るなら別のコード（`es-ES` / `es-419`）にして、行も分ける |
| 共有の規則（S1〜S8） | 帯 A/B/C は目盛りに依らないので動く。ただし文書が TOCFL と書いている | 文書だけ直す。帯の計算（`level-content.ts`）は試験で各目盛りを通す |
| 指示文の中の台湾華語の例 | 英語・日本語・スペイン語のカードに中文の例と「8字」が渡る（今も英語・日本語で起きる形） | P3 で言語ごとのファイルに。各言語の決まった語の一覧の自動の門 |
| 母語のつまずきの表の欠け | 英語の解説に声調の話が入る | 学習言語 × 母語の表がそろうまで `offered` にしない（門） |
| AI の費用 | 解説の控え（語 × 表示言語 × 母語 × 帯）が言語の数だけ増える | 言語ごとの数を分析で見る（`analytics.ts`）。出す前に1語あたりの費用を測る |
| 品質の確かめの人手 | ネイティブが読まないと、文法の崩れが分からない | J4・E4・S7 を出す条件にする。直した事例は試験に残す（規則は検査するほど厳しくなる、`docs/language-rules.md`） |
| 高低アクセント・性の正しさ | AI の答えだけでは間違う | 出どころの辞書を探す（使用許可は要確認）。無ければ既定で隠す |
| App Store | 説明と中身が合わない、名前が台湾華語のまま | D3。`ios/metadata` を言語の数に合わせる |
| 作業中の別の機能 | 「しらべる」（`dictionary-lookup.ts`、未コミット）も中文前提で作られている | 同じパックを読むよう、作っている人と合わせる |
| Web 版・Android | 本物ではない（2026-10-21）。サーバの関数は共有 | サーバの関数だけを直す。Web の画面は直さない |

---

## 8. わからない所（要確認）

- サーバの `MAP_DISPLAY_LANGUAGE`（`target-lang.ts:142`）と `quiz-choices.ts` の受け皿・`reviews.functions.ts:603-605` の先に作る音声を、
  iOS が通るか。iOS は自分で4択を作り（`ReviewStore`）、場所の名前は端末が決めるので、通らないと思うが確かめていない。
- `first-catch-ai.server.ts:243-247` の表示言語の名前の穴（es・ko・vi）を iOS が通るか（初めての1枚の道）。
- 英語・日本語の道が、本番の AI で今どれだけ正しく動くか。コードはあるが、隠してから品質を見た記録は見つけていない。
- 日本語の例文のふりがなの道具（形態素解析）を Edge Function に入れた時の大きさと速さ。
- 日本語の高低アクセント、スペイン語の性・複数形、スペイン語の級ごとの語彙の出どころと使用許可。
- スペイン語のチャンクの上限（語の数）。英語は4語だが、スペイン語は冠詞・前置詞が多く、5語が要るかもしれない。
- スペイン語の声の名前（Google・Azure の声の一覧から選ぶ）。
- 日本語の語に、`category.ts` の中文の規則がどれだけ誤って当たるか。
- `example-patterns.ts` の量詞の規則が、日本語の漢字の例文に掛かるか。

---

## 9. 調べ方（作業する人が同じ数を出すため）

```sh
# アプリの言語の分岐（UIPreview と見本のデータを除く）: 約95行・27ファイル
grep -rn -E '== "en"|== "ja"|!= "en"|!= "ja"|case "en"|case "ja"|hasPrefix\("zh"\)|== "zh-TW"|!= "zh-TW"|isMandarin|\["en", "ja"\]' \
  --include=*.swift ios/CatchWords ios/CatchWordsWidgets ios/Shared | grep -v UIPreview | grep -v Demo/

# サーバの「中文なら」: 28か所・15ファイル
grep -n 'startsWith("zh")' server/src/lib/*.ts | grep -v test

# サーバの「知らない値は台湾華語」の入口を呼ぶ所: 19ファイル
grep -l normalizeTargetLanguage server/src/lib/*.ts | grep -v test

# DB の既定値
grep -n "DEFAULT 'zh-TW'\|DEFAULT 'TOCFL-2'\|Asia/Taipei" supabase/migrations/*.sql
```
