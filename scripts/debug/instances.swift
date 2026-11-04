// Lists Vision's foreground instances of a photo (bounding box 0–1, top-left origin, share of the photo) and writes
// each as a PNG mask. Debug only: swift scripts/debug/instances.swift photo.jpg outdir
import Foundation
import Vision
import CoreImage
import ImageIO

let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("cannot read"); exit(1) }
let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
print("size \(cg.width)x\(cg.height) orientation \(props?["Orientation"] ?? "nil")")
let req = VNGenerateForegroundInstanceMaskRequest()
let h = VNImageRequestHandler(cgImage: cg, orientation: .up)
try h.perform([req])
guard let r = req.results?.first else { print("NO INSTANCES"); exit(0) }
print("instances \(r.allInstances.map { $0 })")
let ctx = CIContext()
for l in r.allInstances {
    let buf = try r.generateScaledMaskForImage(forInstances: IndexSet(integer: l), from: h)
    let ci = CIImage(cvPixelBuffer: buf)
    // bbox of mask
    let w = CVPixelBufferGetWidth(buf), hh = CVPixelBufferGetHeight(buf)
    CVPixelBufferLockBaseAddress(buf, .readOnly)
    let base = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: Float32.self)
    let row = CVPixelBufferGetBytesPerRow(buf) / 4
    var minX = w, minY = hh, maxX = 0, maxY = 0, n = 0
    for y in stride(from: 0, to: hh, by: 2) { for x in stride(from: 0, to: w, by: 2) where base[y * row + x] > 0.5 {
        n += 1; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
    CVPixelBufferUnlockBaseAddress(buf, .readOnly)
    print(String(format: "instance %d box x %.3f-%.3f y %.3f-%.3f share %.3f", l,
                 Double(minX)/Double(w), Double(maxX)/Double(w), Double(minY)/Double(hh), Double(maxY)/Double(hh),
                 Double(n*4)/Double(w*hh)))
    if let png = ctx.pngRepresentation(of: ci, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()) {
        try png.write(to: out.appendingPathComponent("mask-\(l).png"))
    }
}
