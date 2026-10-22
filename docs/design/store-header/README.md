# App Store の製品ページのヘッダー動画（案 A「撮れば、ことばになる」）

製品ページの一番上（アイコンと名前の上）に出る横長の動画です。2026-10-05 に App Store に加わった枠で、
iOS 27・iPadOS 27 以降で表示されます。オーナーの指示（2026-10-22）「A案で。…日本語と英語のバージョン作って」。

| 版 | ファイル | 一言 | タグの意味 |
| --- | --- | --- | --- |
| 日本語（ページの主言語） | `header-ja.mp4` | 撮れば、中国語のことばに。 | マグカップ |
| 英語 | `header-en.mp4` | Snap it. Learn it in Chinese. | mug |

動画（各 約 11MB）はリポジトリに入れていない（2026-10-22 の push で GitHub が「容量が上限に近い」と警告したため）。下の手順でいつでも作り直せる。

タグの単語「馬克杯」（台湾華語のマグカップ）は学ぶ単語なので、どちらの版でも同じです。それ以外の文字は、版ごとに 1 つの言語だけです（`docs/language-rules.md`）。

## Apple の決まり（2026-10-22 に Apple のヘルプで確認）

| 項目 | 値 | この動画 |
| --- | --- | --- |
| 大きさ | 21:9、3840×1646 | 3840×1646 |
| コマ数 | 30fps か 60fps | 30fps |
| 長さ | 5〜30 秒 | 10 秒（切れ目なくループ） |
| 形式 | .mov・.m4v・.mp4 | .mp4（H.264） |
| 音 | 最初は消音。見る人がオンにできる | 音なし |
| 中身（審査基準 2.3.14） | アプリの機能かブランドの表現。価格・URL・©・確かめられない宣伝・他社のロゴは入れない。4+ | 机の上の 3D の場面と、アプリの撮影演出と同じ光のペン・タグ |

- 出典: [Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)、
  [App Review Guidelines 2.3.14](https://developer.apple.com/app-store/review/guidelines/)、
  [App Store asset best practices](https://developer.apple.com/app-store/asset-best-practices/)
- **セーフエリア**（どの端末・向きでも切れない真ん中）は Apple が数値を公開していません。第三者が Apple の型紙から読んだ値
  （横 1097〜2743、縦 493〜1154）に、マグカップ・本・タグ・一言を収めました。入れる前に App Store Connect のプレビューで、
  iPhone と iPad の縦・横を確かめてください。

## 動きの流れ（10 秒）

| 秒 | 動き |
| --- | --- |
| 0〜1.0 | 机の上のマグカップと図鑑の本。カメラがゆっくり横に揺れる（10 秒で 1 往復） |
| 1.0〜1.8 | 角だけの枠が真ん中に出て、マグカップへ移り、カチッと止まって青に（アプリの v10） |
| 1.8〜2.8 | 光のペンがマグカップの輪郭を一筆で描く |
| 2.95〜4.0 | タグ「● 馬克杯 / マグカップ」が弾んで出る。輪郭がゆっくり脈打つ |
| 4.0 | 白い縁が光り、マグカップのステッカーがはがれる（物は机に残る。アプリと同じ） |
| 4.1〜5.5 | 本の表紙が奥へ起き上がり、ステッカーが弧を描いて表紙の内側に貼り付く。小さい光がはじける |
| 5.9〜6.6 | 表紙が閉じる |
| 6.85〜9.6 | 一言が真ん中に出て、消える |
| 9.6〜10 | 最初と同じ静かな机 → 0 秒へ |

## 作り方（3 つの層）

1. **3D の骨格（Blender 5.2）** `scene.py` — 机・マグカップ・図鑑の本（アプリの `DexBook` と同じ青い布張り）・奥のぼけた小物・
   カメラの揺れ・表紙の開閉・ステッカーの飛び方。Cycles で 1920×823 に描き、重ねる時に 2 倍にする
   （3840 幅で描くとこの作業場所の CPU では 1 コマ 2 分＝300 コマで約 10 時間。1920 幅は 1 コマ約 30 秒）。
2. **材料** `prep.py` — マグカップだけの白い型から、毎コマの輪郭（光のペンが描く線）と、白い縁つきのステッカーを作る。
3. **動きの層** `motion/header.html` — 枠・光のペン・タグ・一言を 3840 幅でくっきり描く（アプリの演出のコード
   `docs/design/catch-concepts/film` と同じ値と書き方）。`motion/render.js` が 1 コマずつ描いて H.264 にする。

```sh
S=作業用のフォルダ; P=python   # bpy==5.2.* と opencv-python-headless を入れた Python
$P scene.py mask   $S/mask 960                 # マグカップの型（毎コマ）
$P scene.py mask   $S/m1920 1920 120 120       # ステッカー用の型
$P scene.py frame  $S/st 1920 120 48           # ステッカーの元の絵
$P scene.py points $S 1920                     # 表紙の上の位置（はじける光）
$P prep.py sticker $S/st/still0120.png $S/m1920/m0120.png $S/sticker.png
$P prep.py outlines $S/mask $S/outlines.json
$P scene.py main   $S/main 1920 24 0 299 $S/sticker.png   # 本番の絵（約 2.5 時間。途中で止めても続きから描く）
mkdir -p motion/data && cp $S/outlines.json $S/points.json motion/data/ && ln -sfn $S/main motion/frames
cd motion && python3 -m http.server 8766 --bind 127.0.0.1 &
node render.js ja header-ja.mp4 && node render.js en header-en.mp4   # 各 約 2 分
```

確認用: `http://127.0.0.1:8766/header.html?lang=ja&f=100&safe` で 100 コマ目を、セーフエリアの枠つきで描く。

## AI の画像（ElevenLabs）とモーション（Claude）について

- オーナーの案は「ElevenLabs で画像 → Blender で骨格 → Claude のモーション」。2026-10-22 は ElevenLabs が
  **無料プランの 1 日の画像の上限**で 1 枚も作れなかった（クレジットは使っていない）。そのため、机の木目と奥の壁は Blender の中で作った。
  `textures/desk.png`（机の木目、上から見た継ぎ目のない絵）と `textures/backdrop.png`（ぼけた部屋の壁）を置けば、`scene.py` がそれを使う。
- Claude Motion（Anthropic の動画の機能）はこのアカウントの Artifact の種類に無かった。同じ「コードで動きを書く」方式で、
  `motion/header.html` を書いた。

## App Store Connect に入れる

1. App Store Connect → アプリ → 「製品ページの情報」（Product Page Information）→「ヘッダーと検索結果」（Header and Search Results）。
2. 置き場所で「製品ページのヘッダー」を選び、言語を「日本語」にして `header-ja.mp4` を入れる。
3. 言語を「英語」に切り替えて `header-en.mp4` を入れる。
4. プレビューで、iPhone と iPad の縦・横で、タグと一言が切れていないか見る。
5. 審査に出す（次のバージョンの提出と一緒に、または製品ページの変更として）。
