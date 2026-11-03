# 第2回（qa-2026-11-01-deep.md）の再検証（2026-11-03、HEAD 5b35424 / 7403344 #26 を含む）

監査時点 652a130 以降に iOS で変わったのは `Views/WordDetailView.swift`・`Views/HeroGestures.swift`（#26）と Info.plist の位置の文だけ。サーバは変更なし。パスは `ios/CatchWords/` から。

| 番号 | 一言の内容 | 判定 | 重さ | 根拠（file:line・実行結果） |
|---|---|---|---|---|
| H1 | 復習の保存が通信で失敗すると同じ4択・同じ並びで戻る | 確認 | 中 | `Views/ReviewView.swift:335-341`（`.retry` で今のカードなら `answer = nil`、別のカードなら `requeue`）。選択肢は `ViewModels/ReviewStore.swift:322-327` の `choiceCache[sticker.id]` から同じ配列を返す（並びも同じ）。正解を見た後に同じ問題を答え直すので、間違えた語も「正解」で保存されうる。誤答の記録は残らない |
| H2 | 解析待ちから開いた写真で「撮り直す」→確認なしで写真が消える | 確認 | 高 | `Views/CandidatePickerView.swift:199`（`picker.retake` → `vm.reset()`）、`ViewModels/CaptureViewModel.swift:731-734`（`pendingId` があれば `PendingQueue.shared.remove`・`PendingRetry.forget`）。確認のダイアログは無い。`Views/CaptureView.swift:236` で解析中はタブを隠す |
| H3 | オンボードの「目的」「1日の学習時間」が使われていないのに約束の文 | 確認 | 中 | `Views/OnboardingView.swift:192-193`（「あとから変更できます」「例文の場面をあなたに合わせます」）、`:592` で `learning_preferences` を user_metadata に書くだけ。サーバで読むのは `first-catch-ai.server.ts:257` の `personalizationRule` だけで、iOS は `firstCatchAI` を呼ばない（`grep firstCatchAI ios/` 0件）。設定にも変える所が無い（`grep dailyMinutes ios/` はオンボードだけ） |
| H4 | 表示言語の保存に失敗すると次の起動で前の言語に戻る | 確認 | 低 | `Views/SettingsView.swift:902-908` は画面を先に切り替え、`profile.update` の失敗は `message` だけ。次の `ProfileStore.load`（`ViewModels/ProfileStore.swift:118-127`）で `chosenInSettings` が nil なので `L10n.set(serverUi)` が古い言語に戻す。再送は無い |
| H5 | チャンクの品詞: Vst（喜歡・怕・需要・擔心）が「形容詞」の緑 | 確認 | 中 | `Views/WordDetailView.swift:2561`（`p.hasPrefix("VS")` → `.stative`、Vst も Vs-attr も含む）→ `:2583` の `L("形容詞")`。サーバは Vst を返す（`server/src/lib/pos.ts:18`、`target-profile.ts:504`）。端末の `ChunkRules.isPredicateStative`（`Utilities/ChunkRules.swift:204-207`）は Vst を形容詞にしないのに色だけ違う。決定 6A（常に色を出す）で常に見える |
| H6 | アニメーション オフで自撮りに切り替えると左右反転 | 確認 | 低 | `Views/WordDetailView.swift:1171-1178`（reduceMotion の時 `showSelfie` だけ切り替え、`flipAngle` は 0 のまま）＋`:1092` の `.scaleEffect(x: back ? -1 : 1)` → 反転したまま表示。`applyHeroRole` の側（`:1157`）は 180 にするので開いた時は正しい。見た目だけの不具合 |
| H7 | 2回目以降の写真を押すと1回目の写真で開く | 確認 | 中 | `Services/DexStore.swift:631-636` `albumOwner` は元の語の sticker を返すだけ。`Views/WordDetailView.swift:80` `heroPage = 0` で始まり、開く時に回を指定する入口が無い（ホーム `HomeView.swift:138,222,287`、地図 `DexView.swift:479`）。3秒の自動の切り替えで後から出るだけ |
| H8 | 自撮りの段でタイマーなしのシャッターを2回 → 自撮りが捨てられる | 確認 | 中 | `Views/CaptureView.swift:574-588`（タイマー0は `start` が即 `fire()`、二度押しを止める物が無い）→ 2回目の `camera.capture()` は `Services/CameraService.swift:179` で即 nil → `finishSelfie(nil)`（`ViewModels/CaptureViewModel.swift:271-279`）が selfie=nil で次へ進め、1回目の画像は `step == .selfie` の guard で捨てる。音と光も2回 |
| H9 | AX の文字でチャンクの札が画面の左右にはみ出す | 確認 | 中 | CI の写真 `ci-previews:runs/main/axl-detail.png`（COMMIT = 7403344、今のコード）で札の左端と番号の丸が画面外、右のスピーカーも端に接する |
| H10 | Duo 横長の「新しいことばをキャッチ！」で単語が巨大になり切り抜きに重なる | 確認 | 中 | `Views/CatchCelebrationView.swift:197`（`ws = min(W*150/1080, W*0.66/(n*1.45))` は幅だけで決まり、高さを見ない）。見出しは 10-31 に `k = min(W/1080, H/2340)` へ直したが単語の行は直っていない。計算（横長 951×669）: 2〜3字の語で ws ≈ 132pt、行の中心 y=442 → 上端 ≈376、切り抜き（`CatchStage.swift:87-92`、高さ 167・中心 y=303）の下端 ≈387 と重なる。意味は `38*k` ≈ 10.9pt。CI の `get-duoland-1/2` は文字が出る前の瞬間で、写真では確かめられない |
| H11 | CI の Duo 内側の写真 18 枚が真っ黒、横長の見本は本物の配置を通らない | 確認 | 中 | 最新の Duo の記録 `ci-previews:runs/ccr-1a6814ff-53ld2d-duo/`（532cdd1）でも `*-2007x2853.png` 18 枚が同じ blob `913da3c`。652a130 以降のワークフローの変更は `ios-check.yml`/`ios-uitest.yml` の数行だけ。`Views/UIPreview.swift:2299-2316` の `DuoCanvas` は枠を描くだけで窓の安全域（帯の判定 `railEdge`）を作らない |
| H12 | 4択の問題文「「{意味}」はどれ？」に答えの字が出る | 確認 | 高 | `Views/ReviewView.swift:624,673`。`ReaderLanguage.gloss`（`Services/ReaderLanguage.swift:47-67`）は長さを切るだけで、見出し語と同じ字かを見ない |
| H13 | 正解とも言える誤答（蛋↔雞蛋、電風扇↔電扇、マンゴーに水果） | 一部 | 中 | 蛋→雞蛋・電風扇→電扇は本当: `Models/QuizPool.swift:59-82` の `alsoFits` は語尾の一致と `kindWords`（水果・花…）だけで、`雞蛋`（:97）・`電扇`（:157）は外れない。電風扇・蛋は図鑑の語（`Models/DexCatalog.swift`）。「マンゴーに水果」は CI の見本だけ（本物は芒果を fruit に分類し `kindWords` で水果を外す。`Models/CategoryRules.swift:129`） |
| M-起1 | チュートリアル中に落ちると再起動で「1枚撮る」からやり直し | 確認 | 低 | `Views/MainTabView.swift:486-491`（`tourPending` だけが保存され、段は保存されない → いつも `.tapCamera` から）。終わるまで `tourPending` は true（`:534`） |
| M-起2 | 新規登録・再設定のエラーがすべて「ログインに失敗しました」 | 一部 | 低 | `Services/SupabaseClient.swift:343-352`。「すべて」は言い過ぎ: 登録済み・弱いパスワード・6文字・未確認・"rate limit" は別の文。60秒以内の再送（"you can only request this after 60 seconds"）やメールの形式違いなどは "rate limit" を含まないので「ログインに失敗しました（429/400）」になる（新規登録・再設定の画面でも） |
| M-起3 | 通知の質問の画面がスクロールせず、SE＋大きい文字で「次へ」が外へ | 確かめられない | 低 | `Views/OnboardingView.swift:329-361` に ScrollView は無いのは本当。文字は `AppTypeScale.cap = .accessibility2`（`Utilities/ScaledFont.swift:60`）で止まり、概算で SE（667pt）にほぼ収まる。CI にこの段の SE＋AX の写真が無く、はみ出すかは実機/写真が要る |
| M-起4 | 再インストール・機種変更で同意済みの人にも AI の同意画面が一瞬出る | 確認 | 低 | `Services/AIConsent.swift:74-80`（端末の記録が無ければ `.undecided`）＋ `Views/RootView.swift:22-28`（`isUndecided` で出す）。サーバの同意の読み直し（`syncWithServer`）が返るまで出る |
| M-起5 | 「あとで始める」「スキップ」の後、チュートリアルをもう一度見る入口が無い | 確認 | 低 | `tourPending` を true にするのは `Views/OnboardingView.swift:600` だけ。設定に入口なし（`grep チュートリアル Views/SettingsView.swift` 0件）。決めてほしいこと8は未回答 |
| M-起6 | TOCFL の選択で Lv.4 で切れ、Lv.5・6 が見えない | 確認 | 低 | CI 写真 `runs/main/oblevel-wheel-1.png`（7403344）: Lv.4 の行が「決定する」の上で切れ、Lv.5・6 は画面外。「決定する」はホームバーの近く。半分見える行でスクロールは推せる |
| M-起7 | チュートリアルの札が最初は空の白い箱で出てから文字が入り、位置も動く | 確認 | 低 | CI `runs/main/motion-tour-word.jpg`（7403344、10fps）: 白い空の箱が約 0.4〜0.5 秒、その後に STEP 4 の札が真ん中に出て下へ移る |
| M-起8 | チュートリアルの青いきらめきが時計・Wi-Fi・電池の上に描かれる | 確認 | 低 | CI `runs/main/tour-dexmap-1.png`: 線が Wi-Fi と電池の上・下に重なる。CLAUDE.md「光は画面の内側に収める」に沿っていない |
| M-起9 | STEP 2 の札が日付を隠し、光の枠の下の線が次の日の日付に掛かる | 確認 | 低 | CI `runs/main/tour-home-1.png`: 札がその日の見出しを覆い、枠の下端が「10月31日(土)」に掛かる |
| M-起10 | AI の同意画面が最大の文字で「送/信」と切れ、下で文が切れる（ぼかし無し） | 確認 | 低 | CI `runs/main/axl-aiconsent.png`: 題が「データ送 / 信」、本文がボタンの帯で切れる（ぼかし無し）。「送るものが見えない」は言い過ぎで、見出しと最初の数行は見える |
| M-起11 | Google・Apple のボタンの文字の大きさが違う、韓国語で「가입하기」と「등록」 | 確認 | 低 | CI `runs/main/auth-ko-1.png`: 「Google로 가입하기」（細い）と「Apple로 등록」（大きく太い、システムのボタン） |
| M-カ1 | 選ぶカードの見出しに、持っている語にも「NEW」 | 確認 | 低 | `Views/CardCatch/CatchChooseView.swift:169-170`（`CatchDexChip(label:)` を badge なしで出す）→ `Views/CardCatch/CatchStage.swift:856` `badge ?? "NEW"`。持っているかを見ていない |
| M-カ2 | 入力した語の結果（最大5件）で SE では写真が潰れる、消す方法も無い | 確認 | 中 | `Views/CandidatePickerView.swift:118-129`（写真の段は残りの高さ、下の欄は高さ固定でスクロールなし）、`:644-674`（1行 50pt 以上・意味2行・読み付き、概算 90pt/行）。5行で約 450pt＋入力欄 → SE（667pt）では写真の段がほぼ残らない（計算）。`typedCandidates` を空にするのは `reset()`（＝撮り直し）だけ |
| M-カ3 | 横長写真・Duo で見えない物のタグが端に押し付けられ別の物の上に | 確認 | 中 | `Views/CandidatePickerView.swift:232-236`（`scaledToFill` で写真の左右を切る）、`:375-376` → `Views/CardCatch/CCPickLayout.swift:56-58`（画面外の点を `clampX` で端に寄せる）。計算で確認 |
| M-カ4 | 褒める画面・評価のお願いが次のキャッチの途中に出ることがある | 確認 | 低 | `Views/PraiseCelebrationView.swift:208-217` の `covered()` は着地・単語の頁・Pro・上限だけを見て、カメラの次のキャッチ（`vm.step`）を見ない |
| M-カ5 | 解析待ちから開いた写真に前のカメラロールの写真の位置が付く | 確認 | 中 | `vm.photoLocation` を消すのはシャッター（`Views/CaptureView.swift:604`）だけ。`reset()`・`restore()`（`ViewModels/CaptureViewModel.swift:700-708,722-760`）は消さず、`analyze` が `:193` で使う |
| M-カ6 | 自撮りの段で解析中の写真が「解析待ち」に並び、押すと AI をもう一度呼ぶ | 確認 | 低 | `ViewModels/CaptureViewModel.swift:187` で撮った時に PendingQueue に入れ、`Views/CaptureView.swift:283,1053` の一覧は `dex.pending` をそのまま出す（今の写真を除かない）。押すと `restore` → `PendingRetry.suggest` で、走っている `AIService.suggest` とは合流しない |
| M-カ7 | SE で「新しいことばをキャッチ！」の意味が約11pt・注記約8.5pt、文字の設定に従わず自動で進む | 確認 | 低 | `Views/CatchCelebrationView.swift:244,265,280`（`k = min(W/1080, H/2340)`、`.font(.system(size: 38*k))`/`30*k`、scaledFont でない）。SE: k=0.285 → 10.8pt / 8.6pt。iPhone 15 でも 13.8pt。最後の段で `hand()` が自動で走る（`:415`） |
| M-カ8 | 解析中・タグの画面・カメラ不可で紺の上に黒い時計、起動の後に白い時計が残る | 一部 | 低 | CI（7403344）`analyzing-05.png`・`picker-1.png` は紺の上に黒い時計＝本当。`small-camblocked.png` は白い時計で問題なし。起動の演出の後は今回の写真では確かめていない |
| M-カ9 | 選ぶカードの3つ目の候補が切れ、続きが分からない | 確認 | 低 | CI `runs/main/choose-1.png`: 3つ目「より詳しい言い方」の語が半分で切れる。上に約 150pt の空き。`CatchChooseView.swift:166` の `maxCard` |
| M-カ10 | タグの画面の見出しが「覚えたいことばをタップ」なのにタグが無い | 確かめられない | 低 | CI `picker-1.png` でタグ0は本当だが、タグは `vm.scan?.revealed ?? appeared` で遅れて出る（`CandidatePickerView.swift:389`）。撮るタイミングか不具合か写真からは決められない |
| M-カ11 | 位置の無い物のタグが別の物の上に乗る | 確認 | 低 | CI `picker4-nopos-1.png`（7403344）: ティッシュがタブレットの上、コップがタブレットの横（本物のコップは右上）。ただし本番はサーバが枠を聞き直す（`suggestion-position.ts` `objectsNeedingBoxes`）ので位置なしは少ない |
| M-カ12 | スペイン語で「En la foto: Otros」、候補に意味が無い | 確かめられない | 低 | CI `choose-es-1.png` でそう出るのは本当。見本の候補にスペイン語の意味が入っていないため（見本のデータ）の可能性が高く、本番の返事では確かめられない |
| M-カ13 | 動きのカクつき（候補 62〜64%・着地 45〜55%・スキャン 31%） | 一部 | 低 | CI `runs/main/frames.txt`（7403344）で variants 209/326=64%、landing 285/402=71%、analyzing 125/424=29% の落ち。ただし CI のシミュレーターの値で、実機では未確認 |
| M-ホ1 | 記念アルバムの通知を次の日に押すとアルバムに行けない、✕で二度と出ない | 確認 | 低 | `Views/HomeView.swift:311-318`（帯は `Milestone.today` の日だけ、`wasDismissed` で消える）。アルバムを開く入口は帯だけ（`memorialOpen` を立てるのは `:315` のみ）。✕は確認なしで `Milestone.dismiss` |
| M-ホ2 | 保存中に「完了」→もう一度並べ替えると2回目が消える | 確認 | 低 | `Views/CollageAlbum.swift:178-212`: 保存の Task の最後で `changed = false` にするので、保存中に始めた2回目の動きは `finish()` で `changed` が false → `persist()` されず `live/front` も消える。`saving` 中の「完了」は `guard` で何もしない |
| M-ホ3 | 並べ替えの保存失敗は振動だけ、後で元に戻る | 確認 | 低 | `Views/CollageAlbum.swift:204`（`Haptics.warning()` だけ、文字の知らせ無し）。戻る時間（約30秒）は確かめていない |
| M-ホ4 | 「あなたの記録」のシートが SE・大きい文字で下のボタンが切れる | 確認 | 低 | `Views/HomeView.swift:184`（`.presentationDetents([.medium])` だけ）、`Views/UserStatsPanel.swift:43-104` に ScrollView 無し。既定の文字で中身が概算 350pt、SE の半分の高さ（約 330pt）を超える（計算） |
| M-ホ5 | シートを開いている間の上の知らせがシートの下に隠れる | 確認 | 低 | `Views/MainTabView.swift:332-345`（知らせは MainTabView の `.overlay`。シートはその上に出る） |
| M-ホ6 | 何も撮っていない人に「7日間で0語。思い出の0枚」 | 確認 | 低 | `Views/HomeView.swift:311-313`・`Views/MemorialAlbum.swift:8,24,155` に語の数の条件が無い |
| M-ホ7 | 通知を押すとキャッチの途中でも画面が変わる | 確認 | 低 | `Views/MainTabView.swift:458-483` `openNotification` はカメラの段を見ずに `router.tab` を変える |
| M-ホ8 | 長押しだけで写真がまっすぐになり「手で置いた」として保存 | 確認 | 低 | `Views/CollageAlbum.swift:139-160`（`grab` で前へ出すと `changed = true`、`release` の `AlbumLayout.settle` が水平近くの傾きを0にして `changed = true`）→「完了」で全部を保存 |
| M-ホ9 | ウィジェット: 語が無い時の「今日の単語」が復習を開く、連続日数が減らない、データ無しでも「完了 ✓」 | 確認 | 低 | `CatchWordsWidgets/TodayWordWidget.swift:31`（語が無い → `DeepLink.review`）、`Services/WidgetBridge.swift:15-21,86`（連続日数は復習の画面が渡した値のまま）、`CatchWordsWidgets/ReviewWidget.swift:60,103`（`due == 0` で `allDone`） |
| M-単1 | 例文とチャンクの組み方が端末とサーバで違い、チャンク2つに例文1つになる場合 | 確認 | 中 | サーバ `server/src/lib/example-patterns.ts:985-990` `chunksWithoutExample` は「どれかの文が含めば足りる」。端末 `Utilities/ChunkRules.swift:628-640` `chunkExamples` は1文を1つの型にしか使わない。実行: 型 [點＋紅茶拿鐵]・[紅茶拿鐵＋去冰] と文「我想點紅茶拿鐵去冰。」で `chunksWithoutExample` = `[]`（サーバは足さない）→ 端末は型1に1文、型2は0文（`verify/cover.v2.test.ts`）。さらにサーバは続いた字だけ、端末は離れた字も数える |
| M-単2 | 中国語の字が台湾華語として指定されていない（字形・「，」・VoiceOver） | 確認 | 中 | `ios/CatchWords` に `typesettingLanguage`・`accessibilitySpeechLanguage`・`zh-Hant` の指定が0件（grep）。CI `runs/main/patterns-1.png`（日本語の画面）で例文の「，」が欧文の「,」の形、`patterns-en-1.png` では全角 |
| M-単3 | 例文「沖不下去」が語の途中で改行（C19 に反する） | 確認 | 中 | CI（7403344）`patterns-1.png`「沖不下 / 去！」、`patterns-en-1.png`「沖不 / 下去!」。`Utilities/ChunkRules.swift` `exampleGroups` は `words` に無い字を1字ずつに分ける |
| M-単4 | 「表示する項目と順番」でスイッチが ≡ の左半分を覆う | 確認 | 低 | CI `runs/ccr-1a6814ff-53ld2d/word25-panel-1.png`（532cdd1）。`Views/SectionsPanel.swift` は 652a130 以降変わっていない |
| M-単5 | 長いチャンクが 52% まで縮む（設計は 75% まで） | 確認 | 低 | `Views/ChunkLineView.swift:245`（`fitScales` の最後が 0.52）、`docs/word-detail-design.md:77`（下限 75%） |
| M-単6 | 見出し語・量詞・関連語の字が文字の大きさの設定に従わない | 確認 | 低 | `Views/WordDetailView.swift:550`（`38 * textScale`）、`:1816`、`:1890`（`24 * textScale`）は頁の拡大だけ。チャンクは `detailFontSize(…, dynamicTypeSize, …)`（`Views/ChunkLineView.swift:198`）で端末の文字の設定に従うので、大きい文字でチャンクが見出しより大きくなる |
| M-単7 | 開くたびに「…を作っています」が出て消える場合がある | 確認 | 低 | `Views/WordDetailView.swift:1625-1639`: 端末の `hasContent`（表示言語で消した後）が空なら `filling` を出して `fillSection(onlyIfEmpty: true)` を呼ぶ。サーバは生の中身で「空でない」と判断して何も書かず、次に開いても同じ。起きる語の頻度は本番のデータしだい |
| M-単8 | リンク名が es・vi で切れる、vi「Từ điển Quốc ngữ」が誤訳 | 一部 | 低 | 訳は `Resources/Localization/strings.json:3388`「Từ điển Quốc ngữ giản biên (Bộ Giáo dục Đài Loan)」。後ろに「台湾の教育部」と付くので「ベトナム語の辞書」と取り違える恐れは小さい（ただし Quốc ngữ はベトナム語の文字の名でもあり紛らわしい）。切れる件は CI の vi のリンクの写真が runs/main に無く今回は未確認 |
| M-単9 | es・ko・vi の単語の詳細は CI の見本に説明が無く確かめられていない | 確認 | 低 | CI `runs/main/detail-es-1.png`（7403344）: 意味の項目が無く、チャンクの訳・例文の訳が空 |
| M-図1 | 遅い答えの減点（8秒）にアプリを離れた時間・忘却曲線を見た時間が入る | 確認 | 低 | `Views/ReviewView.swift:577,700,771`（`started` は出た時だけ。scenePhase で止めない、バッジ→曲線のシートの間も数える）。サーバ `server/src/lib/reviews.functions.ts:1011` `response_ms > 8000` で −1 |
| M-図2 | 忘却曲線の「今が復習どき」が 95% 未満で出る（期限は約90%）、復習のタブと食い違う | 確認 | 中 | `Views/ForgettingCurveSheet.swift:307,310`（安定度は間隔の時に 90% になる式なのに `isTime = pct < 95`）。復習のタブはサーバの期限日で出すので「今日はありません」になる日がある |
| M-図3 | チュートリアルの曲線: 「今が復習どき」と「40日後にうろ覚え」が食い違う、凡例に無い語、ラベルに重なる・日付が切れる | 確認 | 低 | CI `runs/main/tour-curve-1.png`（7403344）: 題「今が復習どき」と本文「12/11（40日後）に「うろ覚え」」、凡例の段は はっきり/覚えている/薄れぎみ、線が「はっきり」に重なり、右端の日付が「1」で切れる。`ForgettingCurveSheet.swift:310-314` |
| M-図4 | 答えの札の例文が単語の頁と違う | 確認 | 低 | `Views/AnswerPanel.swift:111-130` は `exampleSentence`（メインの1文）を番号・色なしで出す。単語の頁はチャンクを含む文だけを番号付きで出す（`ChunkRules.chunkExamples`）ので、頁に無い文が出ることがある |
| M-図5 | 空の図鑑のスライドが真っ白 | 確認 | 低 | CI `runs/main/dex-en-1.png`（0 photos で何も無い白い画面）。見本の珍珠奶茶があれば空にならないが、見本を消した人・見本の前には起きる |
| M-図6 | カテゴリーの「3 / 8」が集めると「4 / 9」、分母が増える | 確認 | 低 | `Views/CardCatch/DexGallery.swift:141`（分母 `section.slots.count` = 集めた数＋影5、`Models/DexBook.swift:81,139`）。影5つは CLAUDE.md（10-27）の決定だが「n / m」の分母は決めてほしいこと12で未回答 |
| M-図7 | 地図のピンが空の白い丸、カードに写真が無い | 確かめられない | 低 | CI `runs/main/map-1.png` で2つのピンとも空（今回は1つでなく両方）。CI の見本の写真が読めていないためとみられ、本物の動きは実機/本番が要る |
| M-設1 | 広告のプライバシー設定の行がほとんど出ない（同意情報を読むのが残り少ない時だけ） | 確認 | 中 | `Services/RewardedAds.swift:46-71`（`requestConsentInfoUpdate` は `prepare()` の中だけ）、呼ぶのは `Views/CaptureView.swift:177-180`（残り1回以下）と `CatchLimitSheet.swift:63` だけ。設定の行は `privacyOptionsRequirementStatus == .required`（`:103`、`SettingsView.swift:394`）で、その起動で読む前は required にならない |
| M-設2 | 通知の時刻を2つにして1つ目を変えると並べ替えでもう1つが動く | 確認 | 低 | `Views/SettingsView.swift:513-524`（行の id は順番 `offset`）＋ `Services/ReminderService.swift:31-34`（保存のたびに `Set` → `sorted`）。1つ目を2つ目より後の時刻にすると行が入れ替わる。同じ時刻にすると1つ消える |
| M-設3 | 言語・レベルのカードの ✕・外側が取り消しでなく決定 | 確認 | 低 | `Views/SettingsView.swift:840-848,886-895`（外側のタップ・✕・「閉じる」がすべて `close()` → `commit(chosen)`）。取り消しの道が無い |
| M-設4 | 保存に失敗しても画面の値が戻らない（レベル・復習枚数・名前） | 確認 | 低 | `Views/SettingsView.swift:922-924` など: 先に `profile.currentLevel = v`、`update` が false でも戻さない。次の `ProfileStore.load` でサーバの値に戻る |
| M-設5 | 「場所でリマインド」: 位置の許可が無い時も何も言わずオン | 確認 | 低 | `Views/SettingsView.swift:640-650`（通知の許可だけ確かめる）、`Services/ReminderService.swift:168` は位置の許可を頼むだけで、断られても状態を出さない。おおよその位置の時の動きは推定のまま |
| M-設6 | 設定の画面に題が無く、上に空の帯（ダークで明るい灰色） | 決定で対象外 | 低 | 題は決定 11B（付けない）。ただし帯は CI `runs/main/settings-dark-1.png` で今も見える（時計の後ろが周りより明るい灰色）— 帯だけは残る見た目の問題 |
| M-設7 | Sentry: 写真の保存先のパスにアカウントの ID が入り記録に載る恐れ | 確認 | 低 | `Services/ErrorReporting.swift:43-56` は URL の `?` 以降・headers・cookies を消すだけで、パス（`stickers/<uid>/…`）は残る。`DevLog` の文（`devLog`）もそのまま送る。実際に送られた記録は未確認 |
| M-Duo1 | 外側の画面で着地の知らせ・候補のカード・カメラ不可が右の帯にはみ出す／中心がずれる | 確認 | 低 | CI `runs/ccr-1a6814ff-53ld2d-duo/duo-landing-1398x2034.png`（帯の時計の下まで知らせが伸びる）、`duo-camblocked-…`（帯を含む全幅の真ん中に置かれる）。その後の iOS の変更は単語の頁だけ |
| M-Duo2 | 外側の画面で時計が紺の上に黒、Pro の ✕ が上の端 | 確認 | 低 | 同じ記録の `duo-camblocked-1398x2034.png`（紺の上の黒い時計）、`duo-paywall-1398x2034.png`（✕ が上端に接する）。Pro は今は出していない |
| D1 | 主ボタン9種・カレンダーのシート3通り・閉じる13種など | 一部 | 低 | カレンダーは本当: ホーム `Views/HomeView.swift:155` は `.large`、図鑑 `Views/DexView.swift:221,1057` は `.medium, .large`。種類の数（9・13・20・37・71）は数え直していない |
| D2 | 同じ意味の色が複数、「アカウントを削除」の赤が文字とボタンで違う | 確認 | 低 | `Views/SettingsView.swift:468`（文字 `0xB42329`）と `:501`（ボタン `Theme.destructive` = `0xE62B34`） |
| D3 | コントラスト不足（白×#0083FF 3.7:1 など） | 確認 | 中 | 計算: 白×#0083FF = 3.69、白×#E62B34 = 4.41。主ボタン（`Components.swift:43` のグラデーション #2A9BFF→#0060E0）は明るい側で 2.9:1 |
| D4 | 同じアイコンが複数の意味（↻ など）、通信以外の失敗にも Wi-Fi の印 | 確認 | 低 | ↻系のアイコンが WordDetailView に3つ・ほか6画面（grep）。`wifi.exclamationmark` は保存の拒否（`gradeError`、`ReviewView.swift:356`）にも使う |
| D5 | 押せる大きさが 44pt 未満 | 確認 | 低 | 例: ホームの日記ボタン 36pt（`HomeView.swift:517`）、カメラのズーム 42×32（`CaptureView.swift:470`）。全件は数え直していない |
| D6 | 読めないほど小さい字（記憶の一覧の単語 約7pt、見本の札 9.5pt） | 確認 | 低 | `Views/MemoryOverviewPanel.swift:80-82`（16pt・`minimumScaleFactor(0.45)`・幅 76 → 7.2pt）、`Views/Components.swift:342`・`DexGallery.swift:268`（9.5pt） |
| D7 | 記念アルバムの紙吹雪が「アニメーション オフ」でも飛ぶ | 確認 | 低 | `Views/MemorialAlbum.swift:264`（`Confetti(active: phase != .count)`、reduceMotion を見ない。光線 `:259` は見ている） |
| D8 | 振動が二重のボタン 25・反応の無いボタン 14、スイッチの音の違い | 一部 | 低 | 二重の例は本当: `PressableStyle` が押した時に振動（`Components.swift:13`）＋ボタンの中でも `Haptics.selection()`（`WordDetailView.swift` `heroIcon`）。数は数え直していない |
| D9 | エラーの見せ方3通り、忘却曲線が読み込み中・失敗時に「復習 0 回」 | 確認 | 低 | `Views/ForgettingCurveSheet.swift:106`（`history?.count ?? 0`）、`:78-79`（失敗で空の配列 → 一度も復習していない語に見える） |
| L1 | Pro の画面「今日の無料キャッチ（3回）」→実際は5回（最初の週10回） | 確認 | 低 | `Views/PaywallView.swift:63` と `ViewModels/PlanStore.swift:14-16`（5 / 10 / 7日）。Pro を出していない間は見えない |
| L2 | 同じ設定に2つの名前（発音表記／読みの表記、母語／表示言語、学習言語／学ぶ言語、今のレベル／いまのレベル） | 確認 | 低 | `Resources/Localization/strings.json` に「発音表記」(:4013)「読みの表記」(:4657)「母語」(:3817)「学習言語」(:2949)「学ぶ言語」(:2921)「今のレベル」(:1941)「いまのレベル」(:9277) が別の鍵で並ぶ |
| L3 | 「サーバの更新を待ってください」、言い方の混在（失敗/できません、サーバ/サーバー） | 確認 | 低 | `strings.json` に「サーバの更新を待って」を含む文が1件。混在は数え直していない |
| L4 | en: Something else / Example（単数）/ memorial album / Fading と Slipping / "1 memorable photos" | 確認 | 低 | `strings.json`: その他→"Something else"、例文→"Example"、記念アルバム→"Memorial album…"、忘れかけ→"Fading"・薄れぎみ→"Slipping"、「{2} words in {1} days. We gathered {3} memorable photos.」（複数形の分けが無い） |
| L5 | zh-TW: 同意文だけ「您」、組塊、「在{1}於{2}收集過」、記不太清／記得模糊 | 確認 | 低 | `strings.json`: 「繼續即表示您同意{1}與{2}」、使い方チャンク→組塊、「這個單字你在{1}於{2}收集過」、うろ覚え→「記得模糊」と曲線の文の「記不太清」 |
| L6 | es: 「Eres el primero」、見本と例文が両方 Ejemplo ほか | 確認 | 低 | `strings.json`: 「Eres el primero de todos los usuarios…」、見本→"Ejemplo"・例文→"Ejemplo"。スペイン/中南米の混在・冠詞は数え直していない |
| L7 | ko: 見本の説明に「반당」と助詞の誤り、文体の混在、「잡을」 | 確認 | 低 | `Resources/Onboarding/sample_word.json` に「반당」、`strings.json`「影にない物も…」→「…뭐든 잡을 수 있어요」 |
| L8 | vi: 「Thứ tự mình chụp」が「撮る順番」と読める、「Thực tế」 | 確認 | 低 | `strings.json`: 「自分で撮った物は…」→「Thứ tự mình chụp sẽ dễ nhớ lại hơn.」（「Thứ tự」＝順番と読める）、使われ方→「Thực tế」 |
| L9 | 撮った場所の住所が表示言語で「信義区 西村里 信義路五段No. 7」 | 確認 | 低 | `Services/LocationService.swift:127`（`preferredLocale: L10n.locale`）。CI `runs/main/map-1.png` に「信義区 西村里 信義路五段 No. 7」。決めてほしいこと9は未回答だが、CLAUDE.md 11-01 の例は現地の表記（「台北市 大安區 和平東路一段162號」） |
| CI1 | 見本のデータが意味を直接書き、言語の混ざりを撮ってしまう | 確認 | 低 | `Views/UIPreview.swift:695`（果汁＝"juice"）、`:2014`（珍珠奶茶＝「タピオカミルクティー」を英語の画面でも） |
| CI2 | 見本: 5チャンクに例文3つ、很のホイールが開いたまま、芒果＋很＋甜（禁止の型） | 確認 | 低 | `Views/UIPreview.swift:1254`（芒果＋很＋甜）、`:1007`（鐵板麵＋很＋香、CI `axl-detail.png` に出る）。どれも見本のデータで本物には影響しない |
| 決7 | オンボードの「目的」「1日の学習時間」を使うか消すか | 確認（未回答） | 中 | H3 と同じ。`decisions-2026-11-03.md` で未回答 |
| 決8 | チュートリアルをもう一度見る入口を作るか | 確認（未回答） | 低 | M-起5 と同じ。未回答 |
| 決9 | 住所の表記を表示言語か現地か | 確認（未回答） | 低 | L9 と同じ。未回答 |
| 決10 | 量詞の「一」の読み | 確認（決定済み・未実装） | 低 | 決定 10B（辞書の形 yī）。コードは未対応: `server/src/lib/ai.functions.ts:2964` の量詞の指示の見本が今も「一張 = ㄧˋ / yí zhàng」（注音とピンインも食い違い）、端末で yī に直す処理も無い（`grep sandhi` 0件） |
| 決11 | 設定の画面に題「設定」を付けるか | 決定で対象外 | — | 決定 11B（付けない） |
| 決12 | 図鑑のカテゴリーの「n / m」の分母 | 確認（未回答） | 低 | M-図6 と同じ。未回答 |

## まとめ（97件）

- 判定: 確認 79・確認（未回答の問い）4・確認（決定済み・未実装）1・一部 7・確かめられない 4・決定で対象外 2・誤り 0・直っている 0
- 重さ: 高 2（H2・H12）・中 19・低 75（決11 は —）
- 652a130 以降の iOS の変更は単語の詳細の写真（#26）だけで、この報告の指摘を直した物は無い。

**報告から判定が変わった物**: H13 一部（マンゴー＝水果は見本だけ）、M-起2 一部、M-起3 確かめられない、M-カ8 一部（SE のカメラ不可は白い時計）、M-カ10・M-カ12・M-図7 確かめられない、M-カ13 一部（シミュレーターの値）、M-単8 一部、M-設6 決定で対象外（題）、D1・D8 一部（数は数え直していない）、決10 決定済み・未実装、決11 決定で対象外。推定だった M-ホ4・M-ホ5・M-ホ7・M-単7・M-設7 は確認に上げた。

**新しく見つけた物**
1. 決定 10B（「一」は辞書の形 yī）がまだコードに入っていない: 量詞の指示の見本が `一張 = ㄧˋ / yí zhàng`（`server/src/lib/ai.functions.ts:2964`、注音とピンインも食い違う）。
2. 決定 6A（品詞の色は常に出す）に合わせて CLAUDE.md を直すことになっているが、CLAUDE.md は今も「品詞の色は既定オフ」。
3. H8 は報告より悪い: 2回目の `capture()` は即 nil を返すので、残るのは nil、捨てられるのは1回目の本物の自撮り。
4. H10 の単語の大きさは横長 951×669 の計算で約 132pt（報告は約 110pt）、意味は約 10.9pt。
5. M-図7 は空のピンが2つとも（報告は1つ）。
