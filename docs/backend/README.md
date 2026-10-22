# CatchWords を Lovable から自分の Supabase へ移す — オーナーの手順書

この頁は、**オーナー（あなた）にしかできない作業**を、1つずつ順番に書いたものです。
上から順に進めてください。1つ終わるごとに Claude に「手順○が終わった」と伝えてください。

## 守ってほしい約束（全部の手順で共通）

- **鍵（キー・トークン・パスワード）は、チャットに貼らない。** GitHub にも書かない。
  鍵を入れる場所は、この手順書が指定する「金庫」（Supabase の Secrets、GitHub の Secrets）だけです。
- 画面の表示が手順書と違う、ボタンが見つからない、エラーが出た、というときは、
  **その画面のスクリーンショットか、表示された文字をそのまま** Claude に送ってください（鍵が写っていないか確かめてから）。
- 途中でやめても大丈夫です。どの手順も、今公開中のアプリには影響しません。

## 用語

| 言葉 | 意味 |
|---|---|
| Supabase（スパベース） | データベース・ログイン・写真の保存・サーバの処理をまとめて提供するサービス。CatchWords の新しい土台 |
| プロジェクト `catchwords` | あなたの Supabase の中に作った、CatchWords 用の入れ物（ID: `libwmvpoqvxfxbjgqnuj`、東京） |
| 2段階認証 | パスワードに加えて、スマホのアプリに出る6桁の数字でログインする仕組み。パスワードが盗まれても入られない |
| 認証アプリ | 6桁の数字を出すスマホのアプリ。Google Authenticator、Microsoft Authenticator、1Password など。どれでもよい |
| API キー | AI などのサービスを使うための鍵。持っている人は誰でもあなたのお金で AI を使える |
| Secrets（シークレット） | 鍵を入れておく金庫。入れた値は、後から画面にも出ず、コードやログにも出ない |
| GitHub Actions | GitHub が自動で試験やサーバへの反映をしてくれる仕組み |

## 全体の流れ

| 手順 | 内容 | 時間の目安 |
|---|---|---|
| 1 | Supabase に2段階認証を付ける | 5分 |
| 2 | GitHub に2段階認証を付ける | 5分 |
| 3 | 「反映用の鍵」を作って GitHub の金庫に入れる | 5分 |
| 4 | Lovable に入っている鍵の**名前**を書き写して Claude に送る | 5分 |
| 5 | Gemini（Google の AI）の鍵を作って Supabase の金庫に入れる | 10分 |
| 6 | Claude（Anthropic の AI）の鍵を作って Supabase の金庫に入れる | 10分 |
| 7 | Supabase のログイン設定（戻り先・Apple・匿名ログイン） | 10分 |
| 8 | Google でログインできるようにする（Google Cloud の設定） | 20〜30分 |
| 9 | ここまで終わったら Claude に伝える | — |

手順 9 の後、Claude がサーバを反映し、試験用アカウントで動作を確かめます。
その後に「データの移行」「独自ドメイン」「規約の頁」へ進みます（この頁の最後に予定を書いています）。

---

## 手順1. Supabase に2段階認証を付ける（5分）

**目的**: Supabase のパスワードが盗まれても、アプリのデータに入られないようにする。

1. パソコンで https://supabase.com/dashboard を開き、ログインする
2. 画面の右上（または左下）にある **自分のアイコン** を押す
3. **Account preferences**（アカウントの設定）を押す
4. **Security**（セキュリティ）の欄、または左の一覧の **Security** を押す
5. **Multi-factor authentication**（多要素認証）の **Add new app**（または Enable）を押す
6. 画面に **QR コード** が出る
7. スマホの認証アプリを開き、「QR コードを読み取る」で 6 の QR コードを読む
8. 認証アプリに出た **6桁の数字** を、Supabase の画面の入力欄に入れて確定する
9. **回復用コード（Recovery codes）** が出たら、紙に書くかパスワード管理アプリに保存する
   （スマホをなくしたときに、これが無いと二度と入れなくなります）

**できたかの確認**: 一度ログアウトしてもう一度ログインすると、6桁の数字を聞かれる。

---

## 手順2. GitHub に2段階認証を付ける（5分）

**目的**: GitHub が乗っ取られると、アプリのコードを書き換えられ、Supabase への反映も勝手に行われてしまう。それを防ぐ。

1. https://github.com/settings/security を開く（GitHub にログインした状態で）
2. **Two-factor authentication**（2要素認証）の **Enable two-factor authentication** を押す
   （すでに「Enabled」と出ていれば、この手順は終わりです）
3. **Authenticator app**（認証アプリ）を選ぶ
4. 出た QR コードを、手順1と同じ認証アプリで読み取る
5. 認証アプリの **6桁の数字** を入れて **Continue**
6. **Recovery codes**（回復用コード）を **Download** して、安全な場所に保存する
7. 最後まで進めて完了する

**できたかの確認**: https://github.com/settings/security で「Two-factor authentication: Enabled」と出る。

---

## 手順3. 「反映用の鍵」を作って GitHub の金庫に入れる（5分）

**目的**: コードを `main` に入れたときに、GitHub が自動でサーバ（Supabase）を更新できるようにする。

### 3-1. Supabase で鍵を作る
1. https://supabase.com/dashboard/account/tokens を開く
2. **Generate new token**（新しいトークンを作る）を押す
3. 名前（Name）に `github-actions` と入れる
4. **Resource access**（届く範囲）は **Project**（RECOMMENDED）のまま。
   organization を選び、その下の欄でプロジェクト **catchwords** だけを選ぶ
   （「Create legacy token」は全部に届く古い鍵なので使わない）
5. **Permissions**（権限）は Preset を **No access** のままにして、次の2つだけを付ける
   - **Application services** を開き、**Edge Functions** を **Read-write**
   - **Project** を開き、**Project Settings** を **Read**
   他は全部 None のまま。（反映に要るのはこれだけ。鍵が漏れても、データベースや他のプロジェクトには届かない）
6. 有効期限（Expires）を選べる場合は **なし（Never）** か、いちばん長い期間を選ぶ
   （期限が来ると自動の反映が止まります。期限を付けた場合は、その日をカレンダーに入れてください）
7. **Review access** → 内容を確かめて **Generate token** を押す
8. 出てきた長い文字列（`sbp_` で始まる）の横の **コピー** ボタンを押す
   **この画面を閉じると、二度と表示されません。** 3-2 が終わるまで閉じないでください。

### 3-2. GitHub の金庫に入れる
1. 別のタブで https://github.com/nori-creator/rork-catchwords-728/settings/secrets/actions を開く
2. 緑の **New repository secret** を押す
3. **Name** に、次をそのまま入れる（全部大文字、間違えないようにコピーして貼る）

   ```
   SUPABASE_ACCESS_TOKEN
   ```

4. **Secret** に、3-1 でコピーした文字列を貼る
5. **Add secret** を押す

**できたかの確認**: 同じ頁の一覧に `SUPABASE_ACCESS_TOKEN` が出ている（値は表示されません。それで正しい）。

---

## 手順4. Lovable に入っている鍵の「名前」を書き写す（5分）

**目的**: 今のアプリが使っている外部サービスの鍵を、漏れなく新しい金庫へ移すため。
**値（鍵そのもの）は要りません。名前だけです。**

1. https://lovable.dev を開き、プロジェクト **Capture & Connect** を開く
2. 上の **Cloud** タブを押す
3. 左の一覧から **Secrets** を探して押す
   （見つからないときは、Cloud の中の **Settings** や **Overview** の中にあります）
4. 並んでいる **名前**（例: `GEMINI_API_KEY`、`AZURE_SPEECH_KEY`、`APPLE_TEAM_ID` …）を、**全部** 書き写す
5. 書き写した名前の一覧を、Claude へのメッセージに貼って送る

> 値（`AIza…` や `sk-…` で始まる長い文字列）は、絶対に送らないでください。

---

## 手順5. Gemini（Google の AI）の鍵を作って Supabase の金庫に入れる（10分）

**目的**: 写真から単語を見つける・カードを作るなど、アプリの AI の大部分は Gemini で動いている。
Lovable の中にある鍵は取り出せないので、**新しく作る**（古い鍵は、移行が終わったら手順の最後で止める）。

### 5-1. 鍵を作る
1. https://aistudio.google.com/apikey を開く（今 Lovable で使っている Google アカウントでログイン）
2. **Create API key**（API キーを作成）を押す
3. どの Google Cloud プロジェクトに作るか聞かれたら、**今の有料の鍵が入っているプロジェクト**を選ぶ
   （分からなければ、一覧に出ているプロジェクト名をスクリーンショットで Claude に送ってください）
4. できた鍵（`AIza` で始まる）の **コピー** を押す

### 5-2. Supabase の金庫に入れる
1. 別のタブで https://supabase.com/dashboard/project/libwmvpoqvxfxbjgqnuj/functions/secrets を開く
   （Supabase → プロジェクト catchwords → 左の **Edge Functions** → **Secrets**）
2. **Add new secret**（または Name / Value の入力欄）を探す
3. **Name** に次をそのまま入れる

   ```
   GEMINI_API_KEY
   ```

4. **Value** に、5-1 でコピーした鍵を貼る
5. **Save**（保存）を押す

### 5-3. 使いすぎの通知を付ける（強く勧めます）
1. https://console.cloud.google.com/billing を開く
2. 5-1 で選んだプロジェクトにつながっている **請求先アカウント** を選ぶ
3. 左の **予算とアラート（Budgets & alerts）** → **予算を作成**
4. 金額に、ひと月に使ってよい上限（例: 3,000 円）を入れ、50%・90%・100% で通知が来るようにして保存する

> Google の予算は「通知」です。金額に達しても自動では止まりません。通知が来たら Claude に相談してください。

---

## 手順6. Claude（Anthropic の AI）の鍵を作って Supabase の金庫に入れる（10分）

**目的**: Gemini が止まったときの「控えの AI」と、開発者の設定で選べる AI に使う。

### 6-1. 鍵を作る
1. https://console.anthropic.com/settings/keys を開いてログイン
2. **Create Key** を押す
3. 名前に `catchwords-supabase` と入れて作成
4. 出てきた鍵（`sk-ant-` で始まる）の **コピー** を押す（この画面を閉じると二度と表示されません）

### 6-2. Supabase の金庫に入れる
手順 5-2 と同じ頁で、もう1つ追加する。

- **Name**:

  ```
  ANTHROPIC_API_KEY
  ```

- **Value**: 6-1 でコピーした鍵 → **Save**

### 6-3. 使いすぎの上限を付ける（強く勧めます）
1. https://console.anthropic.com/settings/limits を開く
2. 月の上限金額（Spend limit）を、使ってよい金額（例: 20 ドル）に設定する
   （Anthropic の上限は、達すると実際に止まります）

---

## 手順7. Supabase のログイン設定（10分）

### 7-1. ログイン後の戻り先を登録する
**目的**: Google でログインした後、Supabase がアプリ（CatchWords）に戻ってこられるようにする。
登録した戻り先以外には戻さないので、他人の偽アプリに鍵を渡す攻撃を防げる。

1. https://supabase.com/dashboard/project/libwmvpoqvxfxbjgqnuj/auth/url-configuration を開く
   （Supabase → catchwords → 左の **Authentication** → **URL Configuration**）
2. **Redirect URLs** の **Add URL** を押す
3. 次をそのまま入れて保存する

   ```
   catchwords://auth-callback
   ```

4. **Site URL** は、今は変えない（独自ドメインを取った後に Claude が案内します）

### 7-2. Apple でログインできるようにする
**目的**: iPhone 標準の「Apple でサインイン」の画面から、そのままログインできるようにする。

1. https://supabase.com/dashboard/project/libwmvpoqvxfxbjgqnuj/auth/providers を開く
   （Authentication → **Sign In / Providers** または **Providers**）
2. 一覧の **Apple** を押す
3. **Enable Sign in with Apple**（または Enabled）をオンにする
4. **Client IDs** に、次をそのまま入れる（アプリの識別名）

   ```
   com.nori.catchwords
   ```

5. **Secret Key**（秘密鍵）などの欄は **空のまま** で **Save**
   （iPhone 標準の画面だけを使う方式では不要です。Supabase の公式手順で確認済み）
   保存できずにエラーが出たら、その文字を Claude に送ってください。

### 7-3. 匿名ログインがオフになっているか確かめる
1. 同じ **Sign In / Providers** の頁で、**Allow anonymous sign-ins**（匿名ログインを許可）を探す
2. **オフ** になっていれば、そのままでよい（オンなら、オフにして保存）

**理由**: 匿名ログインは開発用です。本番でオンだと、誰でもアカウントを大量に作れてしまいます。

---

## 手順8. Google でログインできるようにする（20〜30分）

**目的**: アプリの「Google でログイン」を、Lovable ではなく自分の設定で動かす。
Google 側に「CatchWords というアプリが、ログインをお願いしています」という登録をする作業です。

### 8-1. Google Cloud のプロジェクトを選ぶ
1. https://console.cloud.google.com を開く
2. 画面上部の **プロジェクトの選択** を押し、手順5で使ったプロジェクトを選ぶ
   （別にしたい場合は **新しいプロジェクト** → 名前 `CatchWords` で作っても構いません）

### 8-2. 「同意画面」を作る（ログインのときに利用者に見せる画面）
1. 左上のメニュー（≡）→ **API とサービス** → **OAuth 同意画面**
   （画面によっては **Google Auth Platform** という名前で表示されます）
2. **開始（Get started）** を押す
3. **アプリ情報**
   - アプリ名: `CatchWords`
   - ユーザー サポートメール: あなたのメールアドレス
   → **次へ**
4. **対象（Audience）**: **外部（External）** を選ぶ → **次へ**
5. **連絡先情報**: あなたのメールアドレス → **次へ**
6. ポリシーへの同意にチェック → **作成**

### 8-3. ログイン用の「クライアント」を作る
1. 左の **クライアント（Clients）** を押す
   （古い画面では **API とサービス** → **認証情報** → **認証情報を作成** → **OAuth クライアント ID**）
2. **クライアントを作成（Create client）**
3. **アプリケーションの種類**: **ウェブ アプリケーション**
   （iPhone アプリですが、ここは「ウェブ アプリケーション」が正しいです。Google との受け渡しは Supabase が行うため）
4. 名前: `Supabase`
5. **承認済みのリダイレクト URI** の **URI を追加** を押し、次をそのまま入れる

   ```
   https://libwmvpoqvxfxbjgqnuj.supabase.co/auth/v1/callback
   ```

6. **作成** を押す
7. **クライアント ID** と **クライアント シークレット** が表示される。この画面は閉じずに 8-4 へ

### 8-4. Supabase に入れる
1. https://supabase.com/dashboard/project/libwmvpoqvxfxbjgqnuj/auth/providers を開く
2. 一覧の **Google** を押し、**Enable Sign in with Google** をオンにする
3. **Client ID** に 8-3 の **クライアント ID** を貼る
4. **Client Secret** に 8-3 の **クライアント シークレット** を貼る
5. **Save**

### 8-5. 誰でもログインできるように「公開」する
1. Google Cloud の **OAuth 同意画面**（または Google Auth Platform）→ **対象（Audience）**
2. 公開ステータスが **テスト中（Testing）** なら、**アプリを公開（Publish app）** を押して確定する
   （テスト中のままだと、登録したテストユーザーしか Google でログインできません）
3. 「確認が必要」と出た場合は、その画面のスクリーンショットを Claude に送ってください
   （メール・名前だけを使う今回の設定では、通常は Google の審査は要りません）

---

## 手順9. Claude に伝える

ここまで終わったら、Claude に「手順1〜8が終わった」と送ってください。手順4の名前の一覧もここで送ってください。

Claude が次を行います。
1. サーバを Supabase に反映する（GitHub Actions を動かす）
2. 試験用アカウントで、AI を使う機能まで動くか確かめる
3. 結果を報告し、次の段階（データの移行）を案内する

---

## この後の予定（今はまだ何もしなくてよい）

| 段階 | 内容 | オーナーの作業 |
|---|---|---|
| データの移行 | Lovable にある単語・辞書・あなたのカードと写真を、新しい Supabase へ移す | Lovable の書き出し（Export）を1回。**Claude が道具を用意してから**行う |
| 独自ドメイン | `catchwords.app` のような自分の住所を取る | ドメインの購入（年 2,000〜4,000 円程度。種類で変わる） |
| 規約・サポートの頁 | 独自ドメインの上に、規約・プライバシーポリシー・サポート・パスワード再設定の頁を置く（GitHub Pages、無料） | 文面の確認 |
| 確認メールの送り元 | パスワード再設定などのメールを、独自ドメインから送る | メール送信サービス（Resend など、少量は無料）の登録 |
| 公開の準備 | Supabase を Pro に切り替え、新しい版を審査に出す | 支払いの設定、App Store Connect の URL の書き換え |
| Lovable を止める | 新しい版が公開されてから | Lovable Cloud の停止、古い AI の鍵の無効化 |

---

## 片付け（Claude の作業の途中で残った物。急がない）

どれも外からは使えない物です。手順9の後、Claude の確認が終わってから行います。

1. https://supabase.com/dashboard/project/libwmvpoqvxfxbjgqnuj/sql/new を開く（Supabase → **SQL Editor**）
2. 下を貼って **Run**（確認が出たら **Run this query**）

   ```sql
   -- 2026-10-20 の作業の途中で作った物（アプリは使っていない）
   drop function if exists public._probe();
   drop schema if exists _mig cascade;
   drop schema if exists stage cascade;
   drop role if exists cw_migrator;
   drop extension if exists pg_net;
   ```

3. **Edge Functions** → `migration-intake` → **Delete**
4. 試験用アカウント `e2e-test@catchwords.invalid` は、Claude が「消してよい」と言ってから
   **Authentication** → **Users** → そのアカウント → **Delete user**

---

## 技術の覚え書き（Claude と開発者向け）

```
iPhone アプリ（ios/）
   │
   ▼
Supabase「catchwords」（ap-northeast-1、ref: libwmvpoqvxfxbjgqnuj）
   ├ データベース …… supabase/migrations/（Lovable 本番と項目ごとに照合して一致）
   ├ ログイン ……… メール・Apple（id_token）・Google（OAuth + PKCE、catchwords://auth-callback）
   ├ ストレージ …… stickers / tts / avatars
   └ Edge Function native-fn … server/（AI の鍵は Edge Function の Secrets だけ）
```

- `main` に入ると `.github/workflows/server.yml` が試験して反映する（`SUPABASE_ACCESS_TOKEN` が要る）。
  手で動かすとき: Actions → Server（サーバ）→ Run workflow（ブランチを選べる）。
- サーバが読む鍵の名前: `GEMINI_API_KEY`、`ANTHROPIC_API_KEY`、読み上げの `AZURE_SPEECH_KEY` / `AZURE_SPEECH_REGION`、
  Apple の退会処理の `APPLE_TEAM_ID` / `APPLE_KEY_ID` / `APPLE_PRIVATE_KEY` / `APPLE_SERVICES_ID`（手順4の結果で確定）。
