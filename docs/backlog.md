# あとでやること（バックログ）

決まっているが、まだ出していないもの。やるときはこのファイルから消す。

## カメラのタブ: B「浮いた青い丸」を将来の版で入れる（2026-10-16 オーナー決定）

- いまの版は、下のバー（タブバー）とカメラのアイコンを **2026-10-15 より前の見た目のまま**にしている（App Store のスクリーンショットがその見た目のため）。
- 将来の版で、カメラを **バーの上の縁から浮き上がった青い丸（白いカメラ）** にする（B 案）。A（バーの中の青い丸）と C（青いアイコン＋淡いカプセル）はやめた。
- コードの場所: `ios/CatchWords/Views/MainTabView.swift` の `CapsuleTabBar.raisedCameraDisc`（切り替えは `DevChoices.tabBar`、`ios/CatchWords/Services/DevChoices.swift`）。
- いまは **設定 › 開発者 › 開発者の試し › 下のバーのカメラ** で「B 浮いた丸（将来）」を選んだ端末だけに出る。ふつうの利用者には出ない。見本の画面は `-uiPreview tabbar-b`（iOS check の `tabbar-b-*.png`）。
- 入れるとき: `DevChoices.tabBarDefault` を B にする（または `CapsuleTabBar` を B だけにする）→ App Store のスクリーンショットを撮り直す。
