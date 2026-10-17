import SwiftUI

// The dex ギャラリー: one white card per category (`.dcat`), its title and count (`.cat-t`), a 4-column grid
// (`.dexgrid`) of slots (`.slot`): caught words, then the current shadows. Prototype CSS values; in dark mode
// the same layout with the app's dark surfaces.

private enum DexInk {
    static let border = Color(light: 0xE6ECF3, dark: 0x1D2635)
    static let sil = Color(light: 0xC5CFDC, dark: 0x34445A)
    static let no = Color(light: 0x8C96A3, dark: 0x7D8899)
    static let q = Color(light: 0xAEB8C4, dark: 0x5D6B7E)
    static let segBg = Color(light: 0xF1F3F8, dark: 0x132032)
    static let segOn = Color(light: 0xFFFFFF, dark: 0x22324A)
}

/// The landing slot's state in the gallery: its `.sart` is reported to the landing (global coordinates), and once
/// filled its picture runs `fillIn`. No blue ring or fill around it (owner 2026-10-11: 「単語をキャッチしたてのとき、
/// 青表示しないで、普通に切り抜きの画像だけでいい」), and the focus goes once the landing is over (DexView).
struct DexGalleryFocus: Equatable {
    var id: String
    /// `.slot.fill` started (CCClock time); nil = not filled yet.
    var fillStart: Double?
    /// Film v6: the sticker itself landed (arriving 1.3× and tilted): the square settles from that pose instead of
    /// fading in.
    var settle: Bool = false
    /// Film v6: the sticker's anticipation started (CCClock) and when it hits: the waiting silhouette tints blue.
    var anticipAt: Double? = nil
    var impactAt: Double? = nil
}

/// Film v6's marks after a catch has landed: the NEW badge on its square (until the 図鑑 is left), the category's
/// count held back until it rolls, and the breathing ring round the category's next shadow.
struct DexLandingMarks: Equatable {
    var newId: String
    var category: Int
    /// The impact (CCClock time).
    var impact: Double
    /// The category's count still shows the number before the catch (it rolls at impact + .3).
    var countLag: Int = 0
    /// A re-encounter landed on `newId` (its word was caught before): no NEW badge, no count, no next shadow's ring —
    /// only an accessibility mark saying it was met again (the UI tests find the square by it).
    var again: Bool = false
}

struct DexGallery: View {
    let sections: [DexSection]
    let focus: DexGalleryFocus?
    let calm: Bool
    /// Film v6's marks after a landing (nil = none).
    var marks: DexLandingMarks? = nil
    /// The landing slot's `.sart` frame in global coordinates, as it lays out.
    var onTargetFrame: ((CGRect) -> Void)? = nil
    let onOpen: (Sticker) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(sections) { sec in
                DexCategoryCard(section: sec, focus: focus, calm: calm,
                                marks: marks?.category == sec.category.no ? marks : nil,
                                onTargetFrame: onTargetFrame, onOpen: onOpen)
                    .padding(.top, 12)
                    .id("dexcat-\(sec.category.no)")
            }
        }
    }
}

/// `.dcat`: white, radius 22, padding 12 12 14, a 1 pt #E6ECF3 ring and a soft shadow underneath.
private struct DexCategoryCard: View {
    let section: DexSection
    let focus: DexGalleryFocus?
    let calm: Bool
    /// This category's marks after a landing.
    let marks: DexLandingMarks?
    let onTargetFrame: ((CGRect) -> Void)?
    let onOpen: (Sticker) -> Void

    /// The next shadow to find after a landing in this category (its ring breathes).
    private var goalSlot: String? {
        guard let marks, !marks.again else { return nil }
        return section.slots.first { slot in
            if case .shadow = slot.kind { return true }
            return false
        }?.id
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9, alignment: .top), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // .cat-t: 14 pt 800, "n / m" in 12 pt 600 #5C646F, baseline-aligned, margin 2 2 10
            HStack(alignment: .firstTextBaseline) {
                Text("\(section.category.emoji) \(section.category.label)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.foreground)
                Spacer(minLength: 8)
                Text("\(section.caughtCount - (marks?.countLag ?? 0)) / \(section.slots.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(marks == nil || marks?.again == true ? Theme.muted : Theme.primary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 10)
            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(Array(section.slots.enumerated()), id: \.element.id) { index, slot in
                    DexSlotView(slot: slot, index: index, focus: focus?.id == slot.id ? focus : nil, calm: calm,
                                isNew: marks?.again != true && marks?.newId == slot.id,
                                isAgain: marks?.again == true && marks?.newId == slot.id,
                                goalSince: goalSlot == slot.id ? marks?.impact : nil,
                                onTargetFrame: focus?.id == slot.id ? onTargetFrame : nil, onOpen: onOpen)
                        .id(slot.id)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Theme.card, in: .rect(cornerRadius: 22, style: .circular))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .circular).stroke(DexInk.border, lineWidth: 1))
        // 0 6px 18px −12px rgba(20,50,90,.25)
        .background(RoundedRectangle(cornerRadius: 22, style: .circular).fill(Color.rgba(20, 50, 90, 0.25))
            .padding(12).offset(y: 6).blur(radius: 9))
    }
}

/// `.slot`: the square `.sart` (radius 16), `.no` (9.5 pt 700) and `.nm` (13 pt 800; `.nm.q` for shadows).
private struct DexSlotView: View {
    @Environment(DexStore.self) private var dex
    let slot: DexSlot
    /// Its place in the category (the photo cycling is staggered by it, web `DexCyclingPhoto`).
    let index: Int
    let focus: DexGalleryFocus?
    let calm: Bool
    /// Film v6: the word just caught (the NEW badge pops on its square and stays).
    var isNew: Bool = false
    /// A re-encounter just landed on this square (nothing is drawn: an accessibility mark only).
    var isAgain: Bool = false
    /// Film v6: the category's next shadow after a landing (a dashed ring breathes round it from impact + 1 s).
    var goalSince: Double? = nil
    let onTargetFrame: ((CGRect) -> Void)?
    let onOpen: (Sticker) -> Void

    private var lang: String { NativeAPI.targetLanguage }

    var body: some View {
        switch slot.kind {
        case .caught(let s):
            Button { onOpen(s) } label: { column(caught: s) }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityIdentifier("dex.cell")
                .accessibilityLabel(s.word?.headword ?? "")
                // The NEW badge sits on the square's corner, outside the button (its own element: the UI tests find
                // the word that just landed by it).
                .overlay(alignment: .topTrailing) {
                    if isNew { DexNewBadge(calm: calm).offset(x: 4, y: -2) }
                }
                // Its own element too: VoiceOver says the word was met again, and the UI tests find the square by it.
                .overlay(alignment: .topTrailing) {
                    if isAgain {
                        Rectangle().fill(Color.white.opacity(0.001))
                            .frame(width: 8, height: 8)
                            .allowsHitTesting(false)
                            .accessibilityElement()
                            .accessibilityLabel(L("また会えた！"))
                            .accessibilityIdentifier("dex.again")
                    }
                }
        case .shadow(let item):
            column(shadow: item)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("まだ見つけていない言葉 \(DexBook.shadowLabel(item.headword(for: lang), lang: lang))"))
        case .pending:
            pendingColumn()
                .accessibilityHidden(true)
        }
    }

    private var noText: some View {
        Text(slot.no.map { "No.\(String(format: "%03d", $0))" } ?? "No.---")
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.38)
            .foregroundStyle(DexInk.no)
            .lineLimit(1)
    }

    private func column(caught s: Sticker) -> some View {
        VStack(spacing: 3) {
            sart(caught: true) { picture(s) }
                .overlay(alignment: .bottomTrailing) {
                    // Its save failed and it waits to be saved again (owner 2026-10-15: never removed from the dex).
                    if dex.isUnsaved(s.id) { DexUnsavedMark() }
                }
                .detailZoomSource(s.id)   // the word sheet zooms out of this square
            noText
            // A long word (冷氣遙控器) shrinks to its own column instead of running over the next one.
            DexFitWidth(minScale: 0.4, alignment: .center) {
                CCZhuyinWord(headword: s.word?.headword ?? "", zhuyin: s.word?.readingZhuyin ?? "", pinyin: s.word?.pinyin ?? "",
                             size: 13, weight: .heavy, color: Theme.foreground)
            }
        }
        .contentShape(Rectangle())
    }

    private func column(shadow item: DexItem) -> some View {
        VStack(spacing: 3) {
            sart(caught: false) {
                ZStack {
                    DexSilhouette(item: item)
                    if let a = focus?.anticipAt, !calm { DexAnticipTint(item: item, start: a, impact: focus?.impactAt) }
                }
            }
                .overlay {
                    if let since = goalSince { DexGoalRing(since: since, calm: calm) }
                }
            noText
            Text(DexBook.shadowLabel(item.headword(for: lang), lang: lang))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DexInk.q)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipped()
        }
    }

    private func pendingColumn() -> some View {
        VStack(spacing: 3) {
            sart(caught: false) { Color.clear }
            noText
            Text(" ").font(.system(size: 13, weight: .bold))
        }
    }

    /// The square a picture or a shadow stands in. No tile or frame behind it any more (owner 2026-10-11:
    /// 「図鑑の一覧のそれぞれの単語の画像は切り抜きで、画像周りの枠は削除して」): the cut-out stands on the card
    /// like a sticker, a shadow is its grey silhouette alone. The landing slot reports its frame; filled, its
    /// content runs `fillIn`. The prototype's blue `.slot.fill` ring is gone: with the tile gone it was a filled
    /// blue square behind the transparent cut-out (owner 2026-10-11: 「単語をキャッチしたてのとき、青表示しないで、
    /// 普通に切り抜きの画像だけでいい」) — the pop, the burst and the glints mark the landing.
    private func sart<C: View>(caught: Bool, @ViewBuilder content: () -> C) -> some View {
        let inner = content()
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { DexFillIn(start: focus?.fillStart, calm: calm, settle: focus?.settle ?? false) { inner } }
            .background {
                if let report = onTargetFrame {
                    Color.clear
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { frame in
                            report(frame)
                        }
                }
            }
    }

    /// The word's pictures: the cut-out whole (a soft shadow along its outline), a photo still without one rounded —
    /// with no white ring or frame — and, when the word was photographed more than once, each picture in turn.
    private func picture(_ s: Sticker) -> some View {
        let pictures = dex.dexPictures(for: s)
        return DexCyclingPicture(pictures: pictures, stagger: index, calm: calm, headword: s.word?.headword)
            // No picture at all: its internet stand-in is fetched (the square shows the word until then).
            .task(id: s.id) { if pictures.isEmpty { dex.autoHeroSoon(s) } }
    }
}

/// A caught word's pictures in turn (web `DexCyclingPhoto`, owner 2026-10-11: 「単語の写真を複数枚撮った場合は、WEB版の
/// ように図鑑をみているときに、その単語の欄で別の画像が自動で…切り替わるように」): a 1 s crossfade every 3.6 s, squares
/// staggered 0.6 s apart so they never all change at once, only while on screen, and never with 設定 › アニメーション off.
/// Only the picture on show and the next one are drawn (the next one has loaded before it fades in).
struct DexCyclingPicture: View {
    let pictures: [DexPicture]
    let stagger: Int
    let calm: Bool
    /// Drawn on a plain tile when the word has no picture yet (never an empty square).
    var headword: String? = nil

    @Environment(DexStore.self) private var dex
    @State private var shown = 0

    /// Web `DEX_CYCLE_MS` / `DEX_FADE_MS`.
    static let cycle: Double = 3.6
    static let fade: Double = 1.0

    private var cycling: Bool { pictures.count > 1 && !calm }
    private var current: Int { pictures.isEmpty ? 0 : shown % pictures.count }
    private var frames: [Int] {
        guard !pictures.isEmpty else { return [] }
        return cycling ? [current, (current + 1) % pictures.count] : [0]
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack {
                if pictures.isEmpty, let headword, !headword.isEmpty {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.secondary)
                        .frame(width: w * 0.86, height: w * 0.86)
                        .overlay {
                            Text(headword)
                                .font(.system(size: w * 0.2, weight: .heavy))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(2)
                                .minimumScaleFactor(0.4)
                                .multilineTextAlignment(.center)
                                .padding(6)
                        }
                }
                ForEach(frames, id: \.self) { i in
                    one(pictures[i], width: w)
                        .opacity(i == current ? 1 : 0)
                }
            }
            .frame(width: w, height: w)
        }
        .allowsHitTesting(false)
        .task(id: "\(pictures.map(\.path).joined(separator: "|"))|\(calm)") {
            shown = 0
            guard cycling else { return }
            // Web: the first change comes at (stagger × 7 mod 6) × 0.6 s + 1.8 s, then every 3.6 s.
            let offset = Double((stagger * 7) % 6) * (Self.cycle / 6)
            try? await Task.sleep(for: .seconds(offset + Self.cycle / 2))
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: Self.fade)) { shown += 1 }
                try? await Task.sleep(for: .seconds(Self.cycle))
            }
        }
    }

    @ViewBuilder
    private func one(_ p: DexPicture, width w: CGFloat) -> some View {
        if p.isCutout {
            // Decoded at the square's size (a dex of full-size cut-outs did not fit in memory: `StickerImage.maxPoints`).
            StickerImage(path: p.path, url: dex.url(for: p.path), contentMode: .fit, maxPoints: w)
                .frame(width: w * 0.9, height: w * 0.9)
                .shadow(color: .rgba(0, 30, 70, 0.22), radius: 2.5, y: 2.5)
                .frame(width: w, height: w)
        } else {
            StickerImage(path: p.path, url: dex.url(for: p.path), contentMode: .fill, maxPoints: w)
                .frame(width: w * 0.86, height: w * 0.86)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                .shadow(color: .rgba(0, 30, 70, 0.18), radius: 4, y: 3)
                .frame(width: w, height: w)
        }
    }
}

/// `@keyframes fillIn {0% {transform: scale(1.7) rotate(-10deg); opacity: 0} 60% {opacity: 1} 100% {transform: none}}`
/// over .9 s with cubic-bezier(.3,1.5,.5,1) per keyframe segment (transform 0→100%, opacity 0→60% and 60→100%).
private struct DexFillIn<Content: View>: View {
    let start: Double?
    let calm: Bool
    /// Film v6 (`drawTargetSlot` after the impact): the sticker arrived 1.3× and tilted −7°; the picture settles
    /// from there (spring .42 / .52) with the squash of the contact, no fade.
    var settle: Bool = false
    @ViewBuilder let content: Content
    /// The `start` whose animation has played out: the TimelineView goes away instead of redrawing forever.
    @State private var done: Double?

    var body: some View {
        if let start, !calm, done != start {
            TimelineView(.animation) { _ in
                if settle {
                    let u = max(0, CCClock.now - start)
                    let st = Film6.spring(u, response: 0.42, damping: 0.52)
                    let sq = sin(Film6.clamp(u / 0.22) * .pi) * exp(-u * 6)
                    let k = Film6.lerp(1.3, 1, st)
                    content
                        .scaleEffect(x: k * (1 + 0.14 * sq), y: k * (1 - 0.12 * sq))
                        .rotationEffect(.degrees(-6.9 * (1 - st)))
                } else {
                    let t = max(0, min(1, (CCClock.now - start) / 0.9))
                    let e = CCBezier(0.3, 1.5, 0.5, 1)
                    let p = e(t)
                    let o = t < 0.6 ? max(0, min(1, e(t / 0.6))) : 1
                    content
                        .scaleEffect(1.7 + (1 - 1.7) * p)
                        .rotationEffect(.degrees(-10 * (1 - p)))
                        .opacity(o)
                }
            }
            .task(id: start) {
                let left = 0.95 - (CCClock.now - start)
                if left > 0 { try? await Task.sleep(for: .seconds(left)) }
                done = start
            }
        } else {
            content
        }
    }
}

/// `.sil`: the grey silhouette at 72%: art from the asset catalog (`dexsil-<id>`), else the SF Symbol (filled
/// variant when it has one), else (needsArt) a neutral rounded placeholder.
struct DexSilhouette: View {
    let item: DexItem
    /// Another colour than the grey (the landing's blue tint).
    var color: Color? = nil

    /// Reads every shadow's picture once, off the main thread, behind the first screen: the art from the asset catalog,
    /// else the SF Symbol. The first open of the 図鑑 drew them all on the main thread while the system's symbol files
    /// were still being read from the disk (50 s on the UI tour's cold simulator, 2026-10-16); read once here, they are
    /// in the file cache by then.
    nonisolated static func warmUp() {
        for item in DexCatalog.allItems {
            if UIImage(named: "dexsil-\(item.id)") != nil { continue }
            if let sf = item.symbol { _ = UIImage(systemName: sf + ".fill") ?? UIImage(systemName: sf) }
        }
    }

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height) * 0.72
            Group {
                if let art = UIImage(named: "dexsil-\(item.id)") {
                    Image(uiImage: art).renderingMode(.template).resizable().scaledToFit()
                } else if let sf = item.symbol {
                    Image(systemName: sf).resizable().symbolVariant(.fill).scaledToFit()
                } else {
                    // .sil.ph: 52% of the square, radius 22%
                    let ph = min(g.size.width, g.size.height) * 0.52
                    RoundedRectangle(cornerRadius: ph * 0.22, style: .circular)
                        .frame(width: ph, height: ph)
                }
            }
            .foregroundStyle(color ?? DexInk.sil)
            .frame(width: s, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

/// `#dxSeg`: four round buttons (36 pt) in a #F1F3F8 capsule (padding 4, gap 6); the chosen one white with a
/// small shadow. Icons are the prototype's SVGs (18 pt, stroke 2).
struct DexModeSegment: View {
    @Binding var mode: DexMode
    let onSelect: (DexMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DexMode.allCases) { m in
                let on = mode == m
                Button { onSelect(m) } label: {
                    DexModeIcon(mode: m, color: on ? Theme.foreground : Theme.muted)
                        .frame(width: 18, height: 18)
                        .frame(width: 36, height: 36)
                        .background {
                            if on {
                                Circle().fill(DexInk.segOn).shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.label)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("dex.mode.\(m.rawValue)")
            }
        }
        .padding(4)
        .background(DexInk.segBg, in: Capsule())
    }
}

/// The prototype's `#dxSeg` icons (viewBox 24).
private struct DexModeIcon: View {
    let mode: DexMode
    let color: Color

    var body: some View {
        GeometryReader { g in
            let w = 2 * min(g.size.width, g.size.height) / 24
            let round = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
            switch mode {
            case .cover:
                // <rect x=6 y=4 w=12 h=16 rx=2/><path d="M2 7v10M22 7v10"/>
                ZStack {
                    CCSVGPath(d: "M8 4h8a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z").stroke(color, style: round)
                    CCSVGPath(d: "M2 7v10M22 7v10").stroke(color, style: round)
                }
            case .map:
                ZStack {
                    CCSVGPath(d: "M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z").stroke(color, style: round)
                    CCSVGPath(d: "M9 4v14M15 6v14").stroke(color, style: round)
                }
            case .grid:
                // four 7×7 rects (rx 1) at (3,3) (14,3) (3,14) (14,14); stroke 2, square joins
                ZStack {
                    ForEach(["M4 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z",
                             "M15 3h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z",
                             "M4 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1z",
                             "M15 14h5a1 1 0 0 1 1 1v5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1v-5a1 1 0 0 1 1-1z"], id: \.self) { d in
                        CCSVGPath(d: d).stroke(color, lineWidth: w)
                    }
                }
            case .list:
                CCSVGPath(d: "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01").stroke(color, style: round)
            }
        }
    }
}

/// Film v6 (`drawTargetSlot`): the waiting silhouette tints blue as the sticker comes (.55 at the hit).
private struct DexAnticipTint: View {
    let item: DexItem
    let start: Double
    let impact: Double?

    var body: some View {
        TimelineView(.animation) { _ in
            let end = impact ?? start + 0.52
            let an = Film6.seg(CCClock.now, start, max(start + 0.05, end))
            DexSilhouette(item: item, color: Theme.primaryBright)
                .opacity(0.55 * an)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A 「保存待ち」 word's square: a small cloud-with-arrow mark in its corner (its page says why and saves it again).
private struct DexUnsavedMark: View {
    var body: some View {
        Image(systemName: "icloud.and.arrow.up")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Theme.primary, in: Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            .shadow(color: .rgba(0, 40, 90, 0.25), radius: 2, y: 1)
            .offset(x: 2, y: 2)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(L("保存待ち"))
            .accessibilityIdentifier("dex.unsaved")
    }
}

/// Film v6's NEW badge on the square just caught: a red capsule tilted a little, popping in a moment after the impact.
private struct DexNewBadge: View {
    let calm: Bool
    @State private var shown = false

    var body: some View {
        Text(verbatim: "NEW")
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.7)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Color(hex: 0xFF3B30), in: Capsule())
            .shadow(color: .rgba(255, 59, 48, 0.45), radius: 3)
            .rotationEffect(.degrees(-8))
            .scaleEffect(shown ? 1 : 0.01)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityIdentifier("dex.new")
            .onAppear {
                withAnimation(calm ? nil : .spring(response: 0.32, dampingFraction: 0.5).delay(0.1)) { shown = true }
            }
    }
}

/// Film v6: the category's next shadow after a catch — a dashed blue ring that breathes (alpha .55 + .45 sin 4.2 t).
private struct DexGoalRing: View {
    let since: Double
    let calm: Bool

    var body: some View {
        TimelineView(.animation(paused: calm)) { _ in
            let u = CCClock.now - since
            let gp = Film6.seg(u, 1.0, 1.2)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 1.8, dash: [5, 3.6], dashPhase: calm ? 0 : -u * 14))
                .padding(-2)
                .opacity(calm ? 1 : gp * (0.55 + 0.45 * sin(u * 4.2)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
