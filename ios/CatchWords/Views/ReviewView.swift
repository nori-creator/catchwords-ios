import SwiftUI

/// review.tsx (4-choice mode): header + progress + memory bar, then one quiz card at a time.
struct ReviewView: View {
    @Environment(DexStore.self) private var dex
    @Environment(ProfileStore.self) private var profile
    @Environment(AppRouter.self) private var router
    /// Kept by the app (not this screen): read and made ready before the tab opens (`ReviewStore.preload`).
    @Environment(ReviewStore.self) private var store
    @State private var legendOpen: Bool = {
        #if DEBUG
        return StoreShot.memoryOpen
        #else
        return false
        #endif
    }()
    @State private var curveSticker: Sticker?
    /// Verdict for the current card (nil until a choice is picked).
    @State private var answer: Bool?
    @State private var practiceIndex: Int = 0
    /// How far the answer sheet has been dragged sideways (swipe left = next card, like the web's SwipeCard).
    @State private var swipeX: CGFloat = 0
    /// The answer sheet's real height (it grows with the explanation): the question scrolls clear of it.
    @State private var panelHeight: CGFloat = 420
    /// The screen's height (inside the safe area) and the header + memory bar's height: the quiz card is sized from
    /// what is left above the tab bar, so the photo and all four choices fit on screen together, with nothing to
    /// scroll, on every size (owner 2026-10-11: 「スクロールしなくてもきっちり画面内にぴったり収まるように」).
    @State private var viewportHeight: CGFloat = 0
    @State private var topHeight: CGFloat = 0
    /// Bumped by 「いま復習する」: the screen closes the word list and scrolls back up to the quiz card.
    @State private var showQuizRequest = 0
    @Environment(\.appReduceMotion) private var reduceMotion
    /// iPhone Duo open and held sideways (owner 2026-10-29: 「見開き（横長）で開いたとき、復習は左側取った切り抜き画像、右側に
    /// 選択肢」): the picture on the left page, the question and the choices on the right, the answer sheet coming up on the
    /// right page only. Open and upright (「縦にした場合は上に画像、したに選択肢」) and folded, the iPhone's layout.
    @Environment(\.horizontalSizeClass) private var widthClass
    @State private var viewportWidth: CGFloat = 0
    private var spread: Bool { QuizCard.isSpread(widthClass: widthClass, width: viewportWidth, height: viewportHeight) }

    /// Room kept under the card for the floating tab bar (58 pt + its 4 pt + a little air).
    private static let tabBarClearance: CGFloat = 70
    private static let topID = "review.top"

    var body: some View {
        ZStack {
            AppBackground()
            GeometryReader { geo in
                Color.clear.onAppear { viewportHeight = geo.size.height; viewportWidth = geo.size.width }
                    .onChange(of: geo.size.height) { _, h in viewportHeight = h }
                    .onChange(of: geo.size.width) { _, w in viewportWidth = w }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            header
                            MemoryBar(counts: dex.memoryLevelCounts, isOpen: $legendOpen)
                        }
                        .onGeometryChange(for: CGFloat.self) { geo in
                            geo.size.height
                        } action: { h in
                            topHeight = h
                        }
                        .id(Self.topID)
                        if legendOpen {
                            MemoryOverviewPanel(store: store) { s in
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { curveSticker = s }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    // Unanswered: only the tab bar's room (the card already fits). Answered: room under the last
                    // choice for the whole sheet, however tall its explanation is.
                    .padding(.bottom, answer == nil ? Self.tabBarClearance : panelHeight + 16)
                }
                // Nothing to scroll while it fits (a very large text size can still scroll).
                .scrollBounceBehavior(.basedOnSize)
                .refreshable { await store.load(dex: dex, limit: profile.effectiveReviewLimit) }
                .statusBarScrim()
                // A long question (English meanings especially) sat under the sheet that slides up: once
                // answered, bring the question to the top so all of it stays readable above the sheet.
                .onChange(of: answer != nil) { _, answered in
                    guard answered else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9)) {
                        proxy.scrollTo(QuizCard.questionID, anchor: .top)
                    }
                }
                // 「いま復習する」 from the word list under the memory bar: the list stayed open and pushed the quiz below
                // the screen, so nothing seemed to happen (owner 2026-10-14: 「今が復習どきのボタンを押しても復習の画面に
                // ならない」). Back to the top, where the brought-forward card now is.
                .onChange(of: showQuizRequest) { _, _ in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9)) {
                        proxy.scrollTo(Self.topID, anchor: .top)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let answer, let card = router.tour.isReview ? practiceCards[safe: practiceIndex] : store.current {
                AnswerPanel(sticker: card.sticker, correct: answer, showsDex: !router.tour.isReview) {
                    if !router.tour.isReview { router.detailSticker = card.sticker }
                } onNext: {
                    goNext()
                }
                .offset(x: swipeX)
                .rotationEffect(.degrees(Double(swipeX) / 40), anchor: .bottom)
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { v in
                            // Only sideways drags move the sheet; the explanation inside still scrolls up and down.
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            swipeX = min(40, v.translation.width)
                        }
                        .onEnded { v in
                            if v.translation.width < -90 || v.predictedEndTranslation.width < -220 {
                                Haptics.selection()
                                withAnimation(.easeIn(duration: 0.18)) { swipeX = -520 }
                                Task {
                                    try? await Task.sleep(for: .milliseconds(170))
                                    goNext()
                                    swipeX = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { swipeX = 0 }
                            }
                        }
                )
                .accessibilityAction(named: L("次へ")) { goNext() }
                .tourAnchor(.reviewNext, if: router.tour == .reviewNext)
                .padding(.bottom, 66)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                .background(alignment: .bottom) { Theme.card.frame(height: 80) }
                .answerSheetColumn(wide: spread, width: viewportWidth)
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(card.id)
            }
        }
        .overlay {
            if let s = curveSticker {
                // In the first tour its card sits under the curve: the curve goes up and a little shorter.
                let guided = router.tour == .memoryCurve
                ZStack(alignment: guided ? .top : .center) {
                    Color.black.opacity(0.32).ignoresSafeArea()
                        .onTapGesture { if router.tour != .memoryCurve { closeCurve() } }
                    ForgettingCurveSheet(sticker: s, store: store, onReviewNow: {
                        guard !router.tour.isReview else { return }
                        let answered = answer != nil
                        store.bringForward(s, review: dex.reviews[s.id], currentAnswered: answered)
                        if answered { goNext() }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { legendOpen = false }
                        showQuizRequest += 1
                    }, onClose: { if router.tour == .memoryCurve { router.tourFinish() } else { closeCurve() } }, guided: guided)
                    .frame(maxHeight: guided ? 470 : 640)
                    .background(Theme.card, in: .rect(cornerRadius: 32, style: .continuous))
                    .tourAnchor(.memoryCurve)
                    .shadow(color: .black.opacity(0.2), radius: 30, y: 12)
                    .padding(.horizontal, 16)
                    // Kept clear of the tab bar drawn over this screen (owner 2026-10-16: 「今が復習どき」 and its
                    // button were under it): when the card is taller than the room left, it scrolls inside.
                    .padding(.top, guided ? 48 : 8)
                    .padding(.bottom, Self.tabBarClearance + 12)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
                }
                .zIndex(2)
            }
        }
        .task {
            if store.hasLoaded, store.loadedTarget != NativeAPI.targetLanguage { store.reset() }
            if !store.hasLoaded {
                await store.load(dex: dex, limit: profile.effectiveReviewLimit)
                await store.prefetchUpcoming(dex: dex)
            } else {
                // Read at launch (`preload`): shown at once; a queue read long ago is read again on its first card.
                await store.refreshIfStale(dex: dex, limit: profile.effectiveReviewLimit)
            }
            // A word deleted while this tab was closed: its cards leave the round.
            store.dropDeleted(dex: dex)
            applyReviewNow()
        }
        // A word deleted from its page opened here: its cards leave the round.
        .onChange(of: dex.stickers.count) { old, new in
            if new < old { store.dropDeleted(dex: dex) }
        }
        // 「いま復習する」 on a word's page: that word becomes the next card, due or not.
        .onChange(of: router.reviewNow) { _, _ in applyReviewNow() }
        // The tour's practice needs a word in the dex: without one there is nothing to quiz, so finish.
        .task(id: router.tour.isReview && practiceCards.isEmpty) {
            if router.tour.isReview && practiceCards.isEmpty { router.tourFinish() }
        }
        // The tour's last look: a forgetting curve (owner 2026-10-28: 「その単語の記憶の状態が忘却曲線のグラフを表示して…
        // 最適な復習のタイミングが分かる」). The sample word's, when the account has it: its story of three reviews shows
        // the curve back at 100% after each and flatter each time, and today's review due (owner 2026-10-29: 「何回か復習
        // した時のグラフを表示して…ユーザーに見せたい」); the word just practised has only today's answer. It closes when
        // the tour moves on.
        .onChange(of: router.tour) { _, step in
            if step == .memoryCurve, let s = dex.stickers.first(where: { $0.isSample && $0.word != nil }) ?? practiceCards.first?.sticker {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { curveSticker = s }
            } else if step == .complete || step == .off, curveSticker != nil {
                closeCurve()
            }
        }
        // R5 「学習言語台湾華語なのに英語の4択が表示されてる」: a switched learning language starts a fresh queue.
        .onChange(of: profile.targetLanguage) { _, _ in
            store.reset()
            // The dex is re-read for the new language first, so no old-language card slips in.
            Task {
                await dex.load()
                await store.load(dex: dex, limit: profile.effectiveReviewLimit)
            }
        }
        .reviewLiveActivity(store: store, dex: dex, answered: answer != nil, enabled: !router.tour.isReview)
    }

    /// FirstCatchPractice: 撮った1枚で、4択を記録せずに試す（owner 2026-10-28: 「自分が今取ったものを復習」）。Its word
    /// gone or never saved: another word of the dex instead.
    private var practiceCards: [ReviewCard] {
        let own = router.tourStickerId.flatMap { dex.sticker(id: $0) }.flatMap { $0.word == nil ? nil : $0 }
        guard let s = own ?? dex.stickers.first(where: { $0.word != nil }) else { return [] }
        return [ReviewCard(review: ReviewState(stickerId: s.id, ease: 2.5, intervalDays: 0, repetitions: 0), sticker: s)]
    }

    private func goNext() {
        // Never waits for the grade being saved (it used to: 次へ did nothing until the server had answered and the
        // whole review list was read again). A grade that fails later brings its card back at the end (`requeue`).
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { answer = nil }
        if router.tour.isReview { nextPractice() } else { store.advance() }
    }

    private func nextPractice() {
        if practiceIndex + 1 < practiceCards.count {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { practiceIndex += 1 }
            router.advanceTour(from: .reviewNext, to: .reviewPick)
        } else {
            practiceIndex = 0
            router.advanceTour(from: .reviewNext, to: .memoryCurve)
        }
    }

    /// Brings `router.reviewNow` (set by a word page's 「いま復習する」) into the queue once it is loaded.
    private func applyReviewNow() {
        guard let id = router.reviewNow, store.hasLoaded else { return }
        router.reviewNow = nil
        guard !router.tour.isReview, let s = dex.sticker(id: id) else { return }
        let answered = answer != nil
        store.bringForward(s, review: dex.reviews[s.id], currentAnswered: answered)
        if answered { goNext() }
    }

    /// The height the quiz card may take so it ends above the tab bar: the screen (inside the safe area) minus the
    /// top padding, the header + memory bar, the gap, and the tab bar's room. nil until measured.
    private var quizFitHeight: CGFloat? {
        guard viewportHeight > 0, topHeight > 0 else { return nil }
        return viewportHeight - 8 - topHeight - 10 - Self.tabBarClearance
    }

    private func closeCurve() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { curveSticker = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("きょうの復習")).scaledFont(size: 26, weight: .heavy).foregroundStyle(Theme.foreground)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(store.streak > 0 ? L("復習が\(store.streak)日続いています") : L("今日から復習を始めましょう"))
                        .scaledFont(size: 14).foregroundStyle(Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                if !store.queue.isEmpty {
                    Text("\(min(store.index + 1, store.queue.count)) / \(store.queue.count)")
                        .scaledFont(size: 15, monospacedDigit: true).foregroundStyle(Theme.muted)
                }
            }
            GeometryReader { geo in
                let p = store.queue.isEmpty ? 0 : CGFloat(store.index) / CGFloat(store.queue.count)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.secondary)
                    Capsule().fill(Theme.primary).frame(width: max(40, geo.size.width * p))
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: store.index)
                }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private var content: some View {
        if router.tour.isReview, let card = practiceCards[safe: practiceIndex] {
            QuizCard(card: card, choices: store.choices(for: card, dex: dex), percent: nil, isAnswered: answer != nil,
                     fitHeight: quizFitHeight, sideBySide: spread) { correct, _ in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { answer = correct }
                router.advanceTour(from: .reviewPick, to: .reviewNext)
            } onBadge: {}
            .tourAnchor(.quiz)
            .id("practice-\(card.id)")
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
        } else if let err = store.loadError, store.queue.isEmpty {
            VStack(spacing: 12) {
                Label(err, systemImage: "wifi.exclamationmark").foregroundStyle(Theme.foreground)
                Button(L("もう一度読み込む")) { Task { await store.load(dex: dex, limit: profile.effectiveReviewLimit) } }
                    .foregroundStyle(Theme.primary)
            }
            .frame(maxWidth: .infinity).padding(.top, 60)
        } else if !store.hasLoaded {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
        } else if let card = store.current {
            QuizCard(card: card, choices: store.choices(for: card, dex: dex), percent: dex.memoryPercent(for: card.sticker), isAnswered: answer != nil,
                     fitHeight: quizFitHeight, sideBySide: spread) { correct, ms in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { answer = correct }
                // Saved in the background: 次へ moves on at once while this is still on its way.
                Task {
                    switch await store.grade(card, correct: correct, responseMs: ms, dex: dex) {
                    case .saved, .gone:
                        // Saved; or its word was deleted meanwhile (nothing to save — the card leaves the round).
                        break
                    case .retry:
                        // Not saved (offline, the connection dropped, the server failed): the card comes back to be
                        // answered again — on screen when it is still the current one (never wipe the next card's
                        // answer), else at the end of the round (unless its word was deleted meanwhile).
                        if store.current?.id == card.id {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { answer = nil }
                        } else if dex.sticker(id: card.sticker.id) != nil {
                            store.requeue(card)
                        }
                        Haptics.warning()
                    case .refused:
                        // The server refused it (its reason is shown): sent again it would be refused again.
                        Haptics.warning()
                    }
                }
            } onBadge: {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { curveSticker = card.sticker }
            }
            .id(card.id)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            .overlay(alignment: .bottom) {
                if let err = store.gradeError {
                    Label(err, systemImage: "wifi.exclamationmark")
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.destructive.opacity(0.92), in: .rect(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.gradeError)
        } else {
            ReviewDone(total: store.queue.count, correct: store.correctCount, doneToday: store.doneToday,
                       missed: store.missed.count, isRetry: store.isRetry, canLoadMore: store.moreAvailable && !store.isRetry,
                       capped: store.capped || (store.moreAvailable && store.doneToday >= profile.effectiveReviewLimit),
                       dueRemaining: store.dueRemaining,
                       onSettings: { router.tab = .settings },
                       onRetry: {
                           withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { store.startRetry() }
                       },
                       onMore: {
                           Task { await store.loadMore(dex: dex) }
                       },
                       onCamera: { router.tab = .camera })
            .id("done-\(store.isRetry)-\(store.queue.count)")
        }
    }
}

/// Stacked memory bar (6 levels) + expandable legend.
struct MemoryBar: View {
    let counts: [Int]
    @Binding var isOpen: Bool

    var body: some View {
        let total = max(1, counts.reduce(0, +))
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(0..<6, id: \.self) { i in
                                if counts[i] > 0 {
                                    Rectangle().fill(Theme.memoryLevels[i])
                                        .frame(width: geo.size.width * CGFloat(counts[i]) / CGFloat(total))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.secondary)
                        .clipShape(Capsule())
                    }
                    .frame(height: 12)
                    Image(systemName: "chevron.down")
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("記憶の内訳"))

            if isOpen {
                FlowRow {
                    ForEach(0..<6, id: \.self) { i in
                        if counts[i] > 0 {
                            HStack(spacing: 5) {
                                Circle().fill(Theme.memoryLevels[i]).frame(width: 9, height: 9)
                                Text(MemoryBadge.labels[i]).foregroundStyle(Theme.memoryLevels[i].mix(with: Theme.foreground, by: 0.35))
                                Text("\(counts[i])").fontWeight(.bold).foregroundStyle(Theme.memoryLevels[i].mix(with: Theme.foreground, by: 0.35))
                            }
                            .scaledFont(size: 14)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Simple wrapping row.
struct FlowRow: Layout {
    var spacing: CGFloat = 14
    /// The line the views of one row stand on (a chunk: the middle of its characters); nil = their tops.
    var alignment: VerticalAlignment? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let lines = rows(subviews, maxW: maxW)
        let heights = lines.map { metrics($0, subviews).height }
        let widest = lines.map { line in
            line.reduce(0) { w, i in w + subviews[i].sizeThatFits(.unspecified).width + spacing }
        }.max() ?? 0
        return CGSize(width: maxW == .infinity ? widest : maxW,
                      height: heights.reduce(0, +) + 8 * CGFloat(max(0, lines.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, maxW: bounds.width) {
            let (height, line) = metrics(row, subviews)
            var x = bounds.minX
            for i in row {
                let v = subviews[i]
                let s = v.sizeThatFits(.unspecified)
                let drop = alignment.map { line - v.dimensions(in: .unspecified)[$0] } ?? 0
                v.place(at: CGPoint(x: x, y: y + drop), proposal: .unspecified)
                x += s.width + spacing
            }
            y += height + 8
        }
    }

    /// The views of each row, in order: a view goes to the next row when it would pass the edge.
    private nonisolated func rows(_ subviews: Subviews, maxW: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for i in subviews.indices {
            let w = subviews[i].sizeThatFits(.unspecified).width
            if x + w > maxW, x > 0 { rows.append([]); x = 0 }
            rows[rows.count - 1].append(i)
            x += w + spacing
        }
        return rows
    }

    /// A row's height, and how far below its top the views' `alignment` line runs (0 without one).
    private nonisolated func metrics(_ row: [Int], _ subviews: Subviews) -> (height: CGFloat, line: CGFloat) {
        let dims = row.map { subviews[$0].dimensions(in: .unspecified) }
        guard let alignment else { return (dims.map(\.height).max() ?? 0, 0) }
        let above = dims.map { $0[alignment] }.max() ?? 0
        let below = dims.map { $0.height - $0[alignment] }.max() ?? 0
        return (above + below, above)
    }
}

/// The quiz photo's box: the card's width at `height` on iPhone; on the Duo's left page, a 3 : 4 portrait of the page's
/// width, no taller than `height` (centred on the page by the card, after the photo's overlays).
private struct PhotoBox: ViewModifier {
    let sideBySide: Bool
    let height: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if sideBySide {
            // Capped by width so the 3 : 4 box is never taller than `height` (the card sits in a scroll view, which
            // leaves the height open).
            content
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: height * 3 / 4)
        } else {
            content
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
    }
}

extension View {
    /// The answer sheet's width: the whole screen on iPhone; with the Duo open (`wide`), the right page only — the quiz
    /// card's right column, past the gap over the fold — on a screen `width` wide.
    func answerSheetColumn(wide: Bool, width: CGFloat) -> some View {
        frame(width: wide && width > 0 ? QuizCard.rightColumnWidth(width) : nil)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// 4択クイズ: photo → 「meaning」はどれ？ → 4 headwords with zhuyin + pronounce buttons.
struct QuizCard: View {
    @Environment(DexStore.self) private var dex
    let card: ReviewCard
    let choices: [QuizChoice]
    let percent: Int?
    let isAnswered: Bool
    /// The height the whole card should fit in (ReviewView measures it): the photo takes what the question and
    /// the four choices leave, so nothing has to be scrolled to when the card opens. nil = the photo's usual height.
    var fitHeight: CGFloat? = nil
    /// The picture on the left, the question and the choices on the right (`isSpread(widthClass:width:height:)`).
    var sideBySide: Bool = false
    let onAnswer: (Bool, Int) -> Void
    let onBadge: () -> Void

    @State private var picked: String?
    /// The question and the four choices together (measured; they never depend on the photo's height).
    @State private var lowerHeight: CGFloat = 0
    @State private var started: Date = Date()
    @State private var shake: CGFloat = 0

    /// The question line, scrolled to the top after an answer (ReviewView) so the sheet never hides it.
    static let questionID = "quiz.question"
    /// Room kept on each side of a choice's word for the speaker button (40 pt, 10 pt from the edge) and the ✓/✗.
    static let choiceSideInset: CGFloat = 56
    /// The card's padding and the gap between the photo and the question.
    private static let cardPadding: CGFloat = 12
    private static let gap: CGFloat = 10

    /// A short screen (an iPhone SE, a large text size, this iPhone app on an iPad): the choices sit a little closer
    /// so the photo keeps a useful size. Decided from the space alone (never from what is measured inside the card,
    /// which this changes).
    private var compact: Bool { (fitHeight ?? 1000) < 460 }

    /// iPhone Duo open and held sideways — the regular width class on a screen wider than tall (owner 2026-10-29:
    /// 「見開き（横長）で開いたとき…左側取った切り抜き画像、右側に選択肢」): the picture on the left page, the question and the
    /// choices on the right, answered or not (the answer sheet then comes up on the right page, `ReviewView`). Open and
    /// upright, the picture above the choices as on the iPhone (「縦にした場合は上に画像、したに選択肢」).
    static func isSpread(widthClass: UserInterfaceSizeClass?, width: CGFloat, height: CGFloat) -> Bool {
        widthClass == .regular && width > height && height > 0
    }

    /// The gap between the photo and the choices when side by side: it sits over the fold.
    static let sideGap: CGFloat = 24

    /// The right column's width on a screen `width` wide (the review's 16 pt margins, the card's padding, the gap):
    /// the answer sheet takes it on the Duo.
    static func rightColumnWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - 32 - cardPadding * 2 - sideGap) / 2 + cardPadding + 16)
    }

    /// The photo's height: what is left of `fitHeight`, kept between a small but readable picture and 300 pt. Side by
    /// side, at most the card's whole height (up to 520 pt), the picture's box a 3 : 4 portrait of the left page's width
    /// (a photo is taken upright at 3 : 4; a box as tall as the card left grey bands above and under it).
    private var photoHeight: CGFloat {
        if sideBySide { return min(520, max(240, (fitHeight ?? 420) - Self.cardPadding * 2)) }
        guard let fitHeight, lowerHeight > 0 else { return compact ? 120 : 200 }
        let left = fitHeight - lowerHeight - Self.gap - Self.cardPadding * 2
        return min(300, max(64, left))
    }

    private var correctHead: String { card.sticker.word?.headword ?? "" }
    /// The meaning as it is now (read in the reader's language after the card was made).
    /// A short gloss: a sentence-long meaning made the question unreadable (the answer panel keeps it whole).
    private var liveMeaning: String { ReaderLanguage.gloss((dex.sticker(id: card.sticker.id) ?? card.sticker).word?.meaningJa ?? "") }

    var body: some View {
        // Side by side, the right page starts at the top like a book's page: the question and the choices stay clear
        // of the answer sheet that comes up under them on the same page (`ReviewView`).
        let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: Self.sideGap)) : AnyLayout(VStackLayout(spacing: Self.gap))
        layout {
            if isAnswered && !sideBySide {
                // Answered: the photo makes way for the answer sheet; the quiz label and the memory badge stay.
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Theme.primary, in: Circle())
                        Text(L("4択クイズ")).scaledFont(size: 14, weight: .semibold).foregroundStyle(Theme.foreground)
                    }
                    .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
                    .background(Theme.secondary, in: Capsule())
                    Spacer()
                    if let percent { badge(percent) }
                }
            } else {
                // The word's cut-out, as in the dex and on its page (owner 2026-10-11); a photo without one keeps its box.
                let shown = dex.sticker(id: card.sticker.id) ?? card.sticker
                // The dex's own choice (a missing or empty cut-out falls back to the photo).
                let pic = dex.dexPicture(of: shown)
                let path = pic?.path
                let isCutout = pic?.isCutout == true
                (isCutout ? Color.clear : Theme.secondary)
                    .modifier(PhotoBox(sideBySide: sideBySide, height: photoHeight))
                    .overlay {
                        StickerImage(path: path, url: dex.url(for: path, preferThumb: false), contentMode: .fit)
                            .padding(isCutout ? 2 : 6)
                            .shadow(color: .black.opacity(isCutout ? 0.16 : 0), radius: 8, y: 5)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
                    // The word's memory sits at the photo's top right (web CardMemoryBadge), tap → its curve.
                    .overlay(alignment: .topTrailing) {
                        if let percent { badge(percent).padding(.trailing, 4) }
                    }
                    // Side by side: the left page's whole width, so both pages stay as wide as the answer sheet's.
                    .frame(maxWidth: sideBySide ? .infinity : nil)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            VStack(spacing: Self.gap) {
                Text(liveMeaning.isEmpty ? L("この写真の物はどれ？") : L("「\(liveMeaning)」はどれ？"))
                    .scaledFont(size: 17, weight: .bold)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)   // every line of a long meaning, never "…"
                    .id(Self.questionID)

                VStack(spacing: compact ? 6 : 8) {
                    ForEach(choices) { c in choiceRow(c) }
                }
                .offset(x: shake)
            }
            .frame(maxWidth: sideBySide ? .infinity : nil)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { h in
                lowerHeight = h
            }
        }
        .padding(Self.cardPadding)
        .background(Theme.card, in: .rect(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
        .onAppear { started = Date() }
        // A grade that could not be saved hands the card back (isAnswered → false): answer it again.
        .onChange(of: isAnswered) { _, answered in
            if !answered {
                picked = nil
                started = Date()
            }
        }
    }

    /// The memory badge (level colour + %), 44 pt to tap; opens the forgetting curve.
    private func badge(_ percent: Int) -> some View {
        let lv = MemoryBadge.level(percent)
        return Button(action: onBadge) {
            HStack(spacing: 5) {
                Circle().fill(Theme.memoryLevels[lv]).frame(width: 7, height: 7)
                Text("\(percent)%").scaledFont(size: 14, weight: .semibold, monospacedDigit: true)
                    .foregroundStyle(Theme.memoryLevels[lv].mix(with: Theme.foreground, by: 0.35))
            }
            .padding(.horizontal, 10).frame(minHeight: 30)
            .background(Theme.memoryLevels[lv].opacity(0.14), in: Capsule())
            .background(Theme.card.opacity(0.94), in: Capsule())   // stays readable over the photo
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(L("忘却曲線を見る"))
    }

    private func choiceRow(_ c: QuizChoice) -> some View {
        let isCorrect = c.headword == correctHead
        let isPicked = picked == c.headword
        let revealed = picked != nil
        let stroke: Color = revealed && isCorrect ? Theme.ok : (isPicked ? Theme.destructive : Theme.primary.opacity(0.25))
        let fill: Color = revealed && isCorrect ? Theme.ok.opacity(0.08) : (isPicked ? Theme.destructive.opacity(0.07) : Color(light: 0xF7FAFF, dark: 0x132032))
        return ZStack {
            Button { answer(c) } label: {
                // The speaker (40 pt + 10 trailing) and the ✓/✗ mark sit over the row: the word keeps clear of
                // both sides, so a long one ("washing machine") wraps or shrinks instead of running under them.
                // The pinyin is passed so ピンイン (設定 › 発音表記) is honoured here too (owner 2026-10-11
                // 「設定でピン音にしても復習で注音が表示される。」); without it the view always fell back to zhuyin.
                ZhuyinWordView(headword: c.headword, zhuyin: c.zhuyin, size: compact ? 25 : 28, weight: .bold, pinyin: c.pinyin)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Self.choiceSideInset)
                    .padding(.vertical, compact ? 3 : 5)
                    .frame(maxWidth: .infinity, minHeight: compact ? 48 : 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.97))
            .disabled(revealed)
            .accessibilityIdentifier(isCorrect ? "quiz.choice.correct" : "quiz.choice")
            HStack {
                if revealed && (isCorrect || isPicked) {
                    Image(systemName: isCorrect ? "checkmark" : "xmark")
                        .scaledFont(size: 18, weight: .bold)
                        .foregroundStyle(isCorrect ? Theme.ok : Theme.destructive)
                        .padding(.leading, 18)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                PronounceCircle(text: c.headword, size: 40).padding(.trailing, 10)
            }
        }
        .background(fill, in: .rect(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(stroke, lineWidth: revealed && (isCorrect || isPicked) ? 2 : 1.2))
        .animation(.easeOut(duration: 0.2), value: picked)
    }

    private func answer(_ c: QuizChoice) {
        guard picked == nil else { return }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let ok = c.headword == correctHead
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { picked = c.headword }
        // The right word is read out either way (owner 2026-10-20: 「正解の時も不正解の時も発音して」): after a miss it is
        // the word to remember.
        SoundService.shared.speak(correctHead)
        if ok {
            Haptics.correct()
        } else {
            Haptics.wrong()
            Task {
                for x in [10.0, -8, 6, -3, 0] {
                    withAnimation(.spring(response: 0.08, dampingFraction: 0.4)) { shake = x }
                    try? await Task.sleep(for: .milliseconds(60))
                }
            }
        }
        onAnswer(ok, ms)
    }
}

/// The end of a round: the score counts up inside a ring that draws itself, then what to do next —
/// go over the missed words again (practice, not recorded), keep going past the daily limit, or catch more.
struct ReviewDone: View {
    let total: Int
    let correct: Int
    let doneToday: Int
    var missed: Int = 0
    var isRetry: Bool = false
    var canLoadMore: Bool = false
    var capped: Bool = false
    var dueRemaining: Int = 0
    var onSettings: () -> Void = {}
    var onRetry: () -> Void = {}
    var onMore: () -> Void = {}
    let onCamera: () -> Void

    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var shownCorrect = 0
    @State private var ring: CGFloat = 0
    @State private var appeared = false

    private var rate: CGFloat { total == 0 ? 1 : CGFloat(correct) / CGFloat(total) }
    private var ringColor: Color { rate >= 0.8 ? Theme.ok : rate >= 0.5 ? Theme.gold : Theme.primary }

    var body: some View {
        VStack(spacing: 18) {
            if total == 0 {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(Theme.primary)
                    .symbolEffect(.bounce, value: appeared)
            } else {
                ZStack {
                    Circle().stroke(Theme.secondary, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(shownCorrect)")
                            .scaledFont(size: 44, weight: .heavy, design: .rounded, monospacedDigit: true)
                            .contentTransition(.numericText(value: Double(shownCorrect)))
                            .foregroundStyle(Theme.foreground)
                        Text("/ \(total)")
                            .scaledFont(size: 15, weight: .semibold, monospacedDigit: true)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 140, height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(total)問中 \(correct)問 正解"))
            }

            VStack(spacing: 6) {
                Text(title)
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .scaledFont(size: 15).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                if missed > 0 {
                    Button(action: onRetry) {
                        Label(L("まちがえた\(missed)語をもう一度"), systemImage: "arrow.counterclockwise")
                            .scaledFont(size: 16, weight: .semibold).foregroundStyle(Theme.primaryInk)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.primary.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    Text(L("練習なので、記憶の記録は変わりません。"))
                        .scaledFont(size: 12).foregroundStyle(Theme.muted)
                }
                if capped {
                    Button(action: onSettings) {
                        Label(L("設定で枚数を変える"), systemImage: "slider.horizontal.3")
                            .scaledFont(size: 16, weight: .semibold).foregroundStyle(Theme.primaryInk)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.primary.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                if canLoadMore {
                    Button(action: onMore) {
                        Label(capped ? L("もっと復習する") : L("続ける"), systemImage: "plus.circle")
                            .scaledFont(size: 16, weight: .semibold).foregroundStyle(Theme.primaryInk)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.primary.opacity(0.35), lineWidth: 1.2))
                    }
                    .buttonStyle(PressableStyle())
                }
                Button(action: onCamera) {
                    Label(L("単語を撮りに行く"), systemImage: "camera.fill")
                        .scaledFont(size: 16, weight: .semibold).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 8)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .background(Theme.card, in: .rect(cornerRadius: 28, style: .continuous))
        .task { await play() }
    }

    private var title: String {
        if total == 0 { return capped ? L("今日の分は終わりです") : L("今日復習する単語はありません。") }
        if isRetry { return missed == 0 ? L("ぜんぶ覚え直せました") : L("あと\(missed)語、もう少し") }
        return L("\(total)問中 \(correct)問 正解")
    }

    /// web DoneState / EmptyState: more due → keep going; limit used up; or all done until tomorrow.
    private var subtitle: String {
        if total == 0 && !capped { return L("新しい単語をキャッチすると、10分後に最初の復習が出ます。") }
        if isRetry || total == 0 { return L("今日は\(doneToday)回復習しました。") }
        if capped { return L("今日の分は終わりです（\(doneToday)回復習しました）。") }
        if dueRemaining > 0 { return L("あと \(dueRemaining) 語、期限が来ています。続けられます。") }
        return L("また明日の復習で会いましょう。")
    }

    private func play() async {
        if reduceMotion || total == 0 {
            shownCorrect = correct
            ring = rate
            appeared = true
            return
        }
        withAnimation(.easeOut(duration: 0.9)) { ring = rate }
        // Count up one by one, faster for big rounds, a light tick each step.
        let steps = max(1, correct)
        let pause = max(25, min(90, 900 / steps))
        for n in stride(from: 0, through: correct, by: 1) {
            withAnimation(.snappy(duration: 0.2)) { shownCorrect = n }
            if n > 0 { Haptics.selection() }
            try? await Task.sleep(for: .milliseconds(pause))
        }
        if rate >= 0.8 { Haptics.success() }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appeared = true }
    }
}
