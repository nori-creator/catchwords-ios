import SwiftUI

/// 語源・部首 drawn as boxes (`EtymologyDiagram`, owner 2026-10-15, as on the web):
/// [曖 / 日+愛 / 日がかげる] + [昧 / 日+未 / 夜明け前] = [曖昧 / はっきり見えない], the word's box highlighted.
/// A character that cannot be taken apart is one box with what it is made of and a line about it; a loanword, a
/// transliteration or a brand name is the word's box with where its sound came from. Boxes wrap onto the next line on
/// a narrow screen (a word of five characters too). VoiceOver reads it as one sentence.
struct EtymologyDiagramView: View {
    /// Already checked to draw (`EtymologyDiagram.drawable`).
    let diagram: EtymologyDiagram

    @ScaledMetric(relativeTo: .body) private var boxWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .body) private var boxHeight: CGFloat = 112

    private enum Item: Hashable {
        case part(Int), plus(Int), equals, result
    }

    var body: some View {
        Group {
            switch diagram.kind {
            case .compound: compound
            case .single: single
            case .phonetic: phonetic
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(diagram.spoken)
        .accessibilityIdentifier("etymology.diagram")
    }

    // MARK: Kinds

    private var compound: some View {
        var items: [Item] = []
        for i in diagram.parts.indices {
            if i > 0 { items.append(.plus(i)) }
            items.append(.part(i))
        }
        items += [.equals, .result]
        return FlowRow(spacing: 6) {
            ForEach(items, id: \.self) { item in
                switch item {
                case .part(let i): partBox(diagram.parts[i])
                case .plus: sign("+")
                case .equals: sign("=")
                case .result: resultBox
                }
            }
        }
    }

    private var single: some View {
        HStack(alignment: .center, spacing: 14) {
            if let p = diagram.parts.first { partBox(p) }
            let line = [diagram.meaning, diagram.note].filter { !$0.isEmpty }
            if !line.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(line.enumerated()), id: \.offset) { i, t in
                        Text(Sentences.wrappable(t))
                            .scaledFont(size: i == 0 && !diagram.meaning.isEmpty ? 16 : 14,
                                        weight: i == 0 && !diagram.meaning.isEmpty ? .semibold : .regular)
                            .foregroundStyle(i == 0 && !diagram.meaning.isEmpty ? Theme.foreground : Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var phonetic: some View {
        HStack(alignment: .center, spacing: 14) {
            resultBox
            VStack(alignment: .leading, spacing: 6) {
                Text(L("音訳"))
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Theme.primaryInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Theme.primary.opacity(0.1), in: Capsule())
                if !diagram.note.isEmpty {
                    Text(Sentences.wrappable(diagram.note))  // lang-ok: the word's extras, scrubbed for the reader (ReaderLanguage.scrub)
                        .scaledFont(size: 15)
                        .foregroundStyle(Theme.foreground.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                } else if !diagram.source.isEmpty {
                    Text(L("「\(diagram.source)」の音から"))
                        .scaledFont(size: 15)
                        .foregroundStyle(Theme.foreground.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Boxes

    private func partBox(_ p: EtymologyDiagram.Part) -> some View {
        VStack(spacing: 4) {
            Text(p.char)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Theme.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !p.components.isEmpty {
                Text(p.components.joined(separator: "+"))
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.primaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if !p.meaning.isEmpty {
                Text(Sentences.wrappable(p.meaning))  // lang-ok: the word's extras, scrubbed for the reader (ReaderLanguage.scrub)
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(width: boxWidth)
        .frame(minHeight: boxHeight)
        .background(Theme.secondary, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    /// The word's box, in the accent colour.
    private var resultBox: some View {
        VStack(spacing: 4) {
            Text(diagram.word)
                .font(.system(size: diagram.word.count > 3 ? 24 : 30, weight: .heavy))
                .foregroundStyle(Theme.primaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !diagram.meaning.isEmpty, diagram.kind != .single {
                Text(Sentences.wrappable(diagram.meaning))  // lang-ok: the word's extras, scrubbed for the reader (ReaderLanguage.scrub)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(Theme.foreground.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(minWidth: boxWidth)
        .frame(maxWidth: boxWidth * 1.8)
        .frame(minHeight: boxHeight)
        .background(Theme.primary.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.primary, lineWidth: 1.5))
    }

    private func sign(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Theme.muted)
            .frame(width: 18, height: boxHeight)
    }
}
