# 辞書アプリの調べ — 単語の頁に何を移し、AI で何を足すか

調べた日: 2026-11-08。学習言語ごと（台湾華語・日本語・英語・スペイン語）に、学習者がよく使う辞書を調べた。
目的は2つ。(1) 学習者が今の辞書で頼っている物を単語の頁に移し、乗り換えやすくする。(2) 辞書では解けない悩みに、
AI だけが出せる項目で答える。足すかどうかは、どれもオーナーが決める。

---

## 0. 読み方

### 0.1 確かさの印
- **【原文】** 公式の文やデータを直接読んだ。
- **【検索】** 検索エンジンの要約で読んだ。元のページは開けていない。
- **【未確認】** 確かめられなかった。
- この作業環境では、pleco.com・apps.apple.com など多くのサイトを直接開けなかった（ネットワークの許可の外）。
  GitHub の生ファイルと PyPI（Python の部品の置き場）は直接読めた。だから多くは【検索】。
- 数の多くは第三者の推計。公式の数は少ない。
- **法律の判断ではない。** ライセンスは、使う前に原文と専門家で確かめる。

### 0.2 言葉の説明
| 言葉 | 意味 |
|---|---|
| ライセンス | データや作品を使ってよい条件。 |
| CC BY | 出典（作った人の名前など）を書けば、商用でも使ってよい。 |
| CC BY-SA（継承） | CC BY に加えて、手を加えた物を配るなら、同じ条件（誰でも使える形）で配る義務がある。 |
| CC BY-ND（改変禁止） | そのまま使うのは商用でもよい。訳したり書き換えたりした物は配れない。 |
| GPL / LGPL | プログラム向けの継承型のライセンス。配る時、中身を同じ条件で渡す義務がある。App Store の条件と合わないとされた例がある（§6）。 |
| APL | 台湾の Arphic 社のフォントのライセンス。商用可。手を加えた物は誰でも手に入るようにする義務。 |
| OGDL（政府資料開放授權條款） | 台湾政府のオープンデータの条件。決まった形で出典を書けば使える。CC BY 4.0 と互換。 |
| OCR | 写真の中の文字を機械が読み取る技術。 |
| 筆順データ | 字の一画ずつの形と順番。筆順のアニメを作るのに要る。 |
| 部首・部件 | 部首は辞書で字を並べる時の代表の部品。部件は字を作る部品全般（鍊 = 金 + 柬）。 |
| IDS | 漢字を部品の組み合わせで書く記法（好 = ⿰女子）。 |
| 変調 | 隣の声調で声調が変わる規則（你好 nǐhǎo → níhǎo）。 |
| 量詞・助数詞 | 数える時に付ける語（一條手鍊 の 條、鉛筆一本 の 本）。 |
| ピッチアクセント | 日本語の語の中の音の高低（箸 と 橋 の違い）。 |
| IPA | 国際音声記号。どの言語の音も同じ記号で書く。 |
| CEFR | ヨーロッパの語学の段階。A1〜C2 の6段階。 |
| コロケーション | よく一緒に使う語の組み合わせ（CatchWords の「使い方チャンク」に近い）。 |
| 文法上の性 | スペイン語の名詞は男性か女性に分かれ、冠詞（el / la）が変わる。 |
| 間隔反復（SRS） | 忘れそうな頃に復習を出す仕組み。 |

### 0.3 分類の意味
- **移す**: 乗り換える人が「無いと困る」物。今の頁に在る物は「移す（済）」。
- **検討**: 役に立つが、データ・費用・オーナーの決定のどれかが要る。
- **移さない**: CatchWords の使い方に合わない、またはオーナーの決定と合わない。

### 0.4 前提（CatchWords の今）
- 単語はすべて名詞（オーナー 2026-10-20「このアプリ内の単語はすべて名詞だから」）。動詞の活用・句動詞などは要らない。
- 今の単語の頁の項目（`docs/word-detail-design.md`）: 写真 / 見出し語（読み・発音）/ 意味 / 使い方チャンク / 例文 /
  量詞 / 類義語・反義語・関連語 / 台湾メモ / 実際の使われ方（YouTube・Google・Threads・Dcard・YouGlish・教育部の辞書へのリンク）/
  復習モード・文字の大きさ・発音の速さ。撮った語は自動で復習（4択と忘却曲線）に入る。
- 合わせる決定: 品詞は出さない（10-20）。語の TOCFL の級は出さない（10-25）。言語を混ぜない（10-20、`docs/language-rules.md`）。
  チャンクの「場面の一言」は出さない（10-24）。発音は合成音声。

---

## 1. まとめ

### 1.1 学習言語ごとの「移す」物（辞書の土台）
| 学習言語 | 今の頁に在る（済） | 足す候補（移す） |
|---|---|---|
| 台湾華語 | 台湾の読み（注音・ピンイン）、発音、意味、例文、量詞、類義語、台湾メモ、復習 | **字ごとの意味**（Pleco の CHARS）、**図鑑の中の同じ字の語**（Pleco の WORDS を自分の語で） |
| 日本語（将来） | 同じ形が使える | かなの読み、漢字ごとの意味と読み（音・訓）、**ふつうの書き方（漢字・ひらがな・カタカナ）**、助数詞 |
| 英語（将来） | 同じ形が使える | IPA と英米の音声、**数えられるか（可算・不可算）と複数形**、英米の言い方の違い |
| スペイン語（将来） | 同じ形が使える | **性（el / la）と複数形**、**国・地域の印**、スペインと中南米の発音 |

### 1.2 AI だけが足せる項目（一番すすめる物）
- 台湾華語: 「字の組み合わせのわけ」「大陸ではこう言う・こう読む」「この写真ならどの語か」
- 日本語: 「漢字のわけと、ここでの読み」「ふつうはどう書くか」「助数詞のわけ」
- 英語: 「この物は数えられるか（a / 無し）」「カタカナ語との違い」「英米の違い」
- スペイン語: 「性のわけと例外」「国ごとの言い方」

どれも、**事実（読み・性・量詞の候補・地域の印）はデータから、AI は説明だけ**にする。今のサーバも、読みは辞書で決め、
AI を呼ばない（`server/src/lib/sentence-readings.server.ts`）。同じ考え方で作る。

### 1.3 データ源
- **商用に使える（条件つき）**: Unihan（ほぼ自由）、CC-CEDICT（継承）、教育部の辞書（改変禁止）、全字庫（出典の表記）、
  Make Me a Hanzi / Hanzi Writer（APL・LGPL）、KanjiVG（継承）、JMdict・KANJIDIC2（継承＋EDRDG の条件）、
  Tatoeba の文（CC BY）、Wiktionary（継承）、Kanjium（継承）。
- **使わない方がよい**: 教育部の筆順學習網（g0v の写しに「商用不可」とある。公式のページは未読）、
  CJKVI IDS・CHISE（GPL。アプリに入れて配ると App Store と衝突のおそれ）、各社の辞書の中身（Pleco・Outlier・NHK・Oxford など、独自の物）。

### 1.4 分かったこと（要注意）
- **台湾の標準の筆順で、商用に使えるアニメのデータは見つからなかった。** Make Me a Hanzi と Hanzi Writer は大陸の筆順。
- **CC-CEDICT の量詞はごく一部。** 2023-11-07 版の 122,143 語のうち、量詞（CL:）が書いてあるのは 1,751 語。
  保溫瓶・枕頭・衛生紙・鍋子・手環・指甲剪 には無い。手鍊 は語自体が無い【原文: データを数えた】。
- **CC-CEDICT の台湾の読みの印（Taiwan pr.）は 468 語だけ**【原文】。台湾の読みは今どおり教育部の辞書で検める。
- サーバは教育部《重編國語辭典修訂本》の読みを使っている（`server/src/lib/tw-reading.server.ts`）。教育部の辞書の
  ライセンスは出典の表記が条件。**iOS のコードを「教育部」「CC BY」で探した範囲では、アプリの中の出典の表記は
  見つからなかった**（リンクの名前だけ）。読みは事実なので表記が要らない可能性もある。【未確認】、確かめた方がよい。

---

## 2. 台湾華語（zh-TW）

### 2.1 学習者がよく使う辞書
| 辞書 | 種類 | 無料・有料 | よく使われる根拠 |
|---|---|---|---|
| Pleco | iOS / Android アプリ | 本体は無料、追加は有料 | Google Play で約 670 万インストール・評価 4.4 万件（第三者の推計）[Z22]。中国語学習の定番として紹介が多い [Z13][Z14][Z23] |
| 萌典（moedict） | Web・アプリ（教育部の辞書を見やすくした物） | 無料 | 「台湾で中国語を学ぶ人には、中級からは一番の辞書」（英語の無い見出しが多い）[Z23]。「古い・本の言葉」という声もある [Z27] |
| 教育部《重編國語辭典修訂本》《國語辭典簡編本》 | Web（中国語だけ） | 無料 | 台湾の標準の読み（注音）と用法の公式の辞書 [Z24]。簡編本は注音・ピンイン・音声つき（検索の要約。出典のページは特定できず）|
| Hanping | Android の定番、iOS 版も出た | 本体は無料、追加は有料 | 台湾寄りの読みのために Pleco から移った人の声 [Z25]。iOS 版は注音で引ける [Z26] |
| MDBG | Web | 無料 | CC-CEDICT をそのまま引く辞書 [Z28] |
| Google 翻訳 | 翻訳 | 無料 | 台湾の学習者がどれだけ使うかの数は見つからなかった【未確認】 |
| Dr.eye（譯典通） | 台湾の辞書アプリ | — | 台湾の音声・注音つきとして名前が出る [Z25]（詳しく調べていない） |
| LINE 辞書・Yabla | — | — | 台湾華語の学習者が使う根拠は見つからなかった【未確認】 |

よく見る組み合わせ: **Pleco で英語の訳を引き、台湾の読みと用法は 萌典 / 教育部の辞書で確かめる** [Z23][Z25]。

### 2.2 Pleco の機能（無料と有料）
| 機能 | 無料 / 有料 | よく使われるか（根拠） | 分類 | 理由 |
|---|---|---|---|---|
| 辞書本体（CC-CEDICT と Pleco の PLC。約 13 万語、例文 約 2 万） | 無料 [Z3] | 最もよく使う | 移す（済） | 意味・例文は今の頁に在る |
| 追加の辞書（ABC・Oxford など） | 有料 [Z1] | 専門の辞書は普通の学習者には要らない [Z14] | 移さない | 中身は各社の物。AI の意味で足りる |
| ピンイン / 注音の表示 | 無料 [Z8] | 台湾の学習者は注音が要る [Z23] | 移す（済） | 設定で切り替え済み |
| 繁体字 / 簡体字の切り替え | 無料 [Z8] | 両方を出す設定がある [Z8] | 検討 | 簡体字で習った人に「簡体字: 手链」を1行。サーバに OpenCC（字の変換の部品）が在る |
| CHARS（語を字に分け、字ごとの意味・部首・部件） | 無料 [Z3][Z5] | 定義の画面の基本のタブ [Z3] | **移す（新）** | §2.5。字の分解は語彙の学習の鍵という研究 [Z34] |
| WORDS（その字で始まる語・含む語。含む語は頻度順） | 無料 [Z4] | 基本のタブ [Z4] | **移す（形を変える）** | 辞書の全語でなく、**自分の図鑑の中の同じ字の語**にする |
| SENTS（その語を含む例文） | 無料 [Z3] | 基本のタブ | 移す（済） | 例文はチャンクごとに在る |
| 量詞（MW） | 無料（辞書に書いてある範囲）[Z19] | 量詞は「難しいより覚えるのが面倒」[Z30] | 移す（済） | CC-CEDICT の量詞は 1,751 語だけ（§1.4）。今は AI＋検め |
| 筆順アニメ | 500 字は無料、約 2.8 万字は $4.99 [Z1] | 繁体字も大陸の筆順 [Z18]。E-Stroke に移る人もいる [Z18] | 検討 | 台湾の標準で商用に使えるデータが無い（§6） |
| 手書き入力 | 基本は無料、高精度の全画面は $9.99 [Z1] | 崩れた字も読めると好評 [Z1] | 移さない | CatchWords は写真から語が出る。字を書いて引く場面が無い |
| OCR（カメラで字を読む） | $9.99 [Z1][Z7] | 「有料で一番役立つ」という評 [Z15]（信頼度は低い） | 移さない | 単語の頁の機能ではない。看板の字を撮る使い方は別の機能として検討の余地 |
| 文章リーダー（クリップボードの文を引く） | 有料（Basic Bundle に入る）[Z2] | 毎日使う人がいる [Z16] | 移さない | 単語帳の範囲の外 |
| 単語カード（復習） | 高機能は $9.99 [Z1]。基本の無料版は Android の説明書で確認、iOS は【未確認】[Z11] | 「一番大事な追加」[Z13]。Anki（復習アプリ）を使う人も多い [Z17] | 移す（済） | 撮った語は自動で復習に入る |
| 音声 | 端末の合成音声は無料。人の録音 男・女 各 $4.99（約 3.4 万語）、合成の声 約 $9.99（台湾の声 Yafang あり）[Z9][Z10] | よく使う | 移す（済） | 合成音声。人の録音は費用がかかる |
| 字源（Outlier の辞書） | 有料（Expert $59.99）[Z12] | 字が好きな人向け | 移さない | AI に字の古い成り立ちを書かせると間違えやすい。正しいデータは独自の物 |
| 台湾の辞書（教育部）を入れる | 無し | 教育部などに断られたと開発者 [Z21] | — | Pleco の弱い所。CatchWords は教育部の読みを使っている |
| まとめ買い | Basic $29.99 / Professional $59.99 [Z1] | — | — | 参考 |

### 2.3 辞書をまたいだ機能の表
| 機能 | ある辞書 | 学習者の頼り具合（根拠） | 分類 | 理由 |
|---|---|---|---|---|
| 台湾の読み（注音・ピンイン） | Pleco・萌典・教育部・Hanping | 高い。台湾の読みのために教育部・萌典・Hanping を使う [Z23][Z25] | 移す（済） | 教育部の読みで検めている |
| 発音の音声 | Pleco・教育部 簡編本・Hanping | 高い | 移す（済） | — |
| 意味（訳） | 全部 | 最も高い | 移す（済） | 読む人の言語で出す |
| 例文 | Pleco・教育部・萌典 | 高い | 移す（済） | — |
| 量詞 | Pleco・CC-CEDICT（一部） | 悩みが大きい [Z30] | 移す（済） | — |
| 字ごとの意味 | Pleco（CHARS） | 中。研究は分解を重視 [Z34] | **移す（新）** | §2.5 |
| 部首・部件 | Pleco・萌典・教育部 | 中 | 検討 | 字ごとの意味の中に1行。部首は Unihan、部件は Make Me a Hanzi（LGPL）。IDS は GPL なので避ける |
| その字を含む語 | Pleco（WORDS） | 中 | **移す（形を変える）** | 自分の図鑑の中で |
| 筆順アニメ | Pleco（500 字無料）・Hanping（839 字無料）[Z26]・教育部 筆順學習網（4,808 字、台湾の標準）[Z38] | 中 | 検討 | §6。台湾の標準で商用可のアニメのデータが無い |
| 変調の印（一・不・3声の連続） | 調べた辞書では確かめられず【未確認】 | 声調は最大の悩みの1つ [Z30] | 検討 | 規則で決まるので AI は要らない |
| 国語辞典の定義（中国語だけ） | 教育部・萌典 | 中級以上で高い [Z23] | 移さない（リンクは済） | 改変禁止のライセンスで訳せない（§6）。読む人の言語で出す決まりにも合わない |
| 台湾と大陸の違いの印 | CC-CEDICT の「(Tw)」「Taiwan pr.」（468 語）、Pleco は弱い [Z20] | 悩みが大きい [Z20] | **移す（AI で）** | §2.5 の AI 項目 |
| 繁体字 / 簡体字 | Pleco・MDBG | 中 | 検討 | 1行だけ |
| 手書き入力・OCR・リーダー | Pleco・Hanping | 中〜高 | 移さない | 単語の頁の機能ではない |
| 文の機械翻訳 | Google 翻訳 | 不明 | 移さない | — |

### 2.4 辞書では解けない悩み
1. **声調（特に2声と3声）と聞き分け**: r/ChineseLanguage では2声と3声の区別が一番難しいという声が多い（ブログの要約）[Z30]。
   辞書は声調の記号を出すが、変調した後の音は出さない物が多い【未確認】。
2. **量詞**: 「難しいより覚えるのが面倒」[Z30]。CC-CEDICT の量詞はごく一部（§1.4）。辞書は「なぜその量詞か」を書かない。
3. **台湾と大陸の違い**: Pleco は大陸の用法に寄り、台湾の用法を調べにくいという声 [Z20]。違いは主に語（同じ物に違う名前、
   同じ名前で違う物）[Z32]。例: 腳踏車（台湾）/ 自行車、計程車（台湾）/ 出租車、**土豆 は大陸で じゃがいも、台湾で 落花生**
   （CC-CEDICT）[L1]。読みの違いは語の約 3%（主に声調）[Z31]。例: 和（と）は台湾で hàn、垃圾 は台湾で lèsè（CC-CEDICT の Taiwan pr.）[L1]。
4. **近い意味の語の使い分け**: 学習者の誤りは、文の形が同じで意味が少し違う組で多い。違いをはっきり教えると良くなった [Z33]。
5. **母語の漢字との違い（日本語・韓国語の話者）**: 日中で形が同じで意味が違う語は、学習者が母語の意味で取る傾向がある
   （日中同形語の研究の要約）[Z35]。例: 手紙 は中国語で トイレットペーパー、大丈夫 は 立派な男（CC-CEDICT）[L1]。
6. **字の意味が分からない**: 中国語の語の 75〜80% は2字以上の組み合わせ [Z34]。語を字に分けて考える力が要の1つ [Z34]。
   Pleco は字ごとの意味を並べるが、「なぜその組み合わせでその意味か」は書かない。
7. **筆順が台湾と大陸で違う字がある**: Make Me a Hanzi は大陸の筆順で、台湾・日本では違う字があると明記 [L6]。
   Pleco の繁体字も大陸の筆順 [Z18]。

### 2.5 単語の頁の土台（提案）
**辞書の土台（この順）**
1. 写真（済）— CatchWords だけの物。
2. 見出し語・台湾の読み（注音 / ピンイン）・発音（済）— どの辞書にもある一番の基本。読みは教育部で検める。
3. 意味（済）— 読む人の言語で。
4. **字ごとの意味（新）** — Pleco の CHARS に当たる。字・台湾の読み・字の意味（1〜3語）・部首。乗り換える人が毎回見る所。
   読みは教育部、部首と画数は Unihan、字の意味は AI が読む人の言語で書き、Unihan の英語の意味で外れを検める。
5. 量詞（済）。
6. 使い方チャンク（済）— 辞書の「コロケーション」に当たる。
7. 例文（済）。
8. 類義語・反義語・関連語（済）。
9. 台湾メモ（済）— 下の「大陸では」をここに入れてもよい。
10. 実際の使われ方（済）。
11. **図鑑の中の同じ字の語（新、AI でない）** — Pleco の WORDS を、自分が撮った語だけで。「鍊 → 項鍊（3日前に撮った）」。
    写真の単語帳だけができる。
12. 筆順（検討）— データ待ち（§6）。

**AI だけの項目（辞書に無い）**
- **A. 字の組み合わせのわけ** — 例: 手鍊 = 手 ＋ 鍊（くさり）→ 手首に付ける鎖。Pleco は字を並べるだけで、わけを書かない。
  研究は分解の力を重視 [Z34]。字の意味は Unihan・教育部と照らし、合わない物は出さない。字の古い成り立ち（字源）は書かない。
- **B. 大陸ではこう言う・こう読む** — 例: 「大陸では 自行車」「土豆 は台湾では 落花生」。Pleco から乗り換える人は大陸の語で
  習っていることが多い [Z20]。CC-CEDICT の (Tw)・Taiwan pr. と教育部の読みで検める。台湾メモの1行にできる。
- **C. この写真ならどの語か** — 例: 杯子 / 馬克杯 / 玻璃杯 のどれがこの物か、なぜか。近い語の使い分けは誤りが多い [Z33]。
  写真を見て答える辞書は無い。今の「類義語」の解説を、写真に結びつける形。
- **D. 量詞のわけ** — 例: 條 は細長い物。ほかに言える量詞との違い（一串）。量詞は辞書に少なく（§1.4）、わけも書かれない。
  量詞の候補は辞書（CC-CEDICT の CL:、在れば）と照らす。
- **E. あなたの母語の人が間違えやすい所** — 表示言語ごと。例（日本語の読み手）: 手紙 は中国語では トイレットペーパー。
  母語の意味で取る誤りは研究で知られている [Z35]。CC-CEDICT の訳と照らせば外れが少ない。

---

## 3. 日本語（ja、将来の学習言語）

### 3.1 学習者がよく使う辞書
| 辞書 | 種類 | 無料・有料 | よく使われる根拠 |
|---|---|---|---|
| imiwa? | iOS アプリ | 無料、全部使える [J1] | 「iPhone の無料の日本語辞書で一番」[J2] |
| Takoboto | Android の定番、iOS 版は 2025 年3月から [J5] | — | 「総合で一番」という紹介 [J4] |
| Shirabe Jisho | iOS アプリ | 無料 [J3] | 活用表・JLPT の語の表がある [J4] |
| Japanese（Renzo Inc.） | iOS アプリ | — | 評価 約 3,400 件・4.8 [J8] |
| Nihongo | iOS アプリ | 一部有料（写真で引く・ピッチアクセント $9.99）[J9] | 辞書・単語カード・読む助け [J9] |
| Jisho.org | Web | 無料 | JMdict・Tatoeba・KanjiVG を使う [J7]。アプリが無い人が Web で使う [J4] |
| Yomitan（Yomichan の後継） | ブラウザの拡張 | 無料 | 文の上の語を指すと意味が出る。ピッチ・頻度・Anki への書き出し [J10]（iPhone では使えない） |
| Akebi | Android | — | 最終更新 2021 年5月 [J6] |
| Weblio | Web・アプリ（日本人向け） | 無料 | 563 の辞書をまとめて引く、月 約3億ページ表示（2019、第三者の記事）[J11] |
| NHK 日本語発音アクセント辞典・OJAD | 本・アプリ / Web | NHK は有料、OJAD は無料 | ピッチの基準は NHK [J13]。OJAD は名詞 9,000 語以上 [J13] |

国立国語研究所などの調査では、世界の日本語学習者 110 人の画面の録画から、**多くがスマホの辞書アプリや Web の辞書を使う**
ことが示された。中国語の話者でも、漢字の語の意味の推測は簡単とは限らない [J12]。

### 3.2 機能の表
| 機能 | ある辞書 | 学習者の頼り具合（根拠） | 分類 | 理由 |
|---|---|---|---|---|
| かなの読み（ふりがな） | 全部 | 最も高い | 移す | 台湾華語の注音と同じ場所 |
| 意味（多言語） | imiwa（英・仏・独・露）[J1]、JMdict | 高い | 移す | 読む人の言語で |
| 例文（Tatoeba） | imiwa（約 25 万文、語を押すと引ける）[J1]、Jisho [J7] | 高い | 移す（済の形） | チャンクの例文で |
| 漢字ごとの意味・音読み・訓読み | imiwa（13,108 字）[J1]、Jisho、Akebi [J6] | 高い | **移す** | 漢字の読みの迷いに直結 |
| 筆順アニメ | imiwa（KanjiVG、6,702 字）[J1]、Akebi [J6] | 中 | 検討 | KanjiVG は商用可（継承）[L8] |
| 手書き・部首で引く | imiwa、Shirabe [J3]、Akebi | 中 | 移さない | 写真から語が出る |
| ピッチアクセント | imiwa（140,513 語）[J1]、Shirabe（1.9.6 から）[J3]、Nihongo（有料）[J9]、Yomitan（辞書を足すと）[J10] | 上級ほど高い [J13] | 検討 | データの元が問題（§6、Kanjium） |
| ふつう仮名で書く（uk の印） | JMdict の印 [J15] → Jisho・imiwa | 中。ただし印だけでは足りない [J14] | **移す** | 名詞の書き方の迷いに直結 |
| JLPT の級 | imiwa・Shirabe [J4]・Jisho | 中 | 移さない | 2010 年から公式の語の表は無い [J17]。オーナーは TOCFL の級を消した |
| 活用表 | imiwa・Shirabe [J4] | 動詞で高い | 移さない | 名詞だけ |
| 頻度 | Yomitan（頻度の辞書を足すと）[J10] | 中 | 検討 | — |
| 写真の字を読む（OCR） | Nihongo（有料）[J9] | 中 | 移さない | — |
| 単語カード・Anki | Japanese [J8]・Yomitan [J10] | 高い | 移す（済） | — |
| 助数詞 | 項目として持つ辞書は確かめられず【未確認】。多くの辞書は数え方の音の変化を書かない [J16] | 悩みが大きい [J16] | **移す（AI で）** | §3.4 |
| 国語辞典（日本語だけ） | Weblio [J11] | 日本人向け | 移さない | — |

### 3.3 辞書では解けない悩み
1. **漢字の読みが1つでない**: 同じ字で音読み・訓読みが変わる。中国語の話者でも漢字の語は推測しにくい [J12]。
   辞書は読みを並べるが、「この語でなぜその読みか」は書かない。
2. **仮名か漢字か**: 「ふつう仮名で書く」の印は出発点にすぎない。「両方よく使う」と「今はほぼ漢字で書かない」を分けない [J14]。
3. **助数詞**: 形・大きさで決まるが例外がある（チーズの1枚は「切れ」）[J16]。一杯 ippai・二杯 nihai のように音も変わり、
   多くの辞書は書かない [J16]。
4. **ピッチアクセント**: 基準は NHK の辞書だが日本語だけ [J13]。アプリによって有る無しが違う（§3.2）。
5. **母語の漢字との違い（中国語の話者）**: 日中同形語は、上級でも母語の意味で取る傾向 [Z35]。
6. 丁寧さ（お茶・ご飯 の「お・ご」）: 名詞にも関わるが、学習者の声の根拠は今回探していない【未確認】。

### 3.4 単語の頁の土台（提案）
**辞書の土台**
1. 写真。
2. 見出し語（ふつうの書き方）・かなの読み・発音。
3. 意味。
4. **漢字ごとの意味と、この語での読み（音・訓）** — 台湾華語の「字ごとの意味」と同じ部品。データは KANJIDIC2・Unihan。
5. **ふつうの書き方** — 漢字・ひらがな・カタカナのどれが普通か。JMdict の uk の印を出発点に。
6. 助数詞。
7. 使い方チャンク・例文・類義語（台湾華語と同じ）。
8. ピッチアクセント（検討、データ次第）。
9. 筆順（検討、KanjiVG）。

**AI だけの項目**
- **A. 漢字のわけと、ここでの読み** — 例: 自転車 = 自（自分で）＋ 転（ころがる）＋ 車。読みの迷いは辞書で解けない [J12]。
  読みは辞書の読みの中からだけ選ばせる。
- **B. ふつうはどう書くか** — 例: 「りんご」は日常はひらがな・カタカナが多く、林檎 は本や店の名で見る。uk の印だけでは
  分からない差を説明する [J14]。
- **C. 助数詞のわけ** — 例: 傘 は「本」（細長い）。数の音の変わり方（一本 ippon・三本 sanbon）は規則で出す（AI でなく）[J16]。
- **D. 同じ音の語に注意** — 例: 箸 と 橋。ピッチの違いはデータが在る時だけ出す（AI に作らせない）。
- **E. 中国語の話者が間違えやすい所** — 例: 日本語の 手紙 は 手紙（letter）で、中国語の 手紙 と違う。表示言語が台湾華語の時に。

---

## 4. 英語（en、将来の学習言語）

### 4.1 学習者がよく使う辞書
| 辞書 | 種類 | 無料・有料 | よく使われる根拠 |
|---|---|---|---|
| Oxford Learner's Dictionaries | 学習者向けの英英 | Web は無料 | 「多くの学習者に総合で一番」（第三者のまとめ）[E7] |
| Cambridge Dictionary | 学習者向けの英英 | 無料 | 「英米の音声つきで無料の一番」[E7] |
| Longman（LDOCE） | 学習者向けの英英 | Web は無料 | 例文が一番多い、話し言葉と書き言葉の頻度 [E7][E6] |
| Merriam-Webster | 米国の辞書 | 無料 | 米国の英語を学ぶ人向け [E7] |
| YouGlish | YouTube の中の発音 | 無料 | CatchWords が既にリンク（済） |
| Ludwig | 文の検索 | 一部有料 | 信頼できる出典の文を何億も検索 [E8] |
| 英辞郎 on the WEB・Weblio 英和 | 日本人向けの英和 | 無料 | 英辞郎は英和 233 万項目以上 [E9]。**日本人の学習者がどれをどれだけ使うかの調査は見つからなかった**【未確認】 |

Web 版の時、英語の語には ECDICT（意味・活用・頻度）・CMUdict（米国の発音）・CEFR-J（級、商用可）を使っていた
（`server/src/lib/i18n.tsx` の出典の文）。ECDICT と CMUdict のライセンスは今回確かめていない【未確認】。

### 4.2 機能の表
| 機能 | ある辞書 | 学習者の頼り具合（根拠） | 分類 | 理由 |
|---|---|---|---|---|
| 発音記号（IPA） | Oxford・Cambridge・Longman・MW | 高い | **移す** | 綴りと音がずれる言語 |
| 英米の音声 | Oxford [E4]・Cambridge [E7] | 高い | **移す** | 合成音声で英米の2つの声 |
| 意味（英英・英和） | 全部 | 最も高い | 移す | 読む人の言語で |
| CEFR の級（意味ごと） | Oxford（3000/5000、意味ごと）[E1]・Cambridge（A1〜B2）[E5] | 中 | 移さない | オーナーが TOCFL の級を消した決定と同じ扱い |
| 頻度の印（S1/W1） | Longman [E6] | 中 | 検討 | 級でなく「よく使うか」なら決定と衝突しないか、オーナーに確かめる |
| 数えられるか・複数形 | Oxford・Cambridge・Longman（[C]/[U] の印）【未確認: 印の形は確かめていない】 | 高い。冠詞の誤りの主な原因は数えられるかの誤解 [E10] | **移す** | 名詞だけのアプリでも一番効く |
| コロケーション | Oxford の共起語辞典 [E2]・Longman [E6]・Ludwig [E8] | 高い。学習者は動詞と組み合わせを混ぜる [E10] | 移す（済） | 使い方チャンク |
| 例文（多い） | Longman [E7]・Oxford の追加の例文 [E3] | 高い | 移す（済） | — |
| 類語 | Cambridge の SMART thesaurus [E5] | 中 | 移す（済） | 類義語 |
| 英米の言い方の違い | Oxford の英米の注 [E4] | 中 | **移す** | 台湾メモと同じ形のメモ |
| 語源 | Oxford の Word Origin [E3] | 低い | 移さない | — |
| 句動詞・動詞の形 | Oxford・Longman | 動詞で高い | 移さない | 名詞だけ |
| YouTube の中の発音 | YouGlish | 中 | 移す（済） | リンク |
| よくある間違い | Longman Dictionary of Common Errors（別の本）[E6]・Cambridge の誤りカード [E10] | 中 | **移す（AI で）** | §4.4 |

### 4.3 辞書では解けない悩み
1. **冠詞と数えられるか**: 中国語の話者の誤りの研究では、数えられるかの誤解が冠詞の誤りの主な原因 [E10]。
   辞書は [C]/[U] を書くが、「目の前のこの物を言う時 a か無しか」は書かない（glass と a glass）。
2. **コロケーション**: 動詞と組み合わせを混ぜる。母語からの持ち込みが原因の1つ [E10]。
3. **カタカナ語（日本語の話者）**: コンセント は英語で outlet、consent は「同意」[E11]。和製英語は通じない・誤解される [E11]。
4. **英米の違い**: 語も発音も違う（Oxford は英米の音声と注を持つ）[E4]。
5. 発音と綴りのずれ・強勢: 一般に知られる悩みだが、今回は根拠を探していない【未確認】。

### 4.4 単語の頁の土台（提案）
**辞書の土台**
1. 写真。
2. 見出し語・IPA・英米の発音。
3. 意味。
4. **数えられるか・複数形**（a cup / cups、furniture は数えない）。
5. 使い方チャンク・例文・類義語（済の形）。
6. **英米の違い**（メモ）。
7. 実際の使われ方（YouGlish、済）。

**AI だけの項目**
- **A. この物は数えられるか** — 写真の物で a を付けるか、どう数えるか（a glass of water / a glass）。冠詞の誤りの元 [E10]。
  可算・不可算の事実は辞書の印と照らす。
- **B. カタカナ語との違い** — 表示言語が日本語の時。例: コンセント → outlet（米）/ socket（英）[E11]。
- **C. 英米の違い** — 例: trash can（米）/ rubbish bin（英）。Oxford が注を持つ種類の情報 [E4]。

---

## 5. スペイン語（es、将来の学習言語）

### 5.1 学習者がよく使う辞書
| 辞書 | 種類 | 無料・有料 | よく使われる根拠 |
|---|---|---|---|
| SpanishDict | 西英の辞書・翻訳・活用 | 無料、プレミアムで広告なし [S3] | 2014 年に月 1,200 万人（新聞の報道）[S4]。初心者の定番 [S6] |
| WordReference | 多言語の辞書・フォーラム | 無料 | 中級以上の定番、ネイティブが答えるフォーラム [S6]。検索経由の訪問 月 約 1,000 万（2025-07、推計）[S6] |
| RAE（DLE） | スペイン語だけの辞書 | 無料 | スペイン語だけなので上級向け [S6]。地域の印を持つ [S7] |
| Linguee / DeepL | 対訳の用例検索 / 翻訳 | 無料（DeepL は一部有料） | 専門家の訳の文から用例 [S8] |
| Reverso Context | 対訳の用例 | 無料 | 字幕・Web の文で、くだけた言い方に強い [S8] |

よく見る組み合わせ: SpanishDict で基本の意味と活用、WordReference でニュアンス、上級で RAE [S6]。
（比べた記事の一部はアプリを売る会社の物 [S6]。）

### 5.2 機能の表
| 機能 | ある辞書 | 学習者の頼り具合（根拠） | 分類 | 理由 |
|---|---|---|---|---|
| 性（男性・女性）と冠詞 | WordReference（nf / nm）[S6]・SpanishDict・RAE | 最も高い | **移す** | 名詞の一番の事実 |
| 複数形 | 多くの辞書 | 高い | 移す | 短く |
| 意味（訳） | SpanishDict・WordReference | 最も高い | 移す | 読む人の言語で |
| 国・地域の印 | SpanishDict（緑の括弧で国名）[S1]・RAE [S7]・Merriam-Webster [S11] | 高い | **移す** | §5.3 |
| スペインと中南米の音声の切り替え | SpanishDict [S1] | 中 | 検討 | 合成音声で2つの声が要る |
| 発音の動画 | SpanishDict [S5] | 中 | 移さない | — |
| 活用表 | SpanishDict（音声・例文つき）[S2]・WordReference | 動詞で高い | 移さない | 名詞だけ |
| 例文 | SpanishDict・Reverso・Linguee [S8] | 高い | 移す（済） | — |
| フォーラム（ネイティブの答え） | WordReference [S6] | ニュアンスで高い | 移さない | AI の解説で答える |
| スペイン語だけの定義 | RAE | 上級 | 移さない | リンクは検討 |
| 翻訳 | DeepL | 高い | 移さない | — |

### 5.3 辞書では解けない悩み
1. **性の例外**: agua は女性だが単数で el を付ける（el agua fría）。mapa は男性、mano は女性 [S9]。
   radio は中南米で男性のこともある [S9]。辞書は性を書くが「なぜ例外か」は書かない。
2. **国ごとの言い方**: ストロー = pajita（スペイン）/ popote（メキシコ）/ pitillo（コロンビア・ベネズエラ）/ sorbete（アルゼンチン）、
   アボカド = aguacate / palta（アルゼンチン・チリ・ペルーなど）、バス = autobús / guagua（カリブ・カナリア）/ camión（メキシコ）[S10]。
   一つの語では通じない。
3. ser / estar・接続法・por / para: 動詞と文法の悩みで、名詞だけの頁では例文の中で出る時だけ。
4. 見た目の似た語（false friends）: よく知られる悩みだが、今回は根拠を確かめていない【未確認】。

### 5.4 単語の頁の土台（提案）
**辞書の土台**
1. 写真。
2. 見出し語（**el / la を付けて**）・発音。
3. 意味。
4. **性と複数形**。
5. **国・地域の印**（この語はどこで使うか）。
6. 使い方チャンク・例文・類義語（済の形）。

**AI だけの項目**
- **A. 性のわけと例外** — 例: el agua は女性の語（fría）。覚えるための一言。性の事実は辞書（Wiktionary・RAE）と照らす。
- **B. 国ごとの言い方** — 例: 「メキシコでは popote」。AI は地域の語を間違えやすいので、辞書の地域の印や Wiktionary と
  照らし、確かな物だけ出す [S1][S10]。

---

## 6. データ源とライセンス

| データ | 中身 | ライセンス | 義務 | 商用 | 注意・危うさ |
|---|---|---|---|---|---|
| **CC-CEDICT** [L1] | 中英の辞書。12.2 万語。大陸のピンイン、英語の訳、量詞（CL:、1,751 語）、(Tw)・Taiwan pr.（468 語） | CC BY-SA 4.0【原文: ファイルの頭】 | 出典（MDBG・CC-CEDICT）。手を加えて配るなら同じ条件 | 可 | 訳は英語だけ。読みは大陸寄り。**英語の訳を日本語の読み手にそのまま出すと言語が混ざる**。AI の検め（照合）に使うのが合う |
| **教育部《重編國語辭典修訂本》《國語辭典簡編本》** [L3] | 台湾の標準の読み（注音・ピンイン）、中国語の定義、例、部首 | CC BY-ND 3.0 台湾（教育部のページ）【検索】【原文: moedict-data の説明】 | 出典。**本文を変えない**（訳・要約は不可）。使用說明に従う | 可 | 教育部の解釈では「改変の制限は文字の本文。形式の変換やその後の利用は制限しない」[L3]。**定義を AI で訳して出すのは改変にあたるおそれ**。読み（事実）を検めに使うのは今どおり |
| **教育部 常用國字標準字體筆順學習網** [L4] | 台湾の標準の筆順（4,808 字）、アニメ | 著作権は教育部。g0v の写しに「商用不可」とある【原文: g0v の README】、公式のページは未読【未確認】 | — | **不可（とされる）** | 使わない。商用の許可は教育部に問い合わせが要る |
| **全字庫（CNS11643）** [L5] | 字形のフォント、属性（注音・倉頡・画数・部首・ピンイン・部件・**筆順**） | OGDL 台湾 1.0 か OFL 1.1 の一方を選ぶ【検索】 | 決まった形の出典の表記。怠ると最初から許可が無かった扱い [L5] | 可（CC BY 4.0 と互換）[L5] | 筆順は画の種類の並びで、アニメの形のデータではないと思われる【未確認】 |
| **Make Me a Hanzi** [L6] | 9,000 字以上の筆順の形（SVG）、部件（IDS）、字の種類（形声など）、部首、ピンイン、英語の短い意味 | 形のデータは APL、辞書のデータは LGPL 3.0 以上【原文】 | APL: 手を加えたら誰でも手に入るように、ライセンス文を残す。LGPL: 配る時の義務 | 可 | **筆順は大陸の標準**。台湾・日本では違う字があると明記 [L6] |
| **Hanzi Writer** [L7] | 筆順のアニメと書く練習の部品（Web の部品） | 部品は MIT、データは APL（Make Me a Hanzi から）【原文】 | APL の文を残す | 可 | 大陸の筆順。Web の部品なので iOS では Web の画面に入れるか作り直し |
| **KanjiVG** [L8] | 日本の漢字の筆順の形（SVG）、部品 | CC BY-SA 3.0【原文】 | 出典。手を加えたら同じ条件 | 可 | 日本の筆順（台湾華語には使えない） |
| **JMdict / KANJIDIC2**（EDRDG）[L9] | 日本語の語（多言語の訳、読み、uk の印など）、漢字（読み・意味・画数） | CC BY-SA 4.0 ＋ EDRDG の条件【検索】 | EDRDG の決まった形の出典。手を加えたら同じ条件 | 可 | KANJIDIC2 には特別の条件（SKIP 番号・頻度番号は別の権利者）【未確認: 原文未読】 |
| **Tatoeba** [L10] | 多言語の例文と訳 | 文は CC BY 2.0 FR（一部 CC0）。音声は投稿者ごと【検索】 | 作者の表記 | 文は可 | 文の質がばらつく。音声は1つずつ確かめる |
| **Wiktionary** [L11] | 意味・語源・発音・性・地域の語など | CC BY-SA 4.0 と GFDL の二重【検索】 | 出典。手を加えたら同じ条件 | 可 | 質がばらつく。スペイン語の性・地域の語の照合に使える |
| **Unihan**（Unicode）[L12] | 字ごとの読み（kMandarin は大陸・台湾の2つを持てる）、部首と画数、英語の短い意味、繁簡の対応 | Unicode License v3【検索】 | 著作権表示を残す。Unicode の名で宣伝しない | 可 | 一番安全。意味は英語で短い |
| **CJKVI IDS** [L13] | 字の部件の分解（IDS） | ids.txt は CHISE 由来（GPL 2.0 以上）、他も GPLv2【原文】 | GPL | 形の上は可 | **アプリに入れて配ると GPL の義務。GPL の部品が App Store から外された例（VLC、2011）**[L14]。サーバの中だけで使うか、避ける |
| **Kanjium** [L15] | ピッチアクセント（約 12.4 万語）、頻度など | CC BY-SA 4.0、決まった謝辞の文【原文】 | 出典と謝辞 | 可（README に商用可）| ピッチのデータの元が何かは書いていない【未確認】 |
| Pleco・Outlier・NHK・Oxford・Cambridge・Longman・SpanishDict・WordReference の中身 | — | 各社の物 | — | **不可** | 機能の考え方だけ参考にする |

**継承（SA）の注意**: AI が CC BY-SA のデータを書き換えて画面に出すと、その文が「手を加えた物」になるおそれがある。
辞書のデータは、AI の答えを**照らして外れを落とす**のに使い、画面に出すのは AI が書いた説明と、事実（読み・性など）だけにするのが
安全側【法律の判断ではない】。

---

## 7. AI の項目を確かに作るための決まり（全言語）
1. **事実はデータから**: 読み・量詞の候補・性・可算・地域の印・ピッチは、§6 のデータで決めるか照らす。今のサーバの例文の読みと同じ考え方
   （AI を呼ばない、`sentence-readings.server.ts`）。
2. **AI は説明だけ**: 「わけ」「使い分け」「間違えやすい所」を読む人の言語で短く。データと食い違う答えは出さない。
3. **字の古い成り立ち（字源）は AI に書かせない**: 正しいデータは独自の物（Outlier）で、AI は間違えやすい。
4. **写真を使う**: 「この写真ならどの語か」「この物は数えられるか」は写真を見る AI にしかできない。CatchWords の強み。
5. **言語を混ぜない**: CC-CEDICT の英語の訳、教育部の中国語の定義を、そのまま読み手に出さない（R23）。

---

## 8. 未確認・次に確かめること
- 教育部の筆順學習網の商用の可否（公式のページ、または教育部への問い合わせ）。
- 全字庫の筆順の属性の形（アニメに使えるか）。
- EDRDG の KANJIDIC2 の特別の条件の原文。Tatoeba の利用規約の原文。
- Kanjium のピッチのデータの元。
- CatchWords の中に、教育部の辞書の出典の表記が要るか、在るか。
- Pleco の iOS の単語カードの無料の範囲（Android の説明書では基本は無料 [Z11]、iOS は App Store に $9.99 の追加 [Z1]）。
- Pleco の全画面の手書きが有料の追加か設定かは、資料によって違う【未確認】。
- 日本人の英語学習者が使う辞書の割合の調査。
- 台湾の学習者の Google 翻訳・LINE 辞書の使い方。

---

## 出典

### CatchWords の中
- `docs/word-detail-design.md`（今の単語の頁）、`CLAUDE.md`（オーナーの決定）、`server/src/lib/tw-reading.server.ts`・
  `server/src/lib/sentence-readings.server.ts`（教育部の読み・AI を呼ばない読み）、`server/src/lib/i18n.tsx`（Web 版の出典の文）。

### 台湾華語（Z）
- Z1 Pleco（App Store、米国）: https://apps.apple.com/us/app/-/id341922306 【検索】
- Z2 Pleco のまとめ買い: https://www.pleco.com/products/pleco-for-iphone-ipad/pricing-bundles ・ https://test.pleco.com/products/pleco-for-iphone-ipad/pricing-bundles/ 【検索】
- Z3 Pleco 説明書（基本）: https://pleco.com/ipmanual/basictut.html 【検索】
- Z4 Pleco 説明書（辞書、Android）: https://android.pleco.com/manual/310/dict.html 【検索】
- Z5 Pleco 説明書（版の移行）: https://pleco.com/ipmanual/transition.html 【検索】
- Z6 Pleco 説明書（応用、STROKE タブ）: https://pleco.com/ipmanual/advtut.html 【検索】
- Z7 Pleco 説明書（OCR）: https://pleco.com/ipmanual/ocr.html 【検索】
- Z8 Pleco 説明書（設定）: https://pleco.com/ipmanual/settings.html 【検索】
- Z9 Pleco の店: https://store.pleco.com/products.php 【検索】
- Z10 Pleco フォーラム（合成の声）: https://plecoforums.com/goto/post?id=29720 【検索】
- Z11 Pleco 説明書（単語カード、Android）: https://android.pleco.com/manual/310/flash.html 【検索】
- Z12 Outlier（Expert）: https://www.outlier-linguistics.com/products/chinese-dictionary-expert 【検索】
- Z13 Chinese-forums（追加は買う価値があるか）: https://chinese-forums.com/forums/topic/30815-pleco-worth-paying-for-basicpro-add-on-bundles 【検索】
- Z14 LTL の Pleco の評: https://ltl-school.com/pleco/ 【検索】
- Z15 hsklord の Pleco の評（信頼度は低い）: https://hsklord.com/blog/pleco-review 【検索】
- Z16 Chinese-forums（クリップボードのリーダー）: https://chinese-forums.com/forums/topic/59086-more-pleco-telepathy 【検索】
- Z17 Pleco と Anki: https://plecoforums.com/goto/post?id=53307 ・ https://chinese-forums.com/forums/topic/61393-anki-for-flashcards-or-pleco 【検索】
- Z18 Pleco の筆順: https://www.plecoforums.com/threads/disappointed-with-the-stroke-order-add-on.3014/latest ・ https://plecoforums.com/goto/post?id=51450 【検索】
- Z19 Pleco の量詞: https://www.plecoforums.com/threads/measure-words.864 【検索】
- Z20 台湾の用法が分かる辞書（Pleco フォーラム）: https://www.plecoforums.com/threads/dictionaries-that-clearly-state-taiwans-mandarin-style.2495/ 【検索】
- Z21 教育部の辞書を Pleco に: https://chinese-forums.com/forums/topic/44627-taiwan-moe-dictionary-%E5%9C%8B%E8%AA%9E%E8%BE%AD%E5%85%B8-for-pleco 【検索】
- Z22 Pleco のインストール数（第三者）: https://appgoblin.info/apps/com.pleco.chinesesystem 【検索】
- Z23 Hacking Chinese（辞書 21）: https://www.hackingchinese.com/21-essential-dictionaries-and-corpora-for-learning-chinese/ 【検索】
- Z24 Hacking Chinese（教育部の辞書）: https://challenges.hackingchinese.com/resources/stories/45-jiao-yu-bu-guo-yu-tai-yu-ke-yu-ci-dian-min-jian-ban-taiwan-ministry-of-education-online-dictionary 【検索】
- Z25 Forumosa（Android の辞書）: https://tw.forumosa.com/t/the-best-chinese-dictionary-for-android/87357 【検索】
- Z26 Hanping（App Store）: https://apps.apple.com/us/app/hanping-chinese-dictionary/id6755623311 ・説明書 https://hanpingchinese-website.pages.dev/docs 【検索】。Make Me a Hanzi のアニメを使う（[L6] の README）【原文】
- Z27 Pleco フォーラム（繁体字の辞書）: https://plecoforums.com/threads/best-quality-relevance-for-daily-use-traditional-chinese-dictionaries.7427 【検索】
- Z28 MDBG・CC-CEDICT: https://www.mdbg.net/chinese/dictionary?page=cc-cedict ・ https://chinese-forums.com/forums/topic/47531-good-online-dictionary-with-classifiers-for-all-nouns 【検索】
- Z30 難しい所: https://goeastmandarin.com/post-what-is-the-hardest-part-of-learning-chinese-and-how-to-overcome-them/ ・ https://www.italki.com/en/blog/is-chinese-hard-to-learn ・ r/ChineseLanguage の写し https://redlib.cypherpunktools.com/r/ChineseLanguage/comments/1lgmy4x/hard_and_easier_parts_about_learning_chinese 【検索】
- Z31 台湾と大陸の読みの違い（約 3%）: https://toneoz.com/blog/?p=752 【検索】
- Z32 台湾と大陸の語の違い（論文）: https://atlantis-press.com/article/55915676.pdf 【検索】
- Z33 近い意味の語: https://scholars.cityu.edu.hk/en/studentTheses/a-study-on-l2-acquisition-of-chinese-near-synonyms/ ・ https://ah.lib.nccu.edu.tw/bitstream/140.119/120969/1/v14n2a4.pdf 【検索】
- Z34 語の形の知識と語彙: https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2021.736933/full ・ https://pmc.ncbi.nlm.nih.gov/articles/PMC8548468 【検索】
- Z35 日中同形語の誤用（研究の要約。どの論文の記述かは未確認）: https://ir.library.osaka-u.ac.jp/repo/ouka/all/3629/05-01.pdf ・ https://nagoya.repo.nii.ac.jp/record/25359/files/k12155_repository.pdf 【検索】
- Z38 教育部 筆順學習網: https://stroke-order.learningweb.moe.edu.tw/ 【検索】

### 日本語（J）
- J1 imiwa?: https://imiwaapp.com/features.html 【検索】
- J2 Team Japanese: https://teamjapanese.com/?p=232 【検索】
- J3 Shirabe Jisho: https://apps.apple.com/us/app/shirabe-jisho/id1005203380 【検索】
- J4 FluentU（日本語の辞書アプリ）: https://www.fluentu.com/blog/japanese/best-japanese-english-dictionary-app/ 【検索】
- J5 Takoboto（iOS）: https://apps.apple.com/app/id6743079369 ・ https://appgoblin.info/apps/6743079369 【検索】
- J6 Akebi: https://apps.appfollow.io/android/akebi-japanese-dictionary/com.craxic.akebifree?country=us 【検索】
- J7 Jisho.org: https://jisho.org/about 【検索】
- J8 Japanese（Renzo）: https://apps.apple.com/jp/app/japanese/id290664053 【検索】
- J9 Nihongo: https://apps.apple.com/us/app/-/id881697245 【検索】
- J10 Yomitan: https://addons.mozilla.org/en-US/firefox/addon/yomitan ・ https://learnjapanese.moe/yomichan 【検索】
- J11 Weblio: https://pedia.3rd-in.co.jp/wiki/weblio ・ https://apps.apple.com/jp/app/id705736935 【検索】
- J12 国立国語研究所ほか（学習者の辞書の使い方）: https://repository.ninjal.ac.jp/record/2000405/files/jjls_26_1_5.pdf 【検索】
- J13 OJAD: https://www.gavo.t.u-tokyo.ac.jp/ojad/eng/pages/home ・ https://tofugu.com/japanese-learning-resources-database/online-japanese-accent-dictionary 【検索】
- J14 仮名か漢字か: https://community.wanikani.com/t/vocabulary-in-the-real-world/28697 ・ https://jref.com/threads/when-studying-is-it-better-to-focus-on-kanji-form-of-words.57555/?amp=1 【検索】
- J15 JMdict の印（uk）: https://www.edrdg.org/wiki/index.php/Dictionary_Codes 【検索】
- J16 助数詞: https://talenthub.jp/blog/learn-japanese/irregular-japanese-counters/ ・ https://www.lingq.com/blog/japanese-counters/ 【検索】
- J17 JLPT の公式の語の表が無い: https://www.tanos.co.uk/jlpt/jlpt3 【検索】

### 英語（E）
- E1 Oxford 3000 / 5000・CEFR: https://www.oxfordlearnersdictionaries.com/about/wordlists/oxford3000-5000 ・ https://learningenglishwithoxford.oup.com/2021/02/17/how-to-online-learner-dictionaries 【検索】
- E2 Oxford の共起語: https://www.oxfordlearnersdictionaries.com/about/collocations/ 【検索】
- E3 Oxford の追加の例文・語源: https://teachingenglishwithoxford.oup.com/2023/07/24/getting-the-most-out-of-oxford-advanced-learners-dictionary/ 【検索】
- E4 Oxford の英米の音声・注: https://www.oxfordlearnersdictionaries.com/about/wordlists/ ・ https://www.oxfordlearnersdictionaries.com/about/usage_notes 【検索】
- E5 Cambridge の級・類語: https://dictionary-api.cambridge.org/index.php/blog/99-english-profile-levels ・ https://dictionary.cambridge.es/en/catalogue/dictionaries/monolingual/cld 【検索】
- E6 Longman の頻度の印・よくある間違いの本: https://is.muni.cz/el/sci/podzim2009/JAM01/um/Longman_Communication_3000.pdf ・ https://www.marcialpons.es/libros/longman-dictionary-of-common-errors/9780582237520/ 【検索】
- E7 学習者向け辞書の比べ（第三者）: https://learnenglish.life/resources/best-english-dictionaries-for-learners/ ・ https://www.antimoon.com/how/learners-dictionaries-review.htm 【検索】
- E8 Ludwig: https://ludwig.guru/blog/unveiling-ludwig-1-explore-the-power-of-search/ ・ https://lexicoblog.blogspot.com/2020/06/ludwig-guru-review.html 【検索】
- E9 英辞郎 on the WEB: https://apps.apple.com/jp/app/id365874160 【検索】
- E10 冠詞・数えられるか・組み合わせの誤り: https://pure.psu.edu/en/publications/chinese-efl-learners-misconceptions-of-noun-countability-and-arti/ ・ https://www.cambridge.org/elt/blog/wp-content/uploads/2020/03/in-Use-common-error-cards.pdf 【検索】
- E11 和製英語: https://repository.ninjal.ac.jp/record/2190/files/kk_ngkgk_021_05.pdf ・ https://englishhub.jp/news/japanese-english-7.html 【検索】

### スペイン語（S）
- S1 SpanishDict の地域の印・音声: https://help.spanishdict.com/article/105-what-type-of-spanish-does-spanishdict-use 【検索】
- S2 SpanishDict の活用: https://help.spanishdict.com/article/111-conjugation-features 【検索】
- S3 SpanishDict のプレミアム: https://help.spanishdict.com/article/181-what-is-included-with-a-premium-subscription 【検索】
- S4 SpanishDict の利用者数: https://en.wikipedia.org/wiki/SpanishDict 【検索】
- S5 SpanishDict（App Store）: https://apps.apple.com/app/id332510494 【検索】
- S6 WordReference ほかの比べ: https://apps.apple.com/us/app/id515127233 ・ https://medium.com/the-happy-linguist/how-to-use-wordreference-to-enhance-your-language-learning-37cdce782d08 ・ https://www.inklingo.app/blog/What-is-the-best-online-Spanish-dictionary---WordReference-vs.-SpanishDict-vs.-RAE- （アプリを売る会社の記事）・ https://ahrefstop.com/websites/wordreference.com 【検索】
- S7 RAE の地域の印（論文）: https://accedacris.ulpgc.es/bitstream/10553/130778/1/17_2_LYL49_CACERES.pdf 【検索】
- S8 Linguee・Reverso: https://www.inklingo.app/blog/What-s-the-best-dictionary-or-translation-app-for-Spanish-learners- ・ https://europeanpurpose.com/tool/linguee 【検索、信頼度は低い】
- S9 性の例外: https://www.italki.com/en/blog/spanish-nouns ・ https://preply.com/en/blog/spanish-nouns-complete-guide 【検索】
- S10 国ごとの言い方: https://blog.duolingo.com/spanish-dialects/ ・ https://www.speakinglatino.com/spanish-language-words-for-drinking-straw/ 【検索】
- S11 Merriam-Webster の西英の地域の印: https://www.merriam-webster.com/help/explanatory-notes/span-eng-usage 【検索】

### ライセンス（L）
- L1 CC-CEDICT: 2023-11-07 版のファイルの頭と中身（PyPI の pycccedict 1.2.0 に入っていた物）【原文】・ https://www.mdbg.net/chinese/dictionary?page=cc-cedict ・ https://creativecommons.org/licenses/by-sa/4.0/
- L3 教育部の辞書: https://depart.moe.edu.tw/ed2400/cp.aspx?n=D509C3C9F6F496FD 【検索】・ https://github.com/g0v/moedict-data （README）【原文】・ https://creativecommons.org/licenses/by-nd/3.0/tw/
- L4 教育部の筆順: https://github.com/g0v/zh-stroke-data （README の「資料來源 / Copyright」）【原文】
- L5 全字庫: https://data.gov.tw/dataset/5961 ・ https://data.gov.tw/license ・ https://spdx.org/licenses/OGDL-Taiwan-1.0.html 【検索】
- L6 Make Me a Hanzi: https://github.com/skishore/makemeahanzi （README・COPYING）【原文】
- L7 Hanzi Writer: https://github.com/chanind/hanzi-writer ・ https://github.com/chanind/hanzi-writer-data ・ https://raw.githubusercontent.com/chanind/hanzi-writer-data/master/ARPHICPL.TXT 【原文】
- L8 KanjiVG: https://github.com/KanjiVG/kanjivg （README・COPYING）【原文】
- L9 EDRDG: https://www.edrdg.org/edrdg/licence.html 【検索】
- L10 Tatoeba: https://en.wiki.tatoeba.org/articles/show/cc0-contributions ・ https://tatoeba.org/en/terms_of_use （未読）【検索】
- L11 Wiktionary: https://en.wiktionary.org/wiki/Wiktionary:Copyrights 【検索】
- L12 Unicode: https://www.unicode.org/terms_of_use.html ・ https://spdx.org/licenses/Unicode-3.0.html ・ https://www.unicode.org/review/pri483/feedback.html （kMandarin の2つの値）【検索】
- L13 CJKVI IDS: https://github.com/cjkvi/cjkvi-ids （README）【原文】・ CHISE https://gitlab.chise.org/CHISE/ids 【検索】
- L14 GPL と App Store（VLC）: https://www.engadget.com/2011-01-09-the-gpl-the-app-store-and-you.html 【検索】
- L15 Kanjium: https://github.com/mifunetoshiro/kanjium （README）【原文】
