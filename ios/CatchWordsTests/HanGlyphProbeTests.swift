import XCTest
import SwiftUI
import UIKit
import CoreText

/// Probe (not a product test): which way of marking Chinese text makes Han characters take the Taiwan (PingFang TC)
/// shapes on a device whose first language is Japanese. Run with `-testLanguage ja -testRegion JP`.
@MainActor
final class HanGlyphProbeTests: XCTestCase {
    private let sample = "雨骨直角"
    private let size: CGFloat = 60

    /// The ink of an image, cropped to its bounding box and scaled to 96×96 grey levels (so two fonts' different
    /// line metrics do not count as a difference).
    private func ink(_ image: UIImage?) -> [UInt8]? {
        guard let cg = image?.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4] < 128 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX, let crop = ctx.makeImage()?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { return nil }
        let n = 96
        var out = [UInt8](repeating: 0, count: n * n)
        guard let small = CGContext(data: &out, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        small.interpolationQuality = .high
        small.draw(crop, in: CGRect(x: 0, y: 0, width: n, height: n))
        return out
    }

    private func diff(_ a: [UInt8]?, _ b: [UInt8]?) -> Double {
        guard let a, let b, a.count == b.count else { return .nan }
        return Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
    }

    private func render<V: View>(_ v: V) -> UIImage? {
        let r = ImageRenderer(content: v.foregroundStyle(.black).padding(4).background(Color.white))
        r.scale = 2
        return r.uiImage
    }

    private func renderLabel(_ s: NSAttributedString) -> UIImage? {
        let l = UILabel()
        l.attributedText = s
        l.sizeToFit()
        let f = UIGraphicsImageRendererFormat(); f.scale = 2
        return UIGraphicsImageRenderer(bounds: l.bounds.insetBy(dx: -4, dy: -4), format: f).image { ctx in
            UIColor.white.setFill(); ctx.fill(l.bounds.insetBy(dx: -4, dy: -4)); l.drawHierarchy(in: l.bounds, afterScreenUpdates: true)
        }
    }

    func test_whichMarkingGivesTaiwanShapes() {
        print("PROBE preferredLanguages=\(Locale.preferredLanguages)")
        let tc = ink(render(Text(sample).font(.custom("PingFangTC-Regular", size: size))))
        let jp = ink(render(Text(sample).font(.custom("HiraginoSans-W3", size: size))))
        let sc = ink(render(Text(sample).font(.custom("PingFangSC-Regular", size: size))))
        let zh = Locale.Language(identifier: "zh-Hant-TW")
        var attr = AttributedString(sample)
        attr.languageIdentifier = "zh-Hant-TW"
        let ns = NSMutableAttributedString(string: sample, attributes: [.font: UIFont.systemFont(ofSize: size)])
        let nsLang = NSMutableAttributedString(attributedString: ns)
        nsLang.addAttribute(NSAttributedString.Key(rawValue: kCTLanguageAttributeName as String), value: "zh-Hant-TW",
                            range: NSRange(location: 0, length: nsLang.length))
        let cases: [(String, [UInt8]?)] = [
            ("plain Text .system", ink(render(Text(sample).font(.system(size: size))))),
            ("Text.typesettingLanguage(zh-Hant-TW)", ink(render(Text(sample).font(.system(size: size)).typesettingLanguage(zh)))),
            ("View.typesettingLanguage env on parent", ink(render(VStack { Text(sample).font(.system(size: size)) }.typesettingLanguage(zh)))),
            ("environment locale zh-Hant-TW", ink(render(Text(sample).font(.system(size: size)).environment(\.locale, Locale(identifier: "zh_Hant_TW"))))),
            ("AttributedString.languageIdentifier", ink(render(Text(attr).font(.system(size: size))))),
            ("rounded design + typesettingLanguage", ink(render(Text(sample).font(.system(size: size, weight: .bold, design: .rounded)).typesettingLanguage(zh)))),
            ("UILabel plain", ink(renderLabel(ns))),
            ("UILabel NSLanguage zh-Hant-TW", ink(renderLabel(nsLang))),
        ]
        for (name, img) in cases {
            let dTC = diff(img, tc), dJP = diff(img, jp), dSC = diff(img, sc)
            let best = [("TC", dTC), ("JP", dJP), ("SC", dSC)].min { $0.1 < $1.1 }!.0
            print(String(format: "PROBE %@: TC %.1f JP %.1f SC %.1f → %@", name, dTC, dJP, dSC, best))
        }
        print(String(format: "PROBE reference TC-vs-JP %.1f, TC-vs-SC %.1f", diff(tc, jp), diff(tc, sc)))
        // Pass always: this test only reports.
    }
}
