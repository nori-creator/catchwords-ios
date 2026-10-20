# iOS 版の表示言語を足す手順

最終確認: 2026-10-20 ／ 対象: オーナー（コードを書かない人）と、作業する AI・開発者

いまの表示言語は 日本語・English・繁體中文・Español・한국어・Tiếng Việt の6つ。
この文書は、7つ目からを**できるだけ自動で**足すための手順。古い手順（Web 版の `docs/adding-a-language.md` の
2026-09-27 版）は Web の画面の話で、iOS 版にはそのまま使えない。

---

## 0. 言葉の意味

| 言葉 | 意味 |
|---|---|
| **表示言語** | アプリの画面の言葉。**AI が書く単語の解説（意味・例文の訳など）の言語でもある**。設定の「母語」で選ぶ |
| **学習言語** | 学んでいる言語（いまは 繁體字（台灣）だけ） |
| **言語の一覧** | `ios/Localization/languages.json`。表示言語は**ここに1つずつ書いてあるだけ**で、アプリのほかの場所はここから読む |
| **翻訳表** | 日本語の文 → 各言語の訳 の表。アプリの文字は `ios/CatchWords/Resources/Localization/strings.json`、ウィジェット（ホーム画面の小さな窓）は `ios/Shared/Localization/widget-strings.json`、カメラ・位置情報・写真の許可を求める画面の文は `ios/CatchWords/Resources/<言語>.lproj/InfoPlist.strings` |
| **ワークフロー** | GitHub の Mac / Linux が決まった作業を自動でやる仕組み。ボタン1つで動く |
| **Secrets** | GitHub に預ける秘密の値。コードには書かない |
| **API キー** | プログラムが AI（Claude）を呼ぶための鍵。使った分だけ料金がかかる |
| **PR（プルリクエスト）** | 「この変更を入れてよいか」の提案書。中身を見てから取り込む |
| **符号（コード）** | 言語の短い名前。`fr`（フランス語）、`pt-BR`（ブラジルのポルトガル語）、`th`（タイ語）など。Web 版と同じ符号を使う |
| **書く文字** | その言語を書く文字の種類。`latin`（アルファベット）、`hangul`（ハングル）、`han`（漢字）、`kana`（かな）の4つから選ぶ |

---

## 1. 最初に1回だけ: AI の鍵を GitHub に預ける

1. https://console.anthropic.com にログイン → **API Keys** → **Create Key** で鍵を作り、表示された文字列をコピーする
   （画面を閉じると二度と見られない）。
2. GitHub のこのリポジトリ → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**。
   - Name: `ANTHROPIC_API_KEY`
   - Secret: 1 でコピーした文字列
3. 同じ **Settings** → **Actions** → **General** → 一番下の **Workflow permissions** で
   「**Allow GitHub Actions to create and approve pull requests**」にチェックを入れて **Save**
   （ワークフローが PR を作れるようにするため）。

> 費用の目安: 1言語で約1,250件の文を訳す。1回の実行で数百円程度（Anthropic の料金表で確かめる）。

---

## 2. 言語を足す（ボタンを押すだけ）

1. GitHub → **Actions** → 左の一覧から **表示言語を足す（iOS）** → **Run workflow**。
2. 入力する（フランス語の例）:

   | 欄 | 例 | 説明 |
   |---|---|---|
   | 言語の符号 | `fr` | Web 版と同じ符号 |
   | その言語自身での名前 | `Français` | 設定のホイールに出る名前 |
   | 日本語での名前 | `フランス語` | 日本語の画面に出る名前 |
   | 旗の絵文字 | `🇫🇷` | オンボーディングの言語選びに出る |
   | 日付・数の書き方 | `fr_FR` | 言語_国 の形 |
   | 書く文字の種類 | `latin` | フランス語はアルファベット |

3. **Run workflow** を押す。10〜30分で終わる。
4. 終わると、下書きの PR が1つできる（できなかったときは、実行の記録に出るブランチ名から手で PR を作る）。

ワークフローがやること:
- 言語の一覧・Xcode の設定（地域）・許可の説明のファイルに、その言語を足す
- 翻訳表の**すべての文**を、Claude に訳させて埋める（新しい言語の名前を、ほかの言語でも訳す）
- その言語の見分け方（よく使う語・その言語だけの文字）と、チャンクの程度語（很・超…）の訳も Claude に聞いて書く
- アプリの手書き風の文字（フォント）にその言語の文字が全部あるかを調べ、無ければふつうの文字にする
- 訳が全部そろったか・言語が混ざっていないかを確かめる（足りない・混ざっていれば赤くなって止まる）

---

## 3. 画面で確かめる（必ず人の目で）

機械訳は、ボタンの短い言葉が不自然なことがある。

1. 2 でできた PR を開く。「**iOS check**」が終わると、見本の画面の写真が出る（ios-check-report）。
   新しい言語の写真は、`settings-fr` のように名前の後ろに符号が付いた物
   （出したい画面は `.github/workflows/ios-check.yml` の見本の一覧に `"settings-fr 2 1"` のように足す）。
2. その言語が分かる人に、主な画面（設定・オンボーディング・図鑑・単語の詳細・復習）を読んでもらう。
3. 直したい訳は Claude に「strings.json の ○○ の fr を △△ に」と頼む。
4. 読み終わったら、`ios/Localization/languages.json` のその言語の `"reviewed"` を `true` にする。

---

## 4. サーバ（Web 版）にも同じ言語を足す（単語の解説のため）

**単語の解説（意味・例文の訳・チャンクの訳・注記・4択）はサーバの AI が書く。** iOS に足しただけでは、
その言語の人の解説はサーバが書けない。

1. Claude に「Web 版の `docs/adding-a-language.md` の『解説の言語を足す』で `fr` を足して」と頼む
   （Web 版リポジトリ `nori-creator/Lovable-catch-words-app` の `src/lib/explain-languages.ts` に1つ足す作業）。
2. その PR を取り込み、Lovable の編集画面で **Publish → Update** を押す。
3. **iOS 版を App Store に出すのは、2 の後。** 毎日動く「iOS ↔ Web contract」が、iOS の言語がサーバに全部あるかを
   確かめ、無ければ赤くする。

---

## 5. 取り込んで、出す

1. iOS の PR と Web の PR の両方が緑で、画面も確かめたら、取り込む（Web が先）。
2. いつもどおり **iOS release** で TestFlight に送り、iPhone でその言語に切り替えて確かめる。

---

## 6. あとから文が増えたとき（訳の取りこぼしを埋める）

アプリに新しい文を足すと、「iOS check」の最初の段（表示の言語が混ざらないか確かめる）が
「missing es: …」のように**どの言語の訳が無いか**を出して赤くなる。

- AI に作業を頼んでいるなら、その AI が全部の言語の訳を足す（足さないと赤いまま）。
- 自動で埋めるなら: **表示言語を足す（iOS）** → **Run workflow** → 「**足りない訳だけ埋める**」にチェック → Run。
  足りない訳だけを全部の言語で埋めた PR ができる。

---

## 7. 自動でできない場合

| 場合 | 何が要るか |
|---|---|
| **書く文字が4種類のどれでもない**（タイ文字、キリル文字、アラビア文字、デーヴァナーガリーなど） | 言語の混ざりを見分ける規則（`ios/CatchWords/Utilities/LanguageRules.swift` と Web の `note-language.ts` など）に、その文字の判定を足す必要がある。Claude に「docs/adding-a-display-language.md の 7 で ○○語を足して」と頼む |
| **右から左に書く言語**（アラビア語・ヘブライ語） | 上に加えて、画面の並びを左右逆にした見た目の確認が要る |
| **App Store の説明文**もその言語で出したい | `ios/metadata/` にその言語の JSON を足し、**App Store metadata（文言を入れる）** のワークフローで送る（審査の対象になる） |
| **規約・プライバシーポリシー**をその言語で出したい | 法的な文なので機械訳のまま出さない。訳が用意できるまでは英語の頁が開く（言語の一覧の `legalDocs`） |

---

## 仕組み（作業する AI・開発者向け）

- 一覧: `ios/Localization/languages.json` → `scripts/l10n_languages.py` が `ios/Shared/DisplayLanguages.swift` を作る
  （手で書き換えない。CI が「一覧から作った物と同じか」を確かめる）。
- アプリはこの一覧から: 選べる言語（オンボーディング・設定）、端末の言語からの初期値、日付の書き方、区切り・括弧、
  英語・スペイン語の単数（1 word / 1 palabra）、言語の混ざりの判定（書く文字ごと — `LanguageRules`）、
  チャンクの程度語の訳、手書きの文字を使うか、規約の頁の言語。
- 検査: `scripts/check_l10n.py`（訳・ウィジェット・許可の説明・Xcode の地域・言語名）、
  `ios/LanguageRules/cases.json`（言語の混ざりの事例）、`scripts/check_native_contract.py`（サーバの言語）。
- 足す道具: `scripts/add_language.py add / fill / missing`。`fill` は Claude（`claude-opus-5-5`、
  構造化出力・拒否時の自動の切り替え付き）で、足りない訳を全部の言語で埋める。
