import SwiftUI

/// The home album as a book, on a wide screen (the regular width class: iPhone Duo's inner display; owner 2026-10-24
/// 「左側を切り抜きステッカーのページにして右側は日記のようにして、ページめくれるようにする」, 2026-10-25 「IPhone duoならではの美しさ、
/// 操作性、快感を刺激するようなデザイン、機能、アニメーション。細かいディテールまでこだわって」).
///
/// One day a spread, the whole screen high: the left page is the day's paper exactly as the iPhone shows it
/// (`CollageBoard`, its placements unchanged — a page was always one day's board), the right page its diary
/// (`DiaryPageView`). The book's order is the calendar's: older days are earlier pages, today the last.
///
/// - Turning: take a page by its outer edge and it curls under the finger (`PageCurl`, a real roll of paper with its
///   back coming over); past the middle the phone ticks, let go and it lands or falls back. A swipe anywhere, or ‹ ›,
///   turns it by itself.
/// - The ribbon marks today; from another day a tap riffles back to it, a few pages flicking over.
/// - Details of a bound book: the gutter's shadow on both pages, the page block's edge (小口) thicker on the side that
///   holds more days, running heads (the month; the day's places) and page numbers (ノンブル).
/// - The first time in a launch the book lies closed, its cloth cover alone in the middle (owner 2026-10-25: 「ページ
///   開いたときに、背表紙が右ページに見えるのは変」 — no page beside a closed cover), then opens with the book's sound: a
///   hard cover, heavy as it lifts and landing with a short bounce (「紙のように柔らかいアニメーションではなく少し固め」),
///   while the book slides from the middle to its open place.
///
/// - 「振り返る」 on the diary (owner 2026-10-25) opens on the left page: the day's timeline and its words' 使い方 are read
///   on the left while the diary stays open on the right (`DiaryLookBack`). The finished diary's correction opens there
///   too (`DiaryCorrectionView`). Turning the page closes either.
///
/// Reduced motion: no cover, and pages change with a fade instead of a curl.
struct BookSpreadView: View {
    /// Newest first, today leading (`AlbumDay.days`).
    let days: [AlbumDay]
    let onOpen: (Sticker) -> Void
    let onCamera: () -> Void
    var onEditingChange: ((Bool) -> Void)? = nil
    var finishRequest: Int = 0
    /// A day picked in the calendar: the book turns to it when `jumpCount` changes.
    var jumpDay: Date? = nil
    var jumpCount: Int = 0
    /// Previews: the spread to start on, whether the cover opens, and a page held mid-turn.
    var startIndex: Int = 0
    var showsCover: Bool = true
    var heldTurn: (direction: PageTurnDirection, progress: CGFloat, lift: CGFloat)? = nil
    /// Previews (CI's video): turn to the next day by itself this long after appearing.
    var demoTurnAfter: Double? = nil
    /// Previews: 「振り返る」 open on the first spread's left page, on its first word; or its correction.
    var startsLookedBack: Bool = false
    var startsCorrected: Bool = false

    /// A turn in progress: which way, and to which spread.
    private struct Turn: Equatable {
        var direction: PageTurnDirection
        var target: Int
    }

    @State private var index = 0
    @State private var turn: Turn?
    @State private var progress: CGFloat = 0
    @State private var liftY: CGFloat = 0
    @State private var grabY: CGFloat = 0
    /// The turn has gone past the middle (ticked once each way).
    @State private var pastHalf = false
    /// Riffling to today: no other turn until it ends.
    @State private var riffling = false
    /// The two pages' size together (the book, without its page edges).
    @State private var bookSize: CGSize = .zero
    @State private var coverAngle: Double = 0
    @State private var coverUp: Bool = !BookSpreadView.coverOpenedThisLaunch
    /// The closed book lies in the middle (0) and slides to its open place (1) as the cover opens.
    @State private var bookShift: CGFloat = BookSpreadView.coverOpenedThisLaunch ? 1 : 0
    /// The left half (its page, edges and shadow) comes as the cover swings over to lie there.
    @State private var leftReveal: Double = BookSpreadView.coverOpenedThisLaunch ? 1 : 0
    /// A day's photos are being rearranged: the page holds still, no turning.
    @State private var editing = false
    /// What the left page shows instead of the day's paper: 「振り返る」 (and the word it opened on) or the correction.
    private enum Panel {
        case lookBack(focus: String?)
        case correction
    }

    @State private var panel: (day: Date, kind: Panel)?
    @Environment(DexStore.self) private var dex
    @AppStorage(PaperTone.storageKey) private var paperRaw: String = PaperTone.cream.rawValue
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(AlbumAutoScroll.self) private var autoScroll: AlbumAutoScroll?

    /// The cover opens once a launch (opening the app again is not opening the book again).
    static var coverOpenedThisLaunch = false
    /// Room on each side for the page block's edge.
    static let edgeRoom: CGFloat = 12
    /// How wide a page's outer edge takes a finger to turn it.
    static let grabWidth: CGFloat = 44
    private static let space = "book"
    private static let ink = Color(hex: 0x33291F)

    private var tone: PaperTone { PaperTone(rawValue: paperRaw) ?? .cream }
    private var current: AlbumDay? { days.indices.contains(index) ? days[index] : nil }
    private var canForward: Bool { index > 0 }
    private var canBackward: Bool { index + 1 < days.count }
    private var turning: Bool { turn != nil || riffling }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let size = CGSize(width: max(1, geo.size.width - Self.edgeRoom * 2), height: max(1, geo.size.height))
                book(size)
                    .frame(width: size.width, height: size.height)
                    .coordinateSpace(name: Self.space)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { bookSize = size }
                    .onChange(of: size) { _, s in bookSize = s }
            }
            pager
        }
        .onAppear(perform: appear)
        .onChange(of: days.count) { _, _ in index = min(index, max(0, days.count - 1)) }
        .onChange(of: jumpCount) { _, _ in
            guard let d = jumpDay, let i = days.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: d) }) else { return }
            go(to: i)
        }
    }

    // MARK: The book

    private func book(_ size: CGSize) -> some View {
        let pageSize = CGSize(width: size.width / 2, height: size.height)
        return ZStack(alignment: .topLeading) {
            // The book block's shadow on the desk (closed, only the right half's).
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tone.edge)
                .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                .frame(width: pageSize.width * (1 + leftReveal), height: size.height)
                .offset(x: pageSize.width * (1 - leftReveal))
            // The page block's edges: older days under the left page, newer ones under the right.
            HStack(spacing: 0) {
                PageEdges(count: days.count - 1 - index, edge: .leading, tone: tone).frame(width: pageSize.width)
                    .opacity(leftReveal)
                PageEdges(count: index, edge: .trailing, tone: tone).frame(width: pageSize.width)
            }

            if let turn {
                turningPages(turn, size: size, page: pageSize)
            } else if let day = current {
                HStack(spacing: 0) {
                    leftPage(day, live: true).frame(width: pageSize.width, height: pageSize.height)
                        .opacity(leftReveal)
                    rightPage(day, live: true).frame(width: pageSize.width, height: pageSize.height)
                }
                .transition(.opacity)
                .simultaneousGesture(swipe, including: editing ? .subviews : .all)
            }

            // The ribbon, hanging from the top edge in the gutter, centred 14 pt right of the spine (its 44 pt frame is
            // centred on it), clear of the running head at 30 pt (centred at 32 pt it covered the head's first letter —
            // CI `spread`, 2026-10-25). Tucked away while a page turns: drawn over the leaf, it floated on top of the
            // turning page (CI `spread-curl-late`).
            BookRibbon(onToday: index == 0 && turn == nil) { riffleToToday() }
                .offset(x: size.width / 2 + 14 - 22, y: -8)
                .opacity(coverUp || turn != nil ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: turn == nil)

            // The outer edges, where a finger takes the page.
            if !reduceMotion && !editing {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: Self.grabWidth)
                        .contentShape(Rectangle())
                        .gesture(edgeDrag(.backward, size: size))
                        .allowsHitTesting(canBackward || turn?.direction == .backward)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(width: Self.grabWidth)
                        .contentShape(Rectangle())
                        .gesture(edgeDrag(.forward, size: size))
                        .allowsHitTesting(canForward || turn?.direction == .forward)
                        .accessibilityHidden(true)
                }
            }

            if coverUp {
                let month = Date().formatted(.dateTime.year().month(.wide).locale(L10n.locale))
                BookCoverFlip(angle: coverAngle, month: month, tone: tone)
                    .frame(width: pageSize.width, height: pageSize.height)
                    .offset(x: pageSize.width)
                    .zIndex(5)
            }
        }
        // Closed, the book lies in the middle of the desk: the cover's page centred.
        .offset(x: -pageSize.width / 2 * (1 - bookShift))
        .animation(reduceMotion ? .easeOut(duration: 0.25) : nil, value: index)
    }

    /// A page being turned: the spread it uncovers underneath, and over it the leaf (its front the page being turned,
    /// its back the page it will become), curled by the shader.
    @ViewBuilder
    private func turningPages(_ t: Turn, size: CGSize, page: CGSize) -> some View {
        if let here = current, days.indices.contains(t.target) {
            let there = days[t.target]
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    leftPage(t.direction == .forward ? here : there, live: false).frame(width: page.width, height: page.height)
                    rightPage(t.direction == .forward ? there : here, live: false).frame(width: page.width, height: page.height)
                }
                // Going forward the right page goes over and becomes the next day's left page; going back the left page
                // comes over and becomes the day before's right page.
                PageCurlLeaf(progress: progress, liftY: liftY, grabY: grabY, direction: t.direction, size: size,
                             front: t.direction == .forward ? AnyView(rightPage(here, live: false)) : AnyView(leftPage(here, live: false)),
                             back: t.direction == .forward ? AnyView(leftPage(there, live: false)) : AnyView(rightPage(there, live: false)))
            }
            .allowsHitTesting(false)
        }
    }

    private func closePanel() {
        withAnimation(.easeOut(duration: 0.22)) { panel = nil }
    }

    // MARK: Pages

    /// The page number of a day's left page (its right page is the next): the oldest day starts the book at 2.
    private func folio(_ d: AlbumDay) -> Int {
        let i = days.firstIndex(of: d) ?? 0
        return (days.count - 1 - i) * 2 + 2
    }

    @ViewBuilder
    private func leftPage(_ d: AlbumDay, live: Bool) -> some View {
        if live, let p = panel, Calendar.current.isDate(p.day, inSameDayAs: d.day) {
            ZStack(alignment: .topLeading) {
                PaperSurface(tone: tone, spine: .trailing)
                Group {
                    switch p.kind {
                    case .lookBack(let focus):
                        DiaryLookBack(day: d.day, words: DiaryPageView.words(on: d.day, in: dex), focus: focus, onPaper: true) {
                            closePanel()
                        }
                    case .correction:
                        if let c = DiaryStore.shared.correction(for: d.day) {
                            DiaryCorrectionView(day: d.day, correction: c, onPaper: true) { closePanel() }
                        }
                    }
                }
                .padding(.leading, 26)
                .padding(.trailing, 30)
            }
            .clipped()
            .transition(.opacity)
        } else {
            albumPage(d, live: live)
        }
    }

    private func albumPage(_ d: AlbumDay, live: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            PaperSurface(tone: tone, spine: .trailing)
            VStack(alignment: .leading, spacing: 0) {
                runningHead(d.day.formatted(.dateTime.year().month(.wide).locale(L10n.locale)), alignment: .leading)
                if live {
                    ScrollView {
                        leftContent(d, live: true)
                            .padding(.bottom, 20)
                            .background(ScrollViewFinder { [autoScroll] sv in autoScroll?.scrollView = sv })
                    }
                    .scrollDisabled(editing)
                    .scrollIndicators(.hidden)
                } else {
                    leftContent(d, live: false)
                    Spacer(minLength: 0)
                }
                pageNumber(folio(d), alignment: .leading)
            }
            .padding(.leading, 26)
            .padding(.trailing, 30)
        }
        .clipped()
    }

    private func leftContent(_ d: AlbumDay, live: Bool) -> some View {
        let isToday = Calendar.current.isDateInToday(d.day)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(DiaryPageView.title(d.day))
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(Self.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !d.items.isEmpty {
                    Text(L("\(d.items.count)語"))
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(Self.ink.opacity(0.5))
                }
            }
            if d.items.isEmpty {
                VStack(spacing: 14) {
                    if isToday && live {
                        Button(action: onCamera) {
                            Label(L("今日の1枚を撮る"), systemImage: "camera.fill")
                                .scaledFont(size: 15, weight: .semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .frame(minHeight: 46)
                                .background(Theme.primary, in: Capsule())
                                .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 5)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                CollageBoard(items: d.items, editable: live, onOpen: onOpen,
                             onEditingChange: { on in
                                 editing = on
                                 onEditingChange?(on)
                             },
                             finishRequest: finishRequest)
                    .tourAnchor(.album, if: live && index == 0)
            }
        }
    }

    private func rightPage(_ d: AlbumDay, live: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            PaperSurface(tone: tone, spine: .leading)
            VStack(alignment: .leading, spacing: 0) {
                if live {
                    ScrollView {
                        DiaryPageView(day: d.day, onLookBack: { focus in
                            withAnimation(.easeOut(duration: 0.22)) { panel = (d.day, .lookBack(focus: focus)) }
                        }, onCorrection: {
                            withAnimation(.easeOut(duration: 0.22)) { panel = (d.day, .correction) }
                        })
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollIndicators(.hidden)
                } else {
                    DiaryPageView(day: d.day, staticPrint: true)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                }
                pageNumber(folio(d) + 1, alignment: .trailing)
            }
            .padding(.leading, 30)
            .padding(.trailing, 26)
        }
        .clipped()
    }

    private func runningHead(_ text: String, alignment: HorizontalAlignment) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .serif))
            .tracking(1.5)
            .foregroundStyle(Self.ink.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            .frame(height: 44)
            .padding(.top, 6)
            .accessibilityHidden(true)
    }

    private func pageNumber(_ n: Int, alignment: HorizontalAlignment) -> some View {
        Text(verbatim: "\(n)")
            .font(.system(size: 11, weight: .regular, design: .serif))
            .monospacedDigit()
            .foregroundStyle(Self.ink.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
            .frame(height: 30)
            .padding(.bottom, 6)
            .accessibilityHidden(true)
    }

    // MARK: Turning by hand

    /// How far a page has gone with the finger at `x`: its edge is carried to the finger.
    private func travel(_ d: PageTurnDirection, x: CGFloat, size: CGSize) -> CGFloat {
        let p = d == .forward ? (size.width - x) / size.width : x / size.width
        return min(1, max(0, p))
    }

    private func edgeDrag(_ d: PageTurnDirection, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { v in
                if turn == nil {
                    guard begin(d, grabY: v.startLocation.y) else { return }
                }
                guard turn?.direction == d, !riffling else { return }
                progress = travel(d, x: v.location.x, size: size)
                liftY = v.location.y
                tickAtHalf()
            }
            .onEnded { v in
                guard turn?.direction == d, !riffling else { return }
                let thrown = travel(d, x: v.predictedEndLocation.x, size: size)
                if progress > 0.45 || thrown > 0.7 { land() } else { fallBack() }
            }
    }

    /// Starts a turn: false when there is no page that way, or the book is busy.
    private func begin(_ d: PageTurnDirection, grabY y: CGFloat) -> Bool {
        guard turn == nil, !riffling, !coverUp, !editing else { return false }
        let target = d == .forward ? index - 1 : index + 1
        guard days.indices.contains(target) else { return false }
        return begin(d, target: target, grabY: y)
    }

    private func begin(_ d: PageTurnDirection, target: Int, grabY y: CGFloat) -> Bool {
        guard days.indices.contains(target), target != index else { return false }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            panel = nil
            grabY = min(bookSize.height, max(0, y))
            liftY = grabY
            progress = 0
            pastHalf = false
            turn = Turn(direction: d, target: target)
        }
        Haptics.impact(.light, intensity: 0.45)
        return true
    }

    private func tickAtHalf() {
        if progress >= 0.5 && !pastHalf {
            pastHalf = true
            Haptics.selection()
        } else if progress < 0.5 && pastHalf {
            pastHalf = false
            Haptics.selection()
        }
    }

    /// The page goes on over and lands; the book is then on the new day.
    private func land(duration: Double? = nil, then: (() -> Void)? = nil) {
        let left = 1 - progress
        let quick = (duration ?? 1) < 0.3
        // A riffle's quick flicks are quieter than a page turned by hand.
        let volume: Float = quick ? 0.55 : 1
        SoundService.shared.play(.pageTurn, volume: volume)
        withAnimation(.timingCurve(0.25, 0.55, 0.3, 1, duration: duration ?? Double(0.2 + 0.34 * left))) {
            progress = 1
            liftY = grabY
        } completion: {
            settle()
            then?()
        }
    }

    /// The page drops back where it was.
    private func fallBack() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            progress = 0
            liftY = grabY
        } completion: {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { turn = nil }
        }
    }

    /// The landed turn becomes the book's page (with no animation: the leaf already lies exactly there).
    private func settle() {
        guard let t = turn else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            index = t.target
            turn = nil
            progress = 0
        }
        Haptics.impact(.soft, intensity: 0.6)
    }

    // MARK: Turning by itself

    /// A swipe anywhere on the spread turns the page by itself.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { v in
                let w = v.translation.width, h = v.translation.height
                guard abs(w) > abs(h) * 2, abs(w) > 60 else { return }
                if w < 0 { go(to: index - 1) } else { go(to: index + 1) }
            }
    }

    /// Turns to a spread by itself: one page that flicks over (a far day goes over in one turn too, the right days on
    /// its two sides).
    private func go(to target: Int, duration: Double = 0.62, then: (() -> Void)? = nil) {
        guard days.indices.contains(target), target != index, turn == nil else { return }
        if reduceMotion {
            index = target
            then?()
            return
        }
        let d: PageTurnDirection = target < index ? .forward : .backward
        let h = max(1, bookSize.height)
        guard begin(d, target: target, grabY: h * 0.84) else { return }
        // The leaf is drawn flat first, then goes over (the next frame), its corner lifting a little as it does.
        Task { @MainActor in
            liftY = h * 0.84
            withAnimation(.easeOut(duration: duration * 0.35)) { liftY = h * 0.74 }
            land(duration: duration, then: then)
        }
    }

    /// From another day, the ribbon takes the book back to today: a few pages flick over (at most three, the last one
    /// landing on today).
    private func riffleToToday() {
        guard index > 0, turn == nil, !riffling else {
            Haptics.selection()
            return
        }
        let start = index
        let flicks = min(3, start)
        var stops: [Int] = []
        for k in 1...flicks {
            stops.append(Int((Double(start) * Double(flicks - k) / Double(flicks)).rounded(.down)))
        }
        riffling = true
        riffle(stops)
    }

    private func riffle(_ stops: [Int]) {
        guard let next = stops.first else {
            riffling = false
            return
        }
        let rest = Array(stops.dropFirst())
        go(to: next, duration: rest.isEmpty ? 0.5 : 0.26) { riffle(rest) }
    }

    // MARK: Opening

    private func appear() {
        index = min(max(0, startIndex), max(0, days.count - 1))
        if startsLookedBack, let d = current {
            panel = (d.day, .lookBack(focus: DiaryPageView.words(on: d.day, in: dex).first?.word?.headword))
        } else if startsCorrected, let d = current {
            panel = (d.day, .correction)
        }
        if let held = heldTurn {
            coverUp = false
            bookShift = 1
            leftReveal = 1
            // Once the book has its size (it is measured as it appears).
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                let target = held.direction == .forward ? index - 1 : index + 1
                let h = max(1, bookSize.height)
                if begin(held.direction, target: target, grabY: h * 0.86) {
                    progress = held.progress
                    liftY = h * held.lift
                }
            }
            return
        }
        if let wait = demoTurnAfter {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(wait))
                go(to: index - 1, duration: 0.9)
            }
        }
        guard coverUp, showsCover, !reduceMotion else {
            coverUp = false
            bookShift = 1
            leftReveal = 1
            Self.coverOpenedThisLaunch = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            SoundService.shared.play(.bookOpen)
            Haptics.impact(.rigid, intensity: 0.45)
            // A hard cover: slow to lift off the block (its weight), upright half way…
            withAnimation(.timingCurve(0.55, 0.0, 0.8, 0.55, duration: 0.5)) {
                coverAngle = -90
                bookShift = 0.5
            } completion: {
                // …then it falls open and lands with a short bounce; the left page comes in under it.
                withAnimation(.spring(response: 0.46, dampingFraction: 0.7)) {
                    coverAngle = -180
                    bookShift = 1
                }
                withAnimation(.easeIn(duration: 0.3)) { leftReveal = 1 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(260))
                    Haptics.impact(.rigid, intensity: 0.8)
                    try? await Task.sleep(for: .milliseconds(500))
                    coverUp = false
                    Self.coverOpenedThisLaunch = true
                }
            }
        }
    }

    // MARK: Under the book

    private var pager: some View {
        HStack(spacing: 18) {
            Button { go(to: index + 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Self.ink.opacity(0.07), in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .disabled(!canBackward || turning)
            .accessibilityLabel(L("前の日"))
            .accessibilityIdentifier("spread.older")
            Text(current.map { Calendar.current.isDateInToday($0.day) ? L("今日") : DiaryPageView.title($0.day) } ?? "")
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(Self.ink.opacity(0.6))
                .frame(minWidth: 140)
                .contentTransition(.opacity)
            Button { go(to: index - 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Self.ink.opacity(0.07), in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .disabled(!canForward || turning)
            .accessibilityLabel(L("次の日"))
            .accessibilityIdentifier("spread.newer")
        }
        .foregroundStyle(Self.ink)
        .frame(maxWidth: .infinity)
    }
}

/// A day whose diary is open as a sheet (the iPhone's home).
struct DiaryDay: Identifiable, Equatable {
    let day: Date
    var id: Date { day }
}
