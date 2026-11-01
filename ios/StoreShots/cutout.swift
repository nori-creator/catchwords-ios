// Cuts the subject out of each of the App Store screenshots' photos with Vision (the same request the app uses for
// stickers), cropped to the subject: `swift cutout.swift <in dir> <out dir> name=file …` writes <out>/<name>_cut.png.
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
let inDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
let context = CIContext()
var failed = false
for pair in args.dropFirst(3) {
    let parts = pair.split(separator: "=").map(String.init)
    let (name, file) = (parts[0], parts[1])
    guard let image = CIImage(contentsOf: inDir.appendingPathComponent(file)) else { print("✗ \(file): unreadable"); failed = true; continue }
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(ciImage: image)
    do {
        try handler.perform([request])
        guard let result = request.results?.first else { print("✗ \(file): no subject"); failed = true; continue }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
        let cut = CIImage(cvPixelBuffer: buffer)
        guard let cg = context.createCGImage(cut, from: cut.extent) else { print("✗ \(file): render"); failed = true; continue }
        let rep = NSBitmapImageRep(cgImage: cg)
        try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(name)_cut.png"))
        print("✓ \(name)_cut.png \(cg.width)×\(cg.height)")
    } catch {
        print("✗ \(file): \(error)"); failed = true
    }
}
exit(failed ? 1 : 0)
