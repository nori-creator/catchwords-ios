# CatchWords のサーバとデータ（Lovable から自分の Supabase へ）

2026-10-20 に、iOS 版のサーバとデータを Lovable Cloud から**自分の Supabase**へ移し始めた。
この頁は、その全体像と、オーナーにしかできない手順をまとめる。

## 全体像

```
iPhone アプリ（ios/）
   │
   ▼
Supabase「catchwords」（東京 ap-northeast-1、ID: libwmvpoqvxfxbjgqnuj）
   ├ データベース …… supabase/migrations/（表・決まり・権限）
   ├ ログイン ……… メール・Apple（iPhone 標準の画面）・Google（Supabase の画面）
   ├ ストレージ …… 写真（stickers）・発音（tts）・アイコン（avatars）
   └ Edge Function native-fn … server/（AI の処理。AI の鍵は Supabase の Secrets だけに置く）
```

- コードを main に入れると、GitHub Actions（`.github/workflows/server.yml`）が試験してから Supabase に反映する。
- Lovable は使わない。Web 版（Lovable-catch-words-app）は試作として残るが、iOS 版はそれに頼らない。

## できていること（2026-10-20）

| 項目 | 状態 |
|---|---|
| Supabase プロジェクト（東京） | 作成済み（無料プラン） |
| 表・決まり（RLS）・権限・写真の置き場所 | 適用済み。Lovable 本番と項目ごとに照合して一致 |
| サーバ（AI の処理など約 70 機能） | `server/` に移植済み。単体試験 1464 件が通る。実際のログインで呼べることを確認 |
| iOS の接続先・Google ログイン・Apple ログイン | 書き換え済み（この PR） |
| Supabase のセキュリティ点検 | 重大な指摘なし（下の「片付け」を除く） |

## オーナーの手順（上から順に）

### 1. Supabase と GitHub のアカウントを守る（5 分）
1. Supabase: 右上のアイコン → Account preferences → **Multi-factor authentication** を有効にする
2. GitHub: Settings → Password and authentication → **Two-factor authentication** を有効にする

### 2. GitHub に「反映用の鍵」を入れる（5 分）
1. https://supabase.com/dashboard/account/tokens → **Generate new token**（名前は `github-actions`）→ 出た文字列をコピー
2. GitHub で `rork-catchwords-728` → Settings → Secrets and variables → Actions → **New repository secret**
3. Name に `SUPABASE_ACCESS_TOKEN`、Secret に 1 でコピーした文字列 → Add secret

> この鍵はチャットに貼らない。GitHub の金庫に入れると、画面にもログにも出ない。

### 3. AI と読み上げの鍵を Supabase に入れる（10 分）
Supabase → プロジェクト catchwords → **Edge Functions → Secrets** → Add new secret。

| Name | 値の取り方 |
|---|---|
| `GEMINI_API_KEY` | https://aistudio.google.com/apikey → Create API key（新しく作るのを勧める） |
| `ANTHROPIC_API_KEY` | https://console.anthropic.com/settings/keys → Create Key |
| `AZURE_SPEECH_KEY` / `AZURE_SPEECH_REGION` | 読み上げは今 Azure を使っている（本番の設定 `tts_voice`）。Azure portal の Speech リソース → Keys and Endpoint |

Lovable の Cloud → Secrets に、ほかの名前（`APPLE_*`、`ELEVENLABS_API_KEY` など）があれば、
**名前だけ**教えてください（値は不要）。同じ物が要るかを確かめます。

各社の画面で**月の上限金額**も設定してください（Google AI Studio の Billing、Anthropic の Limits）。
鍵が盗まれても、請求が上限を超えません。

### 4. ログインの設定（30 分。画面ごとに案内します）
Supabase → **Authentication**:
1. **URL Configuration → Redirect URLs** に `catchwords://auth-callback` を追加
2. **Providers → Apple** を有効にし、**Client IDs** に `com.nori.catchwords`
3. **Providers → Google** を有効にする。Google Cloud Console で OAuth クライアント（ウェブ アプリケーション）を作り、
   承認済みのリダイレクト URI に `https://libwmvpoqvxfxbjgqnuj.supabase.co/auth/v1/callback`。
   出た Client ID と Client secret を Supabase に入れる
4. **Sign In / Providers → Allow anonymous sign-ins** はオフのまま（本番では使わない）

### 5. データを移す（後日。道具を用意してから案内します）
Lovable 公式の Export（Cloud → Overview → Advanced settings → Export project data）で控えを取り、
新しい Supabase に入れる。写真は `scripts/migrate/storage.mjs`（Web 版のリポジトリ）と同じ方式で運ぶ。

### 6. 規約の頁とドメイン（決めること）
規約・プライバシーポリシー・サポート・パスワード再設定の頁は、まだ `catchwords.lovable.app` にある
（`ios/CatchWords/AppConfig.swift` の `webBaseURL`）。移し先（独自ドメイン＋GitHub Pages など）と、
パスワード再設定のメールの送り元（独自ドメイン＋メール送信サービス）を決める。
プライバシーポリシーの「提供先」（Lovable・Cloudflare）も書き直しが要る。

### 7. 公開の前に
- Supabase を **Pro**（月 25 ドル〜）にする（無料版は使われないと一時停止され、控えをダウンロードできない）
- 新しい版を審査に出し、公開されるまで **Lovable の契約は切らない**（今の公開版は Lovable を見ている）

## 片付け（作業の途中で残った物。どれも外からは使えない）

Supabase → **SQL Editor** で、下を貼って Run（確認が出たら Run this query）:

```sql
-- 2026-10-20 の作業の途中で作った物（アプリは使っていない）
drop function if exists public._probe();
drop schema if exists _mig cascade;
drop schema if exists stage cascade;
drop role if exists cw_migrator;          -- 無効化済みの一時ログイン
drop extension if exists pg_net;
```

- Edge Functions → `migration-intake`（中身は「410 終了」だけ）→ Delete
- 試験用のアカウント `e2e-test@catchwords.invalid` は、サーバの反映を確かめた後に消す
  （Authentication → Users → そのアカウント → Delete user）
