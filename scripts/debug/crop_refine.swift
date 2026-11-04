// Vision on a crop round the thing (its instance's box grown by 6%), the mask written at the crop's size.
// swift crop_refine.swift photo.jpg x0 x1 y0 y1 out.png
import Foundation
import Vision
import CoreImage
import ImageIO
let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil)!
let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let W = Double(cg.width), H = Double(cg.height)
var x0 = Double(a[2])!, x1 = Double(a[3])!, y0 = Double(a[4])!, y1 = Double(a[5])!
let mx = (x1 - x0) * 0.06, my = (y1 - y0) * 0.06
x0 = max(0, x0 - mx); x1 = min(1, x1 + mx); y0 = max(0, y0 - my); y1 = min(1, y1 + my)
let rect = CGRect(x: x0 * W, y: y0 * H, width: (x1 - x0) * W, height: (y1 - y0) * H).integral
let crop = cg.cropping(to: rect)!
let req = VNGenerateForegroundInstanceMaskRequest()
let h = VNImageRequestHandler(cgImage: crop, orientation: .up)
try h.perform([req])
guard let r = req.results?.first else { print("crop: no instances"); exit(0) }
print("crop \(crop.width)x\(crop.height) instances \(r.allInstances.map { $0 })")
let buf = try r.generateScaledMaskForImage(forInstances: r.allInstances, from: h)
let ci = CIImage(cvPixelBuffer: buf)
let png = CIContext().pngRepresentation(of: ci, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())!
try png.write(to: URL(fileURLWithPath: a[6]))
// The photo itself at the crop, for comparing.
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[6] + ".jpg") as CFURL, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(dst, crop, nil); CGImageDestinationFinalize(dst)
