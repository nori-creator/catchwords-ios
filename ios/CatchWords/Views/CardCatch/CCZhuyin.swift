import SwiftUI

/// The prototype's `zyHTML` / `.zw .zu .zcol`: zhuyin in a small column to the right of each character —
/// 0.36em, weight 400, 52% of the character's colour, `margin: 0 .3em 0 .1em` (none after the last
/// character), the tone mark in a second grid column at the top of the last row, a neutral-tone dot on top.
/// With 設定 › 発音表記 = ピンイン (the prototype's `S.read === "py"`) or a reading that does not pair
/// one syllable per character, the word is shown alone, exactly like `zyHTML`. Japanese and English
/// learners get the app's own reading view (the prototype only knew Taiwan Mandarin).
struct CCZhuyinWord: View {
    let headword: String
    let zhuyin: String
    var pinyin: String = ""
    let size: CGFloat
    var weight: Font.Weight = .medium
    var color: Color = Color(hex: 0x0B121A)

    @AppStorage("reading.pref") private var readingPref: String = "zhuyin"

    /// The prototype's `zyOn(w)`: zhuyin is drawn (so the pinyin line is not).
    static func zyOn(headword: String, zhuyin: String, readingPref: String) -> Bool {
        isMandarin && readingPref != "pinyin" && ZhuyinLayout.pair(headword, zhuyin) != nil
    }

    static var isMandarin: Bool { NativeAPI.targetLanguage != "en" && NativeAPI.targetLanguage != "ja" }

    var body: some View {
        if !Self.isMandarin {
            ZhuyinWordView(headword: headword, zhuyin: zhuyin, size: size, weight: weight, color: color,
                           readingColor: color.opacity(0.52), pinyin: pinyin)
        } else if readingPref != "pinyin", let units = ZhuyinLayout.pair(headword, zhuyin) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(units.enumerated()), id: \.offset) { i, u in
                    HStack(alignment: .center, spacing: 0) {
                        Text(u.char).font(.system(size: size, weight: weight))
                        if u.hasReading { column(u, last: i == units.count - 1) }
                    }
                }
            }
            .foregroundStyle(color)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headword)
        } else if readingPref == "pinyin", let units = PinyinLayout.pair(headword, pinyin: pinyin, zhuyin: zhuyin) {
            // Pinyin over each character (owner 2026-10-14), where the prototype showed the word alone.
            PinyinRubyLine(units: units, size: size, weight: weight, color: color, readingColor: color.opacity(0.52))
        } else {
            Text(headword)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .fixedSize()
        }
    }

    /// `.zcol`: font .36em, line-height 1.02, column-gap .1em; `.zn` line-height .7; `.zt` .9em, top of the last row.
    private func column(_ u: ZhuyinUnit, last: Bool) -> some View {
        let zs = size * 0.36
        let row = zs * 1.02
        return HStack(alignment: .bottom, spacing: zs * 0.1) {
            VStack(spacing: 0) {
                if u.neutral {
                    Text("˙").font(.system(size: zs, weight: .regular)).frame(height: zs * 0.7)
                }
                ForEach(Array(u.body.enumerated()), id: \.offset) { _, sym in
                    Text(sym).font(.system(size: zs, weight: .regular)).frame(height: row)
                }
            }
            if u.tone.isEmpty {
                Color.clear.frame(width: 0, height: row)
            } else {
                Text(u.tone)
                    .font(.system(size: zs * 0.9, weight: .regular))
                    .frame(height: row, alignment: .top)
                    .offset(y: -zs * 0.09)
            }
        }
        .foregroundStyle(color.opacity(0.52))
        .padding(.leading, size * 0.036)
        .padding(.trailing, last ? 0 : size * 0.108)
    }
}
