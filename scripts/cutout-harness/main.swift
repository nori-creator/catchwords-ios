// The cut-out harness (docs/cutout-failure-modes.md): the app's own cut-out code — CatchPlan, CutCoverage,
// CatchAnchor, TagPlacement and InstanceMasks, compiled from ios/CatchWords as they are — run with real Vision
// (VNGenerateForegroundInstanceMaskRequest, macOS 14+) on real photos, with server-like boxes next to each photo,
// some of them deliberately wrong (too small, off to one side, missing). For every case it draws the photo with the
// boxes, the cut-out the old plan (OldCatchPlan.swift, before 1.0.1) made and the one the app makes now, measures the
// new one against a reference mask of the thing and fails when a cut-out
//   - covers less than `minCoverage` of the thing,
//   - ends in a straight line where the AI's box crossed the thing (`maxStraight`),
//   - is a rectangle,
//   - takes more than `maxLeak` of another named thing (two things Vision saw as one must still be split).
//
// Build and run (CI: .github/workflows/ios-check.yml, job cutout-harness):
//   swiftc -O ios/CatchWords/Models/CatchPlan.swift ios/CatchWords/Models/CatchGeometry.swift \
//     ios/CatchWords/Models/TagPlacement.swift ios/CatchWords/Services/InstanceMasks.swift \
//     scripts/cutout-harness/OldCatchPlan.swift scripts/cutout-harness/main.swift -o harness
//   ./harness scripts/cutout-harness/cases.json out/
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let minCoverage = 0.85
let maxStraight = 0.35
let maxLeak = 0.12

struct CaseFile: Decodable {
    struct Photo: Decodable {
        let file: String
        let licence: String
        let source: String
    }
    struct Thing: Decodable {
        let name: String
        /// [x, y], 0–1000 of the upright photo (the server's `point`).
        let point: [Double]?
        /// [ymin, xmin, ymax, xmax], 0–1000 (the server's `box_2d`).
        let box_2d: [Double]?
        /// The reference mask of the thing (white = the thing), next to the photo.
        let reference: String?
        /// Measured and asserted (false: only drawn).
        let check: Bool?
        /// "none": Vision has no instance that is this thing alone (see `why`), so the right result is no cut-out; a
        /// cut-out, if one comes, must still pass every check.
        let expect: String?
        let why: String?
    }
    struct Case: Decodable {
        let id: String
        let photo: String
        let what: String
        let things: [Thing]
    }
    let photos: [Photo]
    let cases: [Case]
}

// MARK: Images

func loadUpright(_ url: URL, maxSide: Int = 1600) -> CGImage? {
    // The app draws the camera's photo upright (its EXIF orientation applied) and at most 1600 px before Vision and
    // the upload (`UIImage.normalizedOrientation`, `ImageTools.resized`); ImageIO's thumbnail with its transform does
    // the same here.
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxSide,
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}

func rgba(width: Int, height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Alpha (or grey) of `image` drawn into `rect` of a `width` × `height` canvas (top-left origin), one byte a pixel.
func alpha(of image: CGImage?, in rect: CGRect, width: Int, height: Int, grey: Bool = false) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: width * height)
    guard let image else { return out }
    let ctx = rgba(width: width, height: height)
    // CG's origin is the bottom left: a rect given top-left is flipped.
    ctx.draw(image, in: CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
    guard let data = ctx.data else { return out }
    let row = ctx.bytesPerRow
    let p = data.bindMemory(to: UInt8.self, capacity: row * height)
    for y in 0..<height {
        for x in 0..<width {
            let o = y * row + x * 4
            out[y * width + x] = grey ? p[o] : p[o + 3]
        }
    }
    return out
}

func savePNG(_ image: CGImage, _ url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: The old plan's rendering (before 1.0.1), for the "before" column

func oldClip(_ masks: InstanceMasks, labels: [Int], rect: CGRect) -> InstanceMasks.Cut? {
    guard let full = masks.maskedImage(of: IndexSet(labels)) else { return nil }
    let w = CGFloat(full.width), h = CGFloat(full.height)
    let clip = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard !clip.isNull, clip.width > 0, clip.height > 0 else { return nil }
    let px = CGRect(x: clip.minX * w, y: clip.minY * h, width: clip.width * w, height: clip.height * h).integral
        .intersection(CGRect(x: 0, y: 0, width: w, height: h))
    guard let part = full.cropping(to: px), let inner = InstanceMasks.alphaBounds(part), let cropped = part.cropping(to: inner)
    else { return nil }
    return InstanceMasks.Cut(cg: cropped, box: CGRect(x: (px.minX + inner.minX) / w, y: (px.minY + inner.minY) / h,
                                                      width: inner.width / w, height: inner.height / h))
}

func oldRegionCut(photo: CGImage, box: CGRect) -> InstanceMasks.Cut? {
    let W = CGFloat(photo.width), H = CGFloat(photo.height)
    let wide = box.insetBy(dx: -box.width * 0.12, dy: -box.height * 0.12).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard !wide.isNull, wide.width > 0.02, wide.height > 0.02 else { return nil }
    let px = CGRect(x: wide.minX * W, y: wide.minY * H, width: wide.width * W, height: wide.height * H).integral
    guard px.width >= 16, px.height >= 16, let part = photo.cropping(to: px), let region = InstanceMasks.make(from: part)
    else { return nil }
    let centre = CGPoint(x: (box.midX * W - px.minX) / px.width, y: (box.midY * H - px.minY) / px.height)
    guard let label = region.instances(near: centre).first?.label, let c = region.cut(instance: label) else { return nil }
    let sx = px.width / W, sy = px.height / H
    return InstanceMasks.Cut(cg: c.cg, box: CGRect(x: px.minX / W + c.box.minX * sx, y: px.minY / H + c.box.minY * sy,
                                                   width: c.box.width * sx, height: c.box.height * sy))
}

func oldRender(_ p: OldCatchPlan.Placement, masks: InstanceMasks, photo: CGImage, box: CGRect?) -> InstanceMasks.Cut? {
    switch p.cut {
    case .instance(let l): return masks.cut(instance: l)
    case .union(let ls): return masks.cut(instances: IndexSet(ls))
    case .clip(let ls, let rect): return oldClip(masks, labels: ls, rect: rect)
    case .noMask: return box.flatMap { oldRegionCut(photo: photo, box: $0) }
    }
}

func describe(_ c: CatchPlan.Cut) -> String {
    switch c {
    case .instance(let l): "instance \(l)"
    case .union(let ls): "union \(ls)"
    case .part(let ls, let k): "part of \(ls) (\(k.count) px)"
    case .noMask: "no mask"
    }
}

func describe(_ c: OldCatchPlan.Cut) -> String {
    switch c {
    case .instance(let l): "instance \(l)"
    case .union(let ls): "union \(ls)"
    case .clip(let ls, let r): String(format: "CLIP %@ to box (%.2f,%.2f %.2f×%.2f)", "\(ls)", r.minX, r.minY, r.width, r.height)
    case .noMask: "no mask"
    }
}

// MARK: Measures

struct Measure: Encodable {
    var coverage: Double
    var straight: Double
    var rectangle: Bool
    var leak: Double
}

/// `a`: the cut-out's alpha on the photo's canvas; `ref`: the thing; `others`: the other named things.
func measure(_ a: [UInt8], ref: [UInt8], others: [[UInt8]], box: CGRect?, cut: InstanceMasks.Cut?, width w: Int, height h: Int) -> Measure {
    var inRef = 0, covered = 0, opaque = 0, leaked = 0
    for i in 0..<(w * h) {
        let on = a[i] > 127
        if ref[i] > 127 {
            inRef += 1
            if on { covered += 1 }
        }
        if on {
            opaque += 1
            if others.contains(where: { $0[i] > 127 }) { leaked += 1 }
        }
    }
    // A straight cut: a vertical or horizontal line inside the thing (the thing on both sides of it) along which the
    // cut-out is opaque on one side and empty on the other — the mark of a cut along a box (the AI's box, the old plan's
    // box widened by 4%, or a region's edge). Measured on every column and row; the worst one counts, as the share of
    // that line's length inside the thing.
    var worst = 0.0
    let d = max(2, min(w, h) / 150)
    func line(count: Int, length: Int, at: (Int, Int) -> (Int, Int)) {
        for c in d..<(count - d) {
            var eligible = 0, cutThere = 0
            for t in 0..<length {
                let (x1, y1) = at(c - d, t), (x2, y2) = at(c + d, t)
                let i1 = y1 * w + x1, i2 = y2 * w + x2
                guard ref[i1] > 127, ref[i2] > 127 else { continue }
                eligible += 1
                if (a[i1] > 127 && a[i2] < 32) || (a[i2] > 127 && a[i1] < 32) { cutThere += 1 }
            }
            if eligible >= 20 { worst = max(worst, Double(cutThere) / Double(eligible)) }
        }
    }
    _ = box
    line(count: w, length: h) { c, t in (c, t) }
    line(count: h, length: w) { c, t in (t, c) }
    // A rectangle: the cut-out's four corners all opaque.
    var rect = false
    if let cut {
        let cg = cut.cg
        let full = alpha(of: cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height), width: cg.width, height: cg.height)
        let corners = [(1, 1), (cg.width - 2, 1), (1, cg.height - 2), (cg.width - 2, cg.height - 2)]
        rect = cg.width > 4 && cg.height > 4 && corners.allSatisfy { full[$0.1 * cg.width + $0.0] > 200 }
    }
    return Measure(coverage: inRef == 0 ? 0 : Double(covered) / Double(inRef),
                   straight: worst,
                   rectangle: rect, leak: opaque == 0 ? 0 : Double(leaked) / Double(opaque))
}

// MARK: The sheet: photo with boxes | before | after

func sheet(photo: CGImage, boxes: [CGRect?], refs: [[UInt8]?], before: [InstanceMasks.Cut?], after: [InstanceMasks.Cut?]) -> CGImage {
    let panelH = 420
    let scale = CGFloat(panelH) / CGFloat(photo.height)
    let panelW = Int(CGFloat(photo.width) * scale)
    let rows = max(1, after.count)
    let W = panelW * 3 + 40, H = (panelH + 20) * rows + 20
    let ctx = rgba(width: W, height: H)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let colours: [CGColor] = [CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1), CGColor(red: 0.1, green: 0.4, blue: 0.95, alpha: 1),
                              CGColor(red: 0.1, green: 0.7, blue: 0.2, alpha: 1), CGColor(red: 0.9, green: 0.6, blue: 0, alpha: 1)]
    for r in 0..<rows {
        let top = CGFloat(H - 20 - (panelH + 20) * r - panelH)   // bottom-left origin
        func panel(_ k: Int) -> CGRect { CGRect(x: CGFloat(10 + k * (panelW + 10)), y: top, width: CGFloat(panelW), height: CGFloat(panelH)) }
        // 1. The photo, every thing's box (this row's thicker).
        ctx.draw(photo, in: panel(0))
        for (j, b) in boxes.enumerated() {
            guard let b else { continue }
            let p = panel(0)
            ctx.setStrokeColor(colours[j % colours.count])
            ctx.setLineWidth(j == r ? 3 : 1)
            ctx.stroke(CGRect(x: p.minX + b.minX * p.width, y: p.maxY - b.maxY * p.height, width: b.width * p.width, height: b.height * p.height))
        }
        // 2 and 3. The cut-outs where they are in the photo, on a checkerboard.
        for (k, cut) in [(1, r < before.count ? before[r] : nil), (2, r < after.count ? after[r] : nil)] {
            let p = panel(k)
            let s: CGFloat = 12
            var y = p.minY
            var odd = false
            while y < p.maxY {
                var x = p.minX
                var o = odd
                while x < p.maxX {
                    ctx.setFillColor(o ? CGColor(gray: 0.8, alpha: 1) : CGColor(gray: 0.93, alpha: 1))
                    ctx.fill(CGRect(x: x, y: y, width: min(s, p.maxX - x), height: min(s, p.maxY - y)))
                    o.toggle()
                    x += s
                }
                odd.toggle()
                y += s
            }
            if let cut {
                let b = cut.box
                ctx.draw(cut.cg, in: CGRect(x: p.minX + b.minX * p.width, y: p.maxY - b.maxY * p.height, width: b.width * p.width, height: b.height * p.height))
            }
            if r < boxes.count, let b = boxes[r] {
                ctx.setStrokeColor(colours[r % colours.count].copy(alpha: 0.6)!)
                ctx.setLineWidth(1)
                ctx.stroke(CGRect(x: p.minX + b.minX * p.width, y: p.maxY - b.maxY * p.height, width: b.width * p.width, height: b.height * p.height))
            }
        }
    }
    return ctx.makeImage()!
}

// MARK: Run

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: harness cases.json out-dir")
    exit(2)
}
let casesURL = URL(fileURLWithPath: args[1])
let base = casesURL.deletingLastPathComponent()
let out = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let file = try JSONDecoder().decode(CaseFile.self, from: Data(contentsOf: casesURL))
InstanceMasks.trace = { print("    " + $0) }

struct Row: Encodable {
    let id: String
    let thing: String
    let before: String
    let after: String
    let note: String?
    let measure: Measure?
    let oldMeasure: Measure?
    let failures: [String]
}
var rows: [Row] = []
var failures = 0
var visionWorked = false

for c in file.cases {
    let url = base.appendingPathComponent("photos").appendingPathComponent(c.photo)
    guard let photo = loadUpright(url) else {
        print("::error::\(c.id): cannot read \(c.photo)")
        failures += 1
        continue
    }
    let W = photo.width, H = photo.height
    let rawPoints: [CGPoint?] = c.things.map { t in t.point.map { CGPoint(x: $0[0] / 1000, y: $0[1] / 1000) } }
    let boxes: [CGRect?] = c.things.map { t in
        guard let b = t.box_2d, b.count == 4, b[2] > b[0], b[3] > b[1] else { return nil }
        return CGRect(x: b[1] / 1000, y: b[0] / 1000, width: (b[3] - b[1]) / 1000, height: (b[2] - b[0]) / 1000)
    }
    // As `CatchObject.plannedThings`: the point (the box's middle when only a box came), own when not a repeat.
    let points: [CGPoint?] = c.things.indices.map { i in rawPoints[i] ?? boxes[i].map { CGPoint(x: $0.midX, y: $0.midY) } }
    let own = TagPlacement.distinct(points)
    let things = c.things.indices.map { i in
        CatchPlan.Thing(point: points[i] ?? CGPoint(x: 0.5, y: 0.5), box: boxes[i], own: own[i])
    }
    let oldThings = things.map { OldCatchPlan.Thing(point: $0.point, box: $0.box, own: $0.own) }
    let refs: [[UInt8]?] = c.things.map { t in
        guard let r = t.reference, let img = loadUpright(base.appendingPathComponent("photos").appendingPathComponent(r), maxSide: 4000)
        else { return nil }
        return alpha(of: img, in: CGRect(x: 0, y: 0, width: W, height: H), width: W, height: H, grey: true)
    }
    let started = Date()
    print("\(c.id):")
    guard let masks = InstanceMasks.make(from: photo), let grid = masks.labelMaskCopy() else {
        print("::warning::\(c.id): Vision found no foreground instance")
        rows.append(Row(id: c.id, thing: "-", before: "no Vision instance", after: "no Vision instance", note: nil,
                        measure: nil, oldMeasure: nil, failures: ["Vision found nothing"]))
        failures += 1
        continue
    }
    visionWorked = true
    let labelsFound = Set(grid.mask.filter { $0 != 0 }).sorted()
    let plans = CatchPlan.plan(things: things, mask: grid.mask, width: grid.width, height: grid.height, colours: masks.colourGrid())
    let oldPlans = OldCatchPlan.plan(things: oldThings, mask: grid.mask, width: grid.width, height: grid.height)
    var befores: [InstanceMasks.Cut?] = [], afters: [InstanceMasks.Cut?] = []
    let rendered = masks.render(plans, boxes: c.things.indices.map { own[$0] ? boxes[$0] : nil }, points: things.map(\.point))
    for (i, t) in c.things.enumerated() {
        let made = rendered[i]
        let old = oldRender(oldPlans[i], masks: masks, photo: photo, box: own[i] ? boxes[i] : nil)
        befores.append(old)
        afters.append(made.cut)
        var m: Measure?, om: Measure?
        var fails: [String] = []
        if let ref = refs[i] {
            let others = refs.indices.filter { $0 != i }.compactMap { refs[$0] }
            func onCanvas(_ cut: InstanceMasks.Cut?) -> [UInt8] {
                guard let cut else { return [UInt8](repeating: 0, count: W * H) }
                let b = cut.box
                return alpha(of: cut.cg, in: CGRect(x: b.minX * CGFloat(W), y: b.minY * CGFloat(H), width: b.width * CGFloat(W), height: b.height * CGFloat(H)), width: W, height: H)
            }
            m = measure(onCanvas(made.cut), ref: ref, others: others, box: boxes[i], cut: made.cut, width: W, height: H)
            om = measure(onCanvas(old), ref: ref, others: others, box: boxes[i], cut: old, width: W, height: H)
            if t.expect == "none", made.cut == nil {
                // Expected: no cut-out (cases.json `why`).
            } else if t.check ?? true, let m {
                if m.coverage < minCoverage { fails.append(String(format: "covers %.0f%% of the thing (< %.0f%%)", m.coverage * 100, minCoverage * 100)) }
                if m.straight > maxStraight { fails.append(String(format: "a straight cut through the thing along %.0f%% of a line", m.straight * 100)) }
                if m.rectangle { fails.append("a rectangle") }
                if m.leak > maxLeak { fails.append(String(format: "%.0f%% of it is another named thing", m.leak * 100)) }
            }
        }
        failures += fails.isEmpty ? 0 : 1
        let expected = t.expect == "none" ? " (expected: none — \(t.why ?? ""))" : ""
        rows.append(Row(id: c.id, thing: t.name, before: describe(oldPlans[i].cut), after: describe(plans[i].cut) + (plans[i].refine != nil ? " + region" : "") + (made.cut == nil ? ", no cut-out" : "") + expected,
                        note: made.note, measure: m, oldMeasure: om, failures: fails))
    }
    let img = sheet(photo: photo, boxes: boxes, refs: refs, before: befores, after: afters)
    savePNG(img, out.appendingPathComponent("\(c.id).png"))
    print("\(c.id): \(W)×\(H), Vision instances \(labelsFound), \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
}

// The summary: a Markdown table (also the job's summary on GitHub) and the rows as JSON.
func pct(_ v: Double?) -> String { v.map { String(format: "%.0f%%", $0 * 100) } ?? "-" }
var md = "| case | thing | before (old plan) | after (now) | covers before → after | straight before → after | rectangle | other thing | result |\n"
md += "|---|---|---|---|---|---|---|---|---|\n"
for r in rows {
    md += "| \(r.id) | \(r.thing) | \(r.before) | \(r.after) | \(pct(r.oldMeasure?.coverage)) → \(pct(r.measure?.coverage)) | "
    md += "\(pct(r.oldMeasure?.straight)) → \(pct(r.measure?.straight)) | \(r.oldMeasure.map { $0.rectangle ? "yes" : "no" } ?? "-") → \(r.measure.map { $0.rectangle ? "yes" : "no" } ?? "-") | "
    md += "\(pct(r.measure?.leak)) | \(r.failures.isEmpty ? "ok" : "FAIL: " + r.failures.joined(separator: "; ")) |\n"
}
try? md.write(to: out.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
try? enc.encode(rows).write(to: out.appendingPathComponent("results.json"))
print(md)
for r in rows where !r.failures.isEmpty { print("::error::cut-out harness \(r.id) / \(r.thing): \(r.failures.joined(separator: "; "))") }
if !visionWorked {
    print("::error::Vision's foreground instance request did not run on this machine")
    exit(1)
}
exit(failures == 0 ? 0 : 1)
