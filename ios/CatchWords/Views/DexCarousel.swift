import QuartzCore
import SwiftUI

/// The dex "slide" view — the web's `DexCoverFlow` with `theme="gallery"` (R15): white cards turn on a ring
/// in a pale blue room, like choosing a card pack. The middle card faces you up front; the cards on either
/// side swing back along the ring (outer edge toward you) and the next ones peek, smaller, behind them.
/// The floor reflects each card and small sparks blink in the air. The photos are shown as they are — no
/// holographic foil, light streak or shimmer on them (owner 2026-10-09).
///
/// Position and pose are worked out from one number every frame (`CarouselSpring.value`, in cards), so the
/// ring follows the finger 1:1 and never lags a frame behind. On release the flick's momentum is projected
/// to the card it would coast to, and a critically damped spring (response 0.5) carries the finger's speed
/// into the snap. Only `CoverFlowStage` reads that per-frame number; this view (dots, photo row, sound)
/// redraws only when the middle card changes (`CarouselSpring.index`).
struct DexCoverFlow: View {
    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    let stickers: [Sticker]
    let onOpen: (Sticker) -> Void
    /// The card first put in the middle (the simulator preview opens part-way along).
    var initialIndex = 0

    @State private var spring = CarouselSpring()
    @State private var lastSlideSound: CFTimeInterval = 0
    @State private var muteSlideSound = false
    /// The stage is wide enough for the cards to stand in a row (`CarouselPose.isRow`).
    @State private var wideStage = false
    @State private var stageSize: CGSize = .zero

    private var center: Int {
        guard !stickers.isEmpty else { return 0 }
        return max(0, min(stickers.count - 1, spring.index))
    }

    // MARK: Layout (owner 2026-10-11: 「スライドの図鑑のカードの上が見切れてる。また下にまた余白があるから、
    // カード自体を大きくして。」)

    /// Air between the header and the card's top edge. The header's material fades out over the 18 pt under
    /// it; the card used to start 16 pt down, its top edge under that fade.
    static let cardTop: CGFloat = 26
    /// The floor band kept under the card for its reflection, as a share of the card's height. It was 0.18 —
    /// mostly an empty strip, as the reflection is faint — so that room now goes to the card itself.
    static let reflectionBand: CGFloat = 0.1
    /// Where the reflection has faded out (share of the card's height): inside the band, so the clipped ring
    /// never cuts it off with a visible edge.
    static let reflectionFade: CGFloat = 0.085
    /// The dots row (24 + 4 pt) and the photo row (64 pt, only from two cards up).
    static let dotsHeight: CGFloat = 28
    static let thumbsHeight: CGFloat = 64
    /// The floating tab bar (58 + 4 pt) is drawn over the dex's last points, plus a little air above it. The
    /// old reserve of 120 pt left an empty strip between the photo row and the bar.
    static let bottomReserve: CGFloat = 74

    /// The card's width: as big as the height under the header allows (the card, its reflection band, the
    /// dots, the photo row and the tab bar's room), at most 80% of the width so the neighbours still peek
    /// (web: `--cf-w` for the gallery theme).
    static func cardWidth(in size: CGSize, cards: Int) -> CGFloat {
        let below = dotsHeight + (cards >= 2 ? thumbsHeight : 0) + bottomReserve
        let byHeight = (size.height - cardTop - below) / (1.48 * (1 + reflectionBand))
        return min(size.width * 0.8, 340, max(150, byHeight))
    }

    /// The ring's height for a card width: the air above the card, the card and its reflection band.
    static func stageHeight(cardWidth w: CGFloat) -> CGFloat {
        cardTop + w * 1.48 * (1 + reflectionBand)
    }

    var body: some View {
        GeometryReader { geo in
            let w = Self.cardWidth(in: geo.size, cards: stickers.count)
            VStack(spacing: 0) {
                CoverFlowStage(spring: spring, stickers: stickers, stageWidth: geo.size.width, cardWidth: w,
                               reduceMotion: reduceMotion, onOpen: onOpen, bring: bring)
                    .frame(height: Self.stageHeight(cardWidth: w))
                dots
                thumbnails
                Spacer(minLength: 0)
            }
        }
        .onChange(of: stickers.map(\.id)) { old, _ in
            // The cards changed (a filter, a word added or removed): keep the place, clamped to the new
            // last card, without the slide sound (muted only when the middle card really changes).
            let to = min(center, max(0, stickers.count - 1))
            if to != max(0, min(old.count - 1, spring.index)) { muteSlideSound = true }
            spring.set(Double(to))
        }
        .onChange(of: center) { _, _ in
            if muteSlideSound { muteSlideSound = false; return }
            // A card reached the middle: the recorded "suh" (web: `el-gallery-slide`, gain 0.8) and a selection
            // tick, never closer than 70ms so a fast flick past many cards doesn't jam.
            let now = CACurrentMediaTime()
            guard now - lastSlideSound >= 0.07 else { return }
            lastSlideSound = now
            SoundService.shared.slide()
            Haptics.selection()
        }
        .onAppear {
            SoundService.shared.warmTicks()
            muteSlideSound = initialIndex > 0
            spring.set(Double(max(0, min(stickers.count - 1, initialIndex))))
        }
        .onDisappear { spring.stop() }
        // On a wide stage the row opens a few cards in, so cards stand on both sides of the middle one — once the cards
        // are there (the stage is measured before the dex has loaded).
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            stageSize = size
            startWideRow()
        }
        .onChange(of: stickers.count) { _, _ in startWideRow() }
    }

    private func startWideRow() {
        let w = Double(Self.cardWidth(in: stageSize, cards: stickers.count))
        guard !wideStage, stickers.count >= 3, CarouselPose.isRow(stageWidth: Double(stageSize.width), cardWidth: w) else { return }
        wideStage = true
        guard initialIndex == 0, center == 0 else { return }
        let side = Int(CarouselPose.rowReach(stageWidth: Double(stageSize.width), cardWidth: w)) - 1
        muteSlideSound = true
        spring.set(Double(max(1, min(side, stickers.count / 2))))
    }

    private func bring(_ i: Int) {
        guard !stickers.isEmpty else { return }
        let j = Double(max(0, min(stickers.count - 1, i)))
        if reduceMotion { spring.set(j) } else { spring.to(j, response: 0.5, damping: 1) }
    }

    // MARK: Dots and photo row

    /// The blue dot shows how far along you are (web `progressDots`): first card → left end, last → right end.
    private var dots: some View {
        HStack(spacing: 2) {
            ForEach(Self.progressDots(count: stickers.count, index: center)) { d in
                Button { bring(d.i) } label: {
                    Circle()
                        .fill(d.active ? Theme.primary : Color.black.opacity(0.18))
                        .frame(width: 8, height: 8)
                        .scaleEffect(d.active ? 1.35 : 1)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.snappy(duration: 0.2), value: center)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var thumbnails: some View {
        if stickers.count >= 2 {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(stickers.enumerated()), id: \.element.id) { i, s in
                            Button { bring(i) } label: {
                                Color.black.opacity(0.05).frame(width: 48, height: 48)
                                    .overlay { DexThumb(sticker: s, inset: 3, maxPoints: 48).allowsHitTesting(false) }
                                    .clipShape(.rect(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(i == center ? Theme.primary : .clear, lineWidth: 2))
                                    .opacity(i == center ? 1 : 0.6)
                                    .animation(.easeOut(duration: 0.2), value: center)
                            }
                            .buttonStyle(PressableStyle(scale: 0.92))
                            .accessibilityLabel(s.word?.headword ?? "")
                            .id(s.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .frame(height: 64)
                .onChange(of: center) { _, c in
                    guard stickers.indices.contains(c) else { return }
                    withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(stickers[c].id, anchor: .center) }
                }
            }
        }
    }

    // MARK: Math shared with the web (`lib/spring.ts`, `lib/cover-flow.ts`)

    /// Where a flick would coast to (Apple's deceleration, rate 0.998).
    static func projectMomentum(_ velocity: Double, rate: Double = 0.998) -> Double {
        velocity / 1000 * (rate / (1 - rate))
    }

    static func rubberband(_ overshoot: Double, _ dimension: Double, constant: Double = 0.55) -> Double {
        let d = max(dimension, 0.0001)
        return overshoot * d * constant / (d + constant * abs(overshoot))
    }

    struct Dot: Identifiable {
        let i: Int
        let active: Bool
        var id: Int { i }
    }

    static func progressDots(count: Int, index: Int, limit: Int = 7) -> [Dot] {
        guard count > 0 else { return [] }
        let cur = max(0, min(count - 1, index))
        if count <= limit { return (0..<count).map { Dot(i: $0, active: $0 == cur) } }
        let on = Int((Double(cur) / Double(count - 1) * Double(limit - 1)).rounded())
        return (0..<limit).map { k in
            Dot(i: Int((Double(k) / Double(limit - 1) * Double(count - 1)).rounded()), active: k == on)
        }
    }
}

extension Sticker {
    /// The sticker as the slide dex draws it: its word without the extras (examples, chunks, notes, measure words…),
    /// which no card shows. SwiftUI compares a view's stickers field by field each time the dex redraws, and with the
    /// extras a big dex compared megabytes of text on the main thread every time — the 図鑑 tab froze the screen
    /// (owner 2026-10-18; DexOpenTests' trace: `Sticker.==` holding the main thread for seconds at a time).
    nonisolated var forCards: Sticker {
        guard word?.extras != nil else { return self }
        var s = self
        s.word?.extras = nil
        return s
    }
}

/// The ring itself — the only view that reads the spring's per-frame value, so a swipe redraws the cards'
/// poses and nothing else. Each card's face is its own view (`CarouselCardFace`) whose inputs don't change
/// while it moves, so SwiftUI skips rebuilding it and only the transforms update.
private struct CoverFlowStage: View {
    let spring: CarouselSpring
    let stickers: [Sticker]
    let stageWidth: CGFloat
    let cardWidth: CGFloat
    let reduceMotion: Bool
    let onOpen: (Sticker) -> Void
    let bring: @MainActor (Int) -> Void

    @State private var dragFrom: Double?

    private var center: Int {
        guard !stickers.isEmpty else { return 0 }
        return max(0, min(stickers.count - 1, spring.index))
    }

    private var row: Bool { CarouselPose.isRow(stageWidth: stageWidth, cardWidth: cardWidth) }
    private var rowReach: Double { CarouselPose.rowReach(stageWidth: stageWidth, cardWidth: cardWidth) }

    var body: some View {
        let w = cardWidth
        let width = stageWidth
        let ch = w * 1.48
        let top = DexCoverFlow.cardTop
        let stageH = DexCoverFlow.stageHeight(cardWidth: w)
        let step = w * CarouselPose.stepWidth(row: row)
        let pos = spring.value
        let range = visibleRange(around: pos)
        return ZStack(alignment: .topLeading) {
            ForEach(range, id: \.self) { i in
                // `stickers` can shrink (a delete) between computing the range and drawing it.
                if stickers.indices.contains(i) {
                    slot(i, pos: pos, stageHeight: stageH)
                }
            }
        }
        .frame(width: width, height: stageH, alignment: .topLeading)
        .contentShape(Rectangle())
        .clipped()
        // The white light pooled at the middle card's feet (no pedestal — R15). Behind the clipped ring rather
        // than inside it: with the shorter reflection band the clip would cut the light off in a straight line,
        // so it spreads on under the dots as before.
        .background(alignment: .topLeading) {
            EllipticalGradient(colors: [.white.opacity(0.95), .white.opacity(0)], center: .center)
                .frame(width: w * 2.2, height: w * 0.5)
                .position(x: width / 2, y: top + ch - w * 0.12 + w * 0.25)
                .allowsHitTesting(false)
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { g in
                    if dragFrom == nil {
                        spring.stop()
                        dragFrom = spring.value
                    }
                    let maxPos = Double(max(0, stickers.count - 1))
                    var x = (dragFrom ?? 0) - g.translation.width / step
                    // Resistance past the ends instead of a hard stop.
                    if x < 0 { x = -DexCoverFlow.rubberband(-x, 2) } else if x > maxPos { x = maxPos + DexCoverFlow.rubberband(x - maxPos, 2) }
                    spring.set(x)
                }
                .onEnded { g in
                    dragFrom = nil
                    guard !stickers.isEmpty else { return }
                    let maxPos = Double(stickers.count - 1)
                    // Finger speed in cards per second (dragging left moves the ring forward).
                    var v = -g.velocity.width / step
                    let projected = spring.value + DexCoverFlow.projectMomentum(v)
                    let target = max(0, min(maxPos, projected.rounded()))
                    if reduceMotion {
                        spring.set(target)
                        return
                    }
                    // Carry the finger's speed into the snap, but no more than the spring can absorb over the
                    // distance left — at the ends a hard flick would otherwise sail past the last card.
                    let limit = CarouselSpring.omega(response: 0.5) * abs(target - spring.value) + 1.5
                    v = max(-limit, min(limit, v))
                    spring.to(target, response: 0.5, damping: 1, velocity: v)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: bring(center + 1)
            case .decrement: bring(center - 1)
            @unknown default: break
            }
        }
    }

    private func visibleRange(around pos: Double) -> [Int] {
        guard !stickers.isEmpty else { return [] }
        let reach = row ? rowReach : CarouselPose.reach
        let lo = max(0, Int((pos - reach).rounded(.down)))
        let hi = min(stickers.count - 1, Int((pos + reach).rounded(.up)))
        return lo <= hi ? Array(lo...hi) : []
    }

    /// One card on the ring, projected like the web's `perspective: 1000px` (origin 50% / 45%).
    private func slot(_ i: Int, pos: Double, stageHeight: CGFloat) -> some View {
        let w = cardWidth
        let s = stickers[i]
        let rel = Double(i) - pos
        let p = CarouselPose.pose(rel, reduced: reduceMotion, row: row, rowReach: rowReach)
        let ch = w * 1.48
        let perspective: CGFloat = 1000
        let z = p.z * w
        let scale = perspective / (perspective - z)
        let originY = stageHeight * 0.45
        let cardCenterY = DexCoverFlow.cardTop + ch / 2
        let isCenter = i == center
        return CarouselCard(sticker: s, width: w, mirror: abs(rel) <= 3)
            .contentShape(Rectangle())
            .onTapGesture {
                if isCenter { onOpen(s) } else { bring(i) }
            }
            .rotation3DEffect(.degrees(p.rotateY), axis: (x: 0, y: 1, z: 0), perspective: ch / perspective)
            .scaleEffect(scale)
            .position(x: stageWidth / 2 + p.x * w * scale, y: originY + (cardCenterY - originY) * scale)
            .opacity(p.opacity)
            .zIndex(p.zIndex)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(s.word?.headword ?? "") \(s.word?.meaningJa ?? "")")
            .accessibilityAddTraits(isCenter ? [.isButton, .isSelected] : .isButton)
    }
}

/// Web `carouselPose`: the cards stand on an ellipse `RING_R` wide and `RING_DEPTH` deep (in card widths),
/// `RING_STEP` radians apart; the middle card is at the front (z = 0).
enum CarouselPose {
    static let radius = 1.0
    static let depth = 1.6
    static let angle = 0.78
    /// How far the middle card moves per card, so it sticks to the finger 1:1 (card widths).
    static let step = radius * angle
    /// Cards further round than this are behind the middle one and aren't drawn.
    static let reach = 3.4

    /// On a screen much wider than the card (iPhone Duo's inner screen held sideways) the cards stand in a row across
    /// the whole width instead of on a ring, as many as fit (owner 2026-10-30: 「図鑑のスライドは表示できるだけ全て表示して」):
    /// each `rowGap` card widths from the next, a little smaller further out.
    static let rowGap = 0.58
    static func isRow(stageWidth: Double, cardWidth: Double) -> Bool { cardWidth > 0 && stageWidth >= 800 }
    /// The cards on each side of the middle one that fit in the row.
    static func rowReach(stageWidth: Double, cardWidth: Double) -> Double {
        guard cardWidth > 0 else { return reach }
        return (stageWidth / 2 / (rowGap * 0.88 * cardWidth)).rounded(.up) + 1
    }
    /// How far the middle card moves per card (card widths), so it sticks to the finger.
    static func stepWidth(row: Bool) -> Double { row ? rowGap : step }

    static func pose(_ offset: Double, reduced: Bool, row: Bool = false, rowReach: Double = reach) -> (x: Double, z: Double, rotateY: Double, zIndex: Double, opacity: Double) {
        if row {
            let o = max(-rowReach, min(rowReach, offset))
            let a = abs(o)
            return (
                x: rowGap * o * (1 - min(a, 6) * 0.02),
                z: -0.22 * min(a, 6),
                rotateY: reduced ? 0 : -max(-1, min(1, o)) * 8,
                zIndex: 100 - (min(9, a) * 10).rounded(),
                opacity: 1
            )
        }
        let o = max(-reach, min(reach, offset))
        let a = abs(o)
        let phi = o * angle
        return (
            x: radius * sin(phi),
            z: -depth * (1 - cos(phi)),
            // Turned slightly inward so the outer edge comes toward you; flat with reduced motion.
            rotateY: reduced ? 0 : -phi * 0.3 * 180 / .pi,
            // Nearer is on top; past 4 cards the order stops changing so it never flips.
            zIndex: 100 - (min(4, a) * 10).rounded(),
            // The far side of the ring (past 2 cards) slowly fades out.
            opacity: max(0, min(1, 1 - (a - 2.2) * 0.8))
        )
    }
}

/// A white card (photo, word with its reading, meaning, date and place) and its reflection on the floor.
/// The photo is plain: no foil, streak or shimmer over it (owner 2026-10-09).
private struct CarouselCard: View {
    let sticker: Sticker
    let width: CGFloat
    let mirror: Bool

    var body: some View {
        CarouselCardFace(sticker: sticker, width: width)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(red: 40 / 255, green: 80 / 255, blue: 140 / 255).opacity(0.1), lineWidth: 1))
            // The two shadows as one picture drawn once (`CardShadow`), not cast from the card on every frame: a shadow
            // under a 3D turn was worked out again, off screen, for every card at every frame of a swipe (owner
            // 2026-10-20: 「図鑑のスライドがなめらかじゃない」).
            .background { CardShadow.image.resizable(capInsets: CardShadow.insets).padding(-CardShadow.pad) }
            .background(alignment: .top) {
                if mirror { reflection }
            }
    }

    /// The card's feet on the floor: what the faint upside-down copy showed within the reflection band was the white
    /// of the card's bottom edge (its date line upside down at 22% was all but invisible), so a white glow that fades
    /// out within the band takes its place — a second whole card face for every card cost as much as the card.
    private var reflection: some View {
        UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: width * 1.48 * DexCoverFlow.reflectionFade)
            .offset(y: width * 1.48 + 3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The card's two shadows (0.08 at radius 3, 2 pt down; 0.3 at radius 16, 18 pt down) drawn once into a stretchable
/// picture: its corners and edges are kept and its middle stretched to any card size, so a card in motion is a plain
/// picture behind a plain picture.
enum CardShadow {
    static let pad: CGFloat = 48
    private static let corner: CGFloat = 14
    static var insets: EdgeInsets {
        let c = pad + corner + 4
        return EdgeInsets(top: c, leading: c, bottom: c + 20, trailing: c)
    }

    static let image: Image = {
        let inner = CGSize(width: 120, height: 160)
        let size = CGSize(width: inner.width + pad * 2, height: inner.height + pad * 2)
        let ink = UIColor(red: 40 / 255, green: 70 / 255, blue: 120 / 255, alpha: 1)
        let picture = UIGraphicsImageRenderer(size: size).image { r in
            let cg = r.cgContext
            let card = UIBezierPath(roundedRect: CGRect(x: pad, y: pad, width: inner.width, height: inner.height),
                                    cornerRadius: corner).cgPath
            // SwiftUI's shadow radius is about half of Core Graphics' blur.
            for (alpha, radius, y) in [(0.3, 16.0, 18.0), (0.08, 3.0, 2.0)] {
                cg.saveGState()
                cg.setShadow(offset: CGSize(width: 0, height: y), blur: radius * 2, color: ink.withAlphaComponent(alpha).cgColor)
                cg.addPath(card)
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillPath()
                cg.restoreGState()
            }
        }
        return Image(uiImage: picture)
    }()
}

/// The card's printed face. Its inputs (the sticker and the width) don't change while the ring turns, so
/// SwiftUI keeps the built face and the per-frame work is only the transforms around it.
private struct CarouselCardFace: View {
    let sticker: Sticker
    let width: CGFloat

    private static let ink = Color(hex: 0x1D1D1F)
    private static let muted = Color(hex: 0x5F6B7D)

    var body: some View {
        let s = sticker
        let h = width * 1.48
        return VStack(alignment: .leading, spacing: 0) {
            // The photo takes up to 64% of the card but is the one that gives way: with the higher layout
            // priority it gets the card minus the words' own height, so the word, meaning and date always fit
            // (web DexCoverFlow: photo `h-[64%] min-h-0 shrink`, text `shrink-0`). It used to be a fixed 64%: on a
            // narrow card the text ran over, and the centred face lost its top — the photo's top and the
            // category chip (owner 2026-10-11: 「スライドの図鑑のカードの上が見切れてる」).
            Color.black.opacity(0.05)
                .frame(width: width)
                .frame(maxHeight: h * 0.64)
                .overlay {
                    DexThumb(sticker: s, inset: 10).allowsHitTesting(false)
                }
                .clipped()
                .overlay(alignment: .topLeading) {
                    // One of the 20 dex categories (SPEC §0: no 「その他」), placed exactly like the shadow gallery
                    // does, in that category's colour (light tone behind dark text, deep tone as the rim).
                    let no = DexBook.category(of: s, lang: NativeAPI.targetLanguage)
                    let cat = CCCategory.forDex(no)
                    let emoji = DexCatalog.withOther.first(where: { $0.no == no })?.emoji ?? ""
                    Text("\(emoji) \(DexCatalog.label(no))")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Self.ink)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: cat.b1), in: Capsule())
                        .overlay(Capsule().stroke(Color(hex: cat.b2), lineWidth: 1))
                        .padding(8)
                }
                // No memory % in the top right corner any more (owner 2026-10-11: 「右上の%消して」).
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: 4) {
                DexFitWidth {
                    ZhuyinWordView(headword: s.word?.headword ?? "", zhuyin: s.word?.readingZhuyin, size: 22, weight: .bold,
                                   color: Self.ink, readingColor: Self.muted, pinyin: s.word?.pinyin)
                }
                Text(s.word?.meaningJa ?? "").font(.system(size: 15)).foregroundStyle(Self.ink.opacity(0.9))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    // Shrinks for a long meaning's width only, never for height: its full line is part of the
                    // words' height the photo makes room for.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    Text(JPDate.monthDay(s.takenAt)).monospacedDigit()
                    if s.lat != nil || !(s.locationName ?? "").isEmpty {
                        Label {
                            LocalizedPlaceText(lat: s.lat, lng: s.lng, saved: s.locationName)
                        } icon: {
                            Image(systemName: "mappin")
                        }
                        .lineLimit(1)
                    }
                }
                .font(.system(size: 12)).foregroundStyle(Self.muted)
            }
            .padding(14)
            .frame(width: width, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // Top-aligned: should the words still not fit (a tiny card), the date line goes, never the photo's top.
        .frame(width: width, height: h, alignment: .top)
        .background(.white)
    }
}

/// The pale blue room behind the slide view (web `.dex-cf[data-theme="gallery"] .dex-cf__backdrop` and its sparks).
struct DexGalleryBackdrop: View {
    @Environment(\.appReduceMotion) private var reduceMotion

    /// [left %, top %, delay s] — fixed places, never reshuffled.
    private static let sparks: [(Double, Double, Double)] = [
        (8, 14, 0), (22, 30, 1.6), (37, 9, 0.8), (52, 22, 2.4), (66, 12, 1.1), (81, 27, 0.3),
        (92, 8, 1.9), (14, 44, 2.8), (88, 46, 0.6), (30, 56, 2.1), (72, 58, 1.4), (46, 40, 3.1),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xD6E3F5), location: 0),
                        .init(color: Color(hex: 0xE6EEFA), location: 0.34),
                        .init(color: Color(hex: 0xF4F8FD), location: 0.58),
                        .init(color: .white, location: 0.64),
                        .init(color: Color(hex: 0xE8F0FB), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                // radial-gradient(70% 22% at 50% 62%, white 95% → clear at 70%): the bright floor.
                Ellipse()
                    .fill(EllipticalGradient(colors: [.white.opacity(0.95), .white.opacity(0)], center: .center))
                    .frame(width: geo.size.width * 0.98, height: geo.size.height * 0.308)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.62)
                if reduceMotion {
                    ForEach(Self.sparks.indices, id: \.self) { k in
                        let sp = Self.sparks[k]
                        Spark(alpha: 0.6, dy: 0)
                            .position(x: geo.size.width * sp.0 / 100, y: geo.size.height * sp.1 / 100)
                    }
                } else {
                    // One Canvas drawn 30 times a second: twelve glows as gradients. Twelve views with two shadows
                    // each were twenty-four off-screen passes per frame under the turning cards.
                    TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        Canvas { ctx, size in
                            for sp in Self.sparks {
                                let phase = Self.twinkle(((t - sp.2) / 4.2).truncatingRemainder(dividingBy: 1))
                                Self.drawSpark(in: &ctx, at: CGPoint(x: size.width * sp.0 / 100,
                                                                     y: size.height * sp.1 / 100 + 4 - 7 * phase),
                                               alpha: 0.95 * phase)
                            }
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A spark as the shadows drew it: a blue haze (radius 8), a white glow (radius 4) and the 3 pt dot.
    private static func drawSpark(in ctx: inout GraphicsContext, at p: CGPoint, alpha: Double) {
        guard alpha > 0.01 else { return }
        let haze = Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20))
        ctx.fill(haze, with: .radialGradient(Gradient(colors: [Color(red: 120 / 255, green: 170 / 255, blue: 1).opacity(0.35 * alpha), .clear]),
                                             center: p, startRadius: 0, endRadius: 10))
        let glow = Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
        ctx.fill(glow, with: .radialGradient(Gradient(colors: [.white.opacity(0.9 * alpha), .clear]),
                                             center: p, startRadius: 0, endRadius: 6))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(.white.opacity(alpha)))
    }

    /// 0 → 1 at 45% of the 4.2s cycle → 0 (ease-in-out), like the web's `dex-cf-spark` keyframes.
    private static func twinkle(_ x: Double) -> Double {
        let f = x < 0 ? x + 1 : x
        let u = f < 0.45 ? f / 0.45 : (1 - f) / 0.55
        return u * u * (3 - 2 * u)
    }

    private struct Spark: View {
        let alpha: Double
        let dy: Double

        var body: some View {
            Circle()
                .fill(.white)
                .frame(width: 3, height: 3)
                .shadow(color: .white.opacity(0.9), radius: 4)
                .shadow(color: Color(red: 120 / 255, green: 170 / 255, blue: 1).opacity(0.35), radius: 8)
                .offset(y: dy)
                .opacity(alpha)
        }
    }
}

/// A spring driven every frame (web `createSpring`): Apple's response / damping, the speed carried over
/// from the finger, and retargetable mid-flight without a jump. A CADisplayLink (not SwiftUI's own
/// animation) because the ring is non-linear in this number — cards must travel along the ellipse, appear
/// and drop out at the back, and fire the slide sound / haptic as each card passes the middle — none of which
/// an interpolated `withAnimation` value would report while it runs.
@MainActor @Observable
final class CarouselSpring: NSObject {
    /// Where the ring is, in cards (0 = the first card in the middle). Changes every frame while moving;
    /// read it only in the view that draws the poses.
    private(set) var value: Double = 0
    /// The card nearest the middle (`value` rounded, not clamped). Changes only when a card passes the
    /// middle, so views that just need "which card" don't redraw every frame.
    private(set) var index: Int = 0

    @ObservationIgnored private var velocity: Double = 0
    @ObservationIgnored private var target: Double = 0
    @ObservationIgnored private var stiffness: Double = 0
    @ObservationIgnored private var friction: Double = 0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTime: CFTimeInterval = 0

    /// Angular frequency for Apple's `response` (seconds per oscillation).
    nonisolated static func omega(response: Double) -> Double {
        2 * Double.pi / max(0.05, response)
    }

    /// Put it there at once (following the finger, or with reduced motion).
    func set(_ v: Double) {
        stop()
        move(to: v)
        velocity = 0
        target = v
    }

    func to(_ t: Double, response: Double, damping: Double, velocity v: Double? = nil) {
        target = t
        if let v { velocity = v }
        let omega = Self.omega(response: response)
        stiffness = omega * omega
        friction = 2 * damping * omega
        guard link == nil else { return }
        lastTime = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        velocity = 0
    }

    /// The one place `value` changes; `index` is only written when it really changes (an @Observable
    /// property notifies on every set, equal or not).
    private func move(to x: Double) {
        value = x
        let n = x.isFinite ? Int(x.rounded()) : 0
        if n != index { index = n }
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        var dt = min(1.0 / 20, max(0, now - lastTime))
        lastTime = now
        var x = value
        var v = velocity
        // Small fixed steps keep the spring stable at any frame rate.
        while dt > 0 {
            let h = min(dt, 1.0 / 240)
            let a = -stiffness * (x - target) - friction * v
            v += a * h
            x += v * h
            dt -= h
        }
        if abs(x - target) < 0.0005, abs(v) < 0.005 {
            move(to: target)
            stop()
            return
        }
        velocity = v
        move(to: x)
    }
}
