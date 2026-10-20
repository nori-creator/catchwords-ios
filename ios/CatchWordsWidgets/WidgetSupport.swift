import WidgetKit
import SwiftUI
import UIKit

// MARK: - Look

enum WidgetStyle {
    /// The app's blue (#0A7AFF).
    static let accent = Color(red: 10 / 255, green: 122 / 255, blue: 255 / 255)
    static let ink = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let subInk = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let tile = Color(red: 0.94, green: 0.96, blue: 1.0)
}

// MARK: - Text (the widget follows the app's display language, written into the snapshot)

/// The widgets' few sentences, from `Shared/Localization/widget-strings.json` (Japanese key → every other display
/// language, `{1}` for the number), checked by scripts/check_l10n.py like the app's own table.
enum WidgetText {
    enum Key: String {
        case todayName = "今日の単語"
        case todayDesc = "図鑑から毎日ひとつ、単語を表示します。"
        case reviewName = "復習"
        case reviewDesc = "復習するカードの枚数を表示します。"
        case remaining = "あと {1} 枚"
        case allDone = "今日の復習は完了"
        case emptyWords = "写真を撮って単語を集めよう"
        case wordsCaught = "{1} 語"
        case streak = "{1}日連続"
        case reviewing = "復習中"
        case correct = "正解 {1}"
        case liveDone = "復習おつかれさま"
        /// The gallery sample's meaning (雨傘).
        case sampleMeaning = "かさ"
    }

    /// The app's display language; before the app has written anything, the device's language.
    static var currentLang: String {
        if let l = WidgetShared.load()?.lang { return l }
        for id in Locale.preferredLanguages {
            if let l = DisplayLanguages.forDevice(id) { return l.code }
        }
        return DisplayLanguages.fallback
    }

    private static let table: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "widget-strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return [:] }
        return obj
    }()

    static func t(_ key: Key, _ lang: String) -> String {
        if lang == DisplayLanguages.source { return key.rawValue }
        if let v = table[key.rawValue]?[lang], !v.isEmpty { return v }
        return table[key.rawValue]?[DisplayLanguages.fallback] ?? key.rawValue
    }

    /// `{1}` replaced by `n` (a counted noun after 1 made singular, as in the app: "1 words" → "1 word").
    static func t(_ key: Key, _ lang: String, _ n: Int) -> String {
        var out = t(key, lang)
        if n == 1 {
            for (many, one) in DisplayLanguages.find(lang)?.plurals ?? [:] {
                out = out.replacingOccurrences(of: "{1} " + many, with: "{1} " + one)
            }
        }
        return out.replacingOccurrences(of: "{1}", with: "\(n)")
    }
}

// MARK: - Timeline

struct CatchWordsEntry: TimelineEntry {
    let date: Date
    let lang: String
    let word: WidgetWord?
    let image: UIImage?
    let due: Int
    let totalWords: Int
    let streak: Int?
    /// The app has written a snapshot at least once.
    let hasData: Bool

    static func make(at date: Date, snapshot: WidgetSnapshot?) -> CatchWordsEntry {
        let word = snapshot?.word(for: date)
        let image = word?.thumbFile
            .flatMap { WidgetShared.thumbURL($0) }
            .flatMap { UIImage(contentsOfFile: $0.path) }
        return CatchWordsEntry(date: date, lang: snapshot?.lang ?? WidgetText.currentLang, word: word, image: image,
                               due: snapshot?.dueCount(at: date) ?? 0, totalWords: snapshot?.totalWords ?? 0,
                               streak: snapshot?.streak, hasData: snapshot != nil)
    }

    /// Widget gallery / placeholder.
    static func sample(lang: String) -> CatchWordsEntry {
        // The sample word is in the learning language (繁體字（台灣）, the only one offered) whatever the display language:
        // the display language picked "umbrella" as the headword for an English screen. Its meaning is the screen's.
        let word = WidgetWord(day: "", stickerId: "", headword: "雨傘", reading: "ㄩˇ ㄙㄢˇ",  // l10n-ignore (learning-language sample)
                              meaning: WidgetText.t(.sampleMeaning, lang), thumbFile: nil, isCutout: false)
        return CatchWordsEntry(date: Date(), lang: lang, word: word, image: nil, due: 3, totalWords: 42, streak: 5, hasData: true)
    }
}

struct CatchWordsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CatchWordsEntry {
        .sample(lang: WidgetText.currentLang)
    }

    func getSnapshot(in context: Context, completion: @escaping (CatchWordsEntry) -> Void) {
        let snap = WidgetShared.load()
        if context.isPreview && (snap == nil || snap?.words.isEmpty == true) {
            completion(.sample(lang: snap?.lang ?? WidgetText.currentLang))
        } else {
            completion(.make(at: Date(), snapshot: snap))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CatchWordsEntry>) -> Void) {
        let now = Date()
        let snap = WidgetShared.load()
        let cal = Calendar.current
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        // A new entry whenever a card comes due today (the count goes up on its own) and at midnight (new word).
        var dates: Set<Date> = [now, midnight]
        for d in (snap?.upcomingDue ?? []) where d > now && d < midnight {
            dates.insert(d)
            if dates.count >= 40 { break }
        }
        let entries = dates.sorted().map { CatchWordsEntry.make(at: $0, snapshot: snap) }
        completion(Timeline(entries: entries, policy: .after(midnight)))
    }
}

// MARK: - Pieces

/// The word's photo (cropped) or cut-out (drawn whole), on a soft tile when there is none.
struct WordThumb: View {
    let image: UIImage?
    let isCutout: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isCutout || image == nil ? WidgetStyle.tile : .white)
            if let image {
                if isCutout {
                    Image(uiImage: image).resizable().scaledToFit().padding(6)
                } else {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            } else {
                Image(systemName: "camera.macro").font(.system(size: 22, weight: .semibold)).foregroundStyle(WidgetStyle.accent.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A blue progress ring (Live Activity / lock screen).
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(WidgetStyle.accent.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(WidgetStyle.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

enum DeepLink {
    static let review = URL(string: "catchwords://review")!
    static func word(_ id: String) -> URL {
        id.isEmpty ? review : (URL(string: "catchwords://word/\(id)") ?? review)
    }
}
