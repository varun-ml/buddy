import AppKit
import SwiftUI

// MARK: Buddy on the phone (phone.py streams your sessions to the Android app). The app shows this same buddy:
// drawn here, once per mood, as PNGs it downloads, so there is one source for how Buddy looks.

let phoneDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/pet/phone")
var drawingForPhone = false

/// The PNG cut to the drawn pixels plus a small margin, so the buddy fills the phone's round bubble.
func trimmedPNG(_ img: NSImage) -> Data? {
    guard let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t) else { return nil }
    var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
    for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    guard maxX >= 0, let cg = rep.cgImage else { return rep.representation(using: .png, properties: [:]) }
    let pad = 6, side = max(maxX - minX, maxY - minY) + 2 * pad   // square, centred: it sits in a circle
    let r = CGRect(x: (minX + maxX) / 2 - side / 2, y: (minY + maxY) / 2 - side / 2, width: side, height: side)
    let out = NSImage(size: NSSize(width: side, height: side))
    out.lockFocus()
    NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(x: -r.minX, y: -(CGFloat(rep.pixelsHigh) - r.maxY), width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
    out.unlockFocus()
    guard let t2 = out.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: t2)?.representation(using: .png, properties: [:])
}

extension Model {
    /// Only when the phone server is set up (its folder exists). At launch and when the breed changes.
    @MainActor func exportAvatars(to dir: String = phoneDir + "/avatar") {
        guard FileManager.default.fileExists(atPath: (dir as NSString).deletingLastPathComponent) else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970
        let looks: [(String, String?)] = [("calm", nil), ("busy", "working"), ("waiting", "waiting"), ("asleep", nil)]
        let was = frozenTime
        frozenTime = 800_000_000; drawingForPhone = true   // a still frame, no badge
        defer { frozenTime = was; drawingForPhone = false }
        for (name, state) in looks {
            let pm = Model(); pm.breedIndex = breedIndex
            pm.sessions = state.map { [Session(id: "p", state: $0, ts: now)] } ?? []
            if name == "asleep" { pm.snoozedUntil = Date().addingTimeInterval(3600) }
            let r = ImageRenderer(content: Cat(m: pm).frame(width: 96, height: 84)); r.scale = 3
            if let img = r.nsImage, let png = trimmedPNG(img) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }
    }
}

/// Right-click → Pair phone…: phone.py draws the one QR code (install + pair) and opens it.
func pairPhone() {
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
    DispatchQueue.global().async { _ = run("/usr/bin/python3", [dir + "/phone.py", "--pair"]) }
}
