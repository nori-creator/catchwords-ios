import SwiftUI

// The diary book's materials (2026-10-25, owner: 「IPhone duoならではの美しさ、操作性、快感を刺激するようなデザイン…細かい
// ディテールまでこだわって」, after reference videos of notebook apps on iPhone Duo: a cover that opens, pages that curl
// under the finger, a choice of paper, rule and ink). Paper is only colour, grain and light — no handwriting faces
// (owner 2026-10-20: system fonts only).

/// The paper's colour (設定 in the diary's 「紙とインク」 sheet; kept on this device).
enum PaperTone: String, CaseIterable, Identifiable {
    case cream, white, blush, sage

    var id: String { rawValue }
    static let storageKey = "diary.paper"

    var color: Color {
        switch self {
        case .cream: Color(hex: 0xF8F2E4)
        case .white: Color(hex: 0xFCFBF8)
        case .blush: Color(hex: 0xF6E5E1)
        case .sage: Color(hex: 0xE9EEE4)
        }
    }

    /// The edge of the page block and the gutter's shadow, a step darker than the paper.
    var edge: Color {
        switch self {
        case .cream: Color(hex: 0xE4DAC4)
        case .white: Color(hex: 0xE6E3DC)
        case .blush: Color(hex: 0xE5CFC9)
        case .sage: Color(hex: 0xD3DBCB)
        }
    }

    var name: String {
        switch self {
        case .cream: L("クリーム")
        case .white: L("ホワイト")
        case .blush: L("ピンク")
        case .sage: L("セージ")
        }
    }
}

/// The lines on the writing page.
enum PageRule: String, CaseIterable, Identifiable {
    case lined, grid, dots, plain

    var id: String { rawValue }
    static let storageKey = "diary.rule"

    var name: String {
        switch self {
        case .lined: L("罫線")
        case .grid: L("方眼")
        case .dots: L("ドット")
        case .plain: L("無地")
        }
    }
}

/// The ink the diary is written in (the text and the rules' tint).
enum InkTone: String, CaseIterable, Identifiable {
    case navy, sepia, plum, teal, graphite

    var id: String { rawValue }
    static let storageKey = "diary.ink"

    var color: Color {
        switch self {
        case .navy: Color(hex: 0x24365E)
        case .sepia: Color(hex: 0x5C3D22)
        case .plum: Color(hex: 0x5B2A52)
        case .teal: Color(hex: 0x1F5650)
        case .graphite: Color(hex: 0x2E2E2E)
        }
    }

    var name: String {
        switch self {
        case .navy: L("ネイビー")
        case .sepia: L("セピア")
        case .plum: L("プラム")
        case .teal: L("ティール")
        case .graphite: L("グラファイト")
        }
    }
}

/// A page of the book: the paper's colour with its grain, and the light falling into the gutter on the spine's side
/// (both pages darken softly towards the fold, as a real book's do).
struct PaperSurface: View {
    var tone: PaperTone
    /// Where the spine is (nil: a loose sheet, the iPhone's diary).
    var spine: HorizontalEdge? = nil
    /// The outer corners are rounded like a book's page; the spine's side is square.
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            Rectangle()
                .fill(tone.color)
                .colorEffect(ShaderLibrary.paperGrain(.float(0.035)))
            if let spine {
                // The gutter: a deep, short shadow at the fold and a long soft one rising out of it.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.16), location: 0),
                        .init(color: .black.opacity(0.06), location: 0.035),
                        .init(color: .black.opacity(0.02), location: 0.12),
                        .init(color: .clear, location: 0.26),
                    ],
                    startPoint: spine == .leading ? .leading : .trailing,
                    endPoint: spine == .leading ? .trailing : .leading
                )
                .allowsHitTesting(false)
                // The page's outer edge catches the light.
                LinearGradient(colors: [.white.opacity(0.35), .clear],
                               startPoint: spine == .leading ? .trailing : .leading,
                               endPoint: spine == .leading ? .leading : .trailing)
                    .frame(maxWidth: .infinity)
                    .mask(alignment: spine == .leading ? .trailing : .leading) { Rectangle().frame(width: 3) }
                    .allowsHitTesting(false)
            }
        }
        .clipShape(pageShape)
    }

    private var pageShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: spine == .leading ? 0 : cornerRadius,
            bottomLeadingRadius: spine == .leading ? 0 : cornerRadius,
            bottomTrailingRadius: spine == .trailing ? 0 : cornerRadius,
            topTrailingRadius: spine == .trailing ? 0 : cornerRadius,
            style: .continuous
        )
    }
}

/// The writing page's rules, drawn at the text's own line pitch from `top`, so each line of writing sits on one.
struct PageRules: View {
    var rule: PageRule
    var ink: InkTone
    var pitch: CGFloat
    /// Where the first line of text starts.
    var top: CGFloat = 0
    /// Room kept clear on the left and right.
    var inset: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { ctx, size in
            guard pitch > 4 else { return }
            let hair = 1 / max(1, displayScale)
            let color = ink.color.opacity(rule == .dots ? 0.28 : 0.13)
            let left = inset, right = size.width - inset
            switch rule {
            case .plain:
                break
            case .lined:
                var y = top + pitch
                while y < size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: left, y: y))
                    p.addLine(to: CGPoint(x: right, y: y))
                    ctx.stroke(p, with: .color(color), lineWidth: hair)
                    y += pitch
                }
            case .grid:
                let cell = pitch / 2
                var y = top + pitch
                while y < size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: left, y: y))
                    p.addLine(to: CGPoint(x: right, y: y))
                    ctx.stroke(p, with: .color(color), lineWidth: hair)
                    y += cell
                }
                var x = left
                while x <= right {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: top))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(color.opacity(0.7)), lineWidth: hair)
                    x += cell
                }
            case .dots:
                let cell = pitch / 2
                let dot: CGFloat = 1.3
                var y = top + pitch
                while y < size.height {
                    var x = left
                    while x <= right {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)), with: .color(color))
                        x += cell
                    }
                    y += cell
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The edge of the page block beyond a page (小口): one hairline per few pages still to read on that side, so the
/// book is visibly thicker on the side that holds more days.
struct PageEdges: View {
    /// Pages on this side (only the first few are drawn).
    var count: Int
    var edge: HorizontalEdge
    var tone: PaperTone

    static let step: CGFloat = 1.6
    static let maxLines = 6

    var body: some View {
        let n = min(Self.maxLines, max(0, count))
        ZStack(alignment: edge == .leading ? .trailing : .leading) {
            ForEach(0..<n, id: \.self) { i in
                let inset = CGFloat(i + 1) * Self.step
                UnevenRoundedRectangle(
                    topLeadingRadius: edge == .leading ? 6 : 0,
                    bottomLeadingRadius: edge == .leading ? 6 : 0,
                    bottomTrailingRadius: edge == .trailing ? 6 : 0,
                    topTrailingRadius: edge == .trailing ? 6 : 0,
                    style: .continuous
                )
                .fill(tone.color)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: edge == .leading ? 6 : 0,
                        bottomLeadingRadius: edge == .leading ? 6 : 0,
                        bottomTrailingRadius: edge == .trailing ? 6 : 0,
                        topTrailingRadius: edge == .trailing ? 6 : 0,
                        style: .continuous
                    )
                    .stroke(tone.edge, lineWidth: 0.6)
                )
                .padding(.vertical, inset * 0.6)
                .offset(x: edge == .leading ? -inset : inset)
                .zIndex(Double(-i))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The ribbon bookmark hanging over today's page from the top edge. On another day it marks where today is: a tap
/// riffles the pages back to it (`BookSpreadView.riffleToToday`). It sways once when it is shown.
struct BookRibbon: View {
    var color: Color = Color(hex: 0xA3302B)
    var length: CGFloat = 74
    var onToday: Bool
    var action: () -> Void
    @State private var sway: Double = 0
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            RibbonShape()
                .fill(LinearGradient(colors: [color.mix(with: .white, by: 0.12), color, color.mix(with: .black, by: 0.18)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(RibbonShape().stroke(.black.opacity(0.12), lineWidth: 0.5))
                .frame(width: 13, height: onToday ? length : length * 0.55)
                .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0.5, y: 1)
                .rotationEffect(.degrees(sway), anchor: .top)
                .frame(width: 44, height: max(44, length), alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(onToday ? L("しおり") : L("今日のページに戻る"))
        .accessibilityIdentifier("spread.ribbon")
        .task(id: onToday) {
            guard !reduceMotion else { return }
            sway = 7
            withAnimation(.interpolatingSpring(stiffness: 60, damping: 4)) { sway = 0 }
        }
    }
}

/// A ribbon's cut end: a V notch.
struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let notch = min(rect.width * 0.7, rect.height * 0.2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The book's cloth cover, closed over the right page when the book first opens (`BookSpreadView`). Deep navy cloth with
/// its weave and grain, the name blind-pressed into it, the month under it, and an elastic band. Its inside is the
/// paper of the end page. Animatable: `angle` 0 (closed) … −180 (lying open on the left); past −90 its inside shows, and
/// it fades as it settles so the day's page is there under it.
struct BookCoverFlip: View, Animatable {
    var angle: Double
    var month: String
    var tone: PaperTone

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    private static let cloth = Color(hex: 0x1C2742)
    private static let band = Color(hex: 0x8E2A2A)
    /// Square at the spine, rounded at the fore-edge.
    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 12,
                                                      topTrailingRadius: 12, style: .continuous)

    var body: some View {
        let open = -angle
        let facingAway: Double = min(90, open <= 90 ? open : 180 - open)
        let dim: Double = 0.28 * sin(facingAway * Double.pi / 180)
        ZStack {
            if open <= 90 {
                front
            } else {
                // The inside, seen mirrored as the cover turns over.
                inside
                    .scaleEffect(x: -1, y: 1)
                    .opacity(1 - PageCurlGeometry.smoothstep(130, 178, CGFloat(open)))
            }
        }
        // Lit as it turns: darker the more it faces away from the light. In the cover's own shape (a plain rectangle
        // greyed the desk at the rounded corners — CI `spread-cover`, 2026-10-25), mirrored with the inside.
        .overlay(
            Self.shape.fill(Color.black.opacity(dim))
                .scaleEffect(x: open <= 90 ? 1 : -1, y: 1)
                .allowsHitTesting(false)
        )
        // A gentle perspective: at 0.45 the near edge of a page-sized cover swelled past the book's top and bottom as it
        // stood up (CI `spread`, 2026-10-25).
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var front: some View {
        ZStack {
            Self.shape
                .fill(Self.cloth)
                .colorEffect(ShaderLibrary.paperGrain(.float(0.07)))
            // The weave: fine diagonal threads.
            Canvas { ctx, size in
                var x: CGFloat = -size.height
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    ctx.stroke(p, with: .color(.white.opacity(0.025)), lineWidth: 1)
                    x += 3
                }
            }
            .clipShape(Self.shape)
            // The spine's hinge: a pressed groove near the fold.
            HStack(spacing: 0) {
                Color.clear.frame(width: 14)
                LinearGradient(colors: [.black.opacity(0.35), .white.opacity(0.06), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 6)
                Spacer()
            }
            VStack(spacing: 10) {
                Spacer()
                Text(verbatim: "CatchWords")
                    .font(.system(size: 30, weight: .semibold, design: .serif))
                    .foregroundStyle(.white.opacity(0.16))
                    .shadow(color: .black.opacity(0.55), radius: 0, x: 0, y: -1)
                    .shadow(color: .white.opacity(0.10), radius: 0, x: 0, y: 1)
                Rectangle().fill(.white.opacity(0.12)).frame(width: 46, height: 1)
                Text(month)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.32))
                Spacer()
                Spacer()
            }
            // The elastic band.
            HStack {
                Spacer()
                Rectangle()
                    .fill(LinearGradient(colors: [Self.band.mix(with: .white, by: 0.15), Self.band, Self.band.mix(with: .black, by: 0.3)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 11)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: -1)
                    .padding(.trailing, 30)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 8, x: 2, y: 4)
    }

    private var inside: some View {
        Self.shape
            .fill(tone.edge)
            .colorEffect(ShaderLibrary.paperGrain(.float(0.05)))
    }
}

/// The diary's 「紙とインク」: paper colour, rules and ink, each shown as what it looks like. Kept on this device; the book
/// and the iPhone's diary both follow it.
struct DiaryStyleSheet: View {
    @AppStorage(PaperTone.storageKey) private var paper: String = PaperTone.cream.rawValue
    @AppStorage(PageRule.storageKey) private var rule: String = PageRule.lined.rawValue
    @AppStorage(InkTone.storageKey) private var ink: String = InkTone.navy.rawValue
    @Environment(\.dismiss) private var dismiss

    private var tone: PaperTone { PaperTone(rawValue: paper) ?? .cream }
    private var inkTone: InkTone { InkTone(rawValue: ink) ?? .navy }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(L("紙とインク"))
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(Theme.foreground)
                Spacer()
                Button(L("完了")) { dismiss() }
                    .scaledFont(size: 16, weight: .semibold)
            }

            section(L("紙")) {
                HStack(spacing: 14) {
                    ForEach(PaperTone.allCases) { t in
                        swatch(selected: tone == t, label: t.name) {
                            Circle().fill(t.color).overlay(Circle().stroke(t.edge, lineWidth: 1))
                        } action: { paper = t.rawValue }
                    }
                }
            }

            section(L("罫線")) {
                HStack(spacing: 10) {
                    ForEach(PageRule.allCases) { r in
                        Button {
                            Haptics.selection()
                            withAnimation(.snappy) { rule = r.rawValue }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tone.color)
                                    PageRules(rule: r, ink: inkTone, pitch: 16, top: 2, inset: 6)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .frame(height: 64)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(rule == r.rawValue ? inkTone.color : tone.edge, lineWidth: rule == r.rawValue ? 2 : 1))
                                Text(r.name)
                                    .scaledFont(size: 12, weight: rule == r.rawValue ? .semibold : .regular)
                                    .foregroundStyle(Theme.foreground)
                            }
                        }
                        .buttonStyle(PressableStyle(scale: 0.96))
                        .accessibilityAddTraits(rule == r.rawValue ? .isSelected : [])
                    }
                }
            }

            section(L("インク")) {
                HStack(spacing: 14) {
                    ForEach(InkTone.allCases) { t in
                        swatch(selected: inkTone == t, label: t.name) {
                            Circle().fill(t.color)
                        } action: { ink = t.rawValue }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(Theme.card)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Theme.muted)
            content()
        }
    }

    private func swatch<S: View>(selected: Bool, label: String, @ViewBuilder fill: () -> S, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { action() }
        } label: {
            fill()
                .frame(width: 34, height: 34)
                .padding(4)
                .overlay(Circle().stroke(selected ? Theme.foreground : .clear, lineWidth: 2))
                .frame(width: 46, height: 46)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
