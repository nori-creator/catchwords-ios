# 第3回（qa-2026-11-02-round3.md）の新しい指摘の再検証（2026-11-03、HEAD 5b35424 / origin/main 7403344 の上）

| 番号 | 一言の内容 | 判定 | 重さ | 根拠（file:line・実行結果） |
|---|---|---|---|---|
| S4 | 読みの点検が台湾の読みを大陸の読みに書き換える | 確認 | 高 | `server/src/lib/tw-reading.server.ts:59-69`（TW_CHARS に 嬤・夕・究・播・叔・績・突・惜・傍・和 が無い）。`checkTaiwanReading` を実行: 阿嬤 ā mà→ā mó、夕陽 xì→xī、研究 jiù→jiū、廣播 bò→bō、叔叔 shú→shū、成績 jī→jì、突然 tú→tū、可惜 xí→xī、傍晚 bāng→bàng、和 hàn→hé（すべて `fixed:["pinyin","zhuyin"]`）。`scratchpad/verify/s4.v.test.ts` |
| S5 | 例文の読みが多音字を間違える | 確認 | 中 | `sentence-readings.server.ts:45-60` を実行: 還你錢 hái・長得 cháng dé・跑得 dé・我得去 dé・睡不著 bù zhe・洗髮精 fā・包子/鞋子 zǐ・慢慢地 dì・幹嘛 gān・啦 lā・喔 wō・欸 ǎi・耶 yē。報告どおり（注音設定では出ないのでピンインの人だけ。重さは中）。`verify/s5.v.test.ts` |
| S1 | App Store の 1.0.3 は旧サーバー（Lovable）につながる・更新を促せない・ポリシー URL も旧 | 確認（App Store の今の状態は 確かめられない） | 高 | `git show 582118b:ios/CatchWords/AppConfig.swift:13`（1.0.3 = `catchwords.lovable.app`）、今は `AppConfig.swift:13,57`（catchwords.app・自前の Supabase）。1.0.4 への上げは ddf93fc（10-23「1.0.3 は承認済み」）。版をサーバーに伝える・更新を促す仕組みは grep で 0 件（minVersion/forceUpdate/app_version 無し）。`docs/app-store/backup-zh-Hant/app-info.zh-Hant.json` の privacyPolicyUrl = `catchwords.lovable.app/privacy`。App Store Connect の今の値・販売状態はこの環境から見られない |
| S2 | AI の全体の枠（無料 2,500/日）を1〜2人で使い切れる | 確認（本番の環境変数は 確かめられない） | 高 | `server/src/lib/ai-cap.ts:54-89`: 全体の枠に数える種類の1人の上限の合計は 2,604/日（tts・jev_rank を除く。scan_detect 300・scan_parts 300・suggest 300・image_sense 300・card 200・native_text 200・scene_label 200…）。`:133` 無料の既定 2,500。キャッチ5回の上限は `ViewModels/PlanStore.swift:13` の端末だけ（サーバーに catch の上限は grep で無し） |
| S3 | 語を入力して探す時、番地までの住所を AI に送る（同意・ポリシーに無い） | 確認 | 高 | `ViewModels/CaptureViewModel.swift:248-250,320`（`placeName` を `scene` で送る）、`Services/LocationService.swift:124-136`（精度 50m 以内なら番地まで）、`Services/AIService.swift:92`、`server/src/lib/ai.functions.ts:1123-1124`（「その場の様子: 『…』この様子に合うものを優先」をプロンプトへ）。`site/src/privacy.ja.html` §4 の AI に送る物・同意の画面の「送るもの」に位置は無い |
| S6 | ↻（作り直す）は管理者だけ | 決定で対象外 | — | 決定 13 = B「今のまま管理者だけ」（decisions-2026-11-03.md）。事実は正しい（`ai.functions.ts:2743` Pro か管理者、Pro は売っていない）。CLAUDE.md の「↻ を押した語だけ」の記述と学習者の体験の食い違いは残る（文書の直しの話） |
| S7 | 「今日」が台北の日付とアプリ内の端末の日付で混在 | 確認 | 中 | 台北: `PlanStore.swift:218,241`・`ReviewStore.swift:286-289`・`Models/SRS.swift:39-52`。端末: `HomeView.swift:192,270,408-424,495`・`Services/WidgetBridge.swift:55`・`ReviewStore.swift:418`（`Calendar.current.isDateInToday`）。決めてほしいこと 14 は未回答。利用者の多くは台湾なので重さは中 |
| S8 | 共有の辞書（words）がログインなしで読め、最初に足した人の ID も付く | 確認 | 中 | `supabase/migrations/20261020104215_baseline_part3_policies_grants_storage.sql:141`（`words_select_all … USING (true)`、ロールの指定無し）、`:389`（anon に SELECT）。列 `created_by`（part2 `:131`）は書かれる（`stickers.functions.ts:1015`）。後の移行で取り消しは無い。ID だけで名前は出ないので中 |
| S9 | カードを好きな語で自分で作れる（語の ID を確かめない） | 確認 | 中 | `…part3…sql:89`（`stickers_insert_own` は user_id だけ）、`:357-358`（anon/authenticated に ALL）。所有の確認は「その語のカードがあるか」だけ（`ai.functions.ts:2748-2756`、`:3743-3751` reportAndFixSection）。ただし書き直し（write）は Pro/管理者だけ（`:2743`）なので報告の主張より範囲は狭い。キャッチ上限はもともと端末だけ |
| T1 | 閉じる・ロックで保存が途中で止まる（`beginBackgroundTask` が無い） | 一部 | 中 | `beginBackgroundTask`・`BGTaskScheduler` は ios/ で 0 件（grep）。ただしロック・裏へ回すだけなら通信の失敗として `Views/CaptureView.swift:830-848` の `keepUnsaved` に入り「保存待ち」で同じ `client_catch_id` で再保存（`Services/DexStore.swift:1036-1050`）— 二重にはならない。報告の「解析待ちに戻り AI でもう一度・二重」は**アプリが強制終了された**時だけ（`PendingQueue.add` は撮った時 `CaptureViewModel.swift:187`、成功の `remove` は `CaptureView.swift:819` で、間に落ちると「解析中」のまま残り `PendingRetry` が再解析） |
| T2 | 応答が失われた「保存待ち」を消すと、本当は保存済みの語の写真をストレージから消す | 確認（条件付き） | 中 | `Services/DexStore.swift:1090-1107` `discardUnsaved` はサーバーを確かめずに `ps.uploads` の object/cutout/selfie を `removeObject`。保存済みの札も同じ置き場所を指す（`draft.uploaded` を使い回す `:1043`） |
| T3 | 2回目以降・置き換えた・削除した語の写真がストレージに残る | 確認 | 中 | `server/src/lib/stickers.functions.ts:1851-1860` `stickerStoragePaths` は札の3枚だけ（再会 `encounters` の image/cutout/selfie は消さない。行は連鎖削除）。`replaceStickerPhoto` `:1903-1935` と `encounterPatch` `encounters.functions.ts:211-229` は古い写真・切り抜きを指さなくするだけで消さない。iOS も `removeObject` は avatars だけ（grep）。ポリシー §8「写真…はアプリの中で直接直せます」、§7 は退会で消える |
| T4 | 端末の時計が進んでいると、保存されない採点を「答えた」と数える | 確認 | 低 | iOS は端末の今で `due_at=lte.<now>` を読む（`ViewModels/ReviewStore.swift:224-229`）、サーバーは自分の時計で期限前なら `duplicate:true` を返して保存しない（`reviews.functions.ts:997-1004`、`review-grade-guard.ts` の1分の余裕）。iOS に `duplicate` を読む所は無い（grep）。時計が1分以上進んでいる人だけなので低 |
| T5 | 自動の再保存は5回失敗で30日止まる | 確認 | 低 | `Services/PendingRetry.swift:21`（maxAttempts 5）、`:193`（5回で isDue=false）、`:366-369`（30日触らない記録を捨てる＝その後に再開）。通信が無い時は数えない（`:271-276`）が、タイムアウト・切断は数える（`CatchSave.swift:46-60`）。手で押せばいつでも再保存できる（`:12`）ので低 |
| T6 | 前に戻しても図鑑を読み直さない（2台目の語が出ない） | 確認 | 低 | `Views/RootView.swift:193-203`（active で `dex.load` を呼ばない。`review.preload` は図鑑に無い札を落とす `ReviewStore.swift:235`）。ホームの引っぱって更新（`HomeView.swift:256`）と起動・言語切替でだけ読む。2台で使う人だけなので低 |
| T7 | 表示言語を変えると古い語の意味が図鑑・復習・ウィジェットで消える | 確認 | 中 | `server/src/lib/word-explanation.functions.ts:440` `getReaderMeanings` は読むだけ（その言語の行が無ければ返さない）。埋める `fillReaderMeanings`（`:635`）は iOS から呼ばれない（grep で iOS に 0 件）。`Services/DexStore.swift:1207,1276-1279` は読めた意味だけを使う。単語の頁を開くと `loadExplanation`（`WordDetailView.swift:1612`）で作られる |
| T8 | 同じ iPhone の2つ目のアカウントはその日チュートリアルを終えられない | 確認 | 中 | 回数は端末共通の `plan.used`/`plan.day`（`ViewModels/PlanStore.swift:195-207`、退会・サインアウトで消す所は grep で無し）、ようこその週の初日はキーチェーン `plan.firstDay`（`:210-220`）。シャッターは `plan.canCatch` だけを見る（`Views/CaptureView.swift:191,591,640`、案内中の例外無し）。審査は普通まっさらな端末なので中 |
| T9 | 復習の「n 語待ち」が1日の上限を無視、上限後も通知 | 一部 | 低 | ウィジェットの数は上限を見ない（`Services/WidgetBridge.swift:46-47`）。上限のシートの文「図鑑の単語の復習は、いつでも何回でもできます。」（`Views/CatchLimitSheet.swift:30`）。ただし通知は「30 分ごと」ではない — アプリを開いた時に次の1回（期限の札＋最低30分後）と習慣の1回を組むだけ（`Services/ReminderService.swift:77-83,94-108`、繰り返さない `repeats:false`） |
| T10 | 語を消すと復習の記録も消え、今日の数・連続日数が変わる | 確認 | 低 | `supabase/migrations/…part2…sql:447,450,456`（review_history・reviews は stickers に ON DELETE CASCADE）。連続日数と今日の数は review_history から数える（`ReviewStore.swift:276-289`）。確認の文は「この単語を図鑑から削除しますか？」だけ（`WordDetailView.swift:445`） |
| T11 | 消した語の場所のリマインドが次の起動まで残る・消した語が復習に残る | 一部 | 低 | 場所のリマインドは確認: `DexStore.delete`（`Services/DexStore.swift:2016-2029`）は `applyPlaces` を呼ばず、組み直しは起動・言語切替・設定だけ（`RootView.swift:129,188`、`SettingsView.swift:649`）。復習に残る方は**誤り**: f20eb06（10-15）から `ReviewView.swift:192,197` が `dropDeleted` で外す（最後の1語を消して図鑑が空の時だけ外れない `ReviewStore.swift:462`） |
| T12 | 撮った時刻に時差の情報が無く、旅行後に日・時刻がずれる | 確認 | 低 | `taken_at timestamptz` だけ（`…part2…sql:15`）、時差の列は無い（grep）。表示とアルバムの日は端末の `Calendar.current`（`HomeView.swift:408-409`） |
| T13 | カメラロールの写真は場所は写真の物、日付は今日 | 確認 | 低 | 場所は写真の位置（`CaptureViewModel.swift:255` `locate(given)`）、日付は送らずサーバーの `DEFAULT now()`・端末の仮の札も `Date()`（`Services/DexStore.swift:805,940`）。決めてほしいこと 17 は未回答 |
| T14 | 端末の日付を変えると上限が戻る、未来の時計でようこその週が延びる | 確認 | 低 | `PlanStore.swift:196-199,241`（端末の時計の台北の日）、`:210-226`（初日はキーチェーンに最初の時計で固定、未来なら差が負で `n < 7` が続く）。上限はもともと端末だけなので低 |
| T15 | ポリシーに無い機能（声で調べる・マイク・日記）、同意の取り消しの道順が違う | 確認 | 中 | `site/src/privacy.ja.html` §1「音声（iPhone アプリの『声で調べる』）」、§4「設定の『プライバシー』→『AIへのデータ送信の同意』」（en も同じ）。アプリにマイク・音声認識は無い（SFSpeech・NSMicrophone が ios/ で 0 件）、同意は「規約と表記」→「AIへのデータ送信」（`Views/SettingsView.swift:385-389`）。日記は `DiaryFeature.enabled=false` |
| T16 | ポリシーは「運営者は地名だけ見る」だが番地まで保存し開発者の画面で見える | 確認（App Store の回答は 確かめられない） | 中 | ポリシー §2「撮影した場所の名前（地名）を閲覧」。`LocationService.swift:134`（精度50m以内で番地）、`server/src/lib/admin-users.functions.ts:185,237-241`（location_name をそのまま集計）、`Views/Admin/AdminUserDetailView.swift:185-189`（topPlaces を表示）。b7b7d2f で許可の文は「番地まで」に直したがポリシーは 10-27 のまま |
| T17 | 広告の内容の年齢上限・子ども向けの印が無い、4+ と「追跡なし」 | 確認（審査の判断は推定） | 中 | `maxAdContentRating`・`tagForChildDirected`・`tagForUnderAge` は ios/ で 0 件。`docs/app-store/README.md:30` 4+、`PrivacyInfo.xcprivacy` NSPrivacyTracking=false、ポリシー §6「興味に合わせた広告」 |
| T18 | 規約 §9 の上限が「その月に払った料金」= 0 円、§6 は売っていない定期購入を説明 | 確認（法の判断は専門家） | 低 | `site/src/terms.ja.html` §9（45-46 行目相当: 軽過失は「その月に支払った料金」が上限）、§6（定期購入の説明、`paywallEnabled=false` `PlanStore.swift:28`）。重過失は除外済みなので8条の全部無効ではなく、無料の人に事実上の全部免責になる点の恐れ |
| T19 | アプリを消してもログインが残る | 確認 | 低 | `Services/KeychainStore.swift:16`（キーチェーン、`AfterFirstUnlock`）、`SupabaseClient.swift:71` 起動時に読み戻す。初回起動の印で消す処理は無い（grep）。ポリシー §7「アプリを削除した場合も、端末の中の情報は消えます」 |
| T20 | 表示名の初期値がメールの @ の前 | 確認 | 低 | `supabase/migrations/20261023120000_auth_email_language.sql:19`（`split_part(NEW.email,'@',1)`）。ポリシー §2「メールアドレス…は閲覧の対象に含めません」 |
| T21 | 旧サーバーにデータの写しが残る・移行用の関数が設定に残る | 確かめられない（設定に残るのは確認） | 中 | `supabase/config.toml:11-13`（`migration-import`、`verify_jwt=false`、「TEMPORARY…delete after the move」）、`supabase/functions/migration-import/` も残る（実行は x-run-token の SHA-256 で守る `index.ts:33`）。本番に配備されているか・Lovable 側の中身はこの環境から見られない |
| M1 | 復習の間隔が 24 時間×n で夏時間・早めの復習で1日ずれる | 確認 | 低 | `server/src/lib/reviews.functions.ts:1076`（`now + interval_days*86400*1000`）。期限は日でなく時刻なので、前日より早い時刻に開くと翌日に回る。設計の選び方の話 |
| M2 | 和暦・仏暦の端末で年が変わる | 確認（一部の画面） | 低 | `Date.FormatStyle` は暦を指定せず端末の暦: `Views/CatchCelebrationView.swift:314`（「この言葉、{date}にゲット」）、`Views/AIConsentSettingsSheet.swift:140`。単語の頁などの `JPDate`（`Utilities/Theme.swift:75-105`）は `DateFormatter.locale = L10n.locale` で西暦 |
| M3 | 日付・時刻の形が端末の地域・12/24 時間に従わず、6:17 PM と 18:17 が混在 | 確認 | 低 | 形は表示言語の locale だけ（`Utilities/L10n.swift:113`）。`JPDate.time` は "jmm"（en で 6:17 PM）、`JPDate.full` は "yMMMdHHmm"（HH で常に 24 時間）`Theme.swift:88-102` |
| M4 | 発音の速さのボタンが es・vi で「0.8×」、説明は「0,7×」 | 確認 | 低 | `Views/SectionsPanel.swift:224-225`（`String(format: "%.1f×")` で常に点）、strings.json「長押しはこの 0.7 倍」の es「0,7×」・vi「0,7×」 |
| M5 | 再会の記録を二度送ると二重 | 確認 | 低 | `server/src/lib/encounters.functions.ts:105-133`（重複を防ぐ鍵なしで insert）。応答が失われると iOS は失敗として写真を「解析待ち」に残し（`Views/CaptureView.swift:767-780`）、もう一度押すと2行目 |
| M6 | 語の削除を二度送ると「このカードは削除できません」が 500 | 確認 | 低 | `stickers.functions.ts:1837`（ただの Error）→ `native-fn.ts:200-227` で 500。Sentry は 500 番台を送る |
| M7 | Duo を回す・畳むと単語の頁が閉じて開き直す（チュートリアル中は復習へ進む） | 確認 | 低 | `Views/MainTabView.swift:386-397`（幅・帯の有無で sheet／fullScreenCover／画面の中を切り替え、それぞれ `onDismiss: wordPageDismissed`）、`:266-270`（案内中は `startTourReview()`）。#26 の後も同じ |
| M8 | 退会の最中の写真の送信が残る・応答が失われると端末の掃除が走らない | 確認（時間しだい） | 低 | 退会で送信中の作業を止める処理は無い（`Services/AccountCleanup.swift:40-60` は終わった後の掃除だけ、成功の後にだけ呼ばれる `SettingsView.swift:653-664`） |
| M9 | オンボードの終わりで「終わった」を先に書き、見本・チュートリアルの印は後 | 確認 | 低 | `Views/OnboardingView.swift:586`（onboarded=true を保存）→ `:594` 通信（`updateUserMetadata`）→ `:595-599` 見本と案内の印。間で落ちると `RootView.swift:16` が質問を出さず見本・案内も無い |
| M10 | 先行アップロードがアプリが落ちると指されないまま残る | 確認 | 低 | `ViewModels/CaptureViewModel.swift:628-642`（捨てるのはプロセスの中の `discardPreupload` だけ） |
| M11 | 復習が待っていることがホームにもタブにも出ない | 確認 | 中 | 「復習待ち」の数は `Views/UserStatsPanel.swift:69` だけ。タブの印（badge）は grep で0件 |
| M12 | 4択に「わからない」が無い | 確認 | 中 | `Views/ReviewView.swift` に「わからない」・スキップの選択肢は無い（grep）。決めてほしいこと 18 は未回答 |
| M13 | 写真の機能（表示する写真・写真を替える等）が長押しでしか開かない | 確認 | 中 | #26（7403344）の後も `Views/WordDetailView.swift:747-751`（`HoldPress` の長押しで `pickingHero`）。角の小さなアイコンは元の写真・自撮りの切り替えだけ（CLAUDE.md 11-01）。ほかの入口は VoiceOver の操作 `:1108` だけ |
| M14 | 単語の頁に記憶の％も「いま復習する」も無い（`router.reviewNow` が未使用） | 確認 | 低 | `router.reviewNow` を書く所が無い（`MainTabView.swift:105` の宣言と `ReviewView.swift:200,254-257` の読む所だけ） |
| M15 | 間違えた時に選んだ語の意味が出ない・結果に間違えた語の一覧が無い | 確認 | 低 | `Views/ReviewView.swift:729-765`（選択肢は見出しと ✓✗ だけ）、結果は数だけ（`:856-858`「まちがえた n 語をもう一度」） |
| M16 | 注音が小さい（字の 0.3 倍・最小 7pt） | 確認 | 中 | `Views/ZhuyinWordView.swift:144`（`zhuyinScale = 0.3`）、`:264`・`:384`（下限 7）。文字の大きさの設定は呼ぶ側の `size` 次第（単語の頁は `textScale` を掛ける `WordDetailView.swift:550`、復習は固定 25〜32 `ReviewView.swift:741`） |
| M17 | 発音の速さが単語の頁だけ | 確認 | 低 | `SoundService.speak(_:rate: = 1)`（`Services/SoundService.swift:449`）。速さ `detail.speechRate` は単語の頁の項目だけが使う（grep） |
| M18 | 知らせが 2.4 秒で消え、VoiceOver に読まれない | 一部 | 低 | 2.4 秒は単語の頁だけ（`WordDetailView.swift:1722-1727`）、ほかは 3〜3.5 秒（`CaptureViewModel.swift:717`、`MainTabView.swift:112`）。読み上げの通知は保存の「保存しました」だけ（`SaveStatus.swift:69`） |
| M19 | 4択のスピーカーが答えの行の中、横を押すと答えてしまう | 確認 | 低 | `ReviewView.swift:735-761`（行全体が答えのボタン、その上にスピーカーを重ねる。40pt の丸の外は答えになり、取り消せない `.disabled(revealed)`） |
| M20 | 見出しの鉛筆は語を作り直す重い操作で、場所の鉛筆と紛らわしい | 確認 | 低 | `WordDetailView.swift:553-558`（見出しの鉛筆）、`:1298,1316`（場所の鉛筆）、`saveHeadword` → `dex.setHeadword`（`:1589-1606`、別の語になり中身は作り直し）。使いやすさの判断 |
| M21 | 単語の頁から次の語へめくれない・復習を絞れない | 確認 | 低 | 単語の頁に前後の語へ移る操作は無い（grep）。`ReviewStore` に日・カテゴリーの絞り込みは無い |
| M22 | 地図の画面に日付の切り替えが2か所 | 確認 | 低 | 上の「日付」の絞り込み（`Views/DexView.swift:342,405`）と地図の下の日の帯（`:1393-1406` 前の日・次の日・カレンダー） |
| M23 | アプリの中に使い方・用語の説明が無い | 確認 | 低 | 設定はサポートの Web ページへのリンクだけ（`SettingsView.swift:398`）。ヘルプ・用語の文は strings.json に無い |
| M24 | オンボードの準備の画面の青いカメラの丸が押せない | 確認 | 低 | `Views/OnboardingView.swift:963-973`（絵だけの ZStack、ボタンでない） |
| M25 | 「レベル」が XP と TOCFL の2つの意味 | 確認 | 低 | `Views/UserStatsPanel.swift:129,138`（XP の「レベル n」）と設定・オンボードの TOCFL のレベル |
| M26 | 最初の1分で許可の確認が重なる・「カメラロールに保存」が既定でオン | 確認 | 低 | `SettingsView.swift:15`（`photos.sync` 既定 true）、`DexStore.swift:1488-1496`（最初の保存で写真の許可を求める）。重なり方は実機で見ていない |
| M27 | メールの確認のリンクが法的文書のページに着く | 確かめられない | 低 | 登録の時に `redirect_to` を渡していない（`SupabaseClient.swift` は再設定だけ `:129`）。着く先は本番の Supabase の Site URL の設定しだい |
| M28 | 機種変更・再インストールで表示の設定が黙って既定に戻る | 確認 | 低 | `SettingsView.swift:15-22`、`SectionsPanel.swift:13-16` はすべて `@AppStorage`（端末だけ）。サーバーへ送る所は無い（grep） |
| M29 | 再会の写真はカメラロールに入らず、カメラロールから選んだ写真は縮小版がもう1枚入る | 確認 | 低 | `saveToPhotosIfEnabled` は最初のキャッチの保存だけ（`DexStore.swift:839`）、再会の `recordEncounter`（`:1374-`）は呼ばない。写真の出どころを見ずに `draft.photo` を足す |
| M30 | 再会は連続日数・褒めの「使った日」・記念アルバムに数えられない | 一部 | 低 | 褒めの使った日は stickers と review_history だけ（`server/src/lib/standing.functions.ts:71-125`）。ただし連続日数は復習だけで数える（`ReviewStore.swift:286-287`）ので最初のキャッチも数えない — 再会だけの扱いの差ではない |
| M31 | 同じカードに「一般的な言い方」と青い「ふだんの言い方」の2つの札 | 一部 | 低 | 札は `Models/Models.swift:823`（register）。「ふだんの言い方」は AI が書く distinction の文で、CI の見本のデータ（`Services/Demo/DemoFixtures.swift:1743` など）に入っている。本番では AI の文しだい |
| M32 | 「図鑑で見る」が単語の頁を開く | 確認 | 低 | `Views/AnswerPanel.swift:58` → `ReviewView.swift:113-114`（`router.detailSticker = card.sticker`） |
| M33 | 通知の選び方の名前がオンボードと設定で違う | 確認 | 低 | `OnboardingView.swift:343,345,508-509`（おまかせ・朝と夜）、`SettingsView.swift:257`（自動・時刻を指定） |
| M34 | 読みの一覧（TW_CHARS）に台湾の読みが足りない | 確認（実行） | 中 | `tw-reading.server.ts:59-69`。`readSentence` の実行: 研究 jiū・夾子 jiā・流血 xuè（`verify/r3t/s5.v.test.ts`）、辞書の読み: 熨斗 yùn dòu・研究 jiū・夾子 jiā（`m39.v.test.ts`）。S4 と同じ根 |
| M35 | 単語の1字の読みが例文の同じ字に全部かぶさる | 確認（実行） | 中 | `sentence-readings.server.ts:63-79`。実行: 還(huán)→「我還沒吃」wǒ huán méi、了(le)→「了解」le jiě、一(yí)→「一起」yí qǐ |
| M36 | 量詞・関連語の読みは点検されない、量詞の指示の見本が食い違う | 確認 | 中 | `checkTaiwanReading` を呼ぶのは見出し・チャンクだけ（`tw-reading.server.ts:236`、`chunk-readings.server.ts:25`）。`ai.functions.ts:2964` の見本 `{"word":"一張","zhuyin":"ㄧˋ ㄓㄤ","pinyin":"yí zhàng"}` は 一 も 張（ㄓㄤ=zhāng と zhàng）も食い違う。決定 10B（yī）とも違う |
| M37 | ピンインを引用した英語の説明がスペイン語・ベトナム語と判定されて消える | 一部（実行） | 低 | `note-language.ts:166-170` → `explain-languages.ts:298-310`。実行: "Say hǎo de la, softer." "zhēn de la — really!" "Use de after verbs; la softens." は en の読者に true（消える）。英語の機能語が2つ以上ある普通の文（"Use de after the verb to describe…"）は消えない（`r3t/m37.v.test.ts`）— 短い説明だけ |
| M38 | 図鑑の棚の規則が AI の正しい判断を上書き | 確認（実行） | 中 | `normalizeCategory`（`category.ts:396`、規則 `:320-365`）の実行: 火車站・捷運站・高鐵站・公車站→transport、刮鬍刀・美工刀・獎杯→kitchenware、咖啡機・咖啡廳・牛奶糖→drink、天燈・車燈→furniture、麻花→flower、香蕉船→vehicle（`r3t/m38.v.test.ts`） |
| M39 | 4択の内蔵の語と図鑑の表の誤り（微波爐 ㄨㄟ・熨斗 dòu・發票の棚・香菇の訳） | 確認 | 低 | `Models/QuizPool.swift:155`（"ㄨㄟ ㄅㄛ ㄌㄨˊ" 声調なし）、熨斗は辞書の読みが yùn dòu で AI の dòu も通す（実行）、`Models/DexCatalog.swift:347`（發票は表の10、`normalizeCategory` は document=9 — 11-01 の決定は書類=9）、`:507`（香菇＝キノコ） |
| M40 | 1字の見出し語が例文の別の語の中でも色が付く | 確認 | 低 | `Views/ZhuyinWordView.swift:393-403`（語の切れ目を見ずに字の並びの一致だけ） |
| M41 | 程度の語の一覧に 多・還・好、「人很多」の多・「還雨傘」の還が灰色で入れ替え不可 | 確認 | 低 | `Utilities/ChunkRules.swift:213`、役割 `:463`（含まれれば `.frame`）、入れ替え `:384` |
| M42 | 一・不 の声調変化が例文（変化あり）と見本（変化なし）で違う | 確認（決定 10B に未対応） | 低 | 決定 10 = B「辞書の形（yī）」。今の例文の読みは変化させる: 「一個人」yí gè、「不要」bú yào、「一起」yí qǐ（`readSentence` の実行）。量詞の見本も yí（`ai.functions.ts:2964`） |
| M43 | 漢字だけの日本語の意味が zh-TW を通る | 確認（実行） | 低 | `looksWrongForReader("自転車","zh-TW")`・「冷蔵庫」は false（通る）。かなが混ざれば落ちる（`r3t/m43.v.test.ts`） |
| M44 | 毎回ログインを確かめ直し、一瞬止まるとログアウトされる | 確かめられない | 中 | `server/src/integrations/supabase/auth-middleware.ts:58`（`getClaims`、失敗は Unauthorized → 401）、iOS は 401 が2回で `expireSession`（`SupabaseClient.swift:413-428`）。`getClaims` がネットワークを使うかは本番の JWT の鍵の種類（非対称なら手元で検証）しだい |
| M45 | 候補と作り直しにサーバー側の締め切りが無い | 確認 | 低 | `ai.functions.ts:1196-1219`（`generateStructured` に timeout/abort を渡さない、`ai-provider.server.ts:770-` にも既定の締め切り無し）。iOS は 30 秒（`AIService.swift:94`）。Edge Function 自体の上限で止まる |
| M46 | AI の同意の版が両側で 1 に固定 | 確認（将来） | 低 | `server/src/lib/ai-consent.ts:17`、`ios/CatchWords/Services/AIConsent.swift:28` |
| M47 | 外した写真の一覧を読めないと、外した写真がアルバムに戻る | 確認 | 低 | `Services/DexStore.swift:1680-1686`（失敗時は端末に控えた分だけ。サーバーだけが持つ分は戻る） |
| M48 | 長さの数え方が iOS とサーバーで違い、絵文字入りで「アプリを最新に」 | 確認 | 低 | iOS は字（書記素）で `prefix(500)`（`DexStore.swift:1616`）、サーバーは zod の `.max(500)`（JS の UTF-16 の長さ、`stickers.functions.ts:764,788,2069`）。報告の「コードポイント」は UTF-16 が正しいが結果は同じ。ZodError は「アプリを最新にしてください」（`native-fn.ts:232`） |
| M49 | 何度やっても通らないエラーが 500 で返り保存待ちで再試行し続ける | 確認 | 低 | `target-language.ts:183-186`・`stickers.functions.ts:1556` などはただの Error → 500（`native-fn.ts:226`）。iOS は 500 を再試行できる失敗とする（`Services/CatchSave.swift:66-67`）。ただし自動は5回まで（T5） |
| M50 | 復習の期限の判定がサーバー（最後の復習から180日）とアプリ（期限日だけ）で違う | 確認 | 低 | `server/src/lib/srs.ts:274,297`、iOS は `due_at=lte.now` だけ（`ReviewStore.swift:226-228`） |
| M51 | プロフィールの列を本人が書き換えられる・ストレージに制限なし・エラー文にテーブル名 | 一部 | 低 | `…part3…sql:181-182`（profiles の UPDATE を表ごと付与。created_at なども書ける）。ただし plan はトリガーで守る（`part1:208-226`、part2 `:359`）。`stickers` バケットは大きさ・種類の制限が NULL（part3 `:397-400`）。エラー文はそのまま 300 字まで返す（`native-fn.ts:230-235`） |

M の番号は報告の「M. 優先度 中」の箇条を上から順に振った（時間と地域 M1-4、中断 M5-10、使う流れ M11-33、中国語 M34-43、サーバー M44-51）。

## 集計（81 件）

| 判定 | 件数 |
|---|---|
| 確認 | 69 |
| 一部 | 8（T1・T9・T11・M18・M30・M31・M37・M51） |
| 誤り | 0 |
| 直っている | 0 |
| 決定で対象外 | 1（S6 — 決定 13B） |
| 確かめられない | 3（T21・M27・M44） |

## 報告から判定・重さが変わった物

- S6: 確認 → 決定で対象外（決定 13 = B）。
- T1: 確認 → 一部（ロック・裏へ回すだけなら「保存待ち」で同じ client_catch_id の再保存になり二重にならない。強制終了の時だけ）。高 → 中。
- T9: 確認 → 一部（通知は 30 分ごとに繰り返さない）。高 → 低。
- T11: 確認 → 一部（消した語は f20eb06 から復習の回から外れる。場所のリマインドだけ本当）。高 → 低。
- M18・M30・M31・M37・M51: 確認 → 一部（各行の根拠）。
- M42: 決定 10B（yī）が出たので、「食い違い」から「決定に合わせる作業が残る」に。
- 重さを下げた: S5・S7・S8・S9（最優先 → 中）、T2・T3・T7・T8・T21（高 → 中）、T4・T5・T6・T10・T12・T13・T14・T18・T19・T20（高 → 低）、M の多く（中 → 低）。中のまま: M11・M12・M13・M16・M34・M35・M36・M38・M44。

## 確かめる途中で新しく見つけた物

1. **悠遊卡の棚の食い違い**: 図鑑の表は 10（洗面・日用品。CLAUDE.md 11-01「支払いのカードは洗面・日用品」）だが、`normalizeCategory("悠遊卡","money")` は document → 9（`r3t/m38.v.test.ts`）。發票（M39）と同じ形。
2. **量詞の指示の見本の誤りは 一 だけでない**: `ai.functions.ts:2964` の `"zhuyin":"ㄧˋ ㄓㄤ","pinyin":"yí zhàng"` は 張 も ㄓㄤ（zhāng）と zhàng で食い違う。
3. **連続日数は最初のキャッチも数えない**（復習の記録だけ、`ReviewStore.swift:286-287`）— M30 の「再会だけ数えない」より広い。
4. **プライバシーポリシーの日付が 10-27 のまま**: b7b7d2f（11-01）で位置の許可の文を「番地まで」に直したが、ポリシー §2 の「地名だけ閲覧」は直っていない（T16 の補足）。
