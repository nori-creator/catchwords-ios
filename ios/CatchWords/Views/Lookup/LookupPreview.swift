#if DEBUG
import SwiftUI
import UIKit

/// しらべる as CI photographs it (`-uiPreview lookup…`, .github/workflows/ios-check.yml): the first screen with a few
/// recent searches, a search's answer, and one entry. The answer is the same search (傘) written for each reader.
enum LookupPreviewData {
    static let query: String = L("傘")

    private struct Texts {
        let umbrella: String, parasol: String, folding: String
        let umbrellaSenses: [String]
        let nuanceUmbrella: String, nuanceParasol: String, nuanceFolding: String
        let rain: String, umbrellaChar: String, sun: String, fold: String, stack: String
        let whyUmbrella: String, whyParasol: String, whyFolding: String
        let translation: String
    }

    private static var texts: Texts {
        switch L10n.lang {
        case "en":
            return Texts(umbrella: "umbrella", parasol: "parasol", folding: "folding umbrella",
                         umbrellaSenses: ["rain umbrella"],
                         nuanceUmbrella: "The usual word. 陽傘 is for the sun.",
                         nuanceParasol: "For sun only. Say 雨傘 on rainy days.",
                         nuanceFolding: "A compact one that folds. 雨傘 is any umbrella.",
                         rain: "rain", umbrellaChar: "umbrella", sun: "sun", fold: "fold", stack: "pile up",
                         whyUmbrella: "An umbrella against the rain.",
                         whyParasol: "An umbrella against the sun.",
                         whyFolding: "An umbrella that folds up in layers.",
                         translation: "It's raining outside — don't forget your umbrella.")
        case "zh-TW":
            return Texts(umbrella: "雨傘", parasol: "陽傘", folding: "折疊傘",
                         umbrellaSenses: ["擋雨的傘"],
                         nuanceUmbrella: "最常用的說法。遮陽用的是陽傘。",
                         nuanceParasol: "只用來遮陽。下雨天說雨傘。",
                         nuanceFolding: "可以折小的傘。雨傘泛指所有傘。",
                         rain: "雨", umbrellaChar: "傘", sun: "太陽", fold: "折", stack: "疊",
                         whyUmbrella: "擋雨用的傘。",
                         whyParasol: "擋太陽用的傘。",
                         whyFolding: "可以一層層折起來的傘。",
                         translation: "外面在下雨，記得帶雨傘。")
        default:
            return Texts(umbrella: "傘", parasol: "日傘", folding: "折りたたみ傘",
                         umbrellaSenses: ["雨がさ"],
                         nuanceUmbrella: "ふつうの傘はこれ。日よけ用は陽傘。",
                         nuanceParasol: "日よけ専用。雨の日は雨傘と言う。",
                         nuanceFolding: "小さくたためる傘。雨傘は傘全般。",
                         rain: "あめ", umbrellaChar: "かさ", sun: "日・太陽", fold: "折る", stack: "重ねる",
                         whyUmbrella: "雨をよける傘だから雨傘。",
                         whyParasol: "日ざしをよける傘だから陽傘。",
                         whyFolding: "折り重ねてたためる傘だから折疊傘。",
                         translation: "外は雨だから、傘を忘れずに。")
        }
    }

    static var entries: [LookupEntry] {
        let t = texts
        return [
            LookupEntry(headword: "雨傘", pinyin: "yǔ sǎn", zhuyin: "ㄩˇ ㄙㄢˇ", gloss: t.umbrella, senses: t.umbrellaSenses,  // l10n-ignore (learning-language sample)
                        nuance: t.nuanceUmbrella,
                        chars: [LookupChar(char: "雨", pinyin: "yǔ", meaning: t.rain), LookupChar(char: "傘", pinyin: "sǎn", meaning: t.umbrellaChar)],  // l10n-ignore
                        why: t.whyUmbrella, example: "外面下雨，記得帶雨傘。", exampleTranslation: t.translation,  // l10n-ignore
                        imageQuery: "umbrella", categoryKey: "daily"),
            LookupEntry(headword: "陽傘", pinyin: "yáng sǎn", zhuyin: "ㄧㄤˊ ㄙㄢˇ", gloss: t.parasol, nuance: t.nuanceParasol,  // l10n-ignore
                        chars: [LookupChar(char: "陽", pinyin: "yáng", meaning: t.sun), LookupChar(char: "傘", pinyin: "sǎn", meaning: t.umbrellaChar)],  // l10n-ignore
                        why: t.whyParasol, imageQuery: "parasol", categoryKey: "daily"),
            LookupEntry(headword: "折疊傘", pinyin: "zhé dié sǎn", zhuyin: "ㄓㄜˊ ㄉㄧㄝˊ ㄙㄢˇ", gloss: t.folding, nuance: t.nuanceFolding,  // l10n-ignore
                        chars: [LookupChar(char: "折", pinyin: "zhé", meaning: t.fold), LookupChar(char: "疊", pinyin: "dié", meaning: t.stack),  // l10n-ignore
                                LookupChar(char: "傘", pinyin: "sǎn", meaning: t.umbrellaChar)],  // l10n-ignore
                        why: t.whyFolding, imageQuery: "folding umbrella", categoryKey: "daily"),
        ]
    }

    static var result: LookupResult { LookupResult(query: query, mode: "display", entries: entries) }

    /// The pictures without the network: drawn here (an umbrella on soft colours), handed to the image search.
    @MainActor static func seedPictures() {
        let palette: [(UIColor, UIColor, String)] = [
            (UIColor(red: 0.83, green: 0.92, blue: 1, alpha: 1), UIColor(red: 0.55, green: 0.75, blue: 0.98, alpha: 1), "umbrella.fill"),
            (UIColor(red: 1, green: 0.93, blue: 0.82, alpha: 1), UIColor(red: 0.98, green: 0.76, blue: 0.5, alpha: 1), "sun.max.fill"),
            (UIColor(red: 0.9, green: 0.95, blue: 0.9, alpha: 1), UIColor(red: 0.6, green: 0.82, blue: 0.66, alpha: 1), "cloud.rain.fill"),
        ]
        var shots: [WebImageCandidate] = []
        for (i, p) in palette.enumerated() {
            let size = CGSize(width: 800, height: 600)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                let colors = [p.0.cgColor, p.1.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                }
                let config = UIImage.SymbolConfiguration(pointSize: 260, weight: .regular)
                if let sym = UIImage(systemName: p.2, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    sym.draw(in: CGRect(x: (size.width - sym.size.width) / 2, y: (size.height - sym.size.height) / 2,
                                        width: sym.size.width, height: sym.size.height))
                }
            }
            guard let png = img.pngData() else { continue }
            let url = "data:image/png;base64,\(png.base64EncodedString())"
            let json = #"{"url":"\#(url)","thumb":null,"source":"preview","credit":{"name":"CatchWords \#(i + 1)","link":null}}"#
            if let c = try? JSONDecoder().decode(WebImageCandidate.self, from: Data(json.utf8)) { shots.append(c) }
        }
        for e in entries { WebImages.seed(headword: e.headword, meaning: e.gloss, candidates: shots) }
        // The example's readings (pinyin over each character when 発音表記 is pinyin).
        let chars = Array("外面下雨，記得帶雨傘。").map(String.init)  // l10n-ignore
        let pinyin = ["wài", "miàn", "xià", "yǔ", nil, "jì", "de", "dài", "yǔ", "sǎn", nil]
        let zhuyin = ["ㄨㄞˋ", "ㄇㄧㄢˋ", "ㄒㄧㄚˋ", "ㄩˇ", nil, "ㄐㄧˋ", "˙ㄉㄜ", "ㄉㄞˋ", "ㄩˇ", "ㄙㄢˇ", nil]
        let units = chars.indices.map { SentenceUnit(char: chars[$0], pinyin: pinyin[$0], zhuyin: zhuyin[$0]) }
        SentenceReadings.shared.seed("外面下雨，記得帶雨傘。", units: units)  // l10n-ignore
    }
}

/// The search screen in a state (`-uiPreview lookup` / `lookup-results`).
struct LookupSearchPreview: View {
    var answered: Bool

    var body: some View {
        LookupSearchView(onOpenWord: { _ in },
                         preset: answered ? (LookupPreviewData.query, LookupPreviewData.result) : nil)
            .onAppear {
                LookupPreviewData.seedPictures()
                if !answered {
                    let s = LookupService.shared
                    s.loadRecents()
                    for q in ["yusan", "芒果", "捷運"].reversed() { s.remember(q) }  // l10n-ignore (learning-language samples)
                }
            }
    }
}

/// One entry (`-uiPreview lookup-entry`).
struct LookupEntryPreview: View {
    @State private var ready = false

    var body: some View {
        NavigationStack {
            if ready {
                LookupEntryView(entry: LookupPreviewData.entries[0], siblings: LookupPreviewData.entries, onOpenWord: { _ in })
            }
        }
        .onAppear {
            LookupPreviewData.seedPictures()
            ready = true
        }
    }
}
#endif
