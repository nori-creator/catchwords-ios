# iOS 版を Rork なしで自分で管理する手順

対象: CatchWords の iOS 版（このリポジトリの `ios/`）。Mac がなくても、GitHub だけで組み立て・確認・App Store への提出ができるようにする手順です。

最終更新: 2026-10-01

---

## 0. 言葉の意味（最初に読む）

| 言葉 | 意味 |
|---|---|
| **GitHub** | コードの保管庫。変更の履歴がすべて残る。Rork をやめても消えない。 |
| **リポジトリ** | GitHub 上の1つのプロジェクトの箱。iOS 版は `nori-creator/catchwords-ios`。 |
| **PR（プルリクエスト）** | 「この変更を入れてよいか」の提案書。中身を見てから本体（main）に取り込む。 |
| **GitHub Actions** | GitHub が貸してくれる Mac で、決まった作業を自動でやる仕組み。「ワークフロー」はその作業手順書。 |
| **Secrets** | GitHub に預ける秘密の値（鍵など）。コードには書かず、画面からも読めない。 |
| **App Store Connect** | Apple のアプリ管理画面（https://appstoreconnect.apple.com）。審査への提出・TestFlight・売上などを扱う。 |
| **TestFlight** | 公開前のアプリを iPhone に入れて試せる Apple の仕組み。 |
| **バンドル ID** | アプリの世界で1つだけの名前（例 `com.example.catchwords`）。**一度 App Store Connect に送ると変えられない。** |
| **API キー（.p8）** | GitHub の Mac が、あなたの代わりに Apple へアプリを送るための鍵。 |
| **ビルド番号 / バージョン** | ビルド番号は送るたびに増える通し番号。バージョン（1.0.0 など）は利用者に見える版。 |

---

## 1. Rork を契約している間にやること

### 1-1. バンドル ID を決める（最初の提出の前に1回だけ）

- バンドル ID は **`com.nori.catchwords`**（2026-10-01 に Rork の自動の名前 `app.rork.v075or6kicdigi0jhlze3` から変更。まだ一度も提出していなかったため変えられた）。
- 一度 App Store Connect に提出すると変えられません（Apple の決まり）。
- **データベースとログインは Lovable Cloud（Lovable が管理する Supabase）にある。** 自分の Supabase アカウントには入っていないので、Supabase の管理画面は使わない。
- **Google / Apple のログインは Web 版の `/native-auth` を通る**（2026-10-01）。アプリはシステムの安全なログイン画面で Web 版のページを開き、Web 版と同じ仕組みでログインしてからアプリに戻る。Web 版と同じアカウントになる。Lovable Cloud や Apple Developer 側に追加の設定は要らないが、**Web 版の `/native-auth` が Publish されていないとアプリの Google / Apple ログインは失敗する**（1-2 を先に）。
- 端末内で完結する Apple サインイン（`AppConfig.nativeAppleSignIn`）はオフにしてある。ログインの仕組み側にバンドル ID を登録できないのと、Web 版と別のアカウントになってしまうため。

### 1-2. Web 版を先に公開する

iOS 版の AI・保存は、Web 版のサーバ（`/api/native-fn`）を通ります。iOS 版が呼ぶ関数が Web 版に全部あるかは、ワークフロー「iOS ↔ Web contract（約束の確認）」が毎日確かめます。

1. Web 版の PR（`nori-creator/Lovable-catch-words-app`）を main に取り込む。
2. Lovable の編集画面で右上の **Publish → Update** を押す。

これをしないと、iOS 版では候補が出ず、保存もできません。

### 1-3. App Store に出す（GitHub Actions から）

1. GitHub → **Actions** → **iOS release（App Store Connect へ送る）** → **Run workflow**（手順 2-5 と同じ）。
2. App Store Connect → アプリ → **TestFlight** にビルドが出たら、iPad に TestFlight で入れて「6. 提出前の確認」を一通り試す。
3. App Store Connect の **App Store** タブで「6. 提出チェックリスト」の情報を埋め、そのビルドを選んで**審査へ提出**。

> 注意: Apple は、アカウントを作れるアプリには「アプリの中でアカウントを削除できること」を求めています（審査ガイドライン 5.1.1(v)）。設定画面の「アカウント削除」はログインごと消します（サーバの `deleteMyAccount`）。

---

## 2. Rork をやめる前に必ずやること（順番どおりに）

### 2-1. コードが GitHub にそろっているか確かめる

- GitHub の `nori-creator/catchwords-ios` を開き、最新の変更が main に入っていることを見る。
- Rork の GitHub 連携は有料プランの機能です。解約前に、最後の同期が終わっていることを確かめてください。

### 2-2. App Store Connect API キーを作る

1. https://appstoreconnect.apple.com → **ユーザとアクセス** → **統合（Integrations）** タブ → **App Store Connect API** → **チームキー**。
2. **「＋」（API キーを生成）** を押す。
   - 名前: `GitHub Actions`
   - アクセス: **Admin**（クラウド署名に必要なため。App Manager で動かないことがあります）
3. 表示される **キー ID** と、画面上部の **Issuer ID** をメモする。
4. **API キーをダウンロード**（`AuthKey_XXXXXXXXXX.p8`）。**ダウンロードは1回しかできません。** なくしたら作り直しです。

参考（Apple 公式）: https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api

### 2-3. チーム ID を調べる

- https://developer.apple.com/account → **メンバーシップの詳細** → **チーム ID**（10桁の英数字）。

### 2-4. GitHub に 4 つの Secrets を入れる

GitHub のリポジトリ → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** で、次の4つを1つずつ追加します。

| 名前 | 入れる値 |
|---|---|
| `APPLE_TEAM_ID` | 2-3 のチーム ID |
| `ASC_KEY_ID` | 2-2 のキー ID |
| `ASC_ISSUER_ID` | 2-2 の Issuer ID |
| `ASC_KEY_P8` | .p8 ファイルをメモ帳などで開いた中身を**そのまま全部**（`-----BEGIN PRIVATE KEY-----` から `-----END PRIVATE KEY-----` まで） |

（以前の `ASC_KEY_P8_BASE64`（base64 にした文字列）を入れてある場合は、それでも動きます。）

**.p8 の中身はチャットや Issue に貼らないでください。** 入れる場所は GitHub の Secrets だけです。

### 2-4b. 端末を1台登録する（最初の1回だけ）

自動の署名は、送る前に一度「開発用」で署名するため、Apple Developer に iPhone か iPad が1台以上登録されている必要があります（無いと「Your team has no devices」で止まる）。

1. iPad の「UDID」（端末ごとの40桁ほどの番号）を調べる
   - **Mac**: iPad をケーブルでつなぐ → Finder の左に出る iPad を押す → 名前の下の灰色の文字（機種名・シリアル番号）を何回か押すと「UDID」に変わる → 右クリックで「UDID をコピー」
   - **Windows**: Microsoft Store の「Apple デバイス」アプリを入れる → iPad をケーブルでつなぐ → iPad を選ぶ → シリアル番号を押すと UDID に変わる → コピー
2. https://developer.apple.com/account → Certificates, IDs & Profiles → **Devices** → 「＋」
3. Platform: iOS／Device Name: `iPad`／Device ID (UDID): 1 でコピーした番号 → Continue → Register

### 2-5. Rork なしで1回送ってみる（解約の前に）

1. GitHub → **Actions** → **iOS release（App Store Connect へ送る）** → **Run workflow**。
2. 20分ほどで終わる。緑のチェックが付けば成功です。
3. App Store Connect → アプリ → **TestFlight** に、新しいビルドが出ることを確かめる（処理に10〜30分かかります）。

**ここまで成功したら、Rork を解約して大丈夫です。** 失敗したら、赤くなった手順の記録（Artifacts の `ios-release-logs`）を Claude に見せてください。

---

## 3. Rork をやめた後の、ふだんの回し方

```
やりたいことを Claude に頼む
   ↓
Claude が変更を作り、PR を出す
   ↓
「iOS check」が自動で動き、シミュレーターの画面写真・動画ができる（iPhone がなくても見られる）
   ↓
写真・動画を見て OK なら、PR を main に取り込む
   ↓
Actions の「iOS release」を Run workflow → TestFlight に届く
   ↓
App Store Connect で「審査へ提出」
```

### 画面の確認のしかた（iPhone がなくても）

1. PR の画面 → **Checks** → **iOS check（iOS 版の確認）** → **Summary**。
2. 下の **Artifacts** から `ios-check-report` をダウンロードして開く。
3. `screen-*.png`（写真）と `launch.mp4`（動画）で見た目を確認する。

シミュレーター（画面上で動く仮想の iPhone）では、カメラと「切り抜き（Vision）」は動きません。これらは TestFlight を入れた本物の iPhone で確認します。

### 新しいバージョンを出すとき

- 利用者に見える版（例 1.0.0 → 1.1.0）は、Claude に「バージョンを 1.1.0 にして」と頼む。
- ビルド番号は、ワークフローが自動で決めます（`1000 + 実行回数` と「App Store Connect にあるいちばん大きい番号 + 1」の大きい方）。同じころに Rork など別の所から送られて番号を先に使われた時は、次の番号にして自動で送り直します（3 回まで）。

---

## 4. お金のこと（2026-09 時点）

| 項目 | 金額 | 備考 |
|---|---|---|
| Apple Developer Program | 年 99 ドル | App Store に出すのに必須 |
| GitHub Actions（Mac） | 非公開リポジトリは無料枠を超えると 1 分 0.062 ドル | 1回の release で約 20 分、iOS check で約 15 分。公開リポジトリなら無料 |
| Rork Max | 月 200 ドル | 手順 2 が終われば不要 |

参考: https://docs.github.com/en/billing/reference/actions-runner-pricing

> Mac の分数が無料枠をどの割合で使うかは、GitHub の現在の説明に明記がありません（以前は10倍で数えていました）。GitHub の Settings → Billing で実際の使用量を確認してください。

---

## 5. 困ったとき

| 症状 | 見る所・やること |
|---|---|
| iOS check が赤い | その PR で Claude に「CI を直して」と頼む |
| iOS release が「Secrets が足りません」 | 手順 2-4 をやり直す |
| iOS release が署名で失敗 | API キーのアクセスが Admin か確かめる（手順 2-2） |
| iOS release が「Redundant Binary Upload」で失敗 | 同じころに Rork など別の所からビルドが送られ、同じ番号を先に使われた。今は次の番号で自動で送り直す。3 回続けて失敗したら、別の所からの送信が終わってから、もう一度 Run workflow |
| TestFlight に出てこない | App Store Connect の「アクティビティ」で処理中か確かめる。Apple からのメールも確認 |
| アプリで候補が出ない・保存できない | Web 版が Publish されているか確かめる（手順 1-2） |

---

## 6. App Store 提出チェックリスト（初版 1.0.0・無料のみ・iPhone 専用）

> **2026-10-11: 最新の提出の手順と答えは `docs/app-store/`（README・審査への返信・審査メモ・画面録画の撮り方・年齢区分と App のプライバシー）。**
> この 6 章は 2026-10-01〜10-03 の記録で、説明文（6-2）・App のプライバシーの表（6-3）・審査メモ（6-4）は、本棚・日記・スキャン・声で調べるがあった頃の版のまま。新しく直す時は `docs/app-store/` の方を直す。

### 6-1. 提出前にアプリで確かめること（TestFlight）

| 確かめること | 期待する動き |
|---|---|
| Google で続ける | Safari の小さな画面が開き、Google でログイン → 自動でアプリに戻り、ホームが出る |
| Apple でサインイン | 同じく Apple でログイン → アプリに戻る |
| ログイン画面を閉じる | 何も出ない（エラーにならない） |
| メールでログイン・新規登録・パスワードを忘れた | それぞれ動く |
| 機内モードで起動 | ログインしたまま。「ようこそ」画面が再び出ない |
| Web 版の設定で「すべての端末からログアウト」→ アプリを操作 | ログイン画面に戻り「ログインの有効期限が切れました」と出る |
| 撮影 → 単語を選ぶ → 保存 | 図鑑に着地する。機内モードなら「保存に失敗しました」と出て写真は「解析待ち」に残る |
| 復習で答える（機内モード） | 「採点を保存できませんでした」と出て、もう一度答えられる |
| 設定 | 「Pro にアップグレード」「購入を復元」が出ない。末尾に `1.0.0 (ビルド番号)` が出る |
| 設定 → アカウント削除 | 削除後にログイン画面に戻り、同じメールで再ログインできない。ウィジェットの単語・予約した通知・解析待ちの写真も消える |
| 図鑑（棚） | 上に本棚が出ない。スライド表示でカードが輪になって回り、音が鳴る |
| 初めてログイン（または「ようこそ」の後） | 「AIへのデータ送信について」が出る。「同意しない」→ カメラのタブは「AIの機能は止まっています」になり、撮影・検索はできないが、図鑑・復習は使える。「内容を確認して同意する」→ 同意するとカメラが使える |
| 設定 → プライバシー → AIへのデータ送信の同意 | 同意した日が出る。「同意を取り消す」→ カメラのタブがまた止まる。同じアカウントでログインし直しても聞き直さない |

### 6-2. App Store Connect に入れる情報

| 項目 | 値・下書き |
|---|---|
| 名前 | CatchWords |
| サブタイトル（30字） | 街で見つけた物が、学ぶ言葉になる |
| カテゴリ | 教育（サブ: 辞書/辞典 など任意） |
| 価格 | 無料 |
| 年齢 | 4+（ユーザー生成コンテンツは本人だけが見るため。暴力・性的表現なし） |
| プライバシーポリシー URL | https://catchwords.lovable.app/privacy |
| サポート URL | https://catchwords.lovable.app（問い合わせ先のページがあればそちら） |
| 著作権 | 2026 近藤範之 |
| スクリーンショット | iPhone 6.9 インチ（必須）と 6.5 インチ。実機の画面（ホーム・撮影・図鑑のスライド・単語の詳細・復習）。CI の見本画像は仮の写真なので使わない |
| iPad | 不要（iPhone 専用） |

説明文（日本語の下書き。英語・繁体字は App Store Connect で言語を追加して訳す）:

```
街で見つけた物を撮るだけで、学んでいる言葉（台湾華語・英語・日本語）の単語カードになります。

・写真から単語の候補を出し、読み方と意味を付けて図鑑に集める
・切り抜きのステッカー、撮った場所と日付、ひとことメモ
・覚え具合に合わせて出題される復習（4択）
・看板にかざして調べる「スキャン」、声で調べる
・Web 版（catchwords.lovable.app）と同じアカウントで、集めた単語はどこでも同じ
```

キーワード（100字）: `台湾華語,中国語,英語,単語,語学,学習,図鑑,写真,ステッカー,復習,台湾`

### 6-3. App のプライバシー（質問への答え）

「データを収集しますか」→ **はい**。追跡（トラッキング）→ **いいえ**。すべて「ユーザーに関連付けられる」。用途は全項目「アプリの機能」。加えて「分析」を ユーザー ID・検索履歴・製品の操作・購入履歴 に付ける（開発者の利用者画面・KPI 集計 `metrics.functions.ts` / `admin-users.functions.ts` が `usage_events`・`scan_events`・`plan` を使うため）。第三者広告・開発者の広告やマーケティング・製品のパーソナライズ・その他の目的 は付けない（iPhone アプリは広告なし、販促メールなし、おすすめ表示なし）。

| 種類 | 収集する | 用途 |
|---|---|---|
| 連絡先情報 → メールアドレス | はい | アカウント |
| ユーザー ID | はい | アカウント |
| 位置情報 → 正確な位置情報 | はい | 撮った場所の地名を残す・「場所でリマインド」（許可した時だけ） |
| ユーザーコンテンツ → 写真またはビデオ | はい | 単語の写真・ステッカー |
| ユーザーコンテンツ → 音声データ | いいえ | 声で調べる の音声は当社のサーバに送らない（下の ※） |
| ユーザーコンテンツ → その他 | はい | メモ・日記・学習記録 |
| 連絡先情報 → 名前 | はい | 表示名（プロフィール） |
| 検索履歴 | はい | スキャンで見つかった単語と、押した・保存したかの記録（サーバの `scan_events`。位置を許可していればその位置も） |
| 使用状況データ → 製品の操作 | はい | アプリの機能・分析（サーバが AI の利用回数を `usage_events` に記録し、1日の上限と開発者の利用者画面に使う） |
| 購入 → 購入履歴 | はい | アプリの機能（Pro の購入状態をサーバに保存して Pro を使えるようにする。支払い情報は Apple だけが持つ） |
| 診断 | いいえ | 集めていない |

※ 音声データを「いいえ」にした理由（2026-10-03）: 「声で調べる」（`Services/SpeechService.swift`）は、その言語の認識の仕組みが端末にあれば端末の中だけで文字にし、無ければ Apple の音声認識（Apple のサーバ）が文字にする。当社のサーバや、アプリに組み込んだ他社の部品に音声が渡ることは無く、当社に届くのは文字にした結果だけ（検索履歴・その他のユーザーコンテンツとして答えている）。Apple の App Privacy Details（developer.apple.com/app-store/app-privacy-details/）は「端末の中だけで処理するデータは『収集』に当たらない」「Apple が集めるデータは答えなくてよい」「提携先とは、アプリに入れた分析・広告・他社の SDK などのこと」としているので、音声は答えない。プライバシーポリシー 2-3 と 6 章（提供先の Apple の行）には、音声が Apple に送られることがあると書いてあり、食い違いは無い。音声を当社のサーバや他社の AI に送る機能を足すときは「はい」に戻す。

アプリ内の `PrivacyInfo.xcprivacy` も同じ内容。変えるときは両方そろえる。

### 6-4. 審査メモ（App Review Information）に書くこと

```
テスト用アカウント: （メール）／（パスワード）  ← 審査用に専用アカウントを作って書く

- Google / Apple のサインインは、アプリ内の安全な Safari 画面（ASWebAuthenticationSession）で
  当社の Web サイト catchwords.lovable.app のログインを行い、アプリに戻ります。
- アカウント削除は 設定 → アカウント削除 から行え、サーバのアカウントごと消えます。
- 写真の候補・単語カードの生成は当社サーバ（catchwords.lovable.app）で行います。
- AI: photos and text are sent to third-party AI (Google Gemini via our server) only after the user
  agrees on the consent screen shown before the first AI feature (Settings > Privacy to withdraw).
  Without consent the camera and AI features stay off and nothing is sent.
- この版は無料のみで、アプリ内課金はありません。

ログインが必要な理由（Guideline 5.1.1(v)）:
このアプリは Web 版 CatchWords と同じアカウント・同じデータを使います。撮った写真、単語カード、
復習の記録、日記はアカウントごとに当社サーバに保存され、iPhone と Web のどちらからでも続きを使えます。
写真から単語を見つける・カードを作る・日記を添削するといった中心の機能は、当社サーバの AI で動き、
使い過ぎを防ぐためにアカウントごとに1日の利用回数の上限があります。写真もアカウントごとに保存します。
このため、ログインせずに使える部分はほとんど無く、ログインを必須にしています。
審査では、上のテスト用アカウント（メール: 【審査用メールアドレス】／パスワード: 【審査用パスワード】）で
ログイン画面の「メールアドレスで続ける」から入ってください。単語と写真が入った状態で、撮影・図鑑・復習・日記を
すべて試せます。初回だけ AI への送信の同意画面が出るので「同意して始める」を押してください。

Why sign-in is required (Guideline 5.1.1(v)):
CatchWords on iPhone shares one account and one set of data with the CatchWords web app. The photos you
take, your word cards, review history and journal entries are stored per account on our server, so you can
continue on either iPhone or the web. The core features (finding words in a photo, generating word cards,
correcting journal entries) run on server-side AI, which has a per-account daily usage limit to prevent
abuse, and photos are stored per account. Very little of the app works without an account, so sign-in is
required.
To review the app, please sign in with the demo account (email: [REVIEW_EMAIL] / password:
[REVIEW_PASSWORD]) using "Continue with email" on the sign-in screen. The account already has words and
photos, so the camera, word dex, review and journal can all be tried. On first sign-in a consent screen for
sending data to AI appears; tap "Agree and start".
```

審査メモを書くときは【】と [] の所を、審査用に作ったアカウントの本物のメールとパスワードに置き換える（2か所とも同じもの）。そのアカウントは提出前に Web 版か TestFlight で単語を10語ほど撮って入れ、はじめの設定と AI の同意まで済ませておく（「単語と写真が入った状態」と書いているため）。ボタンの文言はアプリの今の表示に合わせて確かめる。

### 6-5. 提出後によく返ってくる指摘と対応

| 指摘 | 対応 |
|---|---|
| Guideline 2.1（起動時に落ちる・ログインできない） | テスト用アカウントが有効か、Web 版が Publish 済みか確かめる |
| Guideline 5.1.1（権限の説明が足りない） | カメラ・マイク・位置・写真の説明文（pbxproj の `INFOPLIST_KEY_*UsageDescription`）を直す |
| Guideline 4.8（Sign in with Apple） | Google と並べて Apple も出している。指摘があれば Claude に見せる |
| Guideline 5.1.1(v)（アカウント削除） | 設定 → アカウント削除 の場所を審査メモに書く |
| Guideline 5.1.2(i)（第三者の AI への送信） | 初回の同意画面（6-6）と、設定の「AIへのデータ送信の同意」を審査メモに書く |

### 6-6. AI への送信の同意（Guideline 5.1.2(i)）

審査ガイドライン 5.1.2(i) は「第三者の AI を含め、個人データを第三者と共有する場所をはっきり示し、共有の前に明示的な許可を得る」ことを求めている。アプリでは次のように入れた（`docs/legal/checklist.ja.md` 8章 A1）。

- **画面**: ログイン（新しい人は「ようこそ」の後）の直後に、アカウントごとに1回「AIへのデータ送信について」を出す（`Views/AIConsentView.swift`）。送るもの（写真・単語・文章・声で調べた言葉の文字）、送り先（当社のサーバを通して外部の AI サービス〈Google など〉）、使い道、同意しない場合、プライバシーポリシーへのリンク。「同意して始める」／「同意しない」。
- **関所は1か所**: `NativeAPI.call` が、AI に渡る関数（`AIConsent.aiFunctions`: `suggestWords`・`detectScan`・`rankScanCandidates`・`suggestWordCandidates`・`generateCard`・`regenerateCardSection`・`reportAndFixSection`・`getJournalPrompts`・`correctMyJournal`）を、同意が無ければ送る前に `APIError.aiConsentRequired` で止める。画面はそれに合わせて、カメラのタブを止め、単語の「報告」「作り直す」と日記の「AIに添削してもらう」では同意の画面を出す。
- **保存**: 端末の UserDefaults にアカウントごと（`aiConsent.<ユーザー ID>` に状態・版・日時）。送る内容や送り先を変えたら `AIConsent.currentVersion` を上げると、同意した人にも聞き直す（ポリシー 14章）。アカウントを削除すると消える。
- **サーバの記録（アプリ側は入れた。Web 側はパッチ待ち）**: Web 側の変更は `docs/web-changes/`（Web の main `3fd364f` に当てる版。3番目のパッチが同意。仕様は Web の `docs/ios-spec/23-ai-consent.md`）。Web 版にも同じ同意の画面が入り、表 `ai_consents` に「誰が・どの版に・いつ同意し・いつ取り消したか」が残り、同意の無い人の AI の関数はサーバで断られる（checklist 8章 W1）。アプリ側で入れたこと:
  - **見出し**: `/api/native-fn` へのすべての呼び出しに `AI-Consent-Version: 1`（`AIConsent.currentVersion`）を付ける（`NativeAPI.call`）。パッチの入ったサーバは、この見出しが付いた呼び出しだけ同意の記録を確かめる。
  - **書く**: 「同意して始める」「同意しない」・設定での取り消しのたびに `recordAiConsent`（`{version, agreed}`）を送る。送れなかったら、端末にアカウントごとの「未送信」の印（`aiConsent.<ユーザー ID>` の `pending`）を残し、次の起動（ログインの後）で送り直す。
  - **読む**: ログインしてプロフィールを読んだ後に `getAiConsent` を読み、端末とそろえる（画面は待たせない）。サーバが同意済み → 端末も同意済み（別の端末・Web で同意した人に聞き直さない）。この版より前に iPhone で同意し、サーバに記録が無い → その同意を送る。サーバで後から取り消されている（Web・別の端末）→ 端末も取り消す。端末とサーバの日時を比べて新しい方を取る。
  - **断られた時**: AI の関数が 403 `AI_CONSENT_REQUIRED` を返したら `APIError.aiConsentRequired` と同じ扱い。まず端末の同意をサーバに送ってみて、届いたらもう一度だけ呼ぶ。届かなければ端末の同意を外し、同意の画面を出し直す。
  - **今の本番サーバ（パッチ前）とも動く**: `recordAiConsent` / `getAiConsent` が無い（知らない関数・400・404・通信の失敗など）時は、何も表示せず端末の同意をそのまま使う（今までと同じ動き）。見出しは無視される。
  - **デモ（UI テスト）**: `Services/Demo/DemoFunctions.swift` が 2つの関数に Web と同じ形で答える。
  - **`check_native_contract.py`**: 2つの関数は Web の main にまだ無いので、`PENDING_WEB_DEPLOY`（パッチの場所つき）にだけ載せて通している。他の知らない関数は今までどおり落ちる。Web に入ったら警告が出るので、その2行を消す。
- **オーナーがやること（スイッチ）**: Web のパッチを当てて Supabase の移行（`20261003140000_ai_consents.sql`）を流した後、**全員がこの版以降のアプリに上がってから**、Lovable の Secrets に **`AI_CONSENT_ENFORCE_NATIVE=true`** を入れる。入れると、見出しを付けない古いアプリからの呼び出しも、サーバの同意の記録が無ければ AI の関数が断られる（古いアプリは記録を送らないので、AI が使えなくなる）。入れる前は、古いアプリは今までどおり通る（古いアプリも端末の中で同意を確かめてから送っている）。

---

## 7. アプリ内課金（Pro）を始めるとき（2026-10-03 の確認）

初版は無料のみ（`PlanStore.paywallEnabled = false`）。課金を始める前に、次がそろっている必要があります。

### 7-1. いまの仕組みと「iPhone で買った Pro がサーバに伝わらない」理由

- アプリは StoreKit 2 の購入記録（`Transaction.currentEntitlements`）を端末で確かめ、撮影回数などの**端末で決める制限**はそれで外す（`PlanStore.isPro`）。払った人が締め出されることはない。
- **サーバが決める Pro の機能**（項目の「作り直す」、Pro 用の AI モデル、報告からの AI 修正）は、サーバの `isProUser` が `profiles.plan = 'pro'`（または管理者）かで決める。`profiles.plan` を書くのは **Stripe の webhook だけ**で、Apple の購入を確かめる処理は**サーバにない**。だから iPhone で買っても、サーバは無料のまま扱う。
- アプリは「作り直す」を、サーバが Pro と認める時（`PlanStore.serverGrantsPro`）だけ出す（Web と同じ）。課金画面はサーバがまだ認めない機能を約束しない（`PlanStore.serverVerifiesAppStore = false`）。
- App Store 審査ガイドライン 3.1.3(b) により、Web（Stripe）で買った Pro は、同じ機能をアプリ内課金でも買えるようになるまで iPhone では効かせない。アプリ内課金が出ていない間（`PlanStore.inAppPurchaseAvailable` = `paywallEnabled` がオフ）は、Web で Pro の人もアプリでは無料扱い（「作り直す」が出ない）。課金画面も Web 購入への案内も出さない。
- 購入時にユーザー ID を `appAccountToken` として付けるようにした。Apple の署名つき購入記録とサーバ通知に入るので、サーバが持ち主を確かめられる。

### 7-2. Web 版（サーバ）に要る変更（このリポジトリからは入れられない）

1. **App Store Server Notifications V2 の受け口** `/api/appstore-notifications`（POST）
   - 本文 `{ signedPayload }`（JWS）。**Apple のルート証明書（Apple Root CA - G3）までの証明書の鎖と署名を確かめる**（`@apple/app-store-server-library` の `SignedDataVerifier` が使える）。bundleId `com.nori.catchwords`・environment を確かめる。
   - `data.signedTransactionInfo` から `appAccountToken`（＝ユーザー ID）、`originalTransactionId`、`productId`、`expiresDate`、`revocationDate` を取り出す。
   - 種類 `SUBSCRIBED / DID_RENEW / DID_CHANGE_RENEWAL_STATUS / EXPIRED / GRACE_PERIOD_EXPIRED / REFUND / REVOKE` で、有効かどうかを決める。
2. **アプリからすぐ知らせる関数** `syncAppStorePurchase`（`native-fn.ts` の一覧に足す。`requireSupabaseAuth`）
   - 入力 `{ signedTransaction: string }`（StoreKit 2 の `VerificationResult.jwsRepresentation`）。上と同じく署名を確かめ、`appAccountToken` が呼んだ本人の ID と一致する時だけ反映。戻り値 `{ isPro: boolean }`。
   - 足したら iOS 側で、購入・復元・`Transaction.updates` の後にこれを呼ぶ（`ios-contract.test.ts` / `check_native_contract.py` の一覧にも足す）。
3. **持ち主ごとの購入の表** `entitlements(user_id, source 'stripe'|'app_store', original_transaction_id, product_id, expires_at, revoked_at)`。`profiles.plan` は「どれか1つでも有効なら pro」として計算し直す。**今のように Stripe の webhook が `plan` を直接 free に書くと、Apple で払っている人まで無料に戻る**ので、Stripe 側もこの表を通す。
4. App Store Connect → アプリ → App 情報 → **App Store サーバ通知** に 1 の URL（本番・Sandbox）を入れる。

### 7-3. App Store Connect とアプリでやること

- サブスクリプショングループと商品 `catchwords.pro.yearly` / `catchwords.pro.monthly` を作る（名前・説明・価格・審査用スクリーンショット）。
- 有料アプリ契約（Paid Apps Agreement）・税・口座を入れる。
- 利用規約: アプリ説明文の最後に利用規約（EULA）の URL を書くか、App Store Connect の「使用許諾契約」を設定する（課金画面の「利用規約」リンクは https://catchwords.lovable.app/terms）。
- プライバシーポリシーに Apple のアプリ内課金（Apple が決済し、当社はカード情報を受け取らない）を書き足す。
- 7-2 が入ったら `PlanStore.serverVerifiesAppStore` と `paywallEnabled`、必要なら `catchLimitEnabled` をオンにする。
- Pro の中身（課金画面に並べる特典）はオーナーが決める。今の時点で本当に Pro だけなのは「作り直す」（サーバ側）と、オンにした時の撮影回数の上限解除だけ。切り抜きは全員無料。


---

## 8. 検定のレベルの使い方（2026-10-03 オーナー決定）

> 「単語の検定のレベルのデータは削除して。設定の検定のレベルは表示する例文やチャンクの難易度を徹底するだけに使う。」

### 8-1. iOS でやったこと

- **単語ごとの級は使わない。** `words.level` も `generateCard` の戻りの `level` も読まない（`Word` / `CardDetails` に持たない）。スキャンの辞書引きも `tocfl_level` を読まない。復習4択の補充語（`Models/QuizPool.swift`）は級を持たず、図鑑の語（同じカテゴリ優先）→ 池の語（同じカテゴリ → 同じ部屋）の順。デモのデータからも単語の級を消した。
- ただし保存（`saveSticker`）では、`generateCard` が返した `level` をそのまま返す（iOS は中身を見ない）。送らないとサーバが既定の `"TOCFL-2"` を書くため（`SaveStickerInput`）。`updateWordExtras` の `patch` からは外した。
- **設定の「今のレベル」「目標レベル」**は `profiles.current_level` / `level_goal` に書くだけ。iOS で他に使う所はない。例文とチャンクを作る関数（`generateCard`・`regenerateCardSection`）はサーバが `getUserLevels` → `levelInstruction` で profile から読む。iOS から級を送る項目はサーバの入力にない（作らない）。設定画面に「例文とチャンクを、今のレベルから目標レベルのあいだの難しさで作ります。」と書いた。

### 8-2. 「徹底」にサーバで要ること（このリポジトリからは入れられない）

1. **作った時の級が残っていない。** 例文（`words.example_sentence`）は全員で共有の1行、チャンクや追加の例文は `word_explanations`（表示言語 × 母語 ごとの1行）に入り、どちらも**最初に作った人の級**で書かれたまま。級が違う人や、設定で級を変えた人にも同じ物が出る。級ごとに持つなら、`word_explanations` の鍵に級の段（`parseLevelStep` の 1〜6）を足し、`getWordExplanation` は呼んだ人の段の行を選ぶ（無ければ `ReaderLanguage.needsGeneration` と同じく「作る必要あり」を返す）。共有の `example_sentence` は、その人の段の行に例文があればそちらを出す。
2. それが入るまでの小さい手: 生成のたびに `extras` に作った時の段（例 `level_step`）を書くだけでも、iOS / Web は「今の設定と違う」と分かり、`regenerateCardSection`（`only_if_empty: false`）で作り直しを勧められる。今は Pro 限定の関数なので、級の違いによる作り直しは無料で通す扱いが要る。
3. 級を例文・チャンク以外に使っている所: `suggestWords` / `suggestWordCandidates` / `detectScan`（候補語の難しさ）、`getDueReviews`（4択の補充語を `tocfl_level` / `level_step` で選ぶ。iOS は呼ばない）、`correctMyJournal` / `getJournalPrompts`（日記）。オーナー決定に合わせるなら、ここから級を外す。
4. `words.level` の列や Web 側で単語の級を出す所（`WordCard.tsx` など）は Web とデータベースの話で、iOS からは触らない。
