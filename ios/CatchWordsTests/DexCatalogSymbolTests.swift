import XCTest
import UIKit
@testable import CatchWords

/// Every SF Symbol the dex catalog draws as a shadow must exist on the iOS the app runs on (deployment target
/// iOS 18): a missing name would draw nothing. Run on its own by .github/workflows/ios-check.yml.
final class DexCatalogSymbolTests: XCTestCase {
    func testEverySymbolExists() {
        let missing = DexCatalog.allItems.compactMap { item -> String? in
            guard let name = item.symbol else { return nil }
            return UIImage(systemName: name) == nil ? "\(item.id): \(name)" : nil
        }
        XCTAssertTrue(missing.isEmpty, "SF Symbols not found: \(missing.joined(separator: ", "))")
    }

    func testCatalogShape() {
        let cats = DexCatalog.categories
        XCTAssertEqual(cats.count, 20)
        XCTAssertEqual(cats.map(\.no), Array(1...20))
        for c in cats {
            XCTAssertEqual(c.base.count, 5, "category \(c.no)")
            XCTAssertTrue((12...15).contains(c.extra.count), "category \(c.no) has \(c.extra.count) extra items")
        }
        // The base 100 are numbered 001–100 in table order.
        XCTAssertEqual(cats.flatMap(\.base).compactMap(\.baseNo), Array(1...100))
        XCTAssertTrue(cats.flatMap(\.extra).allSatisfy { $0.baseNo == nil })
    }

    func testHeadwordsAreUniquePerLanguage() {
        for lang in ["zh-TW", "en", "ja"] {
            var seen: [String: String] = [:]
            for item in DexCatalog.allItems {
                let k = DexCatalog.norm(item.headword(for: lang), lang: lang)
                XCTAssertNil(seen[k], "\(lang): \(item.id) and \(seen[k] ?? "") share \(k)")
                seen[k] = item.id
            }
        }
        XCTAssertEqual(Set(DexCatalog.allItems.map(\.id)).count, DexCatalog.allItems.count)
    }

    /// The quick katakana → hiragana that replaced ICU's transform in `norm` (it held the main thread for seconds on the
    /// first open of the 図鑑) writes every catalog word and the usual loanwords exactly as the transform did.
    func testKatakanaToHiraganaMatchesTheSystemTransform() {
        let samples = DexCatalog.allItems.map { $0.headword(for: "ja") }
            + ["コーヒー", "ヴァイオリン", "カップ麺", "ティッシュ", "ペットボトル", "ミルクティー", "abc 123", "眼鏡", ""]
        for s in samples {
            let system = s.applyingTransform(.hiraganaToKatakana, reverse: true) ?? s
            XCTAssertEqual(DexCatalog.katakanaToHiragana(s), system, "「\(s)」")
        }
    }

    func testEveryAppCategoryKeyIsMapped() {
        for key in Category.orderedKeys {
            XCTAssertNotNil(DexCatalog.keyToCategory[key], "category key \(key) has no dex category")
        }
    }

    /// The shadow is the thing's shape, not its frame (owner 2026-10-27: the shadows showed as grey rectangles): the
    /// kept bitmap is see-through around the shape and solid inside it, for a symbol and for a drawn art.
    func testShadowBitmapsKeepTheirShape() {
        let items = ["bird", "rabbit", "pigeon"].compactMap { id in DexCatalog.allItems.first { $0.id == id } }
        XCTAssertEqual(items.count, 3)
        for item in items {
            guard let image = DexSilhouette.art(item) ?? DexSilhouette.symbolImage(item), let cg = image.cgImage else {
                XCTFail("\(item.id): no shadow"); continue
            }
            let alphas = Self.alphas(cg)
            XCTAssertEqual(alphas.first ?? 255, 0, "\(item.id): the top-left corner is not clear")
            XCTAssertTrue(alphas.contains { $0 == 0 }, "\(item.id): nothing is clear — a filled rectangle")
            XCTAssertTrue(alphas.contains { $0 > 200 }, "\(item.id): nothing is solid — an empty shadow")
        }
    }

    /// Every pixel's alpha, drawn into a fresh RGBA bitmap (how any renderer reads the image).
    private static func alphas(_ cg: CGImage) -> [UInt8] {
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return stride(from: 3, to: px.count, by: 4).map { px[$0] }
    }
}
