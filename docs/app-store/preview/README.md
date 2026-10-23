# App Store のプレビュー動画（案 A）

App Store の「App プレビュー」（ストアの画面で流れる 15〜30 秒の動画）の作り方です。

## オーナーの決定（2026-10-22）

- **案 A**: 1 つの物を撮って、タグ → 言い方を選ぶ → GET → 図鑑 → 単語ページ → 復習 → ホームまで、1 本で見せる。
- **いまのアプリの動きに合わせる**（「現在のアプリのアニメーションに準拠して」）。録画の速さを変えない。
  動きの途中で切らない。アプリに無い光や飛ぶ動きを足さない。
- **名前の遅い回の録画を使う**（「名前が遅く届いた録画では、待ちの部分が少し長くなる、名前の遅い回の録画を使って」）。
  見本では名前が 6.0 秒後に届く `scanslow`。光のペンが描き終えた後、小さい光が 1 つ回って待つ。
  → 2026-10-23 に変更（「名前のタグが出るのが遅い。やっぱり速いバージョンに作り替えて」）: 名前が 2.4 秒後に届く `analyzing`。
- **枠あり**: 録画を角の丸い枠に縮め、上の余白に字幕を置く。アプリの文字に字幕を重ねない。
- **効果音は v6・v10 のまま**: アプリが鳴らす音（`ios/CatchWords/Resources/Sounds` の `cc-*`・`cc6-*`）を、
  アプリが鳴らした時刻に重ねる。
- **日本語版と英語版を作る**。英語版はアプリの表示も字幕も英語（言語を混ぜない。`docs/language-rules.md`）。

## Apple の決まり（2026-10-22 に公式の情報で確かめた）

| 項目 | 決まり |
| --- | --- |
| 中身 | アプリそのものの画面収録だけ。説明の文字や声を重ねるのはよい（審査基準 2.3.4） |
| 長さ | 15〜30 秒 |
| 大きさ | 6.9・6.5 インチの iPhone は縦 886 × 1920 |
| 形式 | H.264、最大 30 fps、500 MB まで |
| 音 | ステレオ、AAC 256 kbps、44.1 か 48 kHz |
| 本数 | 1 つの言語につき 3 本まで |

出典: [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/)、
[App Review Guidelines 2.3.4](https://developer.apple.com/app-store/review/guidelines/)

## 作り方

### 1. 素材を撮る

- **下書き**: GitHub の `iOS store preview` ワークフロー（`.github/workflows/ios-store-preview.yml`）が、
  シミュレーターでアプリの見本画面を日本語と英語で録画して、ci-previews の `runs/store-preview/` に置く。
  アプリは見本のモードで `-traceSounds YES` を渡した時だけ、鳴らした音と時刻を trace に書く（`SoundService.trace`）。録画には音が入らないので、
  その時刻に同じ音のファイルを重ねる。シミュレーターは GPU を使わないので、コマ落ちが多い。
- 録画は手で動かした時だけ撮る（GitHub の Actions →「iOS store preview」→「Run workflow」）。いまの `edl-*.json` は
  ci-previews の `runs/store-preview/`（COMMIT 219709577）の録画に合わせてある。録り直したら、切る位置と `sound_offset` を合わせ直す。
- **本番**: 実機の画面収録（審査に出すビルド）。シミュレーターの録画は、審査には出さない。

### 2. 切り方と字幕を決める

`edl-ja.json`・`edl-en.json`:

- `segments`: 使う録画（`src` は拡張子を除いた名前）と、使う部分（`in`・`out`、録画の頭からの秒）。
  場面の変わり目でだけ切る。
- `captions`: 字幕（`t0`・`t1` は書き出す動画の頭からの秒）。1 つの字幕は 1.8 秒以上出す。
- `taps`: タップの印（画面収録にはタップが写らない）。`x`・`y` は録画の画素。
- `end`: 最後の表示（アイコン・CatchWords・サブタイトル）の長さとサブタイトル。
- `sound_offset`: 録画を始めた時刻から最初のコマまでの遅れ（秒）。音と絵が合うように、目で確かめて決める。

### 3. 書き出す

```sh
# 道具: ffmpeg、python3（numpy・Pillow）、node（playwright）、字体（Noto Sans JP・Inter）
npm install @fontsource/noto-sans-jp@5.1.0 @fontsource/inter@5.1.0   # どこか作業用の場所で
FONTSOURCE=<その node_modules/@fontsource> NODE_PATH=$(npm root -g) \
  python3 compose.py edl-ja.json <録画のフォルダ> catchwords-preview-ja.mp4
```

- `overlay.html`: 枠の後ろの背景、字幕、タップの印、最後の表示（白い背景。オーナー 2026-10-23）を 1 コマずつ描く。動きの曲線はアプリの値
  （字幕は撮影の枠がカチッと止まる `cubic-bezier(.3,1.3,.5,1)` の 0.54 秒、下の線は止まった枠の青 #6CC8FF、
  消える時は GET の文字と同じ 0.25 秒、アイコンは「新しいことばをキャッチ！」と同じ跳ね方）。
- 字体: アプリはシステムの字体。Linux には無いので、近い Noto Sans JP（日本語）と Inter（英語）で描く。
  手書き風は使わない（オーナー 2026-10-20）。

### 4. 確かめる

```sh
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,sample_rate,channels:format=duration -of compact out.mp4
```

886 × 1920・30 fps・h264・aac 48000 Hz 2ch・15〜30 秒であること。

## 字幕（オーナー 2026-10-23「このアプリ機能がよくわかり、魅力的に思えるように」）

| 場面 | 日本語 | English |
| --- | --- | --- |
| 撮影 | 知らない物も、撮るだけ | Snap it, even if you can't name it |
| タグが出る | AIが撮ったものを分析 | AI analyzes what you shot |
| 言い方を選ぶ | 覚えたい言い方を選べる | Pick the way you want to learn |
| GET | （字幕なし。アプリの「新しいことばをキャッチ！」を読ませる） | （同じ） |
| 図鑑 | 自分だけの図鑑が どんどん増える | Your own collection keeps growing |
| 単語ページ | 自分だけの単語帳になる | Your own word book |
| 最後 | 撮って覚える台湾華語 | Snap it. Learn Taiwanese Mandarin. |
