import AppKit
import SwiftUI

// MARK: agents. One entry per coding agent: how it looks on the card and how to open one of its sessions.
// beat.py has the other half (how to read its hooks). To add an agent, add both, plus a case in test_beat.py.

struct Agent {
    let name: String         // beat.py's name; a session's source starts with it ("codex-desktop")
    let label: String        // "Codex"
    let mark: String         // before its alerts and on its kitten; "" for none
    let color: Color
    let badge: String        // two letters on Burrow's pot
    let glyph: String        // on Glass's app icon
    let gradient: [Color]    // Glass's app icon
    let apps: [String]       // its own app names: when a session runs there, open it the agent's way, not as a terminal tab
    let open: (Session) -> Void
}

let agents: [Agent] = [
    Agent(name: "codex", label: "Codex", mark: "◆", color: codexColor, badge: "Cx", glyph: ">_", gradient: [hex(0x1fc79c), hex(0x0e8f6f)],
          apps: ["ChatGPT", "Codex"], open: { s in
        switch s.source {
        case "codex-desktop" where s.id.hasPrefix("codex-"): NSWorkspace.shared.open(URL(string: "codex://threads/" + s.id.dropFirst(6))!)
        case "codex-desktop": NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/ChatGPT.app"), configuration: .init())
        default: NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init())
        }
    }),
    // last: sessions with no source (or an agent with no entry yet) look and open like Claude Code
    Agent(name: "claude", label: "Claude", mark: "", color: claudeColor, badge: "Cl", glyph: "✳", gradient: [hex(0xe8906f), hex(0xc9643f)],
          apps: ["claude", "Claude"], open: { s in
        if let u = ccdLink(s.id) { NSWorkspace.shared.open(u) } else { activateClaude() }
    }),
]

extension Session {
    var agent: Agent { agents.first { (source ?? "claude").hasPrefix($0.name) } ?? agents.last! }
}
