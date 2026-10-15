import UIKit
import ImageIO
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

nonisolated enum ImageTools {
    /// Same budget as the web (1600px / q0.9) so payloads stay far below the 8MB cap.
    static func jpegForUpload(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.88) -> Data? {
        jpegUpload(image, maxSide: maxSide, quality: quality)?.data
    }

    /// `jpegForUpload` off the main thread (a full-size photo takes 100–200 ms to resize and encode).
    static func jpegForUploadInBackground(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.88) async -> Data? {
        await Task.detached(priority: .userInitiated) { jpegForUpload(image, maxSide: maxSide, quality: quality) }.value
    }

    /// A canvas for pictures that are kept, sent or shown in a list: 8 bits per channel, standard range (sRGB). The
    /// default (`preferredRange` .automatic) draws into an extended-range, 16-bit float canvas on an iPad with an EDR
    /// display whenever the photo is wide colour or HDR: the camera photo then took twice the memory, and a cut-out PNG
    /// came out 16-bit and several times larger — on 2026-10-15 nothing of one photo (a strawberry cake) ever reached
    /// storage in five tries, while photos taken minutes before and after went up.
    static func standardFormat(scale: CGFloat = 1, opaque: Bool = false) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = opaque
        format.preferredRange = .standard
        return format
    }

    static func resized(_ image: UIImage, maxSide: CGFloat, opaque: Bool = false) -> UIImage {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
        return UIGraphicsImageRenderer(size: target, format: standardFormat(opaque: opaque)).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Uploads (8-bit, within a budget)

    /// The most a cut-out PNG may weigh. Larger uploads dropped more often on the way (owner 2026-10-15: 花束's 2.15 MB
    /// cut-out failed about ten times, the strawberry cake's 5 of 5; cut-outs of 0.6–1.6 MB went up at once).
    static let cutoutBudget = 1_200_000
    /// The sides a cut-out is drawn at, largest first, until it fits `cutoutBudget` (its transparency kept).
    static let cutoutSides: [CGFloat] = [1024, 900, 768, 640, 512]
    /// A photo JPEG (1600 px, q 0.88) is 0.3–1 MB; only a picture far past that is made smaller.
    static let photoCap = 3_000_000

    /// One picture ready to upload, and what the developer log needs to know about it.
    nonisolated struct UploadData: Sendable {
        let data: Data
        let width: Int
        let height: Int
        /// Bits per channel of the picture it was drawn from (16: a wide-colour / HDR source, drawn into 8 bits here).
        let sourceBits: Int
        /// Drawn smaller (or at a lower JPEG quality) to fit its budget.
        let shrunk: Bool

        var summary: String { "\(data.count)B \(width)x\(height) from \(sourceBits)bpc\(shrunk ? " shrunk" : "")" }
    }

    /// A photo as an upload: an 8-bit sRGB JPEG at most `maxSide` px (as before: 1600 px, q 0.88). Only one past `cap`
    /// gets a lower quality, then a smaller size (never below 480 px).
    static func jpegUpload(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.88, cap: Int = photoCap) -> UploadData? {
        let bits = image.cgImage?.bitsPerComponent ?? 8
        var side = maxSide
        var q = quality
        var shrunk = false
        while true {
            let flat = resized(image, maxSide: side, opaque: true)
            guard let data = flat.jpegData(compressionQuality: q) else { return nil }
            if data.count <= cap || side <= 480 {
                return UploadData(data: data, width: Int(flat.size.width), height: Int(flat.size.height), sourceBits: bits, shrunk: shrunk)
            }
            shrunk = true
            if q > 0.72 { q = 0.72 } else { side = (side * 0.8).rounded(.down) }
        }
    }

    /// A cut-out as an upload: an 8-bit sRGB PNG with its transparency, at most `maxSide` px (and never above 1024 px),
    /// drawn smaller (900, 768 … 512 px) until it fits `budget`.
    static func pngUpload(_ image: UIImage, maxSide: CGFloat = 1024, budget: Int = cutoutBudget) -> UploadData? {
        let bits = image.cgImage?.bitsPerComponent ?? 8
        let first = min(maxSide, cutoutSides[0])
        let sides = [first] + cutoutSides.filter { $0 < first }
        var last: UploadData?
        for (i, side) in sides.enumerated() {
            let flat = resized(image, maxSide: side)
            guard let data = flat.pngData() else { return last }
            let up = UploadData(data: data, width: Int(flat.size.width), height: Int(flat.size.height), sourceBits: bits, shrunk: i > 0)
            if data.count <= budget { return up }
            last = up
        }
        // Still past the budget at the smallest side: sent as it is (the retries carry it).
        return last
    }

    /// Decodes an image file at most `maxSide` px on its long side, already upright (EXIF orientation
    /// applied), without ever holding the full-resolution bitmap. A 48 MP library photo decoded with
    /// `UIImage(data:)` and then redrawn costs ~200 MB and a long main-thread stall.
    static func downsampled(data: Data, maxSide: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsampled(source: src, maxSide: maxSide)
    }

    static func downsampled(url: URL, maxSide: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsampled(source: src, maxSide: maxSide)
    }

    private static func downsampled(source: CGImageSource, maxSide: CGFloat) -> UIImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxSide)),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// A cut-out with (almost) nothing in it: a speck (both sides tiny — a thin pen is long on one side) or nearly
    /// all transparent. Measured on a 32×32 copy, so it is cheap enough to run on every picture drawn.
    nonisolated static func isNearlyBlank(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        if max(cg.width, cg.height) < 48 { return true }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        // The context draws into the array's own memory, so it lives only inside this closure.
        let drawn = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        var opaque = 0
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] > 25 { opaque += 1 }
        return Double(opaque) / Double(side * side) < 0.015
    }

    /// `downsampled(data:maxSide:)` off the main thread (photos picked from the library).
    static func downsampledInBackground(_ data: Data, maxSide: CGFloat = 2400) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { downsampled(data: data, maxSide: maxSide) }.value
    }
}

/// iOS subject lifting — the same engine as long-pressing a subject in Photos
/// (`VNGenerateForegroundInstanceMaskRequest`). Runs on-device, free, offline.
/// Note: Vision's foreground model does not run on the Simulator; a real iPhone is required.
nonisolated enum CutoutService {
    /// Lifts the subject nearest to `point` (0–1 normalized, top-left origin) or all subjects.
    /// Returns a transparent PNG cropped to the subject, or nil when nothing could be lifted.
    static func liftSubject(from image: UIImage, near point: CGPoint? = nil) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            lift(image: image, point: point, cropped: true)?.cropped
        }.value
    }

    /// Both versions of the lift: `cropped` is the sticker that gets saved; `full` is the same
    /// subject on a transparent canvas the size of `photo`, so it lines up exactly with the photo
    /// on screen — the cut-out animation fades the background away while the subject stays put.
    struct Lift: @unchecked Sendable {
        let cropped: UIImage
        let full: UIImage
        let photo: UIImage
    }

    static func liftDetailed(from image: UIImage, near point: CGPoint? = nil) async -> Lift? {
        await Task.detached(priority: .userInitiated) {
            lift(image: image, point: point, cropped: false)
        }.value
    }

    private static func lift(image source: UIImage, point: CGPoint?, cropped wantCropOnly: Bool) -> Lift? {
        let image = ImageTools.resized(source, maxSide: 1600)
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }

        var instances = result.allInstances
        if let point, let hit = nearestInstance(in: result.instanceMask, to: point), instances.contains(hit) {
            instances = IndexSet(integer: hit)
        }

        let context = CIContext()
        func render(_ crop: Bool) -> UIImage? {
            guard let masked = try? result.generateMaskedImage(
                ofInstances: instances,
                from: handler,
                croppedToInstancesExtent: crop
            ) else { return nil }
            let ci = CIImage(cvPixelBuffer: masked)
            guard let out = context.createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: out)
        }
        guard let croppedImage = render(true) else { return nil }
        // A speck of the photo is not a subject (the 2026-10-11 cut-outs of 優酪乳 / 拿鐵 came out 8–15 KB and the dex
        // squares stayed blank): nothing lifted, so the photo is used.
        if let c = croppedImage.cgImage, let s = image.cgImage,
           Double(c.width * c.height) < 0.004 * Double(s.width * s.height) || ImageTools.isNearlyBlank(croppedImage) {
            return nil
        }
        if wantCropOnly { return Lift(cropped: croppedImage, full: croppedImage, photo: image) }
        guard let fullImage = render(false) else { return nil }
        return Lift(cropped: croppedImage, full: fullImage, photo: image)
    }
}

extension CutoutService {
    /// A selfie cut down to its people and what they hold (owner 2026-10-14: 「自撮りに写る人物とその単語の対象に絞って
    /// 切り抜いてほしい」): the foreground instances that are people, or that touch them (the drink in the hand, the thing
    /// held up beside the face). Shelves and walls behind them are not foreground; a thing standing apart is dropped.
    /// nil when there is no person (the selfie is then shown as it is) or on the Simulator.
    nonisolated static func liftPeople(from image: UIImage) async -> UIImage? {
        await Task.detached(priority: .utility) { liftPeopleNow(image) }.value
    }

    nonisolated private static func liftPeopleNow(_ source: UIImage) -> UIImage? {
        let image = ImageTools.resized(source, maxSide: 1600)
        guard let cg = image.cgImage else { return nil }
        let foreground = VNGenerateForegroundInstanceMaskRequest()
        let people = VNGeneratePersonSegmentationRequest()
        people.qualityLevel = .balanced
        people.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do { try handler.perform([foreground, people]) } catch { return nil }
        guard let result = foreground.results?.first, !result.allInstances.isEmpty,
              let personMask = people.results?.first?.pixelBuffer else { return nil }
        let keep = instancesWithPeople(labels: result.instanceMask, person: personMask)
            .intersection(result.allInstances)
        guard !keep.isEmpty,
              let masked = try? result.generateMaskedImage(ofInstances: keep, from: handler, croppedToInstancesExtent: true)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: masked)
        guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: out)
    }

    /// The instance labels that are people (≥ 30 % of the instance lies on the person mask) or that touch them
    /// (≥ 35 % lies within a short reach of a person — what is held in front of or beside the body).
    nonisolated static func instancesWithPeople(labels: CVPixelBuffer, person: CVPixelBuffer) -> IndexSet {
        CVPixelBufferLockBaseAddress(labels, .readOnly)
        CVPixelBufferLockBaseAddress(person, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(labels, .readOnly)
            CVPixelBufferUnlockBaseAddress(person, .readOnly)
        }
        let lw = CVPixelBufferGetWidth(labels), lh = CVPixelBufferGetHeight(labels)
        let pw = CVPixelBufferGetWidth(person), ph = CVPixelBufferGetHeight(person)
        guard lw > 0, lh > 0, pw > 0, ph > 0,
              let lbase = CVPixelBufferGetBaseAddress(labels), let pbase = CVPixelBufferGetBaseAddress(person) else { return [] }
        let lrow = CVPixelBufferGetBytesPerRow(labels), prow = CVPixelBufferGetBytesPerRow(person)

        // The person mask on a coarse grid (at most 160 cells a side), then widened by ~4 % of the picture.
        let scale = 160.0 / Double(max(pw, ph))
        let gw = max(1, Int(Double(pw) * min(1, scale))), gh = max(1, Int(Double(ph) * min(1, scale)))
        var onPerson = [Bool](repeating: false, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw {
                let px = min(pw - 1, (gx * pw + pw / (2 * gw)) / gw), py = min(ph - 1, (gy * ph + ph / (2 * gh)) / gh)
                onPerson[gy * gw + gx] = pbase.advanced(by: py * prow + px).load(as: UInt8.self) > 127
            }
        }
        guard onPerson.contains(true) else { return [] }
        let reach = max(1, Int(Double(max(gw, gh)) * 0.04))
        var across = [Bool](repeating: false, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw where onPerson[gy * gw + gx] {
                for x in max(0, gx - reach)...min(gw - 1, gx + reach) { across[gy * gw + x] = true }
            }
        }
        var near = [Bool](repeating: false, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw where across[gy * gw + gx] {
                for y in max(0, gy - reach)...min(gh - 1, gy + reach) { near[y * gw + gx] = true }
            }
        }

        var total: [Int: Int] = [:], inside: [Int: Int] = [:], touching: [Int: Int] = [:]
        let step = max(1, max(lw, lh) / 400)
        for y in stride(from: 0, to: lh, by: step) {
            let gy = min(gh - 1, y * gh / lh)
            for x in stride(from: 0, to: lw, by: step) {
                let l = Int(lbase.advanced(by: y * lrow + x).load(as: UInt8.self))
                guard l != 0 else { continue }
                let g = gy * gw + min(gw - 1, x * gw / lw)
                total[l, default: 0] += 1
                if onPerson[g] { inside[l, default: 0] += 1 }
                if near[g] { touching[l, default: 0] += 1 }
            }
        }
        var keep = IndexSet()
        for (l, n) in total where keepsWithPeople(total: n, onPerson: inside[l] ?? 0, nearPerson: touching[l] ?? 0) {
            keep.insert(l)
        }
        return keep
    }

    /// Whether a foreground instance of a selfie stays with its people (counts of its sampled pixels): a person (≥ 30 %
    /// on the person mask), or a thing against them. A thing held up to the camera is large and touches the person only
    /// along one side — the hand (owner 2026-10-15: 冰火菠蘿油 held up in a selfie was dropped, so the album sticker
    /// showed the person without the word's thing). So a thing is kept when most of it is within reach of a person,
    /// or when a real part of it is (≥ 4 % of it, at least a few samples); a thing standing apart is still dropped.
    nonisolated static func keepsWithPeople(total n: Int, onPerson: Int, nearPerson: Int) -> Bool {
        guard n > 0 else { return false }
        if Double(onPerson) / Double(n) >= 0.3 { return true }
        if Double(nearPerson) / Double(n) >= 0.35 { return true }
        return nearPerson >= max(6, n / 25)
    }

    /// The instance label under `point` (0–1, top-left origin) in Vision's label mask, or the nearest
    /// instance within ~8% of the image when the point lands just beside a thin or small subject.
    nonisolated static func nearestInstance(in mask: CVPixelBuffer, to point: CGPoint) -> Int? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let w = CVPixelBufferGetWidth(mask)
        let h = CVPixelBufferGetHeight(mask)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let row = CVPixelBufferGetBytesPerRow(mask)
        let x = min(w - 1, max(0, Int(point.x * CGFloat(w))))
        let y = min(h - 1, max(0, Int(point.y * CGFloat(h))))
        func label(_ px: Int, _ py: Int) -> Int { Int(base.advanced(by: py * row + px).load(as: UInt8.self)) }
        var hit = label(x, y)
        // The AI's point can land just beside a thin or small subject: take the nearest
        // instance within ~8% of the image instead of lifting every subject in the photo.
        if hit == 0 {
            let reach = max(4, Int(Double(max(w, h)) * 0.08))
            let step = max(1, reach / 16)
            var best = Int.max
            for py in stride(from: max(0, y - reach), through: min(h - 1, y + reach), by: step) {
                for px in stride(from: max(0, x - reach), through: min(w - 1, x + reach), by: step) {
                    let l = label(px, py)
                    guard l != 0 else { continue }
                    let d = (px - x) * (px - x) + (py - y) * (py - y)
                    if d < best { best = d; hit = l }
                }
            }
        }
        return hit == 0 ? nil : hit
    }

    /// Every instance label within ~8% of `point` (0–1, top-left origin), nearest first, with its squared
    /// distance in mask pixels (0 = the point lies on it). Card catch hands each object its own instance from
    /// this list (`CatchObject.assignInstances`), so two objects never share one cut-out and box.
    nonisolated static func rankedInstances(in mask: CVPixelBuffer, to point: CGPoint) -> [CatchObject.InstanceHit] {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let w = CVPixelBufferGetWidth(mask)
        let h = CVPixelBufferGetHeight(mask)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(mask) else { return [] }
        let row = CVPixelBufferGetBytesPerRow(mask)
        let x = min(w - 1, max(0, Int(point.x * CGFloat(w))))
        let y = min(h - 1, max(0, Int(point.y * CGFloat(h))))
        func label(_ px: Int, _ py: Int) -> Int { Int(base.advanced(by: py * row + px).load(as: UInt8.self)) }
        var best: [Int: Int] = [:]
        let under = label(x, y)
        if under != 0 { best[under] = 0 }
        let reach = max(4, Int(Double(max(w, h)) * 0.08))
        let step = max(1, reach / 16)
        for py in stride(from: max(0, y - reach), through: min(h - 1, y + reach), by: step) {
            for px in stride(from: max(0, x - reach), through: min(w - 1, x + reach), by: step) {
                let l = label(px, py)
                guard l != 0 else { continue }
                let d = (px - x) * (px - x) + (py - y) * (py - y)
                if d < best[l, default: Int.max] { best[l] = d }
            }
        }
        return best.map { CatchObject.InstanceHit(label: $0.key, distance: $0.value) }
            .sorted { $0.distance != $1.distance ? $0.distance < $1.distance : $0.label < $1.label }
    }

    /// Card catch: ONE foreground-instance request per photo, reused for every object in it.
    /// Nil when Vision finds no subject (or on the Simulator, where the model does not run).
    nonisolated static func instanceMasks(from source: UIImage) async -> InstanceMasks? {
        await Task.detached(priority: .userInitiated) { () -> InstanceMasks? in
            let image = ImageTools.resized(source, maxSide: 1600)
            guard let cg = image.cgImage else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
            do { try handler.perform([request]) } catch { return nil }
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            return InstanceMasks(observation: result, handler: handler, photo: cg)
        }.value
    }
}

/// The result of `CutoutService.instanceMasks`: hit-test a point, and cut one instance out with its alpha
/// bounding box (normalized to the photo, top-left origin) so the cut-out and its box always match.
nonisolated final class InstanceMasks: @unchecked Sendable {
    nonisolated struct Cut: @unchecked Sendable {
        /// The subject on transparency, cropped exactly to `box`.
        let image: UIImage
        /// The opaque pixels' bounding box, 0–1 of the photo.
        let box: CGRect
    }

    private let observation: VNInstanceMaskObservation
    private let handler: VNImageRequestHandler
    /// The photo the masks were made from (for `crop`).
    private let photo: CGImage?
    private let lock = NSLock()
    private var cache: [Int: Cut] = [:]
    private var unionCache: [String: Cut] = [:]
    /// The label mask copy (`labelMask`), made once for the coverage counts.
    private let maskLock = NSLock()
    private var maskCache: (mask: [UInt8], width: Int, height: Int)?
    /// The tags' places (`anchors`), measured once. A lock of their own, so they never wait for a cut-out to render.
    private let anchorLock = NSLock()
    private var anchorCache: [Int: CGPoint]?

    init(observation: VNInstanceMaskObservation, handler: VNImageRequestHandler, photo: CGImage? = nil) {
        self.observation = observation
        self.handler = handler
        self.photo = photo
    }

    /// How much of each instance lies inside `box` (0–1 of the photo), each instance's whole size, and the box's size,
    /// counted on the label mask copy (`CutCoverage.decide`). Heavy the first time: call off the main thread.
    func coverage(of box: CGRect) -> (inBox: [Int: Int], totals: [Int: Int], area: Int) {
        maskLock.lock()
        if maskCache == nil { maskCache = labelMask() }
        let copy = maskCache
        maskLock.unlock()
        guard let m = copy, m.width > 0, m.height > 0 else { return ([:], [:], 0) }
        let x0 = max(0, min(m.width, Int((box.minX * CGFloat(m.width)).rounded(.down))))
        let x1 = max(0, min(m.width, Int((box.maxX * CGFloat(m.width)).rounded(.up))))
        let y0 = max(0, min(m.height, Int((box.minY * CGFloat(m.height)).rounded(.down))))
        let y1 = max(0, min(m.height, Int((box.maxY * CGFloat(m.height)).rounded(.up))))
        var totals: [Int: Int] = [:], inBox: [Int: Int] = [:]
        for y in 0..<m.height {
            let inRows = y >= y0 && y < y1
            for x in 0..<m.width {
                let l = Int(m.mask[y * m.width + x])
                guard l != 0 else { continue }
                totals[l, default: 0] += 1
                if inRows, x >= x0, x < x1 { inBox[l, default: 0] += 1 }
            }
        }
        return (inBox, totals, max(0, x1 - x0) * max(0, y1 - y0))
    }

    /// Every instance at least `minArea` of the photo, the largest first (counted on the label mask copy): the things
    /// the AI gave no place take these, one each (`CatchObject.build`). Heavy the first time: call off the main thread.
    func instancesBySize(minArea: Double = 0.012) -> [Int] {
        maskLock.lock()
        if maskCache == nil { maskCache = labelMask() }
        let copy = maskCache
        maskLock.unlock()
        guard let m = copy, m.width > 0, m.height > 0 else { return [] }
        var counts = [Int](repeating: 0, count: 256)
        for v in m.mask where v != 0 { counts[Int(v)] += 1 }
        let total = Double(m.width * m.height)
        return (1..<256).filter { Double(counts[$0]) / total >= minArea }
            .sorted { counts[$0] != counts[$1] ? counts[$0] > counts[$1] : $0 < $1 }
    }

    /// Several instances cut out together (the person and the thing they hold). Heavy: call off the main thread.
    func cut(instances labels: IndexSet) -> Cut? {
        if labels.count == 1, let only = labels.first { return cut(instance: only) }
        let key = labels.map { String($0) }.joined(separator: ",")
        lock.lock()
        defer { lock.unlock() }
        if let c = unionCache[key] { return c }
        guard let masked = try? observation.generateMaskedImage(ofInstances: labels, from: handler,
                                                               croppedToInstancesExtent: false) else { return nil }
        let ci = CIImage(cvPixelBuffer: masked)
        guard let full = CIContext().createCGImage(ci, from: ci.extent),
              let px = Self.alphaBounds(full),
              let cropped = full.cropping(to: px) else { return nil }
        let w = CGFloat(full.width), h = CGFloat(full.height)
        let c = Cut(image: UIImage(cgImage: cropped),
                    box: CGRect(x: px.minX / w, y: px.minY / h, width: px.width / w, height: px.height / h))
        unionCache[key] = c
        return c
    }

    /// The photo round `box` (0–1, widened by 6% each side): the sticker when no instance covers the thing.
    func crop(_ box: CGRect) -> Cut? {
        guard let photo else { return nil }
        let w = CGFloat(photo.width), h = CGFloat(photo.height)
        let wide = box.insetBy(dx: -box.width * 0.06, dy: -box.height * 0.06)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !wide.isNull, wide.width > 0.01, wide.height > 0.01 else { return nil }
        let px = CGRect(x: wide.minX * w, y: wide.minY * h, width: wide.width * w, height: wide.height * h).integral
        guard let cropped = photo.cropping(to: px) else { return nil }
        return Cut(image: UIImage(cgImage: cropped), box: wide)
    }

    /// The foreground instances near `point`, nearest first (see `CutoutService.rankedInstances`).
    func instances(near point: CGPoint) -> [CatchObject.InstanceHit] {
        let all = observation.allInstances
        return CutoutService.rankedInstances(in: observation.instanceMask, to: point).filter { all.contains($0.label) }
    }

    /// The outlines of the largest foreground instances, largest first, for the catch scan (`CatchOutlineTracer`,
    /// on a copy of Vision's label mask at most 512 px on its long side — the outline is smoothed anyway).
    /// Heavy: call off the main thread.
    func outlines(limit: Int = CatchObject.maxObjects) -> [CatchOutline] {
        guard let m = labelMask() else { return [] }
        return CatchOutlineTracer.outlines(mask: m.mask, width: m.width, height: m.height, limit: limit)
    }

    /// Where each instance's name tag sits (`CatchAnchor`: deep inside its mask, near the middle of the thing), by
    /// label, 0–1 of the photo, top-left origin — read from the same copy of the label mask as the outlines, so a tag
    /// lands inside its own outline. Measured once for every instance, then cached; heavy the first time (reads the
    /// whole mask): call off the main thread (the capture warms it while the AI is still naming the things).
    func anchors() -> [Int: CGPoint] {
        anchorLock.lock()
        defer { anchorLock.unlock() }
        if let cached = anchorCache { return cached }
        let found = labelMask().map { CatchAnchor.anchors(mask: $0.mask, width: $0.width, height: $0.height) } ?? [:]
        anchorCache = found
        return found
    }

    /// A copy of Vision's label mask at most `maxSide` px on its long side (every `step`-th pixel), with only this
    /// observation's own instances kept (0 = background).
    private func labelMask(maxSide: Int = 512) -> (mask: [UInt8], width: Int, height: Int)? {
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let step = max(1, Int((Double(max(w, h)) / Double(maxSide)).rounded(.up)))
        let mw = (w + step - 1) / step, mh = (h + step - 1) / step
        var known = [Bool](repeating: false, count: 256)
        for label in observation.allInstances where label > 0 && label < 256 { known[label] = true }
        var mask = [UInt8](repeating: 0, count: mw * mh)
        for y in 0..<mh {
            let line = base.advanced(by: y * step * row)
            for x in 0..<mw {
                let v = line.load(fromByteOffset: x * step, as: UInt8.self)
                if v != 0, known[Int(v)] { mask[y * mw + x] = v }
            }
        }
        return (mask: mask, width: mw, height: mh)
    }

    /// Renders the cut-outs of the first `limit` instances into the cache. Called off the main thread while the AI
    /// is still naming the things, so the words screen only picks finished cut-outs (they used to be rendered after
    /// the server answered, on the way to the words — owner 2026-10-10: 「ただ待たされる時間は苦痛」).
    func prerenderCuts(limit: Int = 6) {
        for label in observation.allInstances.prefix(limit) { _ = cut(instance: label) }
    }

    /// Heavy (renders a full-size mask): call off the main thread.
    func cut(instance label: Int) -> Cut? {
        lock.lock()
        defer { lock.unlock() }
        if let c = cache[label] { return c }
        guard let masked = try? observation.generateMaskedImage(ofInstances: IndexSet(integer: label), from: handler,
                                                               croppedToInstancesExtent: false) else { return nil }
        let ci = CIImage(cvPixelBuffer: masked)
        guard let full = CIContext().createCGImage(ci, from: ci.extent),
              let px = Self.alphaBounds(full),
              let cropped = full.cropping(to: px) else { return nil }
        let w = CGFloat(full.width), h = CGFloat(full.height)
        let c = Cut(image: UIImage(cgImage: cropped),
                    box: CGRect(x: px.minX / w, y: px.minY / h, width: px.width / w, height: px.height / h))
        cache[label] = c
        return c
    }

    /// Pixel rect (top-left origin) of every pixel whose alpha is above a faint threshold.
    private static func alphaBounds(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let rowStart = y * w * 4
            for x in 0..<w where bytes[rowStart + x * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

extension UIImage {
    /// Camera images carry EXIF orientation; bake it so Vision coordinates match what the user sees.
    /// Drawn in 8 bits, standard range (`ImageTools.standardFormat`): a 16-bit extended-range copy of a 12 MP photo
    /// took ~100 MB and made every upload made from it 16-bit.
    nonisolated func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        return UIGraphicsImageRenderer(size: size, format: ImageTools.standardFormat(scale: scale)).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
