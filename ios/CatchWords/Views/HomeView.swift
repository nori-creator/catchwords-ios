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
    /// 「完了」 pressed: the board being rearranged saves and stops.
    @State private var finishEditing = 0
    /// The calendar (header button): a day picked there scrolls the album to it; the other days stay above and
    /// below it (owner 2026-10-14: 「カレンダーの日付を押すとその日の欄が見えるように。スクロールしてほかの日にも移動できる」).
    @State private var calendarOpen = false
    @State private var calendarDay: Date?
    @State private var jumpCount = 0
    /// Moves the page while a photo is carried to the screen's top or bottom edge (`AlbumAutoScroll`).
    @State private var autoScroll = AlbumAutoScroll()

    private struct MemorialDay: Identifiable {
        let n: Int
        var id: Int { n }
    }

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())

        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let n = profile.createdAt.flatMap({ Milestone.today(start: $0) }),
                       !memorialHidden, !Milestone.wasDismissed(n) {
                        MemorialBanner(n: n, words: dex.stickers.count, photos: Milestone.highlights(dex.stickers).count) {
                            Haptics.impact(.medium)
                            memorialOpen = n
                        } onDismiss: {
                            Milestone.dismiss(n)
                            withAnimation(.snappy) { memorialHidden = true }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Photos kept at the shutter whose analysis has not finished (web Home pending banner).
                    if !dex.pending.isEmpty {
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
                                finishRequest: finishEditing
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
        .background(HomeBackground())
        // Rearranging the album ends with 「完了」 (web: a fixed button above the tab bar), wherever the board is.
        .overlay(alignment: .bottom) {
            if albumEditing {
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
                .padding(.bottom, 84)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("home.album.done")
            }
        }
        .fullScreenCover(item: Binding(get: { memorialOpen.map(MemorialDay.init) }, set: { memorialOpen = $0?.n })) { m in
            MemorialAlbumView(n: m.n, words: dex.stickers.count, picks: Milestone.highlights(dex.stickers)) { s in
                memorialOpen = nil
                router.detailSticker = s
            } onClose: {
                memorialOpen = nil
            }
        }
        .task(id: profile.createdAt) {
            if let start = profile.createdAt { await Milestone.scheduleNotification(start: start) }
        }
        .sheet(isPresented: $calendarOpen) {
            NavigationStack {
                ScrollView {
                    DexCalendarView(stickers: dex.albumStickers, selectedDay: $calendarDay, onOpen: { s in
                        calendarOpen = false
                        router.detailSticker = dex.albumOwner(s)
                    }) { picked in
                        calendarDay = picked
                        calendarOpen = false
                        jumpCount += 1
                    }
                    .padding(.horizontal, 16)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { calendarOpen = false } label: { Image(systemName: "xmark") }
                            .accessibilityLabel(L("閉じる"))
                    }
                }
            }
            // Opened full height: on the half sheet only the first weeks of the month showed (owner 2026-10-14
            // 「カレンダーボタン押したとき、すべての日にちが見えるように開いて。いま半分しか見えない」).
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

    private var header: some View {
        HStack(spacing: 12) {
            Button { Haptics.selection(); showStats = true } label: { AvatarView(url: profile.avatarURL, size: 38) }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel(L("あなたの記録"))
            Text("CatchWords")
                .scaledFont(size: 18, weight: .medium)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                Haptics.selection()
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

    /// Every day with photos, newest first. Today always leads, even before its first photo.
    static func days(from stickers: [Sticker], today: Date) -> [AlbumDay] {
        let cal = Calendar.current
        var byDay = Dictionary(grouping: stickers) { cal.startOfDay(for: $0.takenAt) }
        if byDay[today] == nil { byDay[today] = [] }
        return byDay.keys.sorted(by: >).map { d in
            AlbumDay(day: d, items: (byDay[d] ?? []).sorted { $0.takenAt < $1.takenAt })
        }
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

/// Web `album-hidden-tray`: photos taken off the album, each with 「戻す」. Collapsed by default.
struct AlbumHiddenTray: View {
    @Environment(DexStore.self) private var dex
    @State private var open = false
    @State private var failed = false

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
