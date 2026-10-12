import AppKit
import SwiftUI

// MARK: Buddy on the phone (phone.py streams your sessions to the Android app). The app shows this same buddy:
// drawn here, once per mood, as PNGs it downloads, so there is one source for how Buddy looks.

let phoneDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/pet/phone")

extension Model {
    /// Only when the phone server is set up (its folder exists). At launch and when the breed changes.
    @MainActor func exportAvatars(to dir: String = phoneDir + "/avatar") {
        guard FileManager.default.fileExists(atPath: (dir as NSString).deletingLastPathComponent) else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let now = Date().timeIntervalSince1970
        let looks: [(String, String?)] = [("calm", nil), ("busy", "working"), ("waiting", "waiting"), ("asleep", nil)]
        let was = frozenTime
        frozenTime = 800_000_000   // a still frame
        defer { frozenTime = was }
        for (name, state) in looks {
            let pm = Model(); pm.breedIndex = breedIndex
            pm.sessions = state.map { [Session(id: "p", state: $0, ts: now)] } ?? []
            if name == "asleep" { pm.snoozedUntil = Date().addingTimeInterval(3600) }
            let r = ImageRenderer(content: Cat(m: pm).frame(width: 96, height: 84)); r.scale = 3
            if let img = r.nsImage, let t = img.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }
    }
}
