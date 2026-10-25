import SwiftUI
import UIKit

// The word page's parts as the owner approved them in 版25 (docs/word-detail-design.md, mock
// https://claude.ai/artifact/GWwf6QQp7KQjZSG3tM9g3N): the quiet speaker buttons, the grey boxes' numbers, the examples
// that stay within two lines, the review blur, the ruled Taiwan memo, the two-column links and the jump chips.

extension VerticalAlignment {
    /// The middle of the characters a control reads (a reading drawn over them must not pull the control up — §1).
    nonisolated enum HanCenter: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    nonisolated static let hanCenter = VerticalAlignment(HanCenter.self)
}

/// A size of the word page: the design's point size at the reader's text size (Dynamic Type) and the page's own
/// 「文字の大きさ」 (`pageTextScale`).
func detailFontSize(_ size: CGFloat, _ dynamicTypeSize: DynamicTypeSize, _ pageTextScale: CGFloat) -> CGFloat {
    AppTypeScale.scaled(size, for: dynamicTypeSize) * pageTextScale
}

// MARK: - Speaker (§1)

/// The page's speaker: the headword's is the vivid blue disc (50 pt); every other one is quiet — light blue with a blue
/// mark (34 pt, 30 pt in the examples and related words), dark blue only while it plays. The tap area is 44 pt whatever
/// the look. A long press (0.45 s) plays it at 0.7 × the chosen speed, with 「0.7×」 over the button meanwhile.
struct DetailSpeakButton: View {
    enum Style { case hero, normal, small }

    let text: String
    var style: Style = .normal
    /// 「発音の速さ」 of the page's settings (0.6–1.2).
    @AppStorage("detail.speechRate") private var speechRate: Double = 1
    @State private var playing = false
    @State private var slow = false
    @State private var token = 0
    @Environment(\.appReduceMotion) private var reduceMotion

    private var size: CGFloat {
        switch style {
        case .hero: 50
        case .normal: 34
        case .small: 30
        }
    }

    var body: some View {
        let lit = style == .hero || playing
        Image(systemName: "speaker.wave.2")
            .font(.system(size: style == .hero ? 20 : style == .small ? 13 : 15, weight: .semibold))
            .foregroundStyle(lit ? Color.white : Theme.primaryInk)
            .frame(width: size, height: size)
            .background(lit ? Theme.primary : Theme.primary.opacity(0.12), in: Circle())
            .shadow(color: style == .hero ? Theme.primary.opacity(0.3) : .clear, radius: 6, y: 2)
            .overlay(alignment: .top) {
                if slow {
                    Text(verbatim: "0.7×")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.primaryInk)
                        .fixedSize()
                        .offset(y: -16)
                        .transition(.opacity)
                }
            }
            .scaleEffect(playing && !reduceMotion ? 0.94 : 1)
            .contentShape(Circle().inset(by: -max(0, (44 - size) / 2)))
            .onTapGesture { play(slow: false) }
            .onLongPressGesture(minimumDuration: 0.45) { play(slow: true) }
            .accessibilityElement()
            .accessibilityLabel(L("発音を聞く"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { play(slow: false) }
            // Web `pronounce.prefetch`: fetch the server voice when the button appears, so the tap is instant.
            .task(id: text) { SoundService.shared.prefetch(text) }
    }

    private func play(slow isSlow: Bool) {
        Haptics.selection()
        SoundService.shared.speak(text, rate: speechRate * (isSlow ? 0.7 : 1))
        token += 1
        let mine = token
        withAnimation(.easeOut(duration: 0.15)) {
            playing = true
            slow = isSlow
        }
        Task {
            try? await Task.sleep(for: .milliseconds(isSlow ? 1400 : 800))
            guard mine == token else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                playing = false
                slow = false
            }
        }
    }
}

/// The number of a chunk and of the example that uses it (E: the digit alone, 17 pt bold, muted — §1).
struct DetailNumber: View {
    let n: Int

    var body: some View {
        Text(verbatim: "\(n)")
            .scaledFont(size: 17, weight: .bold, monospacedDigit: true)
            .foregroundStyle(Theme.muted.opacity(0.8))
    }
}

// MARK: - Review (§9)

/// What 「復習モード」 hides until it is tapped: the reader's translations, or the Taiwan Mandarin.
enum ReviewHide: String {
    case translation = "tr"
    case target = "zh"
}

/// The page's review state, handed down to every part that can be hidden.
struct ReviewMask {
    var on: Bool
    var hide: ReviewHide
    var shown: Set<String>
    var reveal: (String) -> Void
}

extension EnvironmentValues {
    @Entry var reviewMask: ReviewMask? = nil
}

/// Blurs a part while the review hides it (`blur 7`, 70 %); a tap shows that one part.
struct ReviewBlur: ViewModifier {
    let key: String
    let kind: ReviewHide
    @Environment(\.reviewMask) private var mask

    func body(content: Content) -> some View {
        let hidden = mask.map { $0.on && $0.hide == kind && !$0.shown.contains(key) } ?? false
        content
            .blur(radius: hidden ? 7 : 0)
            .opacity(hidden ? 0.7 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
            .overlay {
                if hidden {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            Haptics.selection()
                            mask?.reveal(key)
                        }
                        .accessibilityElement()
                        .accessibilityLabel(L("答えはぼかしてあります。ダブルタップで表示"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { mask?.reveal(key) }
                }
            }
            .animation(.easeOut(duration: 0.25), value: hidden)
    }
}

extension View {
    /// Hidden under the review's blur when 「ぼかす所」 is `kind` (§9).
    func reviewBlur(_ key: String, _ kind: ReviewHide) -> some View {
        modifier(ReviewBlur(key: key, kind: kind))
    }
}

// MARK: - Example sentence (§4)

/// An example sentence that stays within two lines (§4): drawn at 19 pt; when it would take three lines it gets 1 pt
/// smaller at a time, never under 16 pt on screen. The chunk's run keeps the colours of its parts (verb red, the word
/// blue, glue black) and never breaks; nor does a word of the sentence, and no line starts with a comma. Pinyin over each
/// character only with ピンイン chosen (owner 2026-10-25: no reading at all with 注音). `trailing` (the speaker) ends the
/// first line, level with its characters; the other lines use the full width.
struct ExampleSentenceView<Trailing: View>: View {
    let sentence: String
    let headword: String
    let target: String
    var hit: ChunkRules.ExampleHit? = nil
    var words: [String] = []
    /// Each character's pinyin (nil: no reading drawn).
    var pinyin: [String?]? = nil
    /// The room the trailing control takes at the end of the first line (its width and the gap before it).
    var reserve: CGFloat = 38
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pageTextScale) private var pageTextScale
    @State private var width: CGFloat = 0

    /// The design's smallest example size on screen (owner 2026-10-25: 「文字が読めないような大きさにはしないで」).
    static var smallest: CGFloat { 16 }

    private struct Style {
        var color: Color
        var bold: Bool
    }

    private struct Fit {
        var size: CGFloat
        var lines: [[Int]]   // character indexes per line
        var unitWidths: [CGFloat]
    }

    private var chars: [String] { Array(sentence).map(String.init) }

    var body: some View {
        let chars = self.chars
        let styles = Self.styles(chars, headword: headword, target: target, hit: hit)
        let readings = pinyin.flatMap { $0.count == chars.count ? $0 : nil }
        let fit = Self.fit(chars, styles: styles, words: words, hit: hit, pinyin: readings,
                           width: width > 0 ? width : 300, reserve: reserve,
                           base: detailFontSize(19, dynamicTypeSize, pageTextScale))
        let gap = readings == nil ? 0 : fit.size * 0.05
        VStack(alignment: .leading, spacing: readings == nil ? fit.size * 0.32 : fit.size * 0.2) {
            ForEach(Array(fit.lines.enumerated()), id: \.offset) { li, line in
                if li == 0 {
                    HStack(alignment: .hanCenter, spacing: 0) {
                        lineView(line, chars: chars, styles: styles, readings: readings, fit: fit, gap: gap)
                        Spacer(minLength: 8)
                        trailing()
                    }
                } else {
                    lineView(line, chars: chars, styles: styles, readings: readings, fit: fit, gap: gap)
                }
            }
            if fit.lines.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    trailing()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
    }

    private func lineView(_ line: [Int], chars: [String], styles: [Style], readings: [String?]?, fit: Fit, gap: CGFloat) -> some View {
        HStack(alignment: .hanCenter, spacing: gap) {
            ForEach(line, id: \.self) { i in
                unit(chars[i], style: styles[i], reading: readings?[i] ?? nil, hasReadings: readings != nil,
                     width: fit.unitWidths[i], size: fit.size)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.map { chars[$0] }.joined())
    }

    @ViewBuilder
    private func unit(_ char: String, style: Style, reading: String?, hasReadings: Bool, width: CGFloat, size: CGFloat) -> some View {
        let text = Text(verbatim: char)
            .font(.system(size: size, weight: style.bold ? .bold : .regular))
            .foregroundStyle(style.color)
            .lineLimit(1)
            .fixedSize()
        if hasReadings {
            VStack(spacing: 0) {
                // The reading line keeps its height over punctuation, so every character stands on one baseline.
                Text(verbatim: reading ?? " ")
                    .font(.system(size: max(9, size * 0.36), weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .fixedSize()
                text
            }
            .frame(width: width)
            .alignmentGuide(.hanCenter) { d in d[.bottom] - size * 0.6 }
        } else {
            text.alignmentGuide(.hanCenter) { d in d[VerticalAlignment.center] }
        }
    }

    /// Each character's colour and weight: the chunk's run in its parts' colours (the word blue, glue black, the others
    /// by their part of speech), the headword elsewhere in blue, everything else the text colour.
    private static func styles(_ chars: [String], headword: String, target: String, hit: ChunkRules.ExampleHit?) -> [Style] {
        var out = Array(repeating: Style(color: Theme.foreground, bold: false), count: chars.count)
        for i in SentenceRuby.marked(chars, headword: headword) where i < out.count {
            out[i] = Style(color: ChunkKind.noun.ink, bold: true)
        }
        if let hit {
            for k in 0..<hit.length where hit.start + k < out.count && k < hit.parts.count {
                let part = hit.parts[k]
                let color: Color = switch ChunkRules.role(part, headword: headword, target: target) {
                case .head: ChunkKind.noun.ink
                case .frame: Theme.foreground
                case .partner: ChunkKind(pos: part.pos).ink
                }
                out[hit.start + k] = Style(color: color, bold: true)
            }
        }
        return out
    }

    /// The size and the lines: from 19 pt down 1 pt at a time until the sentence takes at most two lines, never under
    /// 16 pt on screen (or the base itself when the base is already smaller). The widths are measured with the same
    /// system font the characters are drawn in.
    private static func fit(_ chars: [String], styles: [Style], words: [String], hit: ChunkRules.ExampleHit?,
                            pinyin: [String?]?, width: CGFloat, reserve: CGFloat, base: CGFloat) -> Fit {
        let span = hit.map { $0.start..<($0.start + $0.length) }
        let groups = ChunkRules.exampleGroups(chars, words: words, span: span)
        let floor = min(base, smallest)
        var sizes: [CGFloat] = []
        var s = base
        while s > floor + 0.001 {
            sizes.append(s)
            s -= 1
        }
        sizes.append(floor)
        var last = Fit(size: floor, lines: [], unitWidths: [])
        for size in sizes {
            let gap = pinyin == nil ? 0 : size * 0.05
            let units = chars.indices.map { i -> CGFloat in
                let w = measure(chars[i], size: size, weight: styles[i].bold ? .bold : .regular)
                guard let p = pinyin?[i] ?? nil else { return w }
                return max(w, measure(p, size: max(9, size * 0.36), weight: .medium))
            }
            let groupWidths = groups.map { g in Double(g.map { units[$0] }.reduce(0, +) + gap * CGFloat(max(0, g.count - 1))) }
            // 2 pt to spare on every line: the drawn glyphs can be a hair wider than measured.
            let rest = Double(max(40, width - 2))
            let first = Double(max(40, width - reserve - 2))
            let lineGroups = ChunkRules.lines(widths: groupWidths, gap: Double(gap), first: first, rest: rest)
            let lines = lineGroups.map { ls in ls.flatMap { groups[$0] } }
            last = Fit(size: size, lines: lines, unitWidths: units)
            if lines.count <= 2 { return last }
        }
        return last
    }

    private static func measure(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

// MARK: - Taiwan memo (§7)

/// The Taiwan memo as a ruled notebook page (§7): 15 pt with every line 1.95 × the size apart, a faint line under
/// each, one sentence per paragraph and an empty line between two — no red margin, no marks. A UILabel holds the line
/// height exactly (SwiftUI's Text lets a Han or kana fallback font make a line taller, so the rules would drift).
struct RuledMemo: View {
    let text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pageTextScale) private var pageTextScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let size = detailFontSize(15, dynamicTypeSize, pageTextScale)
        let lineHeight = (size * 1.95).rounded()
        let paragraphs = Sentences.split(text).joined(separator: "\n\n")
        RuledLabel(text: paragraphs, size: size, lineHeight: lineHeight)
            .background(alignment: .top) {
                Canvas { context, canvasSize in
                    let rule = colorScheme == .dark ? Color(white: 0.95, opacity: 0.16) : Color(red: 11 / 255, green: 18 / 255, blue: 26 / 255, opacity: 0.13)
                    let thickness = 1 / max(1, displayScale)
                    var y = lineHeight
                    while y <= canvasSize.height + 0.5 {
                        context.fill(Path(CGRect(x: 0, y: y - thickness, width: canvasSize.width, height: thickness)), with: .color(rule))
                        y += lineHeight
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

/// A UILabel with a fixed line height (min = max), sized to the width SwiftUI gives it.
private struct RuledLabel: UIViewRepresentable {
    let text: String
    let size: CGFloat
    let lineHeight: CGFloat

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributed
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let lines = max(1, (fit.height / lineHeight).rounded())
        return CGSize(width: width, height: lines * lineHeight)
    }

    private var attributed: NSAttributedString {
        let font = UIFont.systemFont(ofSize: size)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakStrategy = .standard
        // The glyphs sit a little above the rule, as handwriting on a ruled page.
        let lift = max(0, (lineHeight - font.lineHeight) / 2 - 1)
        // Theme.foreground at 90 %, as a UIKit colour that follows light / dark by itself.
        let ink = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xF2 / 255, green: 0xF6 / 255, blue: 0xF8 / 255, alpha: 0.9)
                : UIColor(red: 0x0B / 255, green: 0x12 / 255, blue: 0x1A / 255, alpha: 0.9)
        }
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
            .baselineOffset: lift,
        ])
    }
}

// MARK: - Real usage links (§8)

/// The look of one link's 32 pt icon.
enum UsageLinkIcon {
    case youtube, youglish, dcard, threads, google, moe, generic(String)

    @ViewBuilder var view: some View {
        switch self {
        case .youtube:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(hex: 0xE5E5E5), lineWidth: 1))
                .overlay(Image("LogoYouTube").resizable().scaledToFit().frame(width: 24, height: 24))
        case .youglish:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0xE8F0FE))
                .overlay(Image(systemName: "play.circle").font(.system(size: 19, weight: .semibold)).foregroundStyle(Color(hex: 0x1A73E8)))
        case .dcard:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0x006AA6))
                .overlay(Text(verbatim: "D").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white))
        case .threads:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black)
                .overlay(Image("LogoThreads").resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(.white).frame(width: 19, height: 19))
        case .google:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(hex: 0xE5E5E5), lineWidth: 1))
                .overlay(Image("LogoGoogle").resizable().scaledToFit().frame(width: 20, height: 20))
        case .moe:
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0x7A1F2B))
                .overlay(Image(systemName: "book").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
        case .generic(let emoji):
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card)
                .overlay(Text(verbatim: emoji).font(.system(size: 18)))
        }
    }
}

/// One link of 「実際の使われ方」.
struct UsageLink: Identifiable {
    let icon: UsageLinkIcon
    let label: String
    let url: String
    var id: String { label }
}

/// 「実際の使われ方」 in two columns (§8): each link a grey tile with its service's icon and its name (two lines at most).
struct UsageLinkGrid: View {
    let links: [UsageLink]
    @Environment(\.openURL) private var openURL

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(links) { link in
                Button {
                    if let url = URL(string: link.url) { openURL(url) }
                } label: {
                    HStack(spacing: 10) {
                        link.icon.view.frame(width: 32, height: 32)
                        Text(link.label)
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(Theme.foreground)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(Theme.secondary, in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    .contentShape(.rect)
                }
                .buttonStyle(PressableStyle(scale: 0.97))
                .accessibilityHint(L("ブラウザで開く"))
            }
        }
    }
}

// MARK: - Jump chips (§0)

/// The chips under the top bar that take the page to a section (only the sections shown).
struct SectionJumpBar: View {
    let sections: [CardSection]
    let target: String
    let jump: (CardSection) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sections) { s in
                    Button {
                        Haptics.selection()
                        jump(s)
                    } label: {
                        Text(s.shortTitle(for: target))
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                    .accessibilityLabel(s.title(for: target))
                }
            }
            .padding(.horizontal, 16)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                     .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("項目へ移る"))
    }
}

// MARK: - First swap hint (§3)

/// The black bubble under the first dashed word, the first time the app shows one (not per word): what the dashed
/// frame means, and OK. Gone for good after OK or a tap on a dashed word.
struct SwapCoachMark: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(L("点線の枠の語は、押すとほかの語に入れ替えられます"))
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Theme.card)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Text(L("OK"))
                    .scaledFont(size: 13, weight: .bold)
                    .foregroundStyle(Theme.card)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.card.opacity(0.18), in: .rect(cornerRadius: 7, style: .continuous))
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(PressableStyle(scale: 0.95))
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(Theme.foreground, in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
