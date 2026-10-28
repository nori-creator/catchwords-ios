import SwiftUI

/// 「表示する項目と順番」 — the popover under the word page's top-right button (docs/word-detail-design.md §9, 版25), built
/// from the app's own settings parts (`SettingsToggle`, `ChoicePills`): the sections (a blue switch to show or hide,
/// ≡ to drag), 復習 (blur until tapped, and what to blur), and 文字と音 (the page's text size with a sample, the speed
/// of the voice with 「この速さで聞く」). 「既定に戻す」 puts all of it back.
struct SectionsPanel: View {
    let prefs: CardPrefsStore
    /// The word the size sample and 「この速さで聞く」 use (the page's headword and its meaning).
    var sampleWord: String = ""
    var sampleMeaning: String = ""

    @AppStorage("detail.review") private var review: Bool = false
    @AppStorage("detail.reviewHide") private var reviewHide: String = ReviewHide.translation.rawValue
    @AppStorage("detail.textScale") private var textScale: Double = 1
    @AppStorage("detail.speechRate") private var speechRate: Double = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 小 / 標準 / 大 / 特大 (read each time: the display language can change while the app runs).
    static var textScales: [(value: Double, label: String)] {
        [(value: 0.85, label: L("小")), (value: 1, label: L("標準")), (value: 1.15, label: L("大")), (value: 1.3, label: L("特大"))]
    }
    static let speechRates: [Double] = [0.6, 0.8, 1, 1.2]

    /// The panel's height: within 78 % of an iPhone SE's screen, scrolling inside.
    static let height: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    groupTitle(L("項目"), detail: L("スイッチで表示・非表示、≡ を押したまま動かして並べ替え"))
                    card { sectionList }
                    groupTitle(L("復習"))
                    card { reviewSettings }
                    groupTitle(L("文字と音"))
                    card { textAndVoice }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 352, height: Self.height)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(LinearGradient(colors: [Theme.primaryBright, Theme.primaryDeep], startPoint: .top, endPoint: .bottom),
                            in: Circle())
                .shadow(color: Theme.primary.opacity(0.35), radius: 5, y: 3)
                .accessibilityHidden(true)
            Text(L("表示する項目と順番"))
                .scaledFont(size: 16, weight: .heavy)
                .foregroundStyle(Theme.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(L("既定に戻す")) {
                Haptics.selection()
                withAnimation(.snappy) {
                    prefs.reset()
                    review = false
                    reviewHide = ReviewHide.translation.rawValue
                    textScale = 1
                    speechRate = 1
                }
            }
            .scaledFont(size: 13, weight: .bold)
            .foregroundStyle(Theme.primaryInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(minHeight: 44)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func groupTitle(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).scaledFont(size: 13, weight: .bold).foregroundStyle(Theme.muted)
            if let detail {
                Text(detail).scaledFont(size: 11.5, weight: .medium).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: Sections

    /// The rows' height: a 48 pt row and its line.
    private var rowHeight: CGFloat { max(48, AppTypeScale.scaled(48, for: dynamicTypeSize)) }

    private var sectionList: some View {
        List {
            ForEach(prefs.order) { section in
                row(section)
                    .listRowBackground(Theme.card)
                    .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 0))
            }
            .onMove { from, to in
                Haptics.selection()
                prefs.move(from: from, to: to)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .environment(\.editMode, .constant(.active))
        .frame(height: CGFloat(prefs.order.count) * (rowHeight + 1))
    }

    private func row(_ section: CardSection) -> some View {
        let on = prefs.isVisible(section)
        let name = section.title(for: prefs.target)
        return HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(on ? Theme.primary : Theme.muted.opacity(0.45), in: Circle())
                .accessibilityHidden(true)
            Text(name)
                .scaledFont(size: 15, weight: on ? .semibold : .regular)
                .foregroundStyle(on ? Theme.foreground : Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: Binding(get: { on }, set: { v in
                Haptics.selection()
                withAnimation(.snappy) { prefs.setVisible(section, v) }
            })) {
                Text(name)
            }
            .labelsHidden()
            .tint(Theme.primary)
        }
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("タップで切り替え。並べ替えは右の取っ手を使います"))
    }

    // MARK: Review

    private var targetName: String {
        switch prefs.target {
        case "en": L("英語")
        case "ja": L("日本語")
        default: L("台湾華語")
        }
    }

    private var reviewSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsToggle(title: L("復習モード"), detail: L("押すまでぼかし、押すと答えが出る"), isOn: $review)
            Divider().padding(.vertical, 12)
            Text(L("ぼかす所")).scaledFont(size: 15, weight: .bold).foregroundStyle(Theme.foreground).padding(.bottom, 8)
            ChoicePills(options: [(value: ReviewHide.translation.rawValue, label: L("訳")),
                                  (value: ReviewHide.target.rawValue, label: targetName)],
                        selection: $reviewHide)
        }
    }

    // MARK: Text and voice

    private var scaleChoice: Binding<String> {
        Binding(get: { Self.key(textScale) }, set: { v in
            withAnimation(.snappy) { textScale = Double(v) ?? 1 }
        })
    }

    private var rateChoice: Binding<String> {
        Binding(get: { Self.key(speechRate) }, set: { v in speechRate = Double(v) ?? 1 })
    }

    /// A setting's value as the choice it is (0.85 → "0.85", 1 → "1").
    static func key(_ v: Double) -> String { String(format: "%g", v) }

    private var textAndVoice: some View {
        VStack(alignment: .leading, spacing: 0) {
            label(L("文字の大きさ"), note: L("小さいと1画面に多く入る"))
            ChoicePills(options: Self.textScales.map { (value: Self.key($0.value), label: $0.label) }, selection: scaleChoice)
            if !sampleWord.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(sampleWord)
                        .font(.system(size: AppTypeScale.scaled(22, for: dynamicTypeSize) * textScale, weight: .heavy))
                        .foregroundStyle(Theme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !sampleMeaning.isEmpty {
                        Text(sampleMeaning)  // lang-ok: the word's meaning (ReaderLanguage.resolve)
                            .font(.system(size: AppTypeScale.scaled(14, for: dynamicTypeSize) * textScale))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.secondary, in: .rect(cornerRadius: 14, style: .continuous))
                .padding(.top, 10)
                .accessibilityHidden(true)
            }
            Divider().padding(.vertical, 12)
            label(L("発音の速さ"), note: L("長押しはこの 0.7 倍"))
            ChoicePills(options: Self.speechRates.map { (value: Self.key($0), label: String(format: "%.1f×", $0)) }, selection: rateChoice)
            if !sampleWord.isEmpty {
                Button {
                    Haptics.selection()
                    SoundService.shared.speak(sampleWord, rate: speechRate)
                } label: {
                    Label(L("この速さで聞く"), systemImage: "speaker.wave.2")
                        .scaledFont(size: 13.5, weight: .bold)
                        .foregroundStyle(Theme.primaryInk)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Theme.primary.opacity(0.1), in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .padding(.top, 10)
            }
        }
    }

    private func label(_ title: String, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).scaledFont(size: 15, weight: .bold).foregroundStyle(Theme.foreground)
            Spacer(minLength: 4)
            Text(note).scaledFont(size: 12, weight: .medium).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}
