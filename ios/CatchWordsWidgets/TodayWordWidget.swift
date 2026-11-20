import WidgetKit
import SwiftUI

/// 「今日の単語」 — a word from the learner's own collection, with its photo.
struct TodayWordWidget: Widget {
    let kind = "TodayWordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CatchWordsProvider()) { entry in
            TodayWordView(entry: entry)
                .containerBackground(for: .widget) { Color.white }
        }
        .configurationDisplayName(WidgetText.t(.todayName, WidgetText.currentLang))
        .description(WidgetText.t(.todayDesc, WidgetText.currentLang))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWordView: View {
    let entry: CatchWordsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let word = entry.word {
                if family == .systemMedium { medium(word) } else { small(word) }
            } else {
                empty
            }
        }
        .widgetURL(entry.word.map { DeepLink.word($0.stickerId) } ?? DeepLink.review)
    }

    private var title: some View {
        Text(WidgetText.t(.todayName, entry.lang))
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(WidgetStyle.accent)
            .lineLimit(1)
    }

    private func headword(_ word: WidgetWord, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let reading = word.reading {
                Text(reading)
                    .font(.system(size: max(10, size * 0.38), weight: .medium))
                    .foregroundStyle(WidgetStyle.subInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(word.headword)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .taiwanGlyphs(for: word.headword)
        }
    }

    private func small(_ word: WidgetWord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                WordThumb(image: entry.image, isCutout: word.isCutout)
                    .frame(width: 58, height: 58)
                Spacer(minLength: 0)
                title
            }
            Spacer(minLength: 0)
            headword(word, size: 26)
            Text(word.meaning)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WidgetStyle.subInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ word: WidgetWord) -> some View {
        HStack(spacing: 14) {
            WordThumb(image: entry.image, isCutout: word.isCutout)
                .frame(maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 6) {
                title
                Spacer(minLength: 0)
                headword(word, size: 34)
                Text(word.meaning)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WidgetStyle.subInk)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if entry.due > 0 {
                    Text(WidgetText.t(.remaining, entry.lang, entry.due))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(WidgetStyle.accent, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            Spacer(minLength: 0)
            Image(systemName: "camera.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(WidgetStyle.accent)
            Text(WidgetText.t(.emptyWords, entry.lang))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetStyle.ink)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
