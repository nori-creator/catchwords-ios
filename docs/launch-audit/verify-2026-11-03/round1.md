# 第1回点検（qa-2026-11-01.md・qa-2026-11-01-copy.md）の再検証

対象: HEAD 5b35424（origin/main 7403344 #26 を含む）。iOS は読むだけ（Swift の環境なし）、サーバは vitest で実行。
パスは iOS = `ios/CatchWords/`、サーバ = `server/src/lib/`。

## まとめ

全 181 件（A 8・B 42・C 46・訳文 85）。判定: 確認 148・一部 26・直っている 2・確かめられない 4・誤り 1・決定で対象外 0。
重さ: 高 2（A1・A8）・中 15・低 161・なし 3。

- 直っている: B5（b7b7d2f、許可の文を住所に）、B18（b746708／#26、選んだ元の写真で開く）。
- 誤り: B41（第3回の訂正と同じ。iOS が重なった点を位置なしとして扱う）。
- #26 で一部だけ直った: B22（写真のボタンは出なくなった。長押しは今も1枚目に効く）、B23（写真の高さは固定に近くなったが、場所の一覧が長いと今も縮む）。
- 決定待ち（オーナーの答えがまだ無い第1回の問い）: B17（問い3）・B26（問い2）・B32（問い4）・C4（問い5）。決定 13B（↻ は管理者だけ）で B19 は学習者に起きないが、B37 は空の項目の自動の埋め（全員）でも起きる。

**新しく見つけたこと**
1. `NSLocationWhenInUseUsageDescription`（6言語、例 `ja.lproj/InfoPlist.strings:3`「撮った場所の**地名**を記録して」、en「records the **name of the place**」）は b7b7d2f で直っておらず、11-01 からの「番地までの住所」と合わない（B5 は `CapturePlace` の文だけ直した）。
2. es の `InfoPlist.strings` は b7b7d2f で `:6`「haces una foto」（スペイン）になり、同じファイルの `:3`「tomaste una foto」（中南米）と混ざった。
3. B22 の残り: サーバの一覧だけの2枚目以降を見ている時の長押しで、「表示する写真」のシートが1枚目（`current`）に効く（`WordDetailView.swift:136-139,745-749`）。
4. B6 の上限のシートは、広告のボタンが出る時（Release で常に有効）は SE だけでなく 6.1 インチでも .medium に入らない見込み（高さの見積もり 約470pt）。
5. C36 の英語の複数形: 報告の2例は出ないが、「{1} words」系（"{1} words to go — almost there" など）は 1 の時 "1 words" になる。

## A・B（qa-2026-11-01.md）

| 番号 | 一言の内容 | 判定 | 重さ | 根拠（file:line・実行結果） |
|---|---|---|---|---|
| A1 | 日付が変わってもキャッチの上限が戻らない（アプリを終えるまで） | 確認 | 高 | `ViewModels/PlanStore.swift:203-208` `loadUsage()` を呼ぶのは init・`bootstrap()`（`Views/RootView.swift:119` のサインイン時だけ）・記録/取り消し/広告の時だけ。`RootView.swift:186-196` の前に戻った時（scenePhase .active）は呼ばない。`dailyLimit` は日付で引き直すが `usedToday` は前日の値のまま → `remainingToday = 5+0-5 = 0`、`canCatch` false（`CaptureView.swift:191,591,640`）。上限は Release で常に有効（`PlanStore.swift:19-25`） |
| A2 | AI の同意を断ってカメラを押すと案内が止まる | 一部 | 中 | `MainTabView.swift:288` 同意が無いと `AIConsentGateView`。段 `.shoot` の印 `.shutter` が無いので `TourGuide.swift:285-289` hole=nil・`isInteractive`・`nextLabel` nil → 暗転も札も「スキップ」も出ない（ここは本当）。ただし同じ画面に「内容を確認して同意する」（`AIConsentView.swift:146`）があり、タブも動く。次の起動は `beginTourIfPending`（`MainTabView.swift:486-491`）で `.tapCamera` から、印 `.cameraTab` があるので札とスキップが出る。閉じ込めではない（第3回の訂正どおり） |
| A3 | 答えた後タブを替えて戻ると同じ問題がもう一度出て2回数える | 確認 | 中 | 答えた状態は `ReviewView` の `@State answer`（`Views/ReviewView.swift:19`）。タブは `switch router.tab`（`MainTabView.swift:274`）で作り直され消える。`ReviewStore.index` は `advance()`（`ReviewStore.swift:483`）でしか進まないので同じ札が未回答で出る。2回目の `gradeReview` はサーバが `duplicate: true`（`reviews.functions.ts:997-1003`）を返すが iOS の `Graded`（`ReviewStore.swift:424-429`）は読まず、`correctCount`・`doneToday` をもう一度足す（`:383,414`）。5分を超えると `refreshIfStale` が読み直すので起きるのは5分以内 |
| A4 | 1問目に答えて60秒後に戻ると問題が読み直され2問目が「答えた状態」に | 確認 | 中 | `ReviewStore.swift:171` `canRefresh` は `index == 0` で真。`RootView.swift:195` 前に戻ると `preload`、60秒経過（`:177`）で `load()`。答えた札は期限が進み外れ、2問目が `index 0` に来るが `ReviewView` の `answer` は残る（`ReviewView.swift:19`、札が替わっても nil に戻す処理なし）。`load()` は `correctCount = 0`（`:263`）。`.refreshable`（`ReviewView.swift:90`）は `canRefresh` を見ないのでどの段でも同じ |
| A5 | 期限前の語で「いま復習する」→答えても保存されないのに数える | 一部 | 中 | `ForgettingCurveSheet.swift:310` `isTime = pct < 95` で「いま復習する」。サーバの期限は約90%なので期限前の札はサーバが `isAlreadyGraded` で `duplicate`（`reviews.functions.ts:997`）。iOS は読まず正解・`doneToday` を数える（`ReviewStore.swift:383,414`）。「画面は100%に戻る」は誤り（`reloadReviews` でサーバの値のまま） |
| A6 | 語を入力した時・「戻る」で裏の切り抜きと場所が捨てられる | 一部 | 低 | `CaptureViewModel.swift:310`（search）・`:506`（backToCandidates）で `runToken += 1`、`:224,245,249` の `guard token == runToken` で切り抜き・位置・地名を捨てる（本当）。ただしタグは切り抜きより先に出るだけで、入力を終えるまでに普通は終わっている。捨てられるのは数秒の間に限る |
| A7 | カードの控えがレベル帯を区別しない | 一部 | 中 | 鍵は `(language, headword, explain_lang, l1)`（`supabase/migrations/20261020103934_…sql:182`、`generated-cards.ts:461`）。帯の違う人が上書きする（本当）。ただし帯の行は `gen.levels === bandGenLevels(band)` の時だけ埋め（`stickers.functions.ts:1621-1630`）、違えば次に開いた時その帯で作り、埋まれば終わる。「繰り返し」は起きず、費用が1回分増える程度 |
| A8 | `hintCategory` が自由な文字のまま AI の指示に入り共有に広がる | 確認 | 高 | `ai.functions.ts:1048` `z.string().optional()`（長さ・値の制限なし）、`:1582` そのまま指示文へ。結果は `recordGeneratedCards`（`:2178`）と `fillSharedWordFromCard`（`:2201`）で共有の語へ。効き目（AI が従うか）は本番でしか確かめられない |
| B1 | 解析待ちから開き直した写真の日時・場所が「今・ここ」 | 確認 | 中 | `CaptureViewModel.swift:187` キューへは `lat: nil, lng: nil`。`restore()`（`:701-707`）→ `analyze` → `locate(photoLocation)`（`:193,256-259`）は今の位置（`photoLocation` は前のカメラロールの写真の値が残ることもある）。保存の日時は `DexStore.swift:805,940` `takenAt: Date()` |
| B2 | 位置情報の無いカメラロールの写真に今いる場所の住所が付く | 確認 | 中 | `CaptureView.swift:166` `LocationService.photoLocation(data)` が nil → `CaptureViewModel.swift:256-259` `locate(nil)` は `LocationService.shared.current()` |
| B3 | 「図鑑にもうある？」の確認中、最大約30秒何も押せない | 確認 | 中 | `CaptureViewModel.swift:464-471` 確認が失敗すると同じ確認をもう一度、各 `timeout: 15`（`:371-374`）。その間 `CandidatePickerView.swift:143-148` 暗い幕と `.allowsHitTesting(!vm.isCheckingOwned)`。起きるのは通信が遅い時だけ |
| B4 | AI が何も見つけない時、語を入力する道が無い | 確認 | 中 | `AIService.swift:62` 候補0で投げる → `CaptureView.swift:215-221` `FailedView` は「いますぐもう一度試す」「ホームへ」「もう一枚撮る」だけ（`:1024-1026`）。写真は解析待ちで `PendingRetry.maxAttempts = 5`（`Services/PendingRetry.swift:21`） |
| B5 | 正確な位置の許可の文が「お店・駅・公園の名前」のまま | 直っている | — | b7b7d2f で6言語と Info.plist を「住所（番地まで）を記録するため」に（`Resources/*.lproj/InfoPlist.strings:6`、`CatchWords-Info.plist:7-8`） |
| B6 | 上限のシートが小さい iPhone で入りきらない | 確認 | 中 | `MainTabView.swift:440-441` `.presentationDetents([.medium])`、`CatchLimitSheet.swift` はスクロール無し・文は `fixedSize`。広告あり（Release で `RewardedAds.enabled = true`、`Services/RewardedAds.swift:25-31`）の時の高さの見積もり 約470pt（上28＋丸72＋見出し・説明2つ 約130＋間18×4＋広告のボタンと説明 約72＋「復習する」50＋「閉じる」44＋下12）。.medium は画面の約半分（SE で約320pt、6.1インチで約400pt）なので SE に限らず下の「閉じる」が切れる見込み。実機の写真は未確認 |
| B7 | カメラを許可しない／解析失敗／保存失敗でも案内が見えなくなる | 一部 | 低 | カメラ拒否は意図して印を外す（`CaptureView.swift:497-501`、「設定を開く」を暗くしないため）→ 札もスキップも出ない（本当）。解析失敗は `FailedView` に `.pick` の印が無く札が消える（本当）。保存失敗は第3回の訂正どおり誤り。いずれも撮り直す・次の起動で札が戻る |
| B8 | オンボード中、後ろのタブバーが押せる・VoiceOver が後ろに届く | 確認 | 低 | `RootView.swift:43-44` 後ろの `MainTabView` は `accessibilityHidden(needsAIConsent)` だけで、オンボードの時は隠さない。`OnboardingView.swift:1006` 背景は `allowsHitTesting(false)`、ボタンの下（`padding(.bottom, 12〜20)`＋下の安全域）は押せる物が無く後ろへ通る。「約16pt」の正確な幅は実機でしか測れない |
| B9 | オンボードの「ログインする」で次の新しいアカウントがオンボードを飛ばす・新規登録の側に戻る | 確認 | 低 | `OnboardingView.swift:556-561` 端末全体の `onboarding.done` を立てる（注記どおり意図）。`OnboardingState.isDone`（`:631-640`）は次にサインインした**どのアカウントでも**引き継ぐ。`WelcomeView.swift:49-50` は既定で新規登録の側（`errorMessage` がある時だけログイン側、`:83-86`） |
| B10 | 準備の画面がスクロールせず SE＋英語ではみ出す | 一部 | 低 | `OnboardingView.swift:372-430` スクロールなし。見積もり: 見出し・説明・絵（最小260）・ボタン2つで約640pt、SE の安全域内 647pt にほぼ等しく、英語で行が増えるか文字を大きくすると超える。標準の大きさの日本語では入る見込み。実機未確認 |
| B11 | プロフィールの読み込み失敗で AI の同意が先、後でオンボードが割り込む | 確認 | 低 | `RootView.swift:15-17` `needsOnboarding` は `!profile.loadFailed` が条件、`:27` 同意は `loadFailed` でも出る。`:189` 前に戻ると `profile.load()` し直し、成功すると `needsOnboarding` が真になりオンボードが重なる。新しい人で読み込みが1回失敗した時だけ |
| B12 | アルバムが写真の形を違う控えの名前で探し、単語を開いて戻ると位置が動く | 確認 | 中 | `CollageAlbum.swift:102-106` は `ImageCache.shared.image(for: path)`（そのままの名前）で縦横比を読む。アルバムの絵は `StickerImage(…, maxPoints:)`（`:655,660`）で縮小版を `path#<px>`（`ImageCache.swift:123` `smallKey`）に置く。縦横比が見つからず仮の形で並び、単語の頁で原寸が読まれると `path` に入って並びが変わる。`#512` 固定でなく大きさで決まる段（256〜1024）なのが報告との小さな違い |
| B13 | 並べ替え中の「元に戻す」の帯が「完了」に重なる | 確認 | 低 | 「完了」`HomeView.swift:85` 下から `barRoom(84)`・高さ52 → 84〜136pt、帯 `:105` `barRoom(110, rail: 24)` → 110pt から上（帯の高さ 44 以上、`:570`）。26pt 重なる。帯の時（`MainTabView.swift:58` rail=16 と 24）はほぼ全部。帯は5秒で消える（`:108-113`） |
| B14 | 同じ日に同じ語を2回撮り1枚を ✕ で外すと、もう1枚が出てくる | 確認 | 低 | `DexStore.swift:251` `albumStickers` で外した写真を先に除き、その後 `HomeView.swift:409` `onePerWord` で1語1枚に絞るので、外すと残りの1枚が選ばれる |
| B15 | 並べ替え中に下端まで運ぶと台紙が画面外に出て「完了」が消え、揺れたまま | 確かめられない | 低 | 道筋はある: `CollageAlbum.swift:77-82` 画面外で `onDisappear` → `onEditingChange(false)` で「完了」が消えるが、台紙の `@State editing` は true のまま（`HomeView.swift:478` は `LazyVStack`）。戻っても `onChange(of: editing)` は動かない。SwiftUI が画面外の状態を保つか・台紙が本当に画面外に出るかは実機で確かめる要あり |
| B16 | 並べ替えの指が中断されると自動スクロールが止まらない | 確認 | 低 | 並べ替え中の運び（`CollageAlbum.swift:367-390` SwiftUI の `DragGesture`）は `onEnded` でだけ `autoScroll.end()`。中断（取り消し）では `onEnded` が呼ばれず、`AlbumAutoScroll.swift:33-41` の 16ms ごとの `tick` が `fingerY` のまま続く。長押しで掴む方（`LongPressGrab` `:559-562`）は取り消しも扱う。止まるのは「完了」（`HomeView.swift:255` `albumEditing` の変化）まで |
| B17 | Duo 横長で1枚だけの日の写真が折り目の上 | 確認 | 低 | `Models/AlbumLayout.swift:363-364` `alone ? 0.5 : slot.x`。オーナーへの問い3（第1回）は `decisions-2026-11-03.md` にまだ答えが無い（決定待ち、不具合とは言い切れない） |
| B18 | 「表示する写真」で元の写真を選んでも開き直すと切り抜き | 直っている | — | b746708（#26、7403344）: `WordDetailView.swift:1147-1159` `applyHeroRole` が `heroRole == "object"` の時 `showCutout = false`。開いた時（`:332`）にも呼ぶ。CLAUDE.md 11-01 夜の決定どおり |
| B19 | ↻ でチャンクを作り直すとホイールで替えた語が残る | 一部 | 低 | `WordDetailView.swift:1742-1743` `ForEach(… id: \.offset)`、`ChunkLineView.swift:38` `pick: [Int: String]` は行の番号と部品の番号だけで持つので、新しいチャンクにも前の入れ替えが当たる（本当）。ただし ↻ は管理者だけ（`ai.functions.ts` の Pro/管理者の門、決定 13B で学習者には開かない） |
| B20 | 粗い位置で「市・区」と保存した写真が単語の頁では番地まで出る | 確認 | 中 | `Components.swift:325-331` 座標があると保存名を使わず `localizedName` で引き直す。`LocationService.swift:202` `CLLocation(latitude:longitude:)` は精度 0 → `placeName` の `accuracy <= 50`（`:124-131`）で番地まで。精度を保存していないので粗い点にも番地が付く（11-01「粗い時は市と区だけ」と食い違う） |
| B21 | 「写真を替える」で切り抜けないと四角の生の写真のまま | 一部 | 低 | `WordDetailView.swift:2309-2315` `liftSubject` が nil なら何もしない（`StickerCrop.shaped` を使わない）のは本当。ただし物の枠が無い写真の最後の手段は CLAUDE.md 10-26 で「写真全体」なので、角の丸い元の写真とほぼ同じ見た目（第3回の訂正どおり） |
| B22 | 2回目以降の写真がサーバの一覧だけの時、1回目のボタンが出て押しても効かない | 一部 | 低 | #26 でボタンは `mainFace` の角のアイコンになり（`WordDetailView.swift:1030-1080`）、サーバの一覧だけの写真は `laterFace`（`:909-911`）なのでボタンは出なくなった。残るのは長押し: `shown` は `current`（`:136-139`）なので、2枚目以降を見ているのに「表示する写真」のシートが1枚目に効く（`:745-749`） |
| B23 | 「撮った場所（n回）」を開くと写真が急に小さくなる | 一部 | 低 | #26 で写真の箱は頁の半分で固定（`WordDetailView.swift:682-691`）。ただし `min(h*0.5, h-…-metaHeight-…-headHeight-…)` が残り、`metaHeight` は開いた場所の一覧の高さを測る（`:268-269`）。6.1インチで一覧が約170pt を超えると今も縮む。数件なら動かない |
| B24 | 2回目以降の写真に替えた後、スクロールして戻ると1枚目に戻る | 確認 | 低 | 頁の列は `LazyVStack`（`WordDetailView.swift:250`）。写真が画面外で作り直されると `.task(id:)`（`:809-814`）がもう一度走り `heroPage = 0` |
| B25 | 4択に同じ意味の語が2つ並び片方が不正解になり得る | 確認 | 低 | `ReviewStore.swift:334-339` 除くのは見出し語が同じ・`QuizPool.alsoFits`（`Models/QuizPool.swift:59-82`、語尾の一致と「種類の語」だけ）。意味の同じ語（機車／摩托車）は調べない。両方を図鑑に持つ人だけに起きる |
| B26 | 色・形の語の分類が iOS（10）とサーバ（9）で違う | 確認 | 低 | `Models/DexCatalog.swift:93` `"color": 10, "shape": 10`、`server/src/lib/dex-catalog.ts:91-92` `color: 9, shape: 9`。オーナーへの問い2（第1回）は未回答。iOS の図鑑は自分の表で並べるので画面の食い違いは小さい |
| B27 | 図鑑の「カレンダーで選ぶ」で日を押しても絞り込まれない | 確認 | 中 | `DexView.swift:204` `DexCalendarView(…, selectedDay: $dayFilter) { … }` に `onPickDay` を渡していない。`DexCalendarView.swift:89` `onPickDay` が無いとシートの中の `timelineDay` を開くだけで `selectedDay` を変えない |
| B28 | 1問答えるごとに復習の記録を全部読み直す | 一部 | 低 | `ReviewStore.swift:419` 採点ごとに `dex.reloadReviews()` → `DexStore.swift:268-283` `reviews` を全部（1000行ずつ最大20回）。読むのは語ごとに1行の `reviews` で、履歴（`review_history`）ではない。次の問題は待たずに出るので、遅れは裏の通信だけ。語が数百の人なら1回の読み込み |
| B29 | 見本の珍珠奶茶で場所のリマインドが西門町で届く | 確認 | 低 | `Services/ReminderService.swift:170-183` 見本を除かない。見本は `lat/lng` を持つ（`SampleSticker.swift:97-99,104`）。CLAUDE.md の除外の一覧に通知は無いが、文は「この場所で『珍珠奶茶』をキャッチしました」で事実と違う |
| B30 | ウィジェットの「あと n 枚」と自動の復習通知に見本が入る | 一部 | 低 | ウィジェット: `WidgetBridge.swift:44-46` 期限の数は `dex.stickers` 全部（見本を含む）の `reviews`。CLAUDE.md は見本をウィジェットから外すと決めているので本当（「今日の単語」`:51` は除外済み）。通知: `DexStore.swift:244-247` に入るが、通知は除外の一覧に無い（第3回の訂正どおり） |
| B31 | 記念アルバム・図鑑の見出しの枚数にも見本が入る | 一部 | 低 | 記念アルバムの語数は `dex.wordCount`（`HomeView.swift:117,313`、`DexStore.swift:1233` で見本を除く）で誤り。写真の枚数 `Milestone.highlights(dex.stickers)`（`MemorialAlbum.swift:42`）と図鑑の見出し `DexBook.words(dex.stickers…)`（`DexView.swift:265`）には入る。見出しは図鑑に見本を出す決定（10-29）と合う |
| B32 | 画面の明るさ「システム」が効かない | 確認 | 低 | `CatchWords.xcodeproj/project.pbxproj:535,576` `INFOPLIST_KEY_UIUserInterfaceStyle = Light`。「システム」は `CatchWordsApp.swift:16-20,85` `preferredColorScheme(nil)` で上書きしないので Info.plist のライトのまま。選択肢は `SettingsView.swift:280`。問い4（第1回）は未回答 |
| B33 | リマインドの「時刻を追加」が最初の状態で何も増えない | 確認 | 低 | `SettingsView.swift:537` `times + [ReminderService.defaultTime]`（"09:00"）。`ReminderService.swift:33-35` `parseTimes` が `Set` で重複を消す。`saveTimes`（`SettingsView.swift:631-633`）は「保存しました」を出す |
| B34 | オフラインで変えたリマインドが次の起動で古い値に戻る／サインアウトで「場所」がオフ | 一部 | 低 | `ReminderService.swift:145-149` 保存は `try?` で失敗を捨て、`:152-160` 起動ごとにアカウントの値で上書き（本当）。サインアウトで場所のリマインドを切るのは `AccountCleanup.swift:20` の注記どおり意図（個人情報の掃除） |
| B35 | 「1日の復習枚数」を変えても5分以内は前の枚数 | 確認 | 低 | `ReviewView.swift` に復習枚数の変化を受ける `onChange` が無い。読み直しは `refreshIfStale`（`ReviewStore.swift:183-187`、300秒超・1問目のときだけ）か引き下げ更新だけ |
| B36 | 「思い出しどき」の通知が全部復習した後も届く | 確認 | 低 | 通知の組み直し（`ReminderService.refresh`）は `RootView.swift:126,186,199`（サインイン・言語・前に戻った時）と設定だけ。採点の後には呼ばない（`ReviewStore.grade`）。前に戻った時に組んだ予定が残る |
| B37 | ↻ で「使い方」を作り直すと新しいチャンクの例文が作られない | 一部 | 低 | `ai.functions.ts:3115-3140` `usage_chunks` の作り直しは型の門だけで `coverChunks`（`:2001-2019`、`generateCard` だけ）を通らない（本当）。↻ は管理者だけ（決定 13B）。ただし空の項目の自動の埋め（`only_if_empty`、`:2743` で全員に許す）でも同じ道を通るので、学習者にも起きる |
| B38 | 簡体字をはじく・繁体字に直す処理が無い | 確認 | 中 | 実行: `isTargetHeadword("出租车"/"图书馆"/"铅笔", "zh-TW")` がすべて true（`server/src/lib/target-language.ts:54` 注記「簡体字で入れた人も通す」）。簡体→繁体の変換は無い（`grep` で opencc 等なし）。守りは `target-profile.ts:432,474,481` の指示文だけ |
| B39 | 同点の人が全員「1位」「上位10%」 | 一部 | 低 | 実行: 50人中10人が同点の最多で `standingOf` → `{rank:1,total:50,topPercent:2}`（本当は上位20%）。順位が全員1位なのは `standing.ts:8` の注記どおり設計。誤りは % の計算だけ（第3回の訂正どおり） |
| B40 | サーバの処理がアプリの待ち時間より長くなり得る | 確認 | 低 | カード: `ai.functions.ts:403` 並べ始め20秒＋2番手35秒＝55秒（注記）＋型の例文 `CHUNK_EXAMPLES_TIMEOUT_MS` 8秒（`:670`）で 63秒 > iOS 60秒（`AIService.swift:112`）。候補: 12/9/6秒（`:319`、注記の最悪 18秒）＋枠の聞き直し `LOCATE_TIMEOUT_MS` 8秒（`:668`）で 26秒 > iOS 25秒（`AIService.swift:55`）。最悪の重なりの時だけ |
| B41 | 枠の聞き直しが失敗すると別の物の枠のまま（人が切り抜かれる型） | 誤り | — | サーバに重なった枠が残るのは本当（`suggestion-position.ts:126-140,174-200`）。だが iOS は同じ場所の点を「自分の場所でない」とし（`Models/TagPlacement.swift:99-101` `distinct`）、`positioned: t.own`（`Models/CatchObject.swift:92`）で位置なしとして扱い、別の物の塊を渡さない。第3回の訂正どおり |
| B42 | `getMyStanding` が呼ぶたびに3つの表の全行を読む | 確認 | 低 | `standing.functions.ts:70-100` `stickers`・`review_history`・`profiles` を全ページ（`READ = { maxRows: 1_000_000 }`、`:48`）。iOS の待ちは 8〜10秒（`PraiseCelebrationView.swift:192`、`SettingsView.swift:355`）。今の利用者数では問題にならず、増えた時の問題 |

## C（qa-2026-11-01.md の優先度 低。番号は無いので上から C1… と付けた）

| 番号 | 一言の内容 | 判定 | 重さ | 根拠（file:line・実行結果） |
|---|---|---|---|---|
| C1 | 連続日数が復習中に増えない | 確認 | 低 | `ReviewStore.swift:418` `if streak == 0 \|\| !Calendar.current.isDateInToday(now)` — `now` はいつも今日なので後半は常に偽。0 から 1 になるだけで、昨日まで5日なら今日答えても5のまま（読み直しまで） |
| C2 | 結果の合計に戻した問題が入り「x / 11」になり得る | 確認 | 低 | `ReviewView.swift:371` `total: store.queue.count`、保存に失敗した札は `requeue`（`ReviewStore.swift:478-481`）で `queue` の後ろに足される |
| C3 | チュートリアルの練習と最初の本番の4択が同じ並び | 確認 | 低 | `ReviewStore.swift:322-327` 選択肢は語の id ごとに一度作って `choiceCache` に残す。練習（`ReviewView.swift:306`）と本番（`:326`）が同じ `store.choices` を使い、`load()` は次の問題に残る語の控えを消さない（`:256`） |
| C4 | 答えの札を左に払うと横に飛ぶ | 確認 | 低 | `ReviewView.swift:118-140` 左へ払うと `swipeX = -520` で横に出ていく。10-30「横にスライドさせない」は次の問題の出方の決定で、払う動きを残すかは問い5（第1回）として未回答 |
| C5 | 2回目以降の写真しかない日は日付の絞り込みに出ない | 確認 | 低 | `DexView.swift:135-140` `dayCounts` は `dex.stickers` だけ。地図のピンは `albumEncounters` も入れる（`:145`） |
| C6 | 一覧の表示で同じ計算を21回 | 確認 | 低 | `DexView.swift:728-729` 分類ごと（`DexCatalog.withOther`、21）に `filtered`（全語の絞り込み、`:142`）を計算し直す |
| C7 | 広告の同意画面がキャッチの着地中に出る可能性 | 一部 | 低 | `CaptureView.swift:177-180` 残り1回以下で `RewardedAds.prepare()` → `Services/RewardedAds.swift:53-57` `ConsentForm.loadAndPresentIfRequired(from: nil)`。同意の画面が要る地域（EEA・英国など）の人だけ。台湾・日本では出ない見込み |
| C8 | カメラの中断（電話など）を扱っていない | 確認 | 低 | `Services/CameraService.swift` に `AVCaptureSession` の中断・実行時エラーの通知を受ける処理が無い（`grep interruption/runtimeError` 0件）。止まった後に戻るかは実機で |
| C9 | 自撮りの画面が二重に反転している可能性 | 確かめられない | 低 | `CameraPreview.swift:5` `AVCaptureVideoPreviewLayer`（前のカメラは既定で鏡に映す）＋ `CaptureView.swift:336` `scaleEffect(x: -1)`。鏡の設定を変える行は無い（`grep isVideoMirrored` 0件）。結果は鏡でない映りになる見込みだが実機で見る要あり |
| C10 | 位置の予備が60秒前・精度不問の値を使う | 確認 | 低 | `LocationService.swift:63-64` 6秒で良い値が無い時 `best ?? latest ?? 60秒以内の manager.location`（精度を見ない）。精度が粗ければ地名は市と区だけ（`:124-131`）なので害は小さい |
| C11 | レビュー依頼が出なくても120日の待ちが始まる | 確認 | 低 | `PraiseCelebrationView.swift:176-178` `noteCatch` で決めて保存した後、`:180` 案内中・`:185` `waitForCalm` で出さずに戻る道がある |
| C12 | 前の日の保存待ちを消すと今日の回数が1つ戻る | 確認 | 低 | `CaptureView.swift:1081-1084` 保存待ちを消すと `plan.undoCatch()`、`PlanStore.swift:180-184` は今日の数から引く（その語を撮った日を見ない） |
| C13 | `PlaceEditSheet` の「OK」が訳されていない | 確認 | 低 | `Views/PlaceEditSheet.swift:110` `Button("OK", role: .cancel)`（`L()` なし）。R25 の共通表記の一覧に「OK」は無い |
| C14 | 場所を選んですぐ保存すると前の点を保存する／「場所を追加」でも題が「場所を直す」 | 確認 | 低 | `PlaceEditSheet.swift:160-167` 近くの場所を選ぶと名前を替え、地図を 0.35 秒の動きで動かすだけ。`center` は `onMapCameraChange(frequency: .onEnd)`（`:120`）で動き終えた後に替わるので、その前の「保存」（`:170-178`）は前の点に新しい名前。題は `:93` いつも `L("場所を直す")`（入口は `WordDetailView.swift:1298,1313` で「場所を追加」） |
| C15 | 入れ替えの語の読みが消える場合 | 確認 | 低 | `Services/ReaderLanguage.swift:279` 訳を落とす時 `ChunkAlt(text: a.text, ja: "")` で `pinyin`・`zhuyin` も落ちる（同じ処理の型の方 `:295` は読みを残す） |
| C16 | 例文の 16pt の下限が「小」＋小さい文字設定で破れる | 一部 | 低 | `WordDetailParts.swift:299` `floor = min(base, smallest)`。縮める処理は16pt を守るが、学習者が文字を小さく設定して元の大きさが16pt 未満の時はその大きさ（注記どおり意図）。決定「16pt より小さくしない」との境目 |
| C17 | 描画中にディスクを読む | 一部 | 低 | `WordExampleCards.swift:93` 描画で `SentenceReadings.shared.cached` → `SentenceReadings.swift:61-63` `loadIfNeeded()`。ディスクを読むのは最初の1回だけ |
| C18 | 夜中をまたぐと「今日」が古いまま | 一部 | 低 | `HomeView.swift:192,270` `today` は描くたびに `Date()` から作る。日付の変化で描き直す仕組みは無く、何かが変わって描き直されるまで古いまま |
| C19 | 記念アルバムのリマインドが閉じた後も 19:30 に届く | 確認 | 低 | `Views/MemorialAlbum.swift:103-124` 予定はその日の記念日なら 19:30 に組み、見た・閉じた記録（`seenStorageKey`）を見ない |
| C20 | `Milestone.next` が端末の時計が大きく過去だと落ちる | 確認 | 低 | `MemorialAlbum.swift:33` `for n in max(1, today + 1)..<(today + 800)`。`today`（使い始めからの日数）が -800 未満で下限 1 > 上限になり Swift の Range が止まる。時計が使い始めより2年以上前の時だけ |
| C21 | 見開きの写真の幅 0.18 が決定の 0.19〜0.26 の外 | 確認 | 低 | `Models/AlbumLayout.swift:343-348` 3・4枚目の `w` が 0.18（CLAUDE.md 10-31「0.19〜0.26」） |
| C22 | 外した写真を全部戻すと空のシートが残る | 確認 | 低 | `HomeView.swift:594` トレイは空なら何も描かない。シート（`:89-96`）を閉じる処理は無い |
| C23 | 新規登録とログインを切り替えても「確認メールを送りました」が残る | 確認 | 低 | `WelcomeView.swift:404-408` 切り替えで消すのは `errorMessage` だけ。`infoMessage`（`:383`）は残る |
| C24 | Apple のボタンが他のサインイン中も押せる | 確認 | 低 | `AppConfig.swift:54` `nativeAppleSignIn = true` → `WelcomeView.swift:277-286` `SignInWithAppleButton` に `disabled(auth.isBusy)` が無い（Google `:229`・Web 版 Apple `:290` にはある） |
| C25 | Apple のボタンの文字が端末の言語 | 確かめられない | 低 | システムのボタン（`WelcomeView.swift:277`）の文字はシステムが決め、アプリ内の表示言語（`L10n`）は届かない作り。実機で端末とアプリの言語を変えて見る要あり |
| C26 | アカウント削除でオンボードの印・発音の控えが残る | 確認 | 低 | `Services/AccountCleanup.swift:39-80` に `onboarding.done.<uid>`（`OnboardingView.swift:631`）や発音の控えを消す処理が無い。消されたアカウントの id は使われないので害は小さい |
| C27 | ウィジェットがピンイン設定でも注音 | 確認 | 低 | `Services/WidgetBridge.swift:72-73` `reading: w.readingZhuyin`（設定 `reading.pref` を見ない） |
| C28 | 効果音がマナーモードでも鳴る | 確認 | 低 | `Services/SoundService.swift:172,491-492` 音の場を `.playback` にしており消音スイッチを無視する |
| C29 | プロフィールのエラーが「言語」の欄に出る | 確認 | 低 | `SettingsView.swift:216-218` `profile.message` を言語の欄に出す。写真の読み込みの失敗（`:131`）もここに出る |
| C30 | 設定では目標レベルを今より下にできる | 確認 | 低 | `SettingsView.swift:925-927` `.goal` はそのまま保存（オンボードは `lowest:` で下にできない、`OnboardingView.swift:123`） |
| C31 | 利用者の誤りが 500 として Sentry に送られる | 確認 | 低 | `server/src/lib/native-fn.ts:200-226` 名前の付いていない `Error`（「このカードは削除できません」など）は全部 500 |
| C32 | 例文 24 字を超える文も残る | 一部 | 低 | `example-patterns.ts:302` の注記どおり、24字以内が足りない時だけ短い順に長い文も使う（意図した予備） |
| C33 | 台湾メモの `**` の数を確かめていない | 一部 | 低 | サーバに `**` の数・組の点検は無い（`grep`）。ただし画面の `MemoMarks`（`WordDetailParts.swift:434`）は組にならない印を捨てて強調しない（`CatchWordsTests/MemoMarksTests.swift:19`）ので崩れない。「1〜2か所」の上限は守られない |
| C34 | `coverChunks` で足した例文のチャンクに読みが無い | 確認 | 低 | `ai.functions.ts:1983-1984` 読み（`withChunkReadingsInExtras`）は `coverChunks`（`:2001-2019`）より前に付ける |
| C35 | 「比べる相手5人以上」が自分を含めて5人 | 確認 | 低 | `Services/PraiseSchedule.swift:146,151` `total >= 5`、`standing.ts:32` `total` は自分を1から数える。他人は4人で比べる |
| C36 | 英語の 1 の時の複数形（"1 ways" "1 sentences"） | 一部 | 低 | 挙げた2つは出ない: `CandidatePickerView.swift:434` は2つ以上の時だけ、「{1}文は自然です」は止めている日記だけ（`DiaryPageView.swift:526`）。ただし「{1} words」系（`あと{1}語、もう少し` → "{1} words to go"、`まちがえた{1}語をもう一度` など）は 1 で "1 words" になる |
| C37 | 「1日、どれくらい学びたい？」の英訳が問いになっていない | 確認 | 低 | `strings.json` en `"A little time,\nevery day."`（他の5言語は問い） |
| C38 | 英語で "Log in" と "Sign in" が混在 | 確認 | 低 | en: `ログイン`→"Sign in"、`ログインする`→"Log in"、`ログインしてください`→"Please log in"、`確認メール…「ログイン」して`→"tap “Log in”"（そのボタンは "Sign in"） |
| C39 | 英語に "dex" が残る | 一部 | 低 | en の "dex" は `Views/Admin/AppInfoView.swift` など開発者の画面だけ（"Dex copy" "Add to dex → saved"）。学習者の画面には無い |
| C40 | 韓国語で4つだけ 합니다体 | 一部 | 低 | 4つ（`この語の使い方はまだありません`・`添削できませんでした`・`{1}文は自然です`・`テストを送りました`）は止めている日記と開発者の画面だけで学習者には出ない。学習者に出るのは別の1つ（オンボードの「…맞춥니다」、訳文の表の ko 1行目） |
| C41 | 音の「しっかり」が zh-TW・es・vi で「完全」の意味 | 確認 | 低 | `strings.json` `しっかり`: zh-TW「完整」、es「Completo」、vi「Đầy đủ」（en も "Full"） |
| C42 | 「花」の英語が小文字単数 "flower" | 確認 | 低 | `strings.json` `花` en "flower"（es "Flores"・他の分類は大文字始まり）。`Models/Category.swift:89` |
| C43 | 「人・体」の英語が "People" | 確認 | 低 | `strings.json` `人・体` en "People"（体が抜ける。`人` も "People" で同じ名前） |
| C44 | タブの「選択中」が読まれない | 確認 | 低 | `MainTabView.swift:648-649` `accessibilityLabel` だけで `.isSelected` の印が無い |
| C45 | オンボードの見えない戻るボタンに焦点が当たる | 確かめられない | 低 | `OnboardingView.swift:436-443` `opacity(0)`＋`disabled` で `accessibilityHidden` が無い。SwiftUI が透明な物を読み上げから外すかは実機の VoiceOver で確かめる要あり |
| C46 | 「パスワードを忘れた」の押せる大きさが 36pt | 確認 | 低 | `WelcomeView.swift:361-368` `minHeight: 36`（Apple の指針は 44pt）。枠はボタンの外に付くので押せる所は文字の大きさだけの見込み |

## 訳文・文言（qa-2026-11-01-copy.md。番号は無いので言語ごとに上から付けた）

確かめ方: `ios/CatchWords/Resources/Localization/strings.json` の値を読み、使う場所を Swift で `grep`（開発者の画面 `Views/Admin`・`UIPreview` は除く）。

| 番号 | 一言の内容 | 判定 | 重さ | 根拠（file:line・実行結果） |
|---|---|---|---|---|
| ja1 | 上限の画面の「3回」が固定（実際は5/10回） | 確認 | 低 | `Views/PaywallView.swift:63` `L("今日の無料キャッチ（3回）を使い切りました。")`。ただし `PlanStore.paywallEnabled = false`（`PlanStore.swift:31`）で今は出ない。Pro を始める時の問題 |
| ja2 | 発音表記（設定）と読みの表記（オンボード）で名前が違う | 確認 | 低 | `SettingsView.swift:209` `発音表記`、`OnboardingView.swift:492,497` `読みの表記` |
| ja3 | 母語/表示言語・学習言語/学ぶ言語・今のレベル/いまのレベル・目標レベル/目標のレベル | 確認 | 低 | 設定 `SettingsView.swift:187,196,201,204`、オンボード `OnboardingView.swift:476,486,668-669`。en も "Your language"/"App language" など別 |
| ja4 | 「まだ保存できません。サーバの更新を待ってください。」が開発者の言い方 | 確認 | 低 | `Services/DexStore.swift:1816,1840` |
| ja5 | 「記録に失敗しました」があいまい | 確認 | 低 | `CaptureView.swift:771,779`、`DexStore.swift:1402` |
| ja6 | 〜に失敗しました／〜できませんでしたの混在、同じ意味の2つのキー | 確認 | 低 | 「〜に失敗しました」で終わるキー10個（`カード生成に失敗しました`・`保存に失敗しました`・`解析に失敗しました。`…）、`写真の保存に失敗しました。` と `写真を保存できませんでした。` が両方ある |
| ja7 | 「もう一度試してください」(4) と「もう一度お試しください」(15) | 一部 | 低 | 数えると「試してください」2キー・「お試しください」16キー。混在は本当、数は報告と少し違う |
| ja8 | サーバ (2) と サーバー (9) | 確認 | 低 | 「サーバ」（長音なし）8キー（学習者に出るのは AI の同意の2文 `AIConsentView.swift` と `まだ保存できません…` など）、「サーバー」10キー |
| ja9 | 「AI を」（空白あり）と「AIを」の混在 | 確認 | 低 | 空白ありのキー21・なし18（`(AI\|Pro\|iPhone) [をにのがはで]` で数えた） |
| ja10 | 「ゲット」がブランドの動詞「キャッチ」の隣 | 確認 | 低 | `CatchCelebrationView.swift:316,318` `この言葉、…ゲットしています。` |
| ja11 | 「きょうの復習」と「今日の復習」 | 確認 | 低 | `ReviewView.swift:279` `きょうの復習`、`UserStatsPanel` 側 `今日の復習`（両キーが strings.json にある） |
| ja12 | 「{1}問中 {2}問 正解」の空白 | 確認 | 低 | キー `{1}問中 {2}問 正解` のまま |
| ja13 | 知らせの文の末尾の「。」が有ったり無かったり | 確認 | 低 | `WordDetailView.swift:1675-1688` 5つとも末尾に「。」なし（他の知らせは「。」あり） |
| en1 | その他 → "Something else" | 確認 | 低 | `strings.json`、`Models/DexCatalog.swift:85`・`Category.swift:107` |
| en2 | 例文 → "Example"（中身は複数） | 確認 | 低 | `Models/CardSection.swift` の題・飛ぶチップ |
| en3 | 使われ方 "In use" と 実際の使われ方 "Seen in the wild" が合わない | 確認 | 低 | 両キーの値どおり |
| en4 | 記憶の6段階の英語が読み分けられない（Fading … Slipping） | 確認 | 低 | `Views/Components.swift:110` 忘れかけ=Fading・あやうい=Shaky・うろ覚え=Fuzzy・薄れぎみ=Slipping・覚えている=Remembered |
| en5 | 図鑑の Collection/collection の大文字が混在 | 確認 | 低 | en に "Collection" 始まり5・"collection" 17 |
| en6 | 分類の大文字の書き方が2通り | 確認 | 低 | `料理・屋台` "Dishes & Street Food" と `食べ物` "Food & drink"・`学び・遊び` "Learn & play" |
| en7 | 食べ物 → "Food & drink" が飲み物と重なる | 確認 | 低 | `食べ物` en "Food & drink"、`飲み物` "Drinks" |
| en8 | 記念アルバム → "memorial album"（英語では弔いの意味） | 確認 | 低 | `{1}日目の記念アルバムができました` "Your day-{1} memorial album is ready" など3キー |
| en9 | ホームへ → "Go home" | 確認 | 低 | `CaptureView.swift:1025` |
| en10 | 復習へ → "To review" | 確認 | 低 | `TourGuide.swift:128` |
| en11 | ものと一緒に、もう一枚 → "One more, with you" | 確認 | 低 | `CaptureView.swift:410` |
| en12 | 「購入を復元」の引用がボタン名と違う・まっすぐの引用符 | 確認 | 低 | en "try \"Restore Purchases\""、ボタンは "Restore purchases"。`PlanStore.swift:143`。購入は今は出ない |
| en13 | 確認メールの文が存在しない「Log in」ボタンを指す | 確認 | 低 | en "…tap “Log in”."、ボタンは "Sign in" / "I've confirmed — sign in"（`AuthStore.swift:70`） |
| en14 | レベルの説明の書き出しが混在・英国綴り "specialised" | 確認 | 低 | "Understands…" "Reads…" "Follows…" "Can grasp…" "Can discuss specialised…" |
| en15 | 「…あなたのペースで続けましょう。」→ "Make it your own pace." | 確認 | 低 | `OnboardingView.swift:251` |
| en16 | なし → "none"（小文字） | 確認 | 低 | `OnboardingView.swift:520` |
| en17 | 写った物に、名前が付きました → "Everything in the photo got a name" | 確認 | 低 | `TourGuide.swift:62` |
| en18 | {1}回目に撮った写真 → "Photo taken on encounter #{1}" | 確認 | 低 | `WordDetailView.swift:954`、`EncounterHistoryView.swift:102`（読み上げのラベル） |
| en19 | 場所を直す/場所を追加 → "Fix the place"/"Add the place" | 確認 | 低 | `WordDetailView.swift:1298,1313`、`PlaceEditSheet.swift:93` |
| en20 | 一覧を低くする → "Lower the list" | 確認 | 低 | `DexView.swift:1276`（読み上げ） |
| en21 | 既定に戻す → "Use the default" | 確認 | 低 | `SectionsPanel.swift:64` |
| en22 | 「{1}」を獲得したのは + {1}人目 → "You caught “X”" と "No. 1" が合わない | 確認 | 低 | `PraiseSchedule.swift:183-184` の値どおり |
| zh1 | 唯一の「您」 | 確認 | 低 | `続けることで、{1}と{2}に同意したもの…` zh-TW「繼續即表示您同意…」（「您」はこの1つだけ） |
| zh2 | 「記不太清」が札の名前「記得模糊」と違う | 確認 | 低 | `復習しないと…「うろ覚え」になります` zh「…會變成「記不太清」」、`うろ覚え` zh「記得模糊」 |
| zh3 | チャンクの訳「組塊」 | 確認 | 低 | `チャンク`「組塊」、`使い方チャンク`「用法組塊」など5キー（訳語の選び方の提案。誤訳ではない） |
| zh4 | 表示言語がオンボード「選擇介面語言」と設定「顯示語言」で違う | 確認 | 低 | `表示言語を\n選んでください` zh「選擇介面語言」、`表示言語` zh「顯示語言」 |
| zh5 | 「字」を単語の意味で使う（個字・這個字） | 確認 | 低 | `あと{1}語、もう少し`「還剩 {1} 個字」、`まちがえた{1}語をもう一度`「…{1} 個字」、`この言葉に出会った記録`「遇到這個字的紀錄」、`この語の誤りを報告`「回報這個字的錯誤」、忘却曲線の案内「每個字」 |
| zh6 | 「在{1}於{2}」が文法的に変 | 確認 | 低 | `この言葉、{1}に{2}でゲットしています。` zh「這個單字你在{1}於{2}收集過。」 |
| zh7 | 単語を撮りに行く →「去拍單字」 | 確認 | 低 | `ReviewView.swift:887` |
| zh8 | 「後…後」の重なり・分鐘の前の空白 | 確認 | 低 | 「捕捉新單字後，10分鐘後會出現第一次複習。」 |
| zh9 | ひと言 →「一句話」 | 確認 | 低 | `ひと言`「一句話」、`ひと言を編集`「編輯一句話」（`WordDetailView.swift:344,1250`） |
| zh10 | 街 →「街」1字 | 確認 | 低 | `Models/Category.swift:12` |
| zh11 | あやうい →「有點危險」 | 確認 | 低 | `Components.swift:110` の記憶の段階 |
| zh12 | 次の日 →「下一天」（前の日は「前一天」） | 確認 | 低 | `DexView.swift:1401,1406`（読み上げ） |
| zh13 | 解析待ち {1}件 →「等待分析 {1} 件」 | 確認 | 低 | 値どおり |
| zh14 | 「（已複習{1}次）」の空白 | 確認 | 低 | 値どおり |
| zh15 | 台湾メモ →「台灣筆記」 | 確認 | 低 | `CardSection.swift:104`（訳語の提案） |
| es1 | 「Eres el primero」が男性形 | 確認 | 低 | `全ユーザーの中で、あなたが初めてです` es 値どおり |
| es2 | 見本 と 例文 がどちらも "Ejemplo" | 確認 | 低 | `見本`「Ejemplo」（`Components.swift:341`）、`例文`「Ejemplo」 |
| es3 | 例文 → 単数 "Ejemplo" | 確認 | 低 | 同上 |
| es4 | 同意の文に冠詞が無い | 確認 | 低 | 「Al continuar, aceptas {1} y {2}.」、{1}=「Términos del servicio」{2}=「Política de privacidad」 |
| es5 | 「consulta {1} (artículos 4 y 5)」冠詞なし・artículos | 確認 | 低 | 値どおり |
| es6 | 関連語 → "Palabras relacionadas" がチップに長い | 確認 | 低 | `CardSection.swift:70` |
| es7 | 上位{1}% → "{1}% superior" | 確認 | 低 | 2キーとも値どおり |
| es8 | 「Atrapaste «{1}»」だけ «» | 確認 | 低 | es で «» はこの1キーだけ |
| es9 | スペインと中南米の言い方が混在 | 確認 | 低 | スペイン型6（`Haz una foto`×3・`Marcapáginas`・`carrete`・`vídeos`）、中南米型3。**新しく**: b7b7d2f の es `InfoPlist.strings:6` は「mientras **haces** una foto」、同じファイルの `:3` は「donde **tomaste** una foto」で、1つのファイルの中でも混ざった |
| es10 | palabra の性が男性・女性で混在 | 確認 | 低 | `覚えている`「Recordado」・`忘れかけ`「Casi olvidado」（男性）、他の文は atraparla/la olvidarás（女性） |
| es11 | 許可の文が設定と別の名前（recordatorios por lugar） | 確認 | 低 | `es.lproj/InfoPlist.strings:3`「recordatorios por lugar」、設定 `場所でリマインド`「Recordatorios por ubicación」 |
| es12 | 末尾のピリオドが無い文 | 確認 | 低 | 例: `{1}日目の記念アルバムができました`「…está listo」、`使い始めて{1}日。…`「…un solo libro」、`思い出しどき…`「…se te queden」（en は「.」あり） |
| es13 | 集めた単語の数は → "Tus palabras reunidas" | 確認 | 低 | `PraiseSchedule.swift:189` |
| es14 | 「Faltan {1} segundos」/「Quedan {1}」が 1 で合わない | 確認 | 低 | `あと{1}秒`「Faltan {1} segundos」（`SelfieTimer`）、ウィジェットも同様 |
| ko1 | オンボードの「…맞춥니다」が 해요体の中に | 確認 | 低 | `いまのレベルと目標に…` ko「…목표에 맞춥니다. 나중에 … 있어요.」（`OnboardingView.swift:194`） |
| ko2 | 「나에게 … 드려요」の視点の混ざり | 確認 | 低 | `いくつでも選べます。…` ko「예문 상황을 나에게 맞춰 드려요.」（`:193`） |
| ko3 | 「헛되이 외우지 않아요」が不自然 | 確認 | 低 | `OnboardingView.swift:265` |
| ko4 | 「이 단어를 얼마나 기억하는지예요」が非文 | 確認 | 低 | `TourGuide.swift:76` |
| ko5 | 「뭐든 잡을 수 있어요」（他は 캐치） | 確認 | 低 | `TourGuide.swift:93` |
| ko6 | 「‘{1}’를 획득한 건」の助詞が固定 | 確認 | 低 | `PraiseSchedule.swift:183` |
| ko7 | 「제보」と「신고」の混在 | 確認 | 低 | ko に「제보」3・「신고」12 |
| ko8 | 「표현 {1}을(를) 쓴 예문」 | 確認 | 低 | `チャンク{1}を使った例文`（`WordExampleCards.swift:118`） |
| ko9 | しるし（部屋）と 記号（分類）がどちらも「기호」 | 確認 | 低 | `Category.swift:18,97` |
| ko10 | ガジェット →「가젯」 | 確認 | 低 | `Category.swift:93` |
| ko11 | かっこの前の空白 | 確認 | 低 | 例「AI 분석에 실패했어요 ({1})」「서버 오류 ({1})」「무료 캐치 (3회)를」 |
| ko12 | 見本の語 `sample_word.json` の「반당」「잔)로」「세요」 | 確認 | 低 | `Resources/Onboarding/sample_word.json` ko `note1`「반당이 가장 많이…」、`measure`「음료는 杯(잔)로 세요.」 |
| ko13 | 見本の語の「정상 당도」「정상 얼음」 | 確認 | 低 | 同ファイル ko `a_quantang`・`a_zhengchangbing` |
| vi1 | 「Thứ tự mình chụp」で意味が変わる | 確認 | 中 | `自分で撮った物は、思い出しやすい。` vi「Thứ tự mình chụp sẽ dễ nhớ lại hơn.」（チュートリアル `TourGuide.swift:90`、全員が見る。意味の取り違えなので他の訳の不揃いより重い） |
| vi2 | 「Cấp hiện tại」と「Trình độ mục tiêu」の混在 | 確認 | 低 | `今のレベル`「Cấp hiện tại」、`目標レベル`「Trình độ mục tiêu」 |
| vi3 | 使われ方 →「Thực tế」 | 確認 | 低 | `CardSection.swift:71` |
| vi4 | camera と máy ảnh の混在 | 確認 | 低 | vi に「camera」5・「máy ảnh」4 |
| vi5 | 押す動詞が Chạm/Nhấn/bấm で揺れる | 確認 | 低 | 「Chạm/chạm」16・「Nhấn/nhấn」9・「bấm」1 |
| 他1 | 見本の語の太字の中国語が日本語の中黒「・」（zh-TW だけ「、」） | 確認 | 低 | `sample_word.json` en/es/ko/vi に「半糖・」、zh-TW は「半糖、」 |
| 他2 | es の許可の文が設定と違う名前 | 確認 | 低 | es11 と同じ |
| 他3 | 使われていないキー「月」が en "Month"・es "Lun"・vi "T2"（曜日） | 確認 | 低 | `strings.json` `月`。Swift から使われていない |
