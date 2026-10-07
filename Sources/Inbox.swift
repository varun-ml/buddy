import AppKit
import SwiftUI

// MARK: `buddy say`: any agent (Claude, Codex, a scheduled job) can put a message in front of you

let inboxDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/pet/inbox")
extension Model {
    /// One message per 2-s tick, oldest first; say() queues it behind anything already up. Older than 2 h: dropped.
    func readInbox(_ sessions: [Session]) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: inboxDir)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        for f in files {
            let path = (inboxDir as NSString).appendingPathComponent(f)
            guard let d = fm.contents(atPath: path), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let text = j["text"] as? String else { try? fm.removeItem(atPath: path); continue }
            if Date().timeIntervalSince1970 - (j["ts"] as? Double ?? 0) > 7200 { try? fm.removeItem(atPath: path); continue }
            let urgent = j["urgent"] as? Bool ?? false, cwd = j["cwd"] as? String ?? ""
            if snoozed { return }   // napping: leave it on disk; it keeps for 2 h, longer than the 15-min queue
            try? fm.removeItem(atPath: path)
            let from = sessions.first { s in s.cwd.map { cwd == $0 || cwd.hasPrefix($0 + "/") } ?? false }
            let who = from?.repo ?? (cwd as NSString).lastPathComponent
            say("\(who): \(text)", urgent ? .waiting : .calm, seconds: urgent ? 40 : 20, kind: .event, sound: urgent ? nil : "Pop",
                action: from.map { s in { activate(s) } })
            return
        }
    }
}
