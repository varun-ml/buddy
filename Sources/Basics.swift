// Buddy: a desktop pet for Claude Code and Codex. Walks along your screen and tells you what needs you.
// Build and install: ./install.sh [cat|pug]. Files: see CONTRIBUTING.md.
import AppKit
import SwiftUI
import CoreAudio

// MARK: data

struct Session: Codable, Identifiable, Equatable {
    var id: String
    var cwd: String?
    var repo: String?
    var branch: String?
    var state: String?
    var activity: String?
    var prompt: String?
    var ts: Double
    var turnStart: Double?
    var source: String? = nil   // nil = Claude Code, "codex-desktop" (ChatGPT app) or "codex-cli"
    var tty: String? = nil        // the terminal tab it runs in
    var termApp: String? = nil    // Terminal, iTerm2, Ghostty, Cursor… ("claude"/"ChatGPT" = the desktop apps)
    var herdrPane: String? = nil  // set when it runs inside a herdr pane
    var said: String? = nil       // the agent's own last line when it finished (beat.py)
}

struct PastSession { var id: String; var cwd: String; var when: Date; var codex = false }

struct PR: Identifiable {
    var id: String { "\(repo)#\(number)" }
    var repo: String, number: Int, title: String, url: String, branch: String, sha: String, body: String
    var ci: String          // red | green | pending | none
    var failing: [String]
    var isDraft: Bool
    var updated: Date
    var short: String { "\(repo.split(separator: "/").last ?? "")#\(number)" }
    var recent: Bool { Date().timeIntervalSince(updated) < 7 * 86400 }
    /// The only red PRs worth a nag: not a draft, touched this week.
    var needsYou: Bool { ci == "red" && !isDraft && recent }
    /// First real sentence of the description: what the PR is for.
    var summary: String {
        let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("|") && !$0.hasPrefix("<!--") && !$0.hasPrefix("-") } ?? title
    }
}

struct Detail { var why: String?; var session: PastSession? }

enum Mood { case asleep, calm, busy, waiting, upset, happy }

/// event = a real thing happened (coloured border); quote / thought / ambient = Bit just chatting (neutral border).
enum BubbleKind { case event, quote, thought, ambient }
enum Pose { case none, glasses, thinking, trophy, flex }

struct Bubble: Identifiable {
    let id = UUID()
    var text: String
    var tone: Mood
    var kind: BubbleKind = .event
    var byline: String? = nil
    var action: (() -> Void)?
    var react: ((Bool) -> Void)? = nil   // 👍/👎 chips: Buddy learns which ideas you like
}

struct Stats {
    var merged = 0, opened = 0, commits = 0, prompts = 0, sessions = 0
    var codexSessions = 0, codexPrompts = 0
    var yesterdayMerged: Int?
    var team: [(login: String, n: Int)] = []
    var teamTotal = 0
    var me = ""
    var rank: Int? { team.firstIndex { $0.login == me }.map { $0 + 1 } }
    var myCount: Int { team.first { $0.login == me }?.n ?? 0 }
}

/// One plan limit: how much of the window is used and when it resets.
struct Limit: Identifiable { var id: String { name }; var name: String; var used: Double; var resets: Date? }

/// Claude plan usage, from the endpoint Claude Code's own /usage reads, with the login Claude Code keeps in the Keychain.
/// The token never leaves this function. No token or an expired one (Claude Code refreshes it) gives nothing.
func claudeLimits() -> [Limit] {
    // opt-in ("claudeLimits": true): reads the Keychain item "Claude Code-credentials" and calls api.anthropic.com/api/oauth/usage
    guard config["claudeLimits"] as? Bool == true, let raw = run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
          let cred = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
          let tok = (cred["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String else { return [] }
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
    req.setValue("Bearer " + tok, forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    var body: Data?
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { d, r, _ in body = (r as? HTTPURLResponse)?.statusCode == 200 ? d : nil; done.signal() }.resume()
    done.wait()
    guard let b = body, let o = try? JSONSerialization.jsonObject(with: b) as? [String: Any] else { return [] }
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return [("five_hour", "Claude 5h"), ("seven_day", "Claude week")].compactMap { key, name in
        guard let w = o[key] as? [String: Any], let u = w["utilization"] as? Double else { return nil }
        return Limit(name: name, used: u, resets: (w["resets_at"] as? String).flatMap { iso.date(from: $0) })
    }
}

/// Codex plan usage: the newest rate_limits Codex wrote into a rollout file.
func codexLimits() -> [Limit] {
    // newest file that has one (a session that just started may not yet)
    let line = codexFiles(hours: 48).sorted { $0.mod > $1.mod }.lazy.compactMap { f in
        (try? String(contentsOfFile: f.path, encoding: .utf8))?.split(separator: "\n").last { $0.contains("\"rate_limits\"") }
    }.first
    guard let line,
          let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let r = ((o["payload"] as? [String: Any])?["rate_limits"]) as? [String: Any] else { return [] }
    return ["primary", "secondary"].compactMap { k in
        guard let w = r[k] as? [String: Any], let u = w["used_percent"] as? Double else { return nil }
        let mins = w["window_minutes"] as? Double ?? 0
        let span = mins >= 10080 ? "week" : mins >= 300 ? "\(Int(mins / 60))h" : "\(Int(mins))m"
        return Limit(name: "◆ Codex \(span)", used: u, resets: (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) })
    }
}

struct Wisdom: Codable {
    var stoic: [[String]]
    var socratic_quotes: [[String]]
    var socratic_questions: [String]
}
/// The folder Buddy was built in (next to wisdom.json), wherever the repo is cloned.
let petDir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent().path ?? FileManager.default.currentDirectoryPath
/// A command-line tool from Homebrew (Apple silicon or Intel) or ~/.local/bin.
func tool(_ name: String) -> String {
    ["/opt/homebrew/bin", "/usr/local/bin", (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin")]
        .map { ($0 as NSString).appendingPathComponent(name) }.first { FileManager.default.isExecutableFile(atPath: $0) } ?? name
}
let wisdom: Wisdom = {
    // ponytail: NSHomeDirectory() directly; top-level globals init in file order and `home` is declared later
    let p = (petDir as NSString).appendingPathComponent("wisdom.json")
    return (FileManager.default.contents(atPath: p)).flatMap { try? JSONDecoder().decode(Wisdom.self, from: $0) }
        ?? Wisdom(stoic: [["Begin at once to live.", "Seneca"]], socratic_quotes: [], socratic_questions: [])
}()

/// Per-day memory (greeted, milestones fired, quotes used), kept in UserDefaults.
enum Day {
    static var key: String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }
    static func once(_ what: String) -> Bool {
        let k = "bit.\(key).\(what)"
        if UserDefaults.standard.bool(forKey: k) { return false }
        UserDefaults.standard.set(true, forKey: k); return true
    }
}

/// True while any app is recording from the default microphone (a call, a huddle, dictation). Needs no permission.
func micInUse() -> Bool {
    var dev = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return false }
    var running = UInt32(0); size = UInt32(MemoryLayout<UInt32>.size)
    addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
    return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr && running != 0
}

let home = NSHomeDirectory()
/// Settings in ~/.config/buddy.json, e.g. {"pet": "pug", "breakMins": 90, "juggle": 5, "stop": "20:00"}. Restart Buddy after editing.
/// Settings used to live under the binary's old name, "Pet". Copy them over once so a rename loses nothing.
let _migrated: Void = {
    let d = UserDefaults.standard
    guard d.object(forKey: "bit.migrated") == nil else { return }
    for (k, v) in UserDefaults(suiteName: "Pet")?.dictionaryRepresentation() ?? [:] where k.hasPrefix("bit.") && d.object(forKey: k) == nil { d.set(v, forKey: k) }
    d.set(true, forKey: "bit.migrated")
}()
let config: [String: Any] = FileManager.default.contents(atPath: (NSHomeDirectory() as NSString).appendingPathComponent(".config/buddy.json"))
    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
var statsRepos = config["statsRepos"] as? [String] ?? []
/// "cat", "pug", "bear", or "random": cat, pug, bear in turn, one per day.
var pet: String {
    let p = config["pet"] as? String ?? "cat"
    guard p == "random" else { return p }
    // read dozens of times per frame; the calendar only needs asking once a minute
    if Date().timeIntervalSince(randomDay.at) > 60 {
        randomDay = (Date(), ["cat", "pug", "bear"][(Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0) % 3])
    }
    return randomDay.pet
}
var randomDay = (at: Date.distantPast, pet: "cat")
var isBear: Bool { pet == "bear" }
var isPug: Bool { pet == "pug" }
/// Sunglasses, tracksuit and sneakers. Pugs wear it unless buddy.json says "outfit": "none".
var drip: Bool { isPug && (config["outfit"] as? String ?? "drip") == "drip" }
/// A celebration dance: transparent PNG frames in ~/.config/buddy/dance (install.sh makes them from ~/.config/buddy/dance.mp4).
let danceFrames: [NSImage] = {
    let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/buddy/dance")
    return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".png") }.sorted()
        .compactMap { NSImage(contentsOfFile: (dir as NSString).appendingPathComponent($0)) }
}()
let sessionsDir = (home as NSString).appendingPathComponent(".claude/pet/sessions")
let projectsDir = (home as NSString).appendingPathComponent(".claude/projects")
let ghPath = tool("gh")
let staleAfter: Double = 15 * 60
let forgetAfter: Double = 12 * 3600
var blobCenter: () -> CGPoint = { .zero }
var mouseInPet: () -> Bool = { false }

@discardableResult
func run(_ exe: String, _ args: [String]) -> Data? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    guard (try? p.run()) != nil else { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? data : nil
}
func gh(_ args: [String]) -> Data? { run(ghPath, args) }

/// "18:30" today, "Sat 22:32" later this week.
func resetText(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "EEE HH:mm"
    return f.string(from: d)
}

func ago(_ seconds: Double) -> String {
    let s = Int(max(0, seconds))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}

/// Bring forward whichever app the session lives in.
func activate(_ s: Session) {
    if let pane = s.herdrPane { focusHerdr(pane); return }
    if let app = s.termApp, !["claude", "Claude", "ChatGPT", "Codex"].contains(app) { focusTerminal(app, tty: s.tty); return }
    switch s.source {
    case "codex-desktop" where !s.id.hasPrefix("codex-"): NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/ChatGPT.app"), configuration: .init())
    case "codex-cli": NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init())
    case "codex-desktop" where s.id.hasPrefix("codex-"):
        NSWorkspace.shared.open(URL(string: "codex://threads/" + s.id.dropFirst(6))!)
    default:
        if let u = ccdLink(s.id) { NSWorkspace.shared.open(u) } else { activateClaude() }
    }
}

/// Bring a terminal tab forward by its tty. Terminal and iTerm2 can pick the exact tab; other apps just come to the front.
func focusTerminal(_ app: String, tty: String?) {
    let script: String
    switch (app, tty) {
    case ("Terminal", let t?):
        script = """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(t)" then
                set selected of t to true
                set index of w to 1
              end if
            end repeat
          end repeat
          activate
        end tell
        """
    case ("iTerm2", let t?):
        script = """
        tell application "iTerm2"
          repeat with w in windows
            repeat with tb in tabs of w
              repeat with se in sessions of tb
                if tty of se is "\(t)" then
                  select w
                  select tb
                  select se
                end if
              end repeat
            end repeat
          end repeat
          activate
        end tell
        """
    default:
        script = "tell application \"\(app)\" to activate"
    }
    DispatchQueue.global().async { run("/usr/bin/osascript", ["-e", script]) }
}

/// Focus the herdr pane, then the terminal tab where herdr itself is open.
func focusHerdr(_ pane: String) {
    DispatchQueue.global().async {
        run(tool("herdr"), ["agent", "focus", pane])
        // the herdr client is the `herdr` process that owns a tty (the server has none)
        guard let out = run("/bin/ps", ["-axo", "tty=,comm="]).map({ String(decoding: $0, as: UTF8.self) }),
              let line = out.split(separator: "\n").first(where: { $0.hasSuffix("herdr") && !$0.hasPrefix("??") }),
              let t = line.split(separator: " ").first else { return }
        // ponytail: assumes herdr is open in Terminal; read the client's parent app if you use iTerm2 for it
        DispatchQueue.main.async { focusTerminal("Terminal", tty: "/dev/" + t) }
    }
}

/// The desktop-app chat for a Claude Code session id (claude://…/epitaxy/local_…), so a tap opens that exact chat.
func ccdLink(_ cliId: String) -> URL? {
    let root = (home as NSString).appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    guard let e = FileManager.default.enumerator(atPath: root) else { return nil }
    for case let f as String in e where (f as NSString).lastPathComponent.hasPrefix("local_") && f.hasSuffix(".json") {
        guard let d = FileManager.default.contents(atPath: (root as NSString).appendingPathComponent(f)),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (o["cliSessionId"] as? String) == cliId,
              let local = o["sessionId"] as? String else { continue }
        return URL(string: "claude://claude.ai/epitaxy/" + local)
    }
    return nil
}

func activateClaude() {
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Claude.app"), configuration: .init())
}
