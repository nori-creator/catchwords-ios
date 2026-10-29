import SwiftUI

/// Home: the milestone banner, photos still waiting for analysis, then the album — every day's photos as
/// cut-out stickers, newest day first, in one plain vertical scroll (nothing slides or turns sideways).
struct HomeView: View {
    @Environment(DexStore.self) private var dex
    @Environment(ProfileStore.self) private var profile
    @Environment(AppRouter.self) private var router
    @State private var showStats = false
    @State private var memorialOpen: Int?
    @State private var memorialHidden = false
    /// True while a day's photos are being rearranged: the screen holds still under the fingers and 「完了」 shows.
    @State private var albumEditing = false
    /// The photos taken off the album, in a sheet (「外した写真」 beside 「完了」).
    @State private var showingHidden = false
    /// 「完了」 pressed: the board being rearranged saves and stops.
    @State private var finishEditing = 0
    /// The calendar (header button): a day picked there scrolls the album to it; the other days stay above and
    /// below it (owner 2026-10-14: 「カレンダーの日付を押すとその日の欄が見えるように。スクロールしてほかの日にも移動できる」).
    @State private var calendarOpen = false
    /// The calendar's closing pon was played at the tap (× or a picked day), not again when the sheet is gone.
    @State private var calendarPonned = false
    @State private var calendarDay: Date?
    @State private var jumpCount = 0
    /// Moves the page while a photo is carried to the screen's top or bottom edge (`AlbumAutoScroll`).
    @State private var autoScroll = AlbumAutoScroll()
    /// A wide screen (the regular width class: iPhone Duo open): the album is a book, one day a spread, its diary on
    /// the right page (`BookSpreadView`, owner 2026-10-24). The iPhone (compact) keeps the one vertical scroll.
    @Environment(\.horizontalSizeClass) private var widthClass
    /// The day whose diary is open as a sheet (the iPhone's home: 「日記」 on a day).
    @State private var diaryDay: DiaryDay?
    /// The diary's paper (「紙とインク」), for the iPhone's diary sheet.
    @AppStorage(PaperTone.storageKey) private var paperRaw: String = PaperTone.cream.rawValue

    private struct MemorialDay: Identifiable {
        let n: Int
        var id: Int { n }
    }

    var body: some View {
        Group {
            // The book with its diary only while the diary is offered (owner 2026-10-29: not for now); otherwise iPhone
            // Duo open shows the same vertical album as the iPhone.
            if widthClass == .regular && DiaryFeature.enabled { bookBody } else { albumScroll }
        }
        .background(HomeBackground())
        // Rearranging the album ends with 「完了」 (web: a fixed button above the tab bar), wherever the board is.
        .overlay(alignment: .bottom) {
            if albumEditing {
                HStack(spacing: 10) {
                    // The photos taken off with ✕, to put back while rearranging (owner 2026-10-21: after 「完了」 there
                    // was no way back — the tray at the album's end was out of sight).
                    if dex.albumHiddenCount > 0 {
                        Button {
                            Haptics.selection()
                            showingHidden = true
                        } label: {
                            Label(L("外した写真 \(dex.albumHiddenCount)"), systemImage: "eye.slash")
                                .scaledFont(size: 15, weight: .semibold)
                                .foregroundStyle(Theme.foreground)
                                .padding(.horizontal, 18)
                                .frame(minHeight: 52)
                                .background(Theme.card, in: Capsule())
                                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityIdentifier("home.album.hidden")
                    }
                    Button {
                        Haptics.impact(.light)
                        finishEditing += 1
                    } label: {
                        Label(L("完了"), systemImage: "checkmark")
                            .scaledFont(size: 17, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .frame(minHeight: 52)
                            .background(Theme.primary, in: Capsule())
                            .shadow(color: Theme.primary.opacity(0.4), radius: 14, y: 6)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("home.album.done")
                }
                .padding(.bottom, 84)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingHidden) {
            ScrollView {
                AlbumHiddenTray(startOpen: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottom) {
            if let id = dex.albumUndo {
                AlbumUndoBar {
                    withAnimation(.snappy) { dex.albumUndo = nil }
                    Haptics.selection()
                    Task { await dex.setAlbumHidden(id, hidden: false) }
                }
                .padding(.bottom, 110)   // above the tab bar
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: dex.albumUndo) {
            // Offered for 5 seconds; the tray at the album's end still has the photo after that.
            guard dex.albumUndo != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { dex.albumUndo = nil }
        }
        .fullScreenCover(item: Binding(get: { memorialOpen.map(MemorialDay.init) }, set: { memorialOpen = $0?.n })) { m in
            MemorialAlbumView(n: m.n, words: dex.stickers.count, picks: Milestone.highlights(dex.stickers)) { s in
                memorialOpen = nil
                router.detailSticker = s
            } onClose: {
                memorialOpen = nil
            }
        }
        // Again when the display language changes: the scheduled notification carries its text.
        .task(id: "\(profile.createdAt?.timeIntervalSince1970 ?? 0)|\(LanguageState.shared.lang)") {
            if let start = profile.createdAt { await Milestone.scheduleNotification(start: start) }
        }
        .sheet(isPresented: $calendarOpen, onDismiss: {
            // Closed by a swipe down: the same pon back as a word's page closing (owner 2026-10-20), as it ends. × and a
            // picked day pon at the tap (`closeCalendar`); a word opened from it pons open instead.
            if !calendarPonned && router.detailSticker == nil { SoundService.shared.pon(open: false) }
            calendarPonned = false
        }) {
            NavigationStack {
                ScrollView {
                    DexCalendarView(stickers: AlbumDay.onePerWord(dex.albumStickers), selectedDay: $calendarDay, onOpen: { s in
                        calendarOpen = false
                        router.detailSticker = dex.albumOwner(s)
                    }) { picked in
                        calendarDay = picked
                        closeCalendar()
                        jumpCount += 1
                    }
                    .padding(.horizontal, 16)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { closeCalendar() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(L("閉じる"))
                    }
                }
            }
            // Opened full height: on the half sheet only the first weeks of the month showed (owner 2026-10-14
            // 「カレンダーボタン押したとき、すべての日にちが見えるように開いて。いま半分しか見えない」).
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // The day's diary (the iPhone's home; on a wide screen it is the spread's right page).
        .sheet(item: $diaryDay) { d in
            NavigationStack {
                ScrollView {
                    DiaryPageView(day: d.day, standalone: true)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 40)
                }
                .background(PaperSurface(tone: PaperTone(rawValue: paperRaw) ?? .cream, cornerRadius: 0).ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { SoundService.shared.pon(open: false); diaryDay = nil } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(L("閉じる"))
                    }
                }
            }
            .environment(\.colorScheme, .light)  // paper, like the album
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStats) {
            UserStatsPanel(
                onSettings: { showStats = false; router.tab = .settings },
                onReview: { showStats = false; router.tab = .review }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(32)
        }
    }

    /// The iPhone's home: the album as one vertical scroll.
    private var albumScroll: some View {
        let today = Calendar.current.startOfDay(for: Date())

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    memorialBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    // Photos kept at the shutter whose analysis has not finished (web Home pending banner).
                    if !dex.pending.isEmpty {
                        pendingBanner
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                    }

                    Group {
                        if let err = dex.loadError, dex.stickers.isEmpty {
                            // Nothing to show yet and the dex could not be read: say so, offer a retry.
                            AlbumLoadFailed(message: err) { Task { await dex.load() } }
                                .frame(height: 360)
                                .tourAnchor(.album)
                        } else if !dex.hasLoaded, dex.stickers.isEmpty {
                            AlbumSkeleton()
                                .frame(height: 440)
                                .tourAnchor(.album)
                        } else {
                            HomeAlbum(
                                days: AlbumDay.days(from: dex.albumStickers, today: today),
                                // A re-encounter's page opens its word.
                                onOpen: { router.detailSticker = dex.albumOwner($0) },
                                onCamera: { router.tab = .camera },
                                onEditingChange: { on in withAnimation(.snappy) { albumEditing = on } },
                                finishRequest: finishEditing,
                                onDiary: DiaryFeature.enabled ? { (day: Date) in diaryDay = DiaryDay(day: day) } : nil
                            )
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 12)
                    .animation(.easeOut(duration: 0.3), value: dex.hasLoaded)

                    AlbumHiddenTray()
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    Color.clear.frame(height: 120)
                }
                .background(ScrollViewFinder { [autoScroll] sv in autoScroll.scrollView = sv })
            }
            .environment(autoScroll)
            .scrollDisabled(albumEditing)
            // A drag the system cancelled never reports its end: stop the page when rearranging ends either way.
            .onChange(of: albumEditing) { _, _ in autoScroll.end() }
            .refreshable { await dex.load() }
            // The header takes its room from the scroll (instead of covering its top), so a day scrolled to from the
            // calendar shows its date just under it.
            .safeAreaInset(edge: .top, spacing: 8) { header }
            .onChange(of: jumpCount) { _, _ in
                guard let day = calendarDay else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { proxy.scrollTo(day, anchor: .top) }
            }
        }
    }

    /// A wide screen (iPhone Duo open, the regular width class): the album is a book filling the screen under the header
    /// — no page scroll; each page scrolls inside itself (`BookSpreadView`, owner 2026-10-24/25).
    private var bookBody: some View {
        let today = Calendar.current.startOfDay(for: Date())
        return VStack(spacing: 12) {
            memorialBanner
            if !dex.pending.isEmpty { pendingBanner }
            Group {
                if let err = dex.loadError, dex.stickers.isEmpty {
                    AlbumLoadFailed(message: err) { Task { await dex.load() } }
                        .frame(height: 360)
                        .tourAnchor(.album)
                } else if !dex.hasLoaded, dex.stickers.isEmpty {
                    AlbumSkeleton()
                        .frame(height: 440)
                        .tourAnchor(.album)
                } else {
                    BookSpreadView(
                        days: AlbumDay.days(from: dex.albumStickers, today: today),
                        // A re-encounter's page opens its word.
                        onOpen: { router.detailSticker = dex.albumOwner($0) },
                        onCamera: { router.tab = .camera },
                        onEditingChange: { on in withAnimation(.snappy) { albumEditing = on } },
                        finishRequest: finishEditing,
                        jumpDay: calendarDay,
                        jumpCount: jumpCount
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.3), value: dex.hasLoaded)
        }
        .padding(.horizontal, 20)
        // The floating tab bar.
        .padding(.bottom, 78)
        .environment(autoScroll)
        .onChange(of: albumEditing) { _, _ in autoScroll.end() }
        .safeAreaInset(edge: .top, spacing: 8) { header }
    }

    /// The milestone day's banner (100 days, a year …), until it is opened or dismissed.
    @ViewBuilder
    private var memorialBanner: some View {
        if let n = profile.createdAt.flatMap({ Milestone.today(start: $0) }),
           !memorialHidden, !Milestone.wasDismissed(n) {
            MemorialBanner(n: n, words: dex.stickers.count, photos: Milestone.highlights(dex.stickers).count) {
                Haptics.impact(.medium)
                memorialOpen = n
            } onDismiss: {
                Milestone.dismiss(n)
                withAnimation(.snappy) { memorialHidden = true }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Photos kept at the shutter whose analysis has not finished (web Home pending banner).
    private var pendingBanner: some View {
        Button {
            router.openPending = true
            router.tab = .camera
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hourglass").scaledFont(size: 15, weight: .semibold)
                Text(L("解析待ちの写真が\(dex.pending.count)枚あります"))
                    .scaledFont(size: 14, weight: .semibold)
                Spacer()
                Image(systemName: "chevron.right").scaledFont(size: 12, weight: .semibold)
            }
            .foregroundStyle(Color(hex: 0x33291F))
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Color(hex: 0xF3D98A, opacity: 0.45), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(PressableStyle())
    }

    /// × or a picked day: the closing pon at the tap — waiting for the sheet to finish sliding away made it late
    /// (owner 2026-10-20 「バツボタンを押したらちょうど鳴るように」).
    private func closeCalendar() {
        SoundService.shared.pon(open: false)
        calendarPonned = true
        calendarOpen = false
    }

    private var header: some View {
        HStack(spacing: 12) {
            // The avatar and the calendar open a page, like a tab: the same bubble pon and tap as the tab bar
            // (owner 2026-10-15).
            Button { SoundService.shared.pon(open: true); showStats = true } label: { AvatarView(url: profile.avatarURL, size: 38) }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel(L("あなたの記録"))
            Text("CatchWords")
                .scaledFont(size: 18, weight: .medium)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                SoundService.shared.pon(open: true)
                calendarOpen = true
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x33291F))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0x33291F, opacity: 0.07), in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .disabled(albumEditing)
            .accessibilityLabel(L("カレンダー"))
            .accessibilityIdentifier("home.calendar")
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(colors: [.black, .black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// The same faintly blue background as the other tabs (owner 2026-10-14: 「ホームの色をほかのページと統一して。少し青み
/// がかったいろにして」; it was plain white since 2026-10-11).
struct HomeBackground: View {
    var body: some View {
        AppBackground()
    }
}

// MARK: - Album

/// One day of the home album: that day's photos, oldest first (the board lays them out).
struct AlbumDay: Identifiable, Equatable {
    let day: Date
    let items: [Sticker]
    var id: Date { day }

    /// Every day with photos, newest first, one photo per word a day (`onePerWord`). Today always leads, even before
    /// its first photo.
    static func days(from stickers: [Sticker], today: Date) -> [AlbumDay] {
        let cal = Calendar.current
        var byDay = Dictionary(grouping: onePerWord(stickers)) { cal.startOfDay(for: $0.takenAt) }
        if byDay[today] == nil { byDay[today] = [] }
        return byDay.keys.sorted(by: >).map { d in
            AlbumDay(day: d, items: (byDay[d] ?? []).sorted { $0.takenAt < $1.takenAt })
        }
    }

    /// One photo per word per day (owner 2026-10-16: the glasses shot twice in a row stood twice on the day, 「2語」 —
    /// on the server they are one word met twice). The one kept: a cut-out before a photo, then the latest. The order
    /// of first appearance is kept.
    static func onePerWord(_ stickers: [Sticker], language: String = NativeAPI.targetLanguage) -> [Sticker] {
        let cal = Calendar.current
        var kept: [String: Sticker] = [:]
        var order: [String] = []
        for s in stickers {
            let key = "\(cal.startOfDay(for: s.takenAt).timeIntervalSince1970)|\(wordKey(s, language: language))"
            if let k = kept[key] {
                if shows(s, before: k) { kept[key] = s }
            } else {
                kept[key] = s
                order.append(key)
            }
        }
        return order.compactMap { kept[$0] }
    }

    /// Which word a photo is of: its headword as the dex tells words apart, else its word row, else itself.
    static func wordKey(_ s: Sticker, language: String) -> String {
        let h = DexCatalog.norm(s.word?.headword ?? "", lang: language)
        if !h.isEmpty { return "h:" + h }
        if !s.wordId.isEmpty { return "w:" + s.wordId }
        return "id:" + s.id
    }

    /// `a` is shown rather than `b` for the same word on the same day: a cut-out first, then the latest.
    static func shows(_ a: Sticker, before b: Sticker) -> Bool {
        let ac = a.cutoutImageUrl != nil, bc = b.cutoutImageUrl != nil
        if ac != bc { return ac }
        return a.takenAt > b.takenAt
    }
}

/// The album as one plain vertical list: each day's date (no month headings, owner 2026-10-11: 「◯月のアルバムいらない
/// から、日付だけにして、日付の大きさを少し大きく」) and its photos. Any day's photos can be rearranged with a long
/// press (as on the web).
struct HomeAlbum: View {
    let days: [AlbumDay]
    let onOpen: (Sticker) -> Void
    let onCamera: () -> Void
    var onEditingChange: ((Bool) -> Void)? = nil
    var finishRequest: Int = 0
    /// 「日記」 on a day's date: opens that day's diary page (2026-10-24).
    var onDiary: ((Date) -> Void)? = nil

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                daySection(d)
                    .padding(.bottom, 24)
                    .tourAnchor(.album, if: i == 0)
            }
        }
    }

    /// 10月11日(日); a day of another year says its year too (2025年10月11日(土)).
    private static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: day) == cal.component(.year, from: Date())
        return sameYear ? JPDate.monthDayWeek(day) : JPDate.yearMonthDayWeek(day)
    }

    private func daySection(_ d: AlbumDay) -> some View {
        let isToday = Calendar.current.isDateInToday(d.day)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                // Larger (owner 2026-10-14: 「ホーム画面の日付をもう少し大きくして」).
                Text(Self.dayTitle(d.day))
                    .scaledFont(size: 26, weight: .heavy)
                    .foregroundStyle(Color(hex: 0x33291F))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !d.items.isEmpty {
                    Text(L("\(d.items.count)語"))
                        .font(AppFont.mono(14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x33291F, opacity: 0.5))
                }
                if let onDiary {
                    Button {
                        SoundService.shared.pon(open: true)
                        onDiary(d.day)
                    } label: {
                        Image(systemName: "book.pages")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x33291F))
                            .frame(width: 36, height: 36)
                            .background(Color(hex: 0x33291F, opacity: 0.07), in: Circle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.92))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 8 }
                    .accessibilityLabel(L("日記"))
                    .accessibilityIdentifier("home.diary")
                }
            }
            .padding(.horizontal, 10)
            if d.items.isEmpty {
                emptyDay(isToday: isToday)
            } else {
                CollageBoard(items: d.items, editable: true, onOpen: onOpen, onEditingChange: onEditingChange,
                             finishRequest: finishRequest)
            }
        }
    }

    /// Today before its first photo: only the way to the camera (owner 2026-10-15: the handwritten line is gone).
    private func emptyDay(isToday: Bool) -> some View {
        VStack(spacing: 14) {
            if isToday {
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
        .padding(.vertical, 28)
    }
}

/// Right after a photo is taken off the album: 「写真をアルバムから外しました」 with 「元に戻す」.
struct AlbumUndoBar: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(L("写真をアルバムから外しました"))
                .scaledFont(size: 14, weight: .medium)
                .foregroundStyle(.white)
            Button(action: onUndo) {
                Text(L("元に戻す"))
                    .scaledFont(size: 14, weight: .bold)
                    .foregroundStyle(Theme.primaryBright)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.albumUndo")
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .background(Theme.toastInk.opacity(0.9), in: Capsule())
    }
}

/// Web `album-hidden-tray`: photos taken off the album, each with 「戻す」. Collapsed by default.
struct AlbumHiddenTray: View {
    @Environment(DexStore.self) private var dex
    @State private var open: Bool
    @State private var failed = false

    /// `startOpen`: the list shown at once (the sheet opened from 「外した写真」 while rearranging).
    init(startOpen: Bool = false) { _open = State(initialValue: startOpen) }

    private var hidden: [Sticker] { (dex.stickers + dex.albumEncounters).filter { dex.albumHidden.contains($0.id) } }

    var body: some View {
        if !hidden.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { open.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "eye.slash")
                        Text(L("アルバムから外した写真 \(hidden.count)"))
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundStyle(Color(hex: 0x33291F).opacity(0.7))
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if open {
                    // A wrapping grid (nothing on Home slides sideways).
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10, alignment: .top)], alignment: .leading, spacing: 12) {
                        ForEach(hidden) { s in
                            VStack(spacing: 6) {
                                AlbumPhoto(sticker: s, width: 84, height: 84)
                                Text(s.word?.headword ?? "").scaledFont(size: 12, weight: .semibold).lineLimit(1)
                                // The day it was caught (owner 2026-10-21: 「戻すところの単語のそれぞれに日にちを書いて」).
                                Text(JPDate.monthDay(s.takenAt))
                                    .scaledFont(size: 11, monospacedDigit: true)
                                    .foregroundStyle(Color(hex: 0x33291F).opacity(0.6))
                                    .lineLimit(1)
                                Button(L("戻す")) {
                                    Haptics.selection()
                                    Task {
                                        let ok = await dex.setAlbumHidden(s.id, hidden: false)
                                        withAnimation(.easeOut(duration: 0.2)) { failed = !ok }
                                    }
                                }
                                .scaledFont(size: 13, weight: .semibold)
                                .frame(minWidth: 44, minHeight: 32)
                            }
                            .frame(width: 84)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    if failed {
                        Text(L("保存できませんでした。通信を確かめてください。"))
                            .scaledFont(size: 12).foregroundStyle(Color(hex: 0xB91C1C))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(hex: 0xFFFBF2).opacity(0.8), in: .rect(cornerRadius: 16, style: .continuous))
        }
    }
}

/// The album's shape while the dex is still loading: a blank page with soft photo frames that shimmer,
/// so the home screen is never an empty white sheet.
struct AlbumSkeleton: View {
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        let paper = Color(hex: 0xFFFDF8)
        let frame = Color(hex: 0x33291F, opacity: 0.07)
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(paper)
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 18) {
                    RoundedRectangle(cornerRadius: 6).fill(frame).frame(width: 120, height: 16)
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 14).fill(frame).frame(width: 130, height: 130).rotationEffect(.degrees(-4))
                        RoundedRectangle(cornerRadius: 14).fill(frame).frame(width: 118, height: 118).rotationEffect(.degrees(3))
                    }
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 14).fill(frame).frame(width: 112, height: 112).rotationEffect(.degrees(2))
                        RoundedRectangle(cornerRadius: 14).fill(frame).frame(width: 126, height: 126).rotationEffect(.degrees(-3))
                    }
                    RoundedRectangle(cornerRadius: 6).fill(frame).frame(width: 200, height: 12)
                    RoundedRectangle(cornerRadius: 6).fill(frame).frame(width: 150, height: 12)
                }
                .padding(24)
            }
            .overlay {
                // A soft band of light that sweeps across while waiting.
                GeometryReader { geo in
                    // Soft and narrow, so the frames underneath stay visible while it passes.
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.3)
                        .offset(x: geo.size.width * phase)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("読み込み中"))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.5 }
            }
    }
}

/// The album could not be loaded (offline, server down): a calm message and a retry button.
struct AlbumLoadFailed: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(hex: 0xFFFDF8))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color(hex: 0x33291F, opacity: 0.45))
                    Text(L("アルバムを読み込めませんでした"))
                        .scaledFont(size: 18, weight: .bold)
                        .foregroundStyle(Color(hex: 0x33291F))
                    Text(message)
                        .scaledFont(size: 14)
                        .foregroundStyle(Color(hex: 0x33291F, opacity: 0.6))
                        .multilineTextAlignment(.center)
                    Button(action: onRetry) {
                        Label(L("もう一度読み込む"), systemImage: "arrow.clockwise")
                            .scaledFont(size: 16, weight: .semibold).foregroundStyle(.white)
                            .padding(.horizontal, 22).frame(minHeight: 48)
                            .background(Theme.primary, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(28)
            }
    }
}
