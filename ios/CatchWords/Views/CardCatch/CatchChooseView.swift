import SwiftUI

/// Choosing the way to say it (concept film v6 "D", `dGet` before the choice): the photo melts into the app's page,
/// the thing lifts out of the photo as a sticker to the top of the page and floats there, and under it the header
/// (NEW · its 図鑑 number and category, 「覚える言い方を選ぶ」, what is in the photo) and a white card with each way to
/// say it. A choice is marked in blue (the others fade), the card folds away and the sticker glides on to the GET
/// moment — drawn by the same `CatchStageScene`, so the next screen takes over without a seam. A thing with one way to
/// say it gets no card: its sticker lifts out and goes straight on. × goes back to the tags.
struct CatchChooseOverlay: View {
    /// The ways to say it (the everyday one first); one = no card.
    let words: [Candidate]
    /// The thing's name in the reader's language.
    let thing: String
    /// 「No.001 · 飲み物」, nil when the 図鑑's catalog does not know the thing.
    let dexLabel: String?
    let cut: UIImage?
    let fallback: UIImage?
    let palette: StagePalette
    /// The thing's place in the photo (global).
    let start: CGRect?
    /// The tap on the tag (C) and the choice (P), on `CCClock`.
    let tappedAt: Double
    let chosenAt: Double?
    let chosen: Int?
    let closingAt: Double?
    let calm: Bool
    let onChoose: (Int) -> Void
    let onClose: () -> Void

    private let ink = Color(hex: 0x0B121A)
    private let muted = Color(hex: 0x5C646F)
    private let line = Color(hex: 0xE0E5EB)

    private var hasCard: Bool { words.count > 1 }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let size = geo.size
                let o = geo.frame(in: .global).origin
                TimelineView(.animation) { _ in
                    let now = CCClock.now
                    let tD = now - tappedAt
                    let hold = hasCard ? Film6.handoff : Film6.handoffSingle
                    let tc = chosenAt.map { min(now - $0, hold) }
                    let page = calm ? Film6.clamp(tD / 0.2) : Film6.inOutCubic(Film6.seg(tD, 0.05, 0.6))
                    let closing = closingAt.map { Film6.seg(now - $0, 0, 0.3) } ?? 0
                    ZStack(alignment: .topLeading) {
                        CatchStageScene(size: size, cut: cut, fallback: fallback, palette: palette,
                                        start: start.map { $0.offsetBy(dx: -o.x, dy: -o.y) },
                                        sinceTap: calm ? 99 : tD, sinceChoice: tc, live: now, page: page, calm: calm)
                        // Taps beside the card go nowhere (the photo's words under it are put away).
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: size.width, height: size.height)
                        if hasCard {
                            chooser(now: now, tD: tD, size: size)
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .opacity(1 - closing)
                }
            }
            .ignoresSafeArea()

            if hasCard, chosenAt == nil, closingAt == nil {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(muted)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.85), in: Circle())
                                .overlay(Circle().stroke(line, lineWidth: 1))
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                        .accessibilityLabel(L("閉じる"))
                        .accessibilityIdentifier("variant.close")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .environment(\.colorScheme, .light)
        .animation(.easeOut(duration: 0.2), value: chosenAt == nil && closingAt == nil)
    }

    // MARK: The header and the card

    private func chooser(now: Double, tD: Double, size: CGSize) -> some View {
        let W = size.width, H = size.height, k = W / 1080
        let sinceP = chosenAt.map { now - $0 } ?? -1
        let headIn = calm ? Film6.clamp(tD / 0.2) : Film6.outCubic(Film6.seg(tD, 0.45, 0.7))
        let headOut = chosenAt == nil ? 0 : Film6.inOutCubic(Film6.seg(sinceP, 0.02, 0.16))
        let cardIn = calm ? Film6.clamp(tD / 0.2) : Film6.outCubic(Film6.seg(tD, 0.5, 0.82))
        let fold = chosenAt == nil ? 0 : Film6.inOutCubic(Film6.seg(sinceP, 0.22, 0.5))
        let footIn = calm ? Film6.clamp(tD / 0.2) : Film6.outCubic(Film6.seg(tD, 0.9, 1.1))
        let maxCard = max(160, H - Film6.y(1150, H) - 96)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let dexLabel {
                    CatchDexChip(label: dexLabel, scale: W / 393)
                        .padding(.bottom, 46 * k)
                } else {
                    Color.clear.frame(height: 98 * k)
                }
                Text(L("覚える言い方を選ぶ"))
                    .font(.system(size: 50 * k, weight: .heavy))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(L("写っている物：\(thing)"))
                    .font(.system(size: 30 * k, weight: .medium))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 12 * k)
            }
            .padding(.leading, 24 * k)
            .opacity(headIn * (1 - headOut))
            .offset(y: CGFloat(1 - headIn) * 30 * k)
            .padding(.bottom, 40 * k)

            ViewThatFits(in: .vertical) {
                rows(now: now, tD: tD, k: k)
                ScrollView { rows(now: now, tD: tD, k: k) }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: maxCard)
            .background(Color.white, in: .rect(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(line, lineWidth: 1))
            .shadow(color: .rgba(15, 40, 80, 0.08), radius: 18, y: 5)
            .opacity(cardIn)
            .offset(y: CGFloat(1 - cardIn) * 40 * k)

            Text(L("選ぶと、そのことばで図鑑に入ります"))
                .font(.system(size: 30 * k, weight: .medium))
                .foregroundStyle(muted)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 40 * k)
                .opacity(footIn * (1 - headOut))
        }
        .padding(.horizontal, 40 * k)
        .padding(.top, Film6.y(900, H))
        .frame(width: W, alignment: .topLeading)
        .opacity(1 - fold)
        .offset(y: CGFloat(fold) * 60 * k)
        .allowsHitTesting(chosenAt == nil && closingAt == nil)
    }

    private func rows(now: Double, tD: Double, k: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, c in
                let ri = calm ? Film6.clamp(tD / 0.2) : Film6.outCubic(Film6.seg(tD, 0.58 + 0.07 * Double(i), 0.9 + 0.07 * Double(i)))
                row(i, c, now: now, k: k)
                    .opacity(ri)
                    .offset(y: CGFloat(1 - ri) * 18 * k)
                if i < words.count - 1 {
                    Rectangle()
                        .fill(line)
                        .frame(height: 1)
                        .padding(.horizontal, 30 * k)
                        .opacity(ri)
                }
            }
        }
    }

    /// One way to say it (the picker's row: what kind of word, its reading, meaning and how it differs) with its
    /// voice; once chosen, a blue outline and a blue check.
    private func row(_ i: Int, _ c: Candidate, now: Double, k: CGFloat) -> some View {
        let sinceP = chosenAt.map { now - $0 } ?? -1
        let isPick = chosen == i
        let sel = isPick ? Film6.seg(sinceP, 0.06, 0.26) : 0
        let press = isPick ? Film6.seg(sinceP, 0, 0.06) * (1 - Film6.seg(sinceP, 0.12, 0.24)) : 0
        let others = chosen != nil && !isPick ? Film6.seg(sinceP, 0.06, 0.26) : 0
        return HStack(spacing: 8) {
            Button { onChoose(i) } label: {
                content(c, first: i == 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.985))
            .accessibilityIdentifier("variant.\(i)")
            ZStack {
                PronounceCircle(text: c.headword, size: 30, light: true)
                    .opacity(1 - min(1, sel * 2))
                    .allowsHitTesting(sel == 0)
                if sel > 0 {
                    Circle()
                        .fill(Theme.primary)
                        .frame(width: 26, height: 26)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                        .scaleEffect(CGFloat(Film6.outBack(Film6.clamp(sel * 1.2), 2.2)))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44)
        }
        .padding(.leading, 30 * k)
        .padding(.trailing, 18 * k)
        .padding(.vertical, 26 * k)
        .background {
            if sel > 0 {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.rgba(0, 131, 255, 0.08))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.primary, lineWidth: 1.5))
                    .padding(.horizontal, 8 * k)
                    .padding(.vertical, 6 * k)
                    .opacity(sel)
            }
        }
        .scaleEffect(CGFloat(1 - press * 0.025))
        .opacity(1 - others * 0.55)
    }

    private func content(_ c: Candidate, first: Bool) -> some View {
        let meaning = ReaderLanguage.gloss(ReaderLanguage.shown(c.meaningJa))
        let note = ReaderLanguage.shown(c.distinction, hanOnlyOk: false)
        return VStack(alignment: .leading, spacing: 4) {
            Text(CandidatePickerView.registerLabel(c.register, first: first))
                .scaledFont(size: 10.5, weight: .semibold)
                .foregroundStyle(first ? Theme.primaryInk : muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(first ? Theme.primary.opacity(0.12) : Color(hex: 0xEEF1F5), in: Capsule())
            ZhuyinWordView(headword: c.headword, zhuyin: c.zhuyin, size: first ? 30 : 23, weight: first ? .semibold : .medium,
                           color: ink, readingColor: muted, pinyin: c.pinyin)
            if !meaning.isEmpty {
                Text(meaning)
                    .scaledFont(size: 12.5)
                    .foregroundStyle(muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !note.isEmpty {
                Text(note)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Color(hex: 0x0066CC))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
