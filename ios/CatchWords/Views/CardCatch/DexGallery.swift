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
}

struct DexGallery: View {
    let sections: [DexSection]
    let focus: DexGalleryFocus?
    let calm: Bool
    /// The landing slot's `.sart` frame in global coordinates, as it lays out.
    var onTargetFrame: ((CGRect) -> Void)? = nil
    let onOpen: (Sticker) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(sections) { sec in
                DexCategoryCard(section: sec, focus: focus, calm: calm, onTargetFrame: onTargetFrame, onOpen: onOpen)
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
    let onTargetFrame: ((CGRect) -> Void)?
    let onOpen: (Sticker) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9, alignment: .top), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // .cat-t: 14 pt 800, "n / m" in 12 pt 600 #5C646F, baseline-aligned, margin 2 2 10
            HStack(alignment: .firstTextBaseline) {
                Text("\(section.category.emoji) \(section.category.label)")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.foreground)
                Spacer(minLength: 8)
                Text("\(section.caughtCount) / \(section.slots.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .padding(.bottom, 10)
            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(Array(section.slots.enumerated()), id: \.element.id) { index, slot in
                    DexSlotView(slot: slot, index: index, focus: focus?.id == slot.id ? focus : nil, calm: calm,
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
            sart(caught: false) { DexSilhouette(item: item) }
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
            .overlay { DexFillIn(start: focus?.fillStart, calm: calm) { inner } }
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
            StickerImage(path: p.path, url: dex.url(for: p.path), contentMode: .fit)
                .frame(width: w * 0.9, height: w * 0.9)
                .shadow(color: .rgba(0, 30, 70, 0.22), radius: 2.5, y: 2.5)
                .frame(width: w, height: w)
        } else {
            StickerImage(path: p.path, url: dex.url(for: p.path), contentMode: .fill)
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
    @ViewBuilder let content: Content
    /// The `start` whose animation has played out: the TimelineView goes away instead of redrawing forever.
    @State private var done: Double?

    var body: some View {
        if let start, !calm, done != start {
            TimelineView(.animation) { _ in
                let t = max(0, min(1, (CCClock.now - start) / 0.9))
                let e = CCBezier(0.3, 1.5, 0.5, 1)
                let p = e(t)
                let o = t < 0.6 ? max(0, min(1, e(t / 0.6))) : 1
                content
                    .scaleEffect(1.7 + (1 - 1.7) * p)
                    .rotationEffect(.degrees(-10 * (1 - p)))
                    .opacity(o)
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
            .foregroundStyle(DexInk.sil)
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
