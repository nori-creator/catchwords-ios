// Cuts a recording into small JPEG frames, so the motion can be looked at where only pictures are kept (ci-previews;
// recordings stay in the run's artifact). Used by .github/workflows/ios-check.yml.
// Usage: swift scripts/video_frames.swift VIDEO.mp4 OUT_DIR PREFIX [FPS=6] [WIDTH=360]
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: video_frames.swift VIDEO OUT_DIR PREFIX [FPS] [WIDTH]\n".data(using: .utf8)!)
    exit(2)
}
let video = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
let prefix = args[3]
let fps = args.count > 4 ? Double(args[4]) ?? 6 : 6
let width = args.count > 5 ? Double(args[5]) ?? 360 : 360

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let asset = AVURLAsset(url: video)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: width, height: width * 4)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

// The synchronous reads (deprecated, still working) keep this a plain script: no run loop to wait on.
let seconds = asset.duration.seconds

var n = 0
var t = 0.0
while t < seconds {
    let time = CMTime(seconds: t, preferredTimescale: 600)
    if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
        n += 1
        let url = outDir.appendingPathComponent(String(format: "%@-%03d.jpg", prefix, n))
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
            CGImageDestinationFinalize(dest)
        }
    }
    t += 1 / fps
}
print("\(prefix): \(n) frames from \(String(format: "%.1f", seconds)) s")
