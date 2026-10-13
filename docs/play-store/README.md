# Google Play 公開の準備（Android 版 CatchWords）

- アプリの場所: `android/`（Kotlin・Jetpack Compose）
- パッケージ名: `com.nori.catchwords`（iOS のバンドル ID と同じ）
- 版: 1.0.0（versionCode 1）
- アイコン: `docs/play-store/icon-512.png`（iOS と同じマーク。`scripts/android_icons.py` で作り直せる）
- サーバー: iOS・Web と同じ Supabase と `https://catchwords.lovable.app/api/native-fn`。アカウントも単語も 3 つのアプリで共通です。

## Android 版にある機能（ストアの文言はこの範囲だけで書く）

- メールとパスワード、または Google でログイン（Web と同じアカウント）
- 初回設定（表示言語・目標レベル）、AI へのデータ送信の同意（iOS と同じ内容）
- 撮影後のスキャン演出（iOS v10 と同じ: ブラケット → 光のペンが物の輪郭をなぞる → 名前タグが物の上に出る）
- 端末内での切り抜き（ML Kit の被写体分離。iOS の Vision に相当）→ 白ふちステッカー、紙吹雪と光の演出、「図鑑に追加」
- 持っている単語は「再会！」として写真・切り抜き・場所を記録
- 自撮りモード、撮った場所の記録、解析に失敗した写真の「解析待ち」
- ホームのアルバムと本棚、図鑑（分類・一覧・地図・検索）、単語ページ（解説・例文・量詞・関連語・表示する写真の切り替え・再会の記録・発音）
- 4 択の復習（採点は Web の `gradeReview`）
- 復習の通知（おまかせ／時間指定、22〜8 時は鳴らさない）、ホーム画面ウィジェット「今日の単語」
- 設定（プロフィール・言語・レベル・注音/ピンイン・1 日の復習数・効果音・撮影・通知・AI 同意の取り消し・規約類・ログアウト・アカウント削除）

iOS にあって Android にまだ無いもの: 場所でリマインド（Android ではバックグラウンド位置情報の権限と Play の追加審査が要るため保留）、Live Activity、管理者画面。

## ストアの掲載情報（案）

### 日本語（ja-JP）

- タイトル（30 文字以内）: `CatchWords - 台湾華語の単語図鑑`（22 文字）
- 簡単な説明（80 文字以内）: `身の回りの物を撮るだけで、台湾華語（繁体字）の単語が集まる図鑑アプリ。`（35 文字）
- 詳しい説明:

```
撮った物に、台湾華語（繁体字）の単語がその場で付きます。集めた単語は自分の写真と一緒に図鑑に並び、ちょうどよい時期に復習が出ます。

■ 撮る・選ぶ・調べる
・カメラで撮るか写真を選ぶと、写っている物の名前の候補が出ます
・同じ物に言い方がいくつかあるときは、違いの短い説明つきで並べます
・候補に無い言葉は、日本語・英語・中国語で入力して調べられます
・単語を選ぶと、注音・ピンイン・意味・例文のカードができ、そのまま図鑑に入ります

■ 図鑑で見返す
・分類ごとの図鑑と一覧、検索
・単語ページで、解説・例文・量詞・関連する言葉を確認し、発音を聞けます
・ホームには、月ごとのアルバムができます

■ 自分の写真で復習
・覚え具合に合わせて、4 択の復習を出します
・問題には自分で撮った物が出るので、出会った場面と一緒に思い出せます

■ データの扱い
・写真の解析と単語の説明の作成には、外部の AI サービスを使います。送る前にアプリの中で内容を示し、同意をうかがいます。同意しなくても、集めた単語の閲覧と復習は使えます
・アカウントは、設定からいつでも削除できます
・iPhone 版・Web 版と同じアカウントで使えます

表示言語：日本語・English・繁體中文
学べる言語：台湾華語（繁体字）

プライバシーポリシー：https://catchwords.lovable.app/privacy
利用規約：https://catchwords.lovable.app/terms
```

### 英語（en-US）

- Title: `CatchWords: Taiwan Mandarin`（27 characters）
- Short description: `Snap things around you and collect Taiwanese Mandarin words in your own dex.`（76 characters）
- Full description:

```
Point your camera at everyday things and get their names in Taiwanese Mandarin (Traditional Chinese). Every word you catch joins your dex with your own photo, and reviews come back at the right time.

■ Snap, pick or search
・Take a photo or pick one from your gallery to see name candidates for what's in it
・When something has several names, they're listed with a short note on how they differ
・Type a word in English, Japanese or Chinese to look it up
・Pick a word to get a card with Zhuyin, Pinyin, meaning and an example sentence

■ Your dex
・Browse by category or as a list, and search
・Word pages with notes, examples, measure words and related words, with audio
・A monthly album on the home screen

■ Review with your own photos
・4-choice reviews scheduled by how well you remember
・Your own photos appear in the quiz, so you recall where you met the word

■ Your data
・Photo analysis and word explanations use external AI services. The app shows what is sent and asks for your consent first. Without consent you can still browse and review your words
・You can delete your account any time in Settings
・Works with the same account as the iPhone and web apps

Display languages: Japanese, English, Traditional Chinese
Learning language: Taiwanese Mandarin (Traditional Chinese)

Privacy Policy: https://catchwords.lovable.app/privacy
Terms: https://catchwords.lovable.app/terms
```

## データセーフティ（Play Console の回答案）

| 項目 | 回答 |
| --- | --- |
| データを収集しますか | はい |
| 送信中の暗号化 | はい（HTTPS のみ） |
| 削除の手段 | アプリ内（設定 › アカウントを削除）と Web。削除用 URL: https://catchwords.lovable.app/support |
| 個人情報: メールアドレス | 収集・アカウント管理・必須 |
| 個人情報: 名前（表示名） | 収集・アプリの機能・任意 |
| 写真 | 収集・アプリの機能（単語の判定、図鑑）・必須（撮影時） |
| アプリのアクティビティ: アプリ内操作（集めた単語・復習の記録） | 収集・アプリの機能 |
| ユーザー生成コンテンツ（ひとことメモ・入力した単語） | 収集・アプリの機能 |
| 第三者との共有 | 写真と入力した単語を AI 事業者（Google など）へ、単語の判定と解説の作成のためだけに送る。同意画面あり |
| 位置情報（おおよそ・正確） | 収集・アプリの機能（撮った場所の記録、任意・設定でオフ可） |
| 連絡先・マイク・広告 ID | 収集しない |

最終の回答は、プライバシーポリシー（docs/legal）の内容と合わせてあなたが確定してください。

## そのほか Play Console で答えるもの

- コンテンツのレーティング: 教育アプリ。暴力・性的表現・ギャンブルなし。ユーザー同士のやり取りなし。
- ターゲットユーザー: 13 歳以上（子ども向けではない）。
- 広告: なし。
- アプリのアクセス権: ログインが必要 → 審査用アカウント（iOS と同じ `catchwords.review@gmail.com`）を入力。パスワードはここに書かない。
- 金融・健康などの申告: 該当なし。

## 公開までの順番

1. Google Play Console のデベロッパー アカウントを作る（登録料 25 米ドル・本人確認あり）。
2. Play Console で「アプリを作成」→ 名前 CatchWords、既定の言語 日本語、アプリ、無料。
3. Rork の公開ダイアログから Google Play を接続する。
4. Rork が署名済み AAB を作り、内部テストに出す（パッケージ `com.nori.catchwords`）。
5. 2023 年 11 月以降に作った個人アカウントは、製品版の前に「クローズド テストで 12 人以上・14 日間連続」が必要。
6. 掲載情報・スクリーンショット（スマホ 2 枚以上）・フィーチャー グラフィック（1024×500）・データセーフティ・レーティングを入れて、製品版を申請。
