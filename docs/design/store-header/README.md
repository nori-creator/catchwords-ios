# App Store の製品ページのヘッダー動画（v2: 実写・アプリの流れのまま）

製品ページの一番上（アイコンと名前の上）に出る横長の動画。2026-10-05 に App Store に加わった枠で、iOS 27・iPadOS 27 以降で出る。

- 2026-10-22 オーナー「A案で。…日本語と英語のバージョン作って」→ v1（Blender の机・マグカップ・本）。
- 2026-10-23 オーナー「もっとリアルな動画にして。あと本にものがはいるのよくわからない。このアプリのそんな場面ない。
  articarfts の v6.10 の動画参考にして1から作り直して」→ v2（このフォルダ。v1 は消した）。

| 版 | 画面の文字 | タグの意味・ことばの意味 |
| --- | --- | --- |
| 日本語 `header-ja.mp4` | 写真をスキャンしています／覚えたいことばをタップ／新しいことばをキャッチ！／飲み物 | タピオカミルクティー・バイク・黒板 |
| 英語 `header-en.mp4` | Scanning the photo／Tap a word to learn／New word caught!／Drinks | bubble milk tea・scooter・blackboard |

画面の文字はアプリの `strings.json` の訳と同じ。中国語（珍珠奶茶・機車・黑板と読みの注音、図鑑の品の名前）は学ぶ単語なので両方の版で同じ。
動画（各 約 15MB）はリポジトリに入れない（2026-10-22 に GitHub が「容量が上限に近い」と警告）。下の手順で作り直せる。

## 流れ（12 秒・切れ目なくループ）

アプリの演出の 2 つの動画（Artifact「キャッチ演出」の v10 と v6、コードは `docs/design/catch-concepts/film`）と同じ値・見た目。
画面が横長なので、配置だけ変えた。

| 秒 | 動き | もと |
| --- | --- | --- |
| 0〜0.8 | 台湾の街角の写真。カメラがゆっくりカップへ寄る | — |
| 0.8 | シャッター（白く光る）。画面の縁が青く光り、上に「写真をスキャンしています」 | v10 |
| 1.1〜1.9 | 角だけの枠が出て、カップへ移り、カチッと止まって青に | v10 |
| 1.9〜3.6 | 光のペンがカップ→バイク→黒板の輪郭を描く。名前が届く 3.2 秒からペンが追いつく（最大 4 倍） | v10 ⑧ |
| 3.3〜4.4 | タグ「珍珠奶茶」「機車」「黑板」（白いガラスのカプセル・青い点・意味・NEW）。上は「覚えたいことばをタップ」 | v10 |
| 4.75 | 珍珠奶茶のタグを押す | v6 |
| 5.0〜5.6 | 写真が白くとけてアプリの背景に。カップが写真から切り抜かれて浮かぶ。白い縁がつく | v6 |
| 6.2〜7.1 | 「珍珠奶茶」が 1 字ずつ（注音は字の右）、音のボタン、意味（オーナー 2026-10-23「珍珠奶茶にして。珍奶ではなく」） | v6 |
| 6.9 | 「新しいことばをキャッチ！」、NEW・No.001 · 飲み物、ステッカーに虹色の光 | v6 |
| 8.6〜9.6 | 図鑑の「飲み物」のカード。ステッカーが No.001 の枠へ飛んで入り、NEW、6/19 → 7/19 | v6 |
| 11.0〜11.9 | 写真に戻る → 0 秒へ | — |

v6 の「覚える言い方を選ぶ」（3 つの言い方の一覧）は、ヘッダーでは細かすぎるので入れていない（タグを押すと、そのまま珍珠奶茶で入る）。
植木鉢は葉が背景のぼけと混ざって切り抜けないので、光のペンが描くのは 3 つ（アプリの v10 の動画と同じ数）。

## 写真

`assets/photo_src.jpg`（1916×821）はオーナーが ChatGPT で作った日中の写真（2026-10-23。前の夕方の写真は「夕暮れどきっぽくて見づらい。V６．１０のような光にして、日中の」で差し替え）。アプリの v10 の写真
（`docs/design/catch-concepts/film/assets/photo_1080.jpg`）を参考にして作るプロンプトで作った。
`assets/photo.jpg` は、それを AI（EDSR ×2）で 3840×1646 に拡大した物。

## Apple の決まり（2026-10-22 に Apple のヘルプで確認）

| 項目 | 値 | この動画 |
| --- | --- | --- |
| 大きさ | 21:9、3840×1646 | 3840×1646 |
| コマ数・長さ | 30fps か 60fps、5〜30 秒 | 30fps、12 秒 |
| 形式 | .mov・.m4v・.mp4 | .mp4（H.264） |
| 音 | 最初は消音（見る人がオンにできる） | 音なし |
| 中身（審査基準 2.3.14） | アプリの機能かブランド。価格・URL・©・確かめられない宣伝・他社のロゴは入れない。4+ | アプリの画面の流れと実写の写真。文字・ロゴの無い写真 |

- 出典: [Creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)、
  [App Review Guidelines 2.3.14](https://developer.apple.com/app-store/review/guidelines/)、
  [App Store asset best practices](https://developer.apple.com/app-store/asset-best-practices/)
- **セーフエリア**（どの端末でも切れない真ん中。Apple は数値を出していない。第三者が型紙から読んだ値は横 1097〜2743・縦 493〜1154）:
  タグ・ステッカー・ことば・図鑑のカードはこの中。写真のカップの下半分はこの外（写真の構図のため）。iPhone では上下は切れない
  （左右が切れる）。入れる前に App Store Connect のプレビューで iPhone・iPad の縦横を確かめる。

## 作り方

```sh
P=python   # opencv-contrib-python-headless・rembg・onnxruntime を入れた Python
$P prep.py upscale assets/photo_src.jpg EDSR_x2.pb   # 拡大（EDSR_x2.pb は github.com/Saafke/EDSR_Tensorflow の models/。CPU で約 8 分）
$P prep.py objects                                  # 切り抜きと輪郭 → assets/objects.json・cup_cut.png・cup_border.png
python3 -m http.server 8767 --bind 127.0.0.1 &      # このフォルダで
cd motion && node render.js ja header-ja.mp4 && node render.js en header-en.mp4   # 各 約 5 分
```

確認用: `http://127.0.0.1:8767/motion/header.html?lang=ja&f=200&safe` で 200 コマ目をセーフエリアの枠つきで描く。

## 検索結果の動画（3:2）

オーナー 2026-10-23「この検索結果という項目も作って」（App Store Connect の「ヘッダと検索結果」の「検索結果」）。

| 版 | ファイル | 大きさ |
| --- | --- | --- |
| 日本語 | `search-ja.mp4` | 2880×1920（3:2）・30fps・12 秒 |
| 英語 | `search-en.mp4` | 同じ |

- Apple の決まり: 3:2、1920×1280〜3840×2560、5〜30 秒、30fps か 60fps。**検索結果では消音のまま**（見る人がオンにできない）。
  Apple の勧めは「何のアプリかが一目で分かる」「アプリの画面や体験を見せる」。
- 中身はヘッダーと同じ流れ。ヘッダーの絵の真ん中（写真の横 686〜3155）を切り出し、1.17 倍で描く（タグ・ことば・図鑑のカードが大きく見える）。
  写真が 3840 幅までなので、3840×2560 にすると引き伸ばしすぎる。2880×1920 にした。
- 作り方: `node render.js ja search-ja.mp4 search`、`node render.js en search-en.mp4 search`。確認は `header.html?lang=ja&fmt=search&f=200`。

## App Store Connect に入れる

1. App Store Connect → アプリ → 「製品ページの情報」→「ヘッダーと検索結果」（画面の名前は変わることがある）。
2. 「製品ページのヘッダー」を選び、言語「日本語」に `header-ja.mp4`、「英語」に `header-en.mp4` を入れる。
3. 「検索結果」を選び、言語ごとに `search-ja.mp4`・`search-en.mp4` を入れる。
4. プレビューで iPhone と iPad の縦・横を見て、タグと図鑑のカードが切れていないか確かめる。
5. オーナーの画面（2026-10-23）には「承認済みのアセットをチェックして、ヘッダアセットを選択します」とある。動画をアセットライブラリに入れて承認されてから選ぶ形とみられる（細かい手順はその画面の案内に従う）。
6. 審査に出す。
