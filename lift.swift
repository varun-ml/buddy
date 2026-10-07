// Cut the subject out of every frame in a folder, on-device (macOS 14+ "lift subject"), into transparent PNGs.
// All frames are cropped to one shared box so the subject doesn't jump between frames.
// Usage: lift <frames-in> <frames-out> [px to trim off the bottom, e.g. a floor reflection]
import AppKit
import Vision
import CoreImage

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: lift <in> <out>"); exit(2) }
let (inDir, outDir) = (args[1], args[2])
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let names = (try fm.contentsOfDirectory(atPath: inDir)).filter { $0.hasSuffix(".png") }.sorted()
let ctx = CIContext()

var cut: [(String, CIImage)] = []
var box = CGRect.null
for n in names {
    let url = URL(fileURLWithPath: (inDir as NSString).appendingPathComponent(n))
    guard let src = CIImage(contentsOf: url) else { continue }
    let req = VNGenerateForegroundInstanceMaskRequest()
    let h = VNImageRequestHandler(ciImage: src)
    try h.perform([req])
    guard let r = req.results?.first else { print("no subject in \(n)"); continue }
    let masked = try r.generateMaskedImage(ofInstances: r.allInstances, from: h, croppedToInstancesExtent: false)
    let img = CIImage(cvPixelBuffer: masked)
    // tight bounds of non-transparent pixels, via the mask's own extent
    let mask = CIImage(cvPixelBuffer: try r.generateScaledMaskForImage(forInstances: r.allInstances, from: h))
    let bounds = alphaBounds(mask)
    box = box.union(bounds)
    cut.append((n, img))
}
if args.count > 3, let trim = Double(args[3]) { box = CGRect(x: box.minX, y: box.minY + trim, width: box.width, height: box.height - trim) }   // CI y runs bottom-up
for (n, img) in cut {
    let out = img.cropped(to: box).transformed(by: CGAffineTransform(translationX: -box.minX, y: -box.minY))
    let url = URL(fileURLWithPath: (outDir as NSString).appendingPathComponent(n))
    try ctx.writePNGRepresentation(of: out, to: url, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
}
print("lifted \(cut.count)/\(names.count) frames → \(outDir) (\(Int(box.width))×\(Int(box.height)))")

/// Bounding box of pixels brighter than ~0 in a one-channel mask.
func alphaBounds(_ m: CIImage) -> CGRect {
    guard let cg = ctx.createCGImage(m, from: m.extent) else { return m.extent }
    let w = cg.width, hgt = cg.height
    var px = [UInt8](repeating: 0, count: w * hgt)
    let c = CGContext(data: &px, width: w, height: hgt, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: hgt))
    var (x0, y0, x1, y1) = (w, hgt, -1, -1)
    for y in 0..<hgt { for x in 0..<w where px[y * w + x] > 20 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    if x1 < 0 { return m.extent }
    // bitmap rows run top-down; CIImage y runs bottom-up
    return CGRect(x: x0, y: hgt - 1 - y1, width: x1 - x0 + 1, height: y1 - y0 + 1)
}
