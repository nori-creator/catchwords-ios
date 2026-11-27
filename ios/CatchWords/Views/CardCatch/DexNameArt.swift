import SwiftUI
import UIKit

/// A 図鑑 square's name — the word with its zhuyin beside each character, or its pinyin over each character — drawn once
/// into a picture and kept (owner 2026-11-27: the add to 図鑑 froze; Sentry caught the main thread held 7 s in the
/// 図鑑's scroll to the word's place on the owner's iPad).
///
/// Measured (`MainProfiler`, the landing into a 230-word 図鑑): most of the main thread's time while the page scrolled to
/// the word's place went to SwiftUI resolving the squares' text. Each square's name was a row of views — one per
/// character, one per zhuyin symbol and tone mark (about fifteen for a three-character word), each resolved and laid
/// out, then measured and laid out again to shrink a long word into its column (`DexFitWidth`) — and a scroll builds a
/// whole screen of squares at once. Drawn here with UIKit's text drawing (off the main thread for the words the 図鑑
/// holds: `warm`), the square shows one picture.
///
/// The picture is black with the reading at 52% (`CCZhuyinWord`'s colours) and drawn as a template, so one picture
/// serves light and dark. The layout is `CCZhuyinWord`'s (`.zw .zu .zcol`: the column 0.36 of the character, line 1.02,
/// the tone mark at the top of the last row, the neutral dot on top) and `PinyinRubyLine`'s (pinyin centred over each
/// character, at least 9 pt). The Han characters are set in the Taiwan shapes (`TaiwanGlyphs`).
nonisolated enum DexNameArt {
    struct Key: Hashable, Sendable {
        let headword: String
        let zhuyin: String
        let pinyin: String
        /// 設定 › 発音表記 = ピンイン.
        let pinyinFirst: Bool
        let size: CGFloat
        let scale: CGFloat

        var cacheKey: NSString {
            "\(pinyinFirst ? "py" : "zy")|\(size)|\(scale)|\(headword)|\(zhuyin)|\(pinyin)" as NSString
        }
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 2000
        return c
    }()

    /// The name's picture: kept, or drawn now.
    static func image(_ key: Key) -> UIImage? {
        if let hit = cache.object(forKey: key.cacheKey) { return hit }
        guard let made = draw(key) else { return nil }
        cache.setObject(made, forKey: key.cacheKey)
        return made
    }

    /// Draws the names of these words ahead, off the main thread (the 図鑑's words, as it loads).
    static func warm(_ keys: [Key]) {
        for key in keys where cache.object(forKey: key.cacheKey) == nil {
            if let made = draw(key) { cache.setObject(made, forKey: key.cacheKey) }
        }
    }

    // MARK: Drawing

    private static func draw(_ key: Key) -> UIImage? {
        let word = key.headword.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return nil }
        if key.pinyinFirst, let units = PinyinLayout.pair(word, pinyin: key.pinyin, zhuyin: key.zhuyin) {
            return pinyinArt(units, key: key)
        }
        if !key.pinyinFirst, let units = ZhuyinLayout.pair(word, key.zhuyin) {
            return zhuyinArt(units, key: key)
        }
        return plainArt(word, key: key)
    }

    private static func charAttributes(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: UIColor.black,
         TaiwanGlyphs.languageKey: TaiwanGlyphs.identifier]
    }

    private static func readingAttributes(_ size: CGFloat, weight: UIFont.Weight = .regular) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: UIColor.black.withAlphaComponent(0.52)]
    }

    private static func render(_ size: CGSize, scale: CGFloat, _ body: () -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let canvas = CGSize(width: max(1, size.width.rounded(.up)), height: max(1, size.height.rounded(.up)))
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in body() }
            .withRenderingMode(.alwaysTemplate)
    }

    /// `CCZhuyinWord`: each character, then its zhuyin column to the right (none after a non-Han character).
    private static func zhuyinArt(_ units: [ZhuyinUnit], key: Key) -> UIImage {
        let size = key.size
        let charAttr = charAttributes(size)
        let zs = size * 0.36
        let row = zs * 1.02
        let symAttr = readingAttributes(zs)
        let toneAttr = readingAttributes(zs * 0.9)
        let charFont = UIFont.systemFont(ofSize: size, weight: .heavy)
        let symFont = UIFont.systemFont(ofSize: zs)

        struct Placed {
            let char: NSAttributedString
            let charWidth: CGFloat
            let unit: ZhuyinUnit
            let symbolWidth: CGFloat
            let toneWidth: CGFloat
            let columnHeight: CGFloat
            let width: CGFloat
        }
        var placed: [Placed] = []
        for (i, u) in units.enumerated() {
            let c = NSAttributedString(string: u.char, attributes: charAttr)
            let cw = c.size().width
            guard u.hasReading else {
                placed.append(Placed(char: c, charWidth: cw, unit: u, symbolWidth: 0, toneWidth: 0, columnHeight: 0, width: cw))
                continue
            }
            let marks = (u.neutral ? ["˙"] : []) + u.body
            let sw = marks.map { NSAttributedString(string: $0, attributes: symAttr).size().width }.max() ?? 0
            let tw = u.tone.isEmpty ? 0 : NSAttributedString(string: u.tone, attributes: toneAttr).size().width
            let ch = (u.neutral ? zs * 0.7 : 0) + CGFloat(u.body.count) * row
            let last = i == units.count - 1
            let column = sw + (u.tone.isEmpty ? 0 : zs * 0.1 + tw)
            let w = cw + size * 0.036 + column + (last ? 0 : size * 0.108)
            placed.append(Placed(char: c, charWidth: cw, unit: u, symbolWidth: sw, toneWidth: tw, columnHeight: ch, width: w))
        }
        let height = max(charFont.lineHeight, placed.map(\.columnHeight).max() ?? 0)
        let width = placed.reduce(0) { $0 + $1.width }
        return render(CGSize(width: width, height: height), scale: key.scale) {
            var x: CGFloat = 0
            for p in placed {
                p.char.draw(at: CGPoint(x: x, y: (height - charFont.lineHeight) / 2))
                if p.unit.hasReading {
                    var y = (height - p.columnHeight) / 2
                    let cx = x + p.charWidth + size * 0.036
                    func symbol(_ s: String, rowHeight: CGFloat) {
                        let a = NSAttributedString(string: s, attributes: symAttr)
                        let w = a.size().width
                        a.draw(at: CGPoint(x: cx + (p.symbolWidth - w) / 2, y: y + (rowHeight - symFont.lineHeight) / 2))
                        y += rowHeight
                    }
                    if p.unit.neutral { symbol("˙", rowHeight: zs * 0.7) }
                    for s in p.unit.body { symbol(s, rowHeight: row) }
                    if !p.unit.tone.isEmpty {
                        // Beside the last row, at its top (`.zt`), a little raised.
                        let lastRowTop = (height - p.columnHeight) / 2 + p.columnHeight - row
                        NSAttributedString(string: p.unit.tone, attributes: toneAttr)
                            .draw(at: CGPoint(x: cx + p.symbolWidth + zs * 0.1, y: lastRowTop - zs * 0.09))
                    }
                }
                x += p.width
            }
        }
    }

    /// `PinyinRubyLine`: the pinyin centred over each character, the characters on one line.
    private static func pinyinArt(_ units: [PinyinUnit], key: Key) -> UIImage {
        let size = key.size
        let charAttr = charAttributes(size)
        let readingSize = max(9, size * 0.36)
        let readAttr = readingAttributes(readingSize, weight: .medium)
        let charFont = UIFont.systemFont(ofSize: size, weight: .heavy)
        let readFont = UIFont.systemFont(ofSize: readingSize, weight: .medium)
        let gap = size * 0.05
        let cells = units.map { u -> (NSAttributedString, NSAttributedString, CGFloat) in
            let c = NSAttributedString(string: u.char, attributes: charAttr)
            let r = NSAttributedString(string: u.reading ?? " ", attributes: readAttr)
            return (c, r, max(c.size().width, r.size().width))
        }
        let height = readFont.lineHeight + charFont.lineHeight
        let width = cells.reduce(0) { $0 + $1.2 } + gap * CGFloat(max(0, cells.count - 1))
        return render(CGSize(width: width, height: height), scale: key.scale) {
            var x: CGFloat = 0
            for (c, r, w) in cells {
                r.draw(at: CGPoint(x: x + (w - r.size().width) / 2, y: 0))
                c.draw(at: CGPoint(x: x + (w - c.size().width) / 2, y: readFont.lineHeight))
                x += w + gap
            }
        }
    }

    /// A word whose reading does not pair one syllable per character: the word alone (`CCZhuyinWord`'s last case).
    private static func plainArt(_ word: String, key: Key) -> UIImage {
        let a = NSAttributedString(string: word, attributes: charAttributes(key.size))
        let s = a.size()
        return render(s, scale: key.scale) { a.draw(at: .zero) }
    }
}
