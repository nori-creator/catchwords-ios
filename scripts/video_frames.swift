// Cuts a recording into small frames laid on one JPEG sheet, so the motion can be looked at where only pictures are
// kept (ci-previews; recordings stay in the run's artifact). One sheet per recording: a file per frame (~900 files in
// a run) hit GitHub's secondary rate limit and nothing reached ci-previews (2026-10-28). Used by ios-check.yml.
// Usage: swift scripts/video_frames.swift VIDEO.mp4 OUT_DIR PREFIX [FPS=6] [WIDTH=360] [START=0]
// START skips the opening seconds (the simulator's home screen and the app's white launch).
// Writes PREFIX.jpg (frames left to right, top to bottom, COLUMNS a row) and PREFIX.txt
// ("frames N columns C width W height H fps F start S") to cut it apart again.
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: video_frames.swift VIDEO OUT_DIR PREFIX [FPS] [WIDTH] [START]\n".data(using: .utf8)!)
    exit(2)
}
let video = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
let prefix = args[3]
let fps = args.count > 4 ? Double(args[4]) ?? 6 : 6
let width = args.count > 5 ? Double(args[5]) ?? 360 : 360
let start = args.count > 6 ? Double(args[6]) ?? 0 : 0
let columns = 8

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let asset = AVURLAsset(url: video)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: width, height: width * 4)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

// The synchronous reads (deprecated, still working) keep this a plain script: no run loop to wait on.
let seconds = asset.duration.seconds

var frames: [CGImage] = []
var t = start
while t < seconds {
    if let image = try? generator.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
        frames.append(image)
    }
    t += 1 / fps
}
guard let first = frames.first else {
    print("\(prefix): no frames from \(String(format: "%.1f", seconds)) s")
    exit(0)
}
let w = first.width, h = first.height
let cols = min(columns, frames.count)
let rows = (frames.count + cols - 1) / cols
guard let ctx = CGContext(data: nil, width: w * cols, height: h * rows, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    exit(1)
}
for (i, image) in frames.enumerated() {
    // Core Graphics counts y from the bottom: the first row goes at the top.
    let x = (i % cols) * w, y = (rows - 1 - i / cols) * h
    ctx.draw(image, in: CGRect(x: x, y: y, width: w, height: h))
}
if let sheet = ctx.makeImage(),
   let dest = CGImageDestinationCreateWithURL(outDir.appendingPathComponent("\(prefix).jpg") as CFURL,
                                              UTType.jpeg.identifier as CFString, 1, nil) {
    CGImageDestinationAddImage(dest, sheet, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
    CGImageDestinationFinalize(dest)
}
let info = "frames \(frames.count) columns \(cols) width \(w) height \(h) fps \(fps) start \(start)\n"
try? info.write(to: outDir.appendingPathComponent("\(prefix).txt"), atomically: true, encoding: .utf8)
print("\(prefix): \(frames.count) frames from \(String(format: "%.1f", seconds)) s")
