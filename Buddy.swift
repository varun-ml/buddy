// Buddy: a desktop pet for Claude Code and Codex. Walks along your screen and tells you what needs you.
// Build and install: ./install.sh [cat|pug]
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
let statsRepos = config["statsRepos"] as? [String] ?? []
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

// MARK: Codex — sessions live in ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl (CLI and the ChatGPT desktop app)

let codexDir = ProcessInfo.processInfo.environment["BIT_CODEX_DIR"] ?? (NSHomeDirectory() as NSString).appendingPathComponent(".codex/sessions")

/// Rollout files touched in the last `hours`, from today's and yesterday's folders.
func codexFiles(hours: Double) -> [(path: String, mod: Date)] {
    let fm = FileManager.default
    let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"
    var out: [(String, Date)] = []
    for day in [Date(), Date().addingTimeInterval(-86400)] {
        let dir = (codexDir as NSString).appendingPathComponent(f.string(from: day))
        for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".jsonl") {
            let p = (dir as NSString).appendingPathComponent(name)
            if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, Date().timeIntervalSince(m) < hours * 3600 { out.append((p, m)) }
        }
    }
    return out
}

func jsonLines(_ text: Substring) -> [[String: Any]] {
    text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
}

/// A real typed prompt, not an injected AGENTS.md / environment block.
func codexPrompt(_ o: [String: Any]) -> String? {
    guard (o["type"] as? String) == "response_item", let p = o["payload"] as? [String: Any],
          (p["type"] as? String) == "message", (p["role"] as? String) == "user" else { return nil }
    let t = ((p["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty || t.hasPrefix("<") || t.hasPrefix("# AGENTS.md") || t.hasPrefix("The following is the Codex agent history") { return nil }
    // attached files come first; your words follow "## My request:"
    if let r = t.range(of: "## My request") { return String(t[r.upperBound...].drop { ":  ".contains($0) || $0 == "\n" }).trimmingCharacters(in: .whitespacesAndNewlines) }
    return t
}

var codexMeta: [String: (id: String, cwd: String, branch: String, desktop: Bool)] = [:]   // per file, read once

let codexLock = NSLock()

func codexHead(_ path: String) -> (id: String, cwd: String, branch: String, desktop: Bool)? {
    codexLock.lock(); defer { codexLock.unlock() }
    if let m = codexMeta[path] { return m }
    guard let h = FileHandle(forReadingAtPath: path) else { return nil }
    let head = String(data: h.readData(ofLength: 64_000), encoding: .utf8) ?? ""
    h.closeFile()
    guard let first = head.split(separator: "\n").first, let o = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any],
          let p = o["payload"] as? [String: Any], let id = p["id"] as? String else { return nil }
    let cwd = p["cwd"] as? String ?? ""
    let branch = (run("/usr/bin/git", ["-C", cwd, "branch", "--show-current"]).flatMap { String(data: $0, encoding: .utf8) } ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    codexMeta[path] = (id, cwd, branch, (p["originator"] as? String ?? "").contains("Desktop"))
    return codexMeta[path]
}

/// Codex thread titles ("Guardian review", …) from ~/.codex/session_index.jsonl, for sessions with no typed prompt.
func codexTitles() -> [String: String] {
    guard let t = try? String(contentsOfFile: (NSHomeDirectory() as NSString).appendingPathComponent(".codex/session_index.jsonl"), encoding: .utf8) else { return [:] }
    var out: [String: String] = [:]
    for o in jsonLines(Substring(t)) { if let id = o["id"] as? String, let n = o["thread_name"] as? String { out[id] = n } }
    return out
}

/// Today's Codex sessions and typed prompts.
func codexToday() -> (sessions: Int, prompts: Int) {
    let files = codexFiles(hours: 24).filter { Calendar.current.isDateInToday($0.mod) }
    var prompts = 0
    for f in files {
        guard let text = try? String(contentsOfFile: f.path, encoding: .utf8) else { continue }
        for line in text.split(separator: "\n") where line.contains("\"role\":\"user\"") {
            if let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], codexPrompt(o) != nil { prompts += 1 }
        }
    }
    return (files.count, prompts)
}

/// Newest Codex session whose folder is on `branch`, or sits on the PR's head commit (Codex desktop worktrees are detached).
func findCodexSession(branch: String, sha: String) -> PastSession? {
    var head: [String: String] = [:]
    return codexFiles(hours: 24 * 2).compactMap { f -> PastSession? in
        guard let m = codexHead(f.path) else { return nil }
        if head[m.cwd] == nil {
            head[m.cwd] = run("/usr/bin/git", ["-C", m.cwd, "rev-parse", "HEAD"]).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        }
        guard m.branch == branch || (!sha.isEmpty && head[m.cwd] == sha) else { return nil }
        return PastSession(id: m.id, cwd: m.cwd, when: f.mod, codex: true)
    }.max { $0.when < $1.when }
}

/// Newest Claude Code transcript on this Mac that worked on `branch`.
func findSession(branch: String) -> PastSession? {
    guard !branch.isEmpty, let out = run("/usr/bin/grep", ["-rl", "--include=*.jsonl", "\"gitBranch\":\"\(branch)\"", projectsDir]),
          let text = String(data: out, encoding: .utf8) else { return nil }
    let fm = FileManager.default
    let files = text.split(separator: "\n").map(String.init)
    let newest = files.compactMap { f -> (String, Date)? in
        guard let d = (try? fm.attributesOfItem(atPath: f))?[.modificationDate] as? Date else { return nil }
        return (f, d)
    }.max { $0.1 < $1.1 }
    guard let (file, when) = newest, let h = FileHandle(forReadingAtPath: file) else { return nil }
    let head = String(data: h.readData(ofLength: 200_000), encoding: .utf8) ?? ""
    h.closeFile()
    guard let r = head.range(of: "\"cwd\":\"") else { return nil }
    let cwd = String(head[r.upperBound...].prefix { $0 != "\"" })
    return PastSession(id: ((file as NSString).lastPathComponent as NSString).deletingPathExtension, cwd: cwd, when: when)
}

/// The first real error line from the newest failed GitHub Actions run on the branch.
func findWhy(_ pr: PR) -> String? {
    guard let data = gh(["run", "list", "--repo", pr.repo, "--branch", pr.branch, "-L", "15", "--json", "databaseId,conclusion"]),
          let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          let id = runs.first(where: { ($0["conclusion"] as? String) == "failure" })?["databaseId"] as? Int,
          let log = gh(["run", "view", "\(id)", "--repo", pr.repo, "--log-failed"]),
          let text = String(data: log, encoding: .utf8) else { return nil }
    let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*m")
    for line in text.split(separator: "\n") {
        guard let r = line.range(of: "##[error]") else { continue }
        var msg = String(line[r.upperBound...])
        msg = ansi.stringByReplacingMatches(in: msg, range: NSRange(msg.startIndex..., in: msg), withTemplate: "")
        if msg.hasPrefix("Process completed with exit code") { continue }
        return String(msg.prefix(220))
    }
    return nil
}

final class Model: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var prs: [PR] = []
    @Published var details: [String: Detail] = [:]
    @Published var mergedToday = 0 { didSet {
        if mergesLoaded && mergedToday > oldValue {
            sunUntil = Date().addingTimeInterval(90)
            DispatchQueue.main.asyncAfter(deadline: .now() + 91) { self.objectWillChange.send() }   // redraw to clear the sun
        }
        mergesLoaded = true
    } }
    var mergesLoaded = false
    @Published var sunUntil = Date.distantPast   // CI weather: sun for 90 s after a merge
    var workingSince: Date? = UserDefaults.standard.object(forKey: "bit.workingSince") as? Date {   // the current stretch without a 5-min break; survives restarts
        didSet { UserDefaults.standard.set(workingSince, forKey: "bit.workingSince") }
    }
    @Published var workedToday: TimeInterval = UserDefaults.standard.double(forKey: "bit.\(Day.key).active")   // time at the keyboard today
    var sinceBreak: TimeInterval? { workingSince.map { Date().timeIntervalSince($0) } }
    var lastBreakNudge = Date.distantPast
    var lastJuggleNudge = Date.distantPast
    var lastStopNudge = Date.distantPast
    @Published var diskFreeGB: Double = -1
    @Published var worktrees: [Worktree] = []
    var lastDiskNudge = Date.distantPast
    var life = loadLife()                       // ~/.config/buddy/life.json: your people, goals, stop time
    @Published var tasks = loadTasks()          // open "- [ ]" lines in ~/.config/buddy/tasks.md
    @Published var tab = "work"                 // card tab: work | personal
    @Published var themeName = T.name
    @Published var bubble: Bubble?
    @Published var showCard = false
    @Published var showStale = false
    @Published var prsCheckedAt: Date?
    @Published var snoozedUntil: Date?
    @Published var shake = 0
    @Published var celebrate = 0
    @Published var hearts = 0
    @Published var busyAction: String?
    @Published var hovering = false
    @Published var walking = false
    @Published var facingLeft = true
    @Published var leftSide = false
    @Published var cardHeight: CGFloat = 0   // the card's full height, so the window can fit all of it
    @Published var tight = false   // the card would overflow the screen: drop the quote first, never scroll
    @Published var cardWidth: CGFloat = { let w = UserDefaults.standard.double(forKey: "bit.cardWidth"); return w >= 300 ? w : 330 }() {
        didSet { UserDefaults.standard.set(Double(cardWidth), forKey: "bit.cardWidth") }
    }
    var gripFrom: (mouse: CGFloat, width: CGFloat)?   // drag-to-resize start
    @Published var stats = Stats()
    @Published var statsLoaded = false
    @Published var pose: Pose = .none
    @Published var breedIndex = UserDefaults.standard.integer(forKey: "bit.breed") % breeds.count
    @Published var gesture: Gesture = .none
    @Published var gestureAt = Date.distantPast
    var zoomies = false
    @Published var squatting = false
    @Published var limits: [Limit] = []
    func loadLimits() {
        DispatchQueue.global().async {
            let l = claudeLimits() + codexLimits()
            DispatchQueue.main.async {
                if !l.isEmpty { self.limits = l }
                // one nudge per limit per day at 80%, another at 95%
                for x in l where x.used >= 80 {
                    let level = x.used >= 95 ? 95 : 80
                    if Day.once("limit\(level)-\(x.name)") {
                        self.say("\(x.name) limit at \(Int(x.used))%\(x.resets.map { ", resets " + resetText($0) } ?? "")", .waiting, seconds: 12)
                    }
                }
            }
        }
    }
    @Published var dancingUntil = Date.distantPast
    var dancing: Bool { Date() < dancingUntil }
    private var lastDance = Date.distantPast
    /// Play the dance clip once; at most once a minute so a busy hour isn't one long dance.
    func dance() {
        guard isPug, !danceFrames.isEmpty, !squatting, Date().timeIntervalSince(lastDance) > 60 else { return }
        lastDance = Date()
        let secs = Double(danceFrames.count) / 15
        dancingUntil = Date().addingTimeInterval(secs)
        DispatchQueue.main.asyncAfter(deadline: .now() + secs + 0.05) { [weak self] in self?.objectWillChange.send() }
    }
    @Published var rotateTick = 0   // the wisdom box advances on this; the view itself re-renders too often to own a timer

    // MARK: same scolding twice — the same correction given to 3+ sessions today

    static let scoldings: [(key: String, gist: String, rule: String, pattern: String)] = [
        ("explain", "to explain it simply first", "Explain the mechanism in plain words first, then the detail. Check I follow before going deeper.",
         "i don'?t understand|what do you mean|\\bwdym\\b|\\bexplain\\b|samjh|kya hai|what is this"),
        ("verbose", "to keep it short", "Keep answers short: lead with the result, no walls of text, one idea per message.",
         "too (long|verbose|much text)|wall of text|\\bconcise\\b|less text|\\bverbose\\b"),
        ("scope", "to stay in scope", "Stay strictly in the asked scope. Ask before expanding; never change files I didn't name.",
         "only (do|change)|don'?t (change|touch)|out of scope"),
        ("verify", "to prove it actually works", "Verify before claiming done: re-run it, show the evidence, say what you did not check.",
         "did you (test|check|verify)|are you sure|how do you know|\\bprove\\b"),
        ("useless", "that the result is useless", "Before showing me something, ask: is this information or just data? Lead with what I can act on.",
         "\\bbekar\\b|\\bshit\\b|useless|un ?useful|not useful|\\bwtf\\b"),
    ]

    func scanScoldings() {
        DispatchQueue.global().async {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let today = f.string(from: Date())
            let fm = FileManager.default
            var sessionsBy: [String: Set<String>] = [:]
            let regexes = Model.scoldings.map { try! NSRegularExpression(pattern: $0.pattern, options: .caseInsensitive) }
            for dir in (try? fm.contentsOfDirectory(atPath: projectsDir)) ?? [] {
                let d = (projectsDir as NSString).appendingPathComponent(dir)
                for file in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where file.hasSuffix(".jsonl") {
                    let path = (d as NSString).appendingPathComponent(file)
                    guard let mod = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                          Calendar.current.isDateInToday(mod), let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                    for line in text.split(separator: "\n") where line.contains("\"type\":\"user\"") && line.contains("\"timestamp\":\"\(today)") && !line.contains("tool_use_id") {
                        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                              let msg = o["message"] as? [String: Any] else { continue }
                        let c = msg["content"]
                        let t = (c as? String) ?? ((c as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: " ") ?? "")
                        if t.hasPrefix("<") || t.count > 600 { continue }
                        for (i, r) in regexes.enumerated() where r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
                            sessionsBy[Model.scoldings[i].key, default: []].insert(file)
                        }
                    }
                }
            }
            for f in codexFiles(hours: 24) where Calendar.current.isDateInToday(f.mod) {
                guard let text = try? String(contentsOfFile: f.path, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") where line.contains("\"role\":\"user\"") {
                    guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let t = codexPrompt(o), t.count <= 600 else { continue }
                    for (i, r) in regexes.enumerated() where r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
                        sessionsBy[Model.scoldings[i].key, default: []].insert(f.path)
                    }
                }
            }
            DispatchQueue.main.async {
                for sc in Model.scoldings {
                    let n = sessionsBy[sc.key]?.count ?? 0
                    guard n >= 3, Day.once("scold.\(sc.key)") else { continue }
                    self.say("You told \(n) sessions \(sc.gist) today.\nWrite it down once?", .calm, seconds: 25, kind: .thought,
                             pose: .thinking) { [weak self] in self?.copy(sc.rule); self?.flash = "Rule copied 📋 paste it into CLAUDE.md" }
                    self.scoldRule = sc.rule
                    return
                }
            }
        }
    }
    @Published var scoldRule: String?
    var breed: Breed { breeds[breedIndex % breeds.count] }   // the list changes size when a random day changes pet

    func nextBreed(quiet: Bool = false) {
        breedIndex = (breedIndex + 1) % breeds.count
        UserDefaults.standard.set(breedIndex, forKey: "bit.breed")
        hearts += 1
        if !quiet { say("I'm a \(breed.name) now \(isBear ? "🐻" : isPug ? "🐶" : "😼")", .happy, seconds: 3, kind: .ambient) }
    }

    /// A little bit of business: stretch, yawn, chase tail, wash, loaf, sneeze, zoomies, knock something off, hop.
    /// Bears: rear up and roar, eat honey, swipe a fish out of the air, scratch their back.
    func doGesture(_ g: Gesture? = nil) {
        let pick = g ?? (isBear ? [Gesture.stretch, .yawn, .loaf, .sneeze, .zoomies, .hop, .roar, .roar, .honey, .fish, .scratch]
            : [Gesture.stretch, .yawn, .spin, .wash, .loaf, .sneeze, .zoomies, .knock, .hop] + (drip ? [.shimmy, .shimmy] : [])).randomElement()!
        gesture = pick
        gestureAt = Date()
        if pick == .zoomies { zoomies = true }
        if pick == .hop { celebrate += 1 }
        let dur: Double = pick == .loaf ? 6 : pick == .zoomies || pick == .honey || pick == .scratch ? 3 : 2.4
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak self] in
            if self?.gesture == pick { self?.gesture = .none; self?.zoomies = false }
        }
    }
    @Published var todayQuote = wisdom.stoic.randomElement()!
    private var nextSlot = Date().addingTimeInterval(CommandLine.arguments.contains("--demo") ? 4 : 90)
    private var lastEventAt = Date.distantPast
    private var hoverEndedAt = Date.distantPast
    private var lastRank: Int?
    private var lastAmbient = ""
    private var said: [String: Date] = [:]
    private func fresh(_ line: String) -> Bool { Date().timeIntervalSince(said[line] ?? .distantPast) > 3600 }
    private var lastStates: [String: String] = [:]
    private var lastCI: [String: String] = [:]
    private var detailFor: [String: String] = [:]  // pr id -> sha the detail was fetched for
    private var bubbleTimer: Timer?
    /// Every quote and question Bit has said, newest first.
    @Published var history: [Bubble] = []
    @Published var favorites: Set<String> = Model.loadFavorites()
    static let favFile = (petDir as NSString).appendingPathComponent("favorites.md")

    static func loadFavorites() -> Set<String> {
        let text = (try? String(contentsOfFile: favFile, encoding: .utf8)) ?? ""
        return Set(text.split(separator: "\n").compactMap { l in
            guard l.hasPrefix("- ") else { return nil }
            return String(l.dropFirst(2).split(separator: "|").first ?? "").trimmingCharacters(in: .whitespaces)
        })
    }

    func full(_ b: Bubble) -> String { b.byline.map { "\(b.text) \($0)" } ?? b.text }

    func copyBubble(_ b: Bubble) {
        copy(full(b))
        flash = "Copied 📋"
    }

    func toggleFavorite(_ b: Bubble) {
        let key = b.text
        if favorites.contains(key) {
            favorites.remove(key)
            let kept = ((try? String(contentsOfFile: Model.favFile, encoding: .utf8)) ?? "")
                .split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix("- \(key)") }
            try? kept.joined(separator: "\n").write(toFile: Model.favFile, atomically: true, encoding: .utf8)
        } else {
            favorites.insert(key)
            if !FileManager.default.fileExists(atPath: Model.favFile) {
                try? "# Buddy — saved quotes and questions\n\n".write(toFile: Model.favFile, atomically: true, encoding: .utf8)
            }
            if let h = FileHandle(forWritingAtPath: Model.favFile) {
                h.seekToEndOfFile()
                h.write("- \(key) | \(b.byline ?? "") | \(Day.key)\n".data(using: .utf8)!)
                h.closeFile()
            }
            hearts += 1
            flash = "Saved ♥"
        }
    }

    /// A fresh quote straight into history, without a bubble.
    func anotherQuote() {
        let q = wisdom.stoic.filter { fresh($0[0]) }.randomElement() ?? wisdom.stoic.randomElement()!
        said[q[0]] = Date()
        history.insert(Bubble(text: "“\(q[0])”", tone: .calm, kind: .quote, byline: "— \(q[1])"), at: 0)
    }

    @Published var flash: String? { didSet { if flash != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.flash = nil } } } }

    /// Pointer on a bubble: keep it. Pointer leaves: let it go a few seconds later.
    func holdBubble(_ holding: Bool) {
        bubbleTimer?.invalidate()
        guard !holding else { return }
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.bubble = nil
            self?.pose = .none
            self?.onExpandChange?()
        }
    }
    var onExpandChange: (() -> Void)?

    var expanded: Bool { bubble != nil || showCard }
    var snoozed: Bool { (snoozedUntil ?? .distantPast) > Date() }

    func isStuck(_ s: Session) -> Bool { s.state == "working" && Date().timeIntervalSince1970 - s.ts > staleAfter }

    var waiting: [Session] { sessions.filter { $0.state == "waiting" } }
    var stuck: [Session] { sessions.filter { isStuck($0) } }
    var working: [Session] { sessions.filter { $0.state == "working" && !isStuck($0) } }
    /// Finished in the last hour: the ball is in your court.
    var yourTurn: [Session] { sessions.filter { $0.state == "finished" && Date().timeIntervalSince1970 - $0.ts < 3600 } }
    var needsYouPRs: [PR] { prs.filter(\.needsYou) }
    var draftRed: [PR] { prs.filter { $0.ci == "red" && $0.isDraft && $0.recent } }
    var staleRed: [PR] { prs.filter { $0.ci == "red" && !$0.recent } }
    var badge: Int { waiting.count + stuck.count + needsYouPRs.count }

    var mood: Mood {
        if snoozed { return .asleep }
        if !needsYouPRs.isEmpty { return .upset }
        if !waiting.isEmpty || !stuck.isEmpty { return .waiting }
        if !working.isEmpty { return .busy }
        if !sessions.isEmpty { return .calm }
        return .asleep
    }

    var headline: String {
        if snoozed { return "Napping till \(DateFormatter.localizedString(from: snoozedUntil!, dateStyle: .none, timeStyle: .short))" }
        if let s = waiting.first { return "\(s.repo ?? "A session") is waiting for your OK" }
        if needsYouPRs.count == 1 { return "1 PR needs a fix" }
        if needsYouPRs.count > 1 { return "\(needsYouPRs.count) PRs need a fix" }
        if let s = stuck.first { return "\(s.repo ?? "A session") has been quiet \(ago(Date().timeIntervalSince1970 - s.ts))" }
        if working.count == 1 { return "\(working[0].repo ?? "1 session") is cooking" }
        if working.count > 1 { return "\(working.count) sessions cooking" }
        return mergedToday > 0 ? "All clear. \(mergedToday) merged today" : "All clear"
    }

    func say(_ text: String, _ tone: Mood, seconds: Double = 10, kind: BubbleKind = .event, byline: String? = nil,
             pose: Pose = .none, sound: String? = nil, react: ((Bool) -> Void)? = nil, action: (() -> Void)? = nil) {
        if snoozed && tone != .happy { return }
        if squatting && kind != .event { return }
        if kind == .event && (tone == .upset || tone == .waiting) { lastEventAt = Date() }
        // a sound when something needs you: approval or limit (Glass), red PR (Basso), a session done (Pop)
        if kind == .event && tone == .happy { dance() }
        if isBear && kind == .event && tone == .upset { doGesture(.roar) }   // a red PR gets roared at
        if isBear && kind == .event && tone == .happy { doGesture(.fish) }   // a merge gets a salmon
        if let name = sound ?? (kind != .event ? nil : tone == .waiting ? "Glass" : tone == .upset ? "Basso" : nil) { NSSound(named: name)?.play() }
        if showCard { if tone == .happy { celebrate += 1 }; return }
        bubble = Bubble(text: text, tone: tone, kind: kind, byline: byline, action: action, react: react)
        said[text] = Date()
        if kind == .quote || kind == .thought {
            history.insert(bubble!, at: 0)
            if history.count > 60 { history.removeLast() }
        }
        if let h = FileHandle(forWritingAtPath: "/tmp/buddy.said.log") ?? { FileManager.default.createFile(atPath: "/tmp/buddy.said.log", contents: nil); return FileHandle(forWritingAtPath: "/tmp/buddy.said.log") }() {
            h.seekToEndOfFile()
            h.write("\(ISO8601DateFormatter().string(from: Date())) [\(kind)] \(text.replacingOccurrences(of: "\n", with: " / "))\n".data(using: .utf8)!)
            h.closeFile()
        }
        self.pose = pose
        if kind == .event && (tone == .upset || tone == .waiting) { shake += 1 }
        if tone == .happy { celebrate += 1 }
        onExpandChange?()
        bubbleTimer?.invalidate()
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.bubble = nil
            self?.pose = .none
            self?.onExpandChange?()
        }
    }

    func hoverEnded() { hoverEndedAt = Date() }

    // MARK: today's numbers (every 10 min)

    func loadStats() {
        DispatchQueue.global().async {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let today = f.string(from: Date()), yest = f.string(from: Date().addingTimeInterval(-86400))
            // GitHub reads a bare date as UTC; give it your own midnight, or 00:00–05:30 IST merges count as yesterday
            let z = DateFormatter(); z.dateFormat = "xxx"; let tz = z.string(from: Date())   // "+05:30"
            let from = "\(today)T00:00:00\(tz)", yFrom = "\(yest)T00:00:00\(tz)"
            // one set of repos for your tiles and the leaderboard, so the two always agree
            // which repos count: ~/.config/buddy.json "statsRepos": ["owner/repo", ...]; none set → no PR tiles or leaderboard
            guard !statsRepos.isEmpty else { DispatchQueue.main.async { self.applyStats(Stats()) }; return }
            let repos = statsRepos.map { "repo:\($0)" }.joined(separator: " ")
            let q = """
            query{ viewer{login}
             merged: search(query:"is:pr author:@me is:merged merged:>=\(from) \(repos)",type:ISSUE){issueCount}
             opened: search(query:"is:pr author:@me created:>=\(from) \(repos)",type:ISSUE){issueCount}
             yest: search(query:"is:pr author:@me is:merged merged:\(yFrom)..\(from) \(repos)",type:ISSUE){issueCount} }
            """
            var s = Stats()
            if let d = gh(["api", "graphql", "-f", "query=\(q)"]),
               let root = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["data"] as? [String: Any] {
                let count = { (k: String) in (root[k] as? [String: Any])?["issueCount"] as? Int }
                s.me = (root["viewer"] as? [String: Any])?["login"] as? String ?? ""
                s.merged = count("merged") ?? 0
                s.opened = count("opened") ?? 0
                s.yesterdayMerged = count("yest")
            }
            // the team: every merged PR today, 100 per page (a busy day is 150+; one page dropped the rest)
            var by: [String: Int] = [:], after = "", total = 0
            for _ in 0..<10 {
                let tq = "query{ search(query:\"is:pr is:merged merged:>=\(from) \(repos)\",type:ISSUE,first:100\(after)){issueCount pageInfo{hasNextPage endCursor} nodes{... on PullRequest{author{login}}}} }"
                guard let d = gh(["api", "graphql", "-f", "query=\(tq)"]),
                      let r = ((try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["data"] as? [String: Any])?["search"] as? [String: Any] else { break }
                total = r["issueCount"] as? Int ?? total
                for n in (r["nodes"] as? [[String: Any]]) ?? [] { if let l = (n["author"] as? [String: Any])?["login"] as? String { by[l, default: 0] += 1 } }
                guard let pi = r["pageInfo"] as? [String: Any], pi["hasNextPage"] as? Bool == true, let c = pi["endCursor"] as? String else { break }
                after = ",after:\"\(c)\""
            }
            s.teamTotal = total
            s.team = by.map { ($0.key, $0.value) }.sorted { $0.n > $1.n || ($0.n == $1.n && $0.login < $1.login) }
            if !s.me.isEmpty, let d = gh(["api", "search/commits?q=author:\(s.me)+committer-date:>=\(today)&per_page=1", "--jq", ".total_count"]) {
                s.commits = Int(String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            }
            let sh = "find \"\(projectsDir)\" -name '*.jsonl' -newermt \(today) -print0 2>/dev/null"
            if let d = run("/bin/sh", ["-c", "\(sh) | xargs -0 grep -c '' 2>/dev/null | wc -l"]) {
                s.sessions = Int(String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            }
            if let d = run("/bin/sh", ["-c", "\(sh) | xargs -0 grep -h '\"type\":\"user\"' 2>/dev/null | grep '\"timestamp\":\"\(today)' | grep -vc tool_use_id"]) {
                s.prompts = Int(String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            }
            let cx = codexToday()
            s.codexSessions = cx.sessions; s.codexPrompts = cx.prompts
            s.sessions += cx.sessions; s.prompts += cx.prompts
            DispatchQueue.main.async { self.applyStats(s) }
        }
    }

    private func applyStats(_ s: Stats) {
        let first = !statsLoaded
        let prevMerged = stats.merged
        stats = s
        statsLoaded = true
        mergedToday = s.merged
        if first && Calendar.current.component(.hour, from: Date()) >= 6 && Day.once("greeted") {
            let y = s.yesterdayMerged.map { "Yesterday you merged \($0)." } ?? ""
            say("Morning! \(y)\n\(todayQuote[0])", .happy, seconds: 12, kind: .quote, byline: "— \(todayQuote[1])", pose: .glasses)
        }
        // milestones and taking #1: once each per day
        // ponytail: on launch, milestones already passed are marked silently; only new crossings celebrate
        for m in [5, 10, 15, 20] where s.merged >= m && Day.once("milestone\(m)") && !first && prevMerged < m {
            say(m >= 15 ? "\(m) merged! Absolute unit. 💪" : "\(m) merged today! 🎉", .happy, seconds: 8, kind: .ambient, pose: .flex)
            hearts += 1
        }
        if s.rank == 1, lastRank != 1, Day.once("crown") {
            say("You took #1 in the merge-off 👑", .happy, seconds: 8, kind: .ambient, pose: .trophy)
        }
        lastRank = s.rank
    }

    // MARK: ambient chatter (checked every 30 s, at most one bubble per 15 min)

    var hasP0: Bool { !needsYouPRs.isEmpty || !waiting.isEmpty }

    func ambientTick() {
        let now = Date()
        let demo = CommandLine.arguments.contains("--demo")
        guard now >= nextSlot, bubble == nil || demo, !showCard, !snoozed, !hovering,
              demo || now.timeIntervalSince(lastEventAt) > 180, demo || now.timeIntervalSince(hoverEndedAt) > 120 else { return }
        nextSlot = now.addingTimeInterval(demo ? 12 : 8 * 60)
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 19, Day.once("recap") { recap(); return }
        // Weighted draw without replacement; a card with nothing worth saying returns false and the next draw gets a go.
        var bag: [(Int, () -> Bool)] = [(40, socratic), (30, stoic), (20, tally), (10, team)]
        while !bag.isEmpty {
            var r = Int.random(in: 0..<bag.reduce(0) { $0 + $1.0 })
            let i = bag.firstIndex { r -= $0.0; return r < 0 }!
            if bag.remove(at: i).1() { return }
        }
    }

    private func stoic() -> Bool {
        var q = wisdom.stoic.randomElement()!
        if !needsYouPRs.isEmpty || !stuck.isEmpty, let calm = wisdom.stoic.first(where: { $0[0].hasPrefix("You have power over your mind") }), Bool.random() { q = calm }
        if !fresh(q[0]) { return false }
        said[q[0]] = Date()
        lastAmbient = q[0]
        say("“\(q[0])”", .calm, seconds: 16, kind: .quote, byline: "— \(q[1])", pose: .glasses)
        return true
    }

    private func socratic() -> Bool {
        var vars: [String: String] = ["sessions": "\(sessions.count)"]
        if !statsRepos.isEmpty { vars["merged"] = "\(stats.merged)" }
        if let p = needsYouPRs.first ?? draftRed.first { vars["pr"] = p.short }
        if let r = working.first?.repo ?? sessions.first?.repo { vars["repo"] = r }
        let usable = wisdom.socratic_questions.filter { q in
            let need = q.components(separatedBy: "{").dropFirst().map { $0.components(separatedBy: "}")[0] }
            guard need.allSatisfy({ vars[$0] != nil }) else { return false }
            if q.contains("{sessions}") && sessions.count < 2 { return false }
            if q.contains("{merged}") && stats.merged < 3 { return false }
            return fresh(q)
        }
        guard var q = usable.randomElement() else { return false }
        said[q] = Date()
        lastAmbient = q
        for (k, v) in vars { q = q.replacingOccurrences(of: "{\(k)}", with: v) }
        say(q, .calm, seconds: 13, kind: .thought, pose: .thinking)
        return true
    }

    private func tally() -> Bool {
        let s = stats
        guard statsLoaded else { return false }
        var line: String?
        if let y = s.yesterdayMerged, y > 0, s.merged >= y { line = "\(s.merged) merged. That's already yesterday's whole day (\(y)). 🐾" }
        else if s.merged <= 1 && s.prompts >= 30 { line = "Only \(s.merged) merged, but \(s.prompts) prompts. Deep-work day, huh?" }
        else if s.merged > 0, let y = s.yesterdayMerged { line = "\(s.merged) merged so far, \(max(0, y - s.merged)) to match yesterday." }
        guard let l = line, fresh(l) else { return false }
        lastAmbient = l
        say(l, .calm, seconds: 7, kind: .ambient, pose: s.merged >= 10 ? .flex : .none)
        return true
    }

    private func team() -> Bool {
        let s = stats
        guard s.teamTotal > 0, let top = s.team.first else { return false }
        var l: String
        if s.rank == 1 { l = "You lead the merge-off with \(top.n). Team's at \(s.teamTotal) today. 👑" }
        else if let r = s.rank { l = "Merge-off: \(top.login) has \(top.n). You're #\(r) with \(s.myCount). Team: \(s.teamTotal). 😼" }
        else { l = "Team shipped \(s.teamTotal) today. \(top.login) leads with \(top.n)." }
        if !fresh(l) { return false }
        lastAmbient = l
        say(l, .calm, seconds: 7, kind: .ambient, pose: .trophy)
        return true
    }

    private func recap() {
        let s = stats
        let q = ["Which merge would you undo?", "What would tomorrow-you want you to stop doing now?", "What did you learn today that you didn't know this morning?"].randomElement()!
        say("Day so far: \(s.merged) merged, \(s.opened) opened, \(s.prompts) prompts.\n\(q)", .calm, seconds: 12, kind: .thought, pose: .thinking)
    }

    // MARK: your day (every 30 s): breaks, juggling, hard stop

    func dayCare() {
        let now = Date()
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle < 300 {   // counts as working: active in the last 5 min. This runs every 30 s, so add 30 s.
            let k = "bit.\(Day.key).active", v = UserDefaults.standard.double(forKey: k) + 30
            UserDefaults.standard.set(v, forKey: k); workedToday = v
        }
        if idle >= 300 { workingSince = nil; return }   // a 5-min break resets the clock; nobody to talk to anyway
        if workingSince == nil { workingSince = now }
        life = loadLife()   // edits to the files apply within 30 s, no restart
        let t = loadTasks(); if t != tasks { tasks = t }
        guard !snoozed, bubble == nil, !showCard, !micInUse() else { return }   // mic on = you're in a call
        if lifeNudge(now) { return }

        // break nudge: 90 min straight (buddy.json "breakMins"), then every 30 min until you take one
        if now.timeIntervalSince(workingSince!) >= Double(config["breakMins"] as? Int ?? 90) * 60, now.timeIntervalSince(lastBreakNudge) >= 30 * 60 {
            lastBreakNudge = now
            doGesture(.stretch)
            say("\(ago(now.timeIntervalSince(workingSince!))) without a break. 10-minute walk? 🚶", .calm, seconds: 20, kind: .ambient)
            return
        }
        // juggling: too many sessions in flight at once (buddy.json "juggle", default 5)
        let inFlight = working.count + waiting.count + stuck.count
        if inFlight >= (config["juggle"] as? Int ?? 5), now.timeIntervalSince(lastJuggleNudge) >= 60 * 60 {
            lastJuggleNudge = now
            say("You're juggling \(inFlight) sessions. Finish one before starting another?", .calm, seconds: 15, kind: .ambient)
            return
        }
        // hard stop (buddy.json "stop": "20:00"): yawn, list what's open, copy it as a note for tomorrow
        let stop = (life?.stop ?? config["stop"] as? String ?? "20:00").split(separator: ":").compactMap { Int($0) }
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let nowMins = c.hour! * 60 + c.minute!
        if stop.count == 2, nowMins >= stop[0] * 60 + stop[1], nowMins < (minutes(life?.resume) ?? 24 * 60), now.timeIntervalSince(lastStopNudge) >= 45 * 60 {
            lastStopNudge = now
            doGesture(.yawn)
            let open = working + waiting + stuck + yourTurn
            let note = (["Tomorrow, pick up:"] + open.map { "• \($0.repo ?? "?"): \($0.prompt ?? $0.activity ?? "")" }
                        + needsYouPRs.map { "• fix \($0.short): \($0.title)" } + todos.map { "• \($0.text)" }).joined(separator: "\n")
            say("It's past \(stop[0]):\(String(format: "%02d", stop[1])). Time to stop 🌙\n\(open.count) sessions and \(needsYouPRs.count) red PRs still open. Tap to copy a note for tomorrow.",
                .calm, seconds: 25, kind: .event, sound: "Purr") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note, forType: .string)
            }
        }
    }

    // MARK: sessions (every 2 s)

    func loadSessions() {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        var out: [Session] = []
        for f in (try? fm.contentsOfDirectory(atPath: sessionsDir)) ?? [] where f.hasSuffix(".json") {
            let p = (sessionsDir as NSString).appendingPathComponent(f)
            guard let data = fm.contents(atPath: p), let s = try? JSONDecoder().decode(Session.self, from: data) else { continue }
            if now - s.ts > forgetAfter { try? fm.removeItem(atPath: p); continue }
            out.append(s)
        }
        // Codex threads with no typed prompt (automations like "Guardian review") show their thread title
        if out.contains(where: { $0.prompt == nil && $0.id.hasPrefix("codex-") }) {
            let titles = codexTitles()
            for i in out.indices where out[i].prompt == nil && out[i].id.hasPrefix("codex-") { out[i].prompt = titles[String(out[i].id.dropFirst(6))] }
        }
        out.sort { $0.ts > $1.ts }
        readInbox(out)
        for s in out {
            let prev = lastStates[s.id]
            let name = s.repo ?? "A session"
            if prev != nil, prev != s.state {
                if s.state == "waiting" {
                    say("\((s.source ?? "").hasPrefix("codex") ? "◆ " : "")\(name) wants your OK\n\(s.activity ?? "")", .waiting, seconds: 25, action: { activate(s) })
                } else if s.state == "finished", prev == "working" {
                    let took = s.turnStart.map { " in \(ago(now - $0))" } ?? ""
                    let mark = (s.source ?? "").hasPrefix("codex") ? "◆ " : ""
                    say("\(mark)\(name) is done\(took). Tap to open ✨\n\(s.said ?? s.prompt ?? "")", .happy, seconds: 15, sound: "Pop", action: { activate(s) })
                }
            }
            lastStates[s.id] = s.state
        }
        if out != sessions { sessions = out }   // publishing redraws everything; only when something changed
    }

    // MARK: PRs (every 2 min)

    func loadPRs() {
        DispatchQueue.global().async {
            let q = "query{viewer{pullRequests(states:OPEN,first:100,orderBy:{field:UPDATED_AT,direction:DESC}){nodes{number title url body isDraft updatedAt headRefName headRefOid repository{nameWithOwner} commits(last:1){nodes{commit{statusCheckRollup{state contexts(first:60){nodes{__typename ... on CheckRun{name conclusion} ... on StatusContext{context state}}}}}}}}}}}"
            guard let data = gh(["api", "graphql", "-f", "query=\(q)"]),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let nodes = ((((root["data"] as? [String: Any])?["viewer"] as? [String: Any])?["pullRequests"] as? [String: Any])?["nodes"] as? [[String: Any]])
            else { return }
            let bad: Set<String> = ["FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "ERROR"]
            let iso = ISO8601DateFormatter()
            let prs: [PR] = nodes.compactMap { n in
                guard let num = n["number"] as? Int, let title = n["title"] as? String, let url = n["url"] as? String,
                      let repo = (n["repository"] as? [String: Any])?["nameWithOwner"] as? String else { return nil }
                let rollup = ((((n["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any])
                let state = rollup?["state"] as? String ?? "NONE"
                let ctx = ((rollup?["contexts"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
                let failing = ctx.compactMap { c -> String? in
                    let r = (c["conclusion"] as? String) ?? (c["state"] as? String) ?? ""
                    return bad.contains(r) ? ((c["name"] as? String) ?? (c["context"] as? String)) : nil
                }
                let ci = (state == "FAILURE" || state == "ERROR") ? "red" : state == "SUCCESS" ? "green" : state == "NONE" ? "none" : "pending"
                return PR(repo: repo, number: num, title: title, url: url, branch: n["headRefName"] as? String ?? "",
                          sha: n["headRefOid"] as? String ?? "", body: n["body"] as? String ?? "", ci: ci,
                          failing: failing, isDraft: n["isDraft"] as? Bool ?? false,
                          updated: iso.date(from: n["updatedAt"] as? String ?? "") ?? .distantPast)
            }
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            let mq = "query{search(query:\"is:pr author:@me is:merged merged:>=\(fmt.string(from: Date()))\",type:ISSUE){issueCount}}"
            let merged = gh(["api", "graphql", "-f", "query=\(mq)"])
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { (($0["data"] as? [String: Any])?["search"] as? [String: Any])?["issueCount"] as? Int }
            DispatchQueue.main.async { self.apply(prs, merged: merged) }
        }
    }

    private func apply(_ new: [PR], merged: Int?) {
        let first = prsCheckedAt == nil
        for pr in new where pr.recent {
            let prev = lastCI[pr.id]
            if !first, prev != pr.ci {
                if pr.needsYou {
                    say("Oh no, \(pr.short) broke\nhover me to see why", .upset, seconds: 30)
                } else if pr.ci == "green", prev == "red" || prev == "pending" {
                    say("\(pr.short) is green ✨", .happy, seconds: 8) { NSWorkspace.shared.open(URL(string: pr.url)!) }
                }
            }
            lastCI[pr.id] = pr.ci
        }
        if let merged = merged {
            if !first, merged > mergedToday { say("Merged! That's \(merged) today 🏆", .happy, seconds: 8) }
            mergedToday = merged
        }
        prs = new
        prsCheckedAt = Date()
        enrich()
        if first {
            if let p = needsYouPRs.first {
                say("\(p.short) needs a fix\nhover me to see why", .upset, seconds: 14)
            } else if mergedToday > 0 {
                say("Hi! \(mergedToday) merged today 🏆", .happy, seconds: 8)
            }
        }
    }

    /// For each PR that needs you: why it failed, and which past session worked on it. Once per commit.
    private func enrich() {
        for pr in needsYouPRs where detailFor[pr.id] != pr.sha {
            detailFor[pr.id] = pr.sha
            DispatchQueue.global().async {
                let d = Detail(why: findWhy(pr), session: findSession(branch: pr.branch) ?? findCodexSession(branch: pr.branch, sha: pr.sha))
                DispatchQueue.main.async { self.details[pr.id] = d }
            }
        }
    }

    // MARK: actions

    func fixPrompt(_ pr: PR) -> String {
        let why = details[pr.id]?.why.map { "The failing check says: \($0)" } ?? "Failing checks: \(pr.failing.joined(separator: ", "))."
        return "CI is failing on PR \(pr.url) (branch \(pr.branch)). \(why) Find the cause, fix it, run that check locally, and push."
    }

    /// Reopen the session that worked on this PR, in Terminal, with the failure as its next prompt.
    func continueSession(_ pr: PR) {
        guard let s = details[pr.id]?.session else { return }
        guard FileManager.default.fileExists(atPath: s.cwd) else {
            copy(fixPrompt(pr)); say("That session's folder is gone\nI copied the fix prompt instead 📋", .waiting, seconds: 8); return
        }
        let tag = UUID().uuidString.prefix(8)
        let promptFile = "/tmp/bit-prompt-\(tag).txt", script = "/tmp/bit-continue-\(tag).sh"
        try? fixPrompt(pr).write(toFile: promptFile, atomically: true, encoding: .utf8)
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let tool = s.codex ? "\(tool("codex")) resume" : "\(tool("claude")) --resume"
        let body = "#!/bin/bash\ncd \(q(s.cwd)) || exit 1\nexec \(tool) \(s.id) \"$(cat \(promptFile))\"\n"
        try? body.write(toFile: script, atomically: true, encoding: .utf8)
        let osa = "tell application \"Terminal\"\n do script \"bash \(script)\"\n activate\nend tell"
        DispatchQueue.global().async { run("/usr/bin/osascript", ["-e", osa]) }
        say("Reopening that session in Terminal 🐾", .happy, seconds: 5)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func rerunFailed(_ pr: PR) {
        busyAction = pr.id
        DispatchQueue.global().async {
            var n = 0
            if let data = gh(["run", "list", "--repo", pr.repo, "--branch", pr.branch, "-L", "30", "--json", "databaseId,conclusion"]),
               let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for r in runs where ["failure", "timed_out"].contains(r["conclusion"] as? String ?? "") {
                    if let id = r["databaseId"] as? Int, gh(["run", "rerun", "\(id)", "--failed", "--repo", pr.repo]) != nil { n += 1 }
                }
            }
            DispatchQueue.main.async {
                self.busyAction = nil
                self.say(n > 0 ? "Rerunning \(n) failed run\(n == 1 ? "" : "s") on \(pr.short) 🔁" : "Nothing to rerun on \(pr.short)", n > 0 ? .busy : .waiting, seconds: 6)
            }
        }
    }

    func toggleSnooze() {
        snoozedUntil = snoozed ? nil : Date().addingTimeInterval(3600)
        if snoozed { bubble = nil }
        onExpandChange?()
    }
}

// MARK: the cat

extension Mood {
    var color: Color {
        switch self {
        case .asleep: return Color(red: 0.55, green: 0.58, blue: 0.66)
        case .calm: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .busy: return Color(red: 0.36, green: 0.62, blue: 0.98)
        case .waiting: return Color(red: 0.96, green: 0.72, blue: 0.27)
        case .upset: return Color(red: 0.94, green: 0.33, blue: 0.33)
        case .happy: return Color(red: 0.36, green: 0.82, blue: 0.55)
        }
    }
    var word: String {
        switch self {
        case .asleep: return "napping"
        case .calm: return "chilling"
        case .busy: return "watching your sessions"
        case .waiting: return "waiting on you"
        case .upset: return "worried"
        case .happy: return "happy"
        }
    }
}

let fur = Color(red: 0.89, green: 0.55, blue: 0.36)
let claudeColor = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)   // Anthropic clay
let codexColor = Color(red: 16 / 255, green: 163 / 255, blue: 127 / 255)    // OpenAI green

let furDark = Color(red: 0.72, green: 0.40, blue: 0.25)
let ink = Color(red: 0.16, green: 0.11, blue: 0.10)

struct Breed {
    var name: String
    var fur: Color, dark: Color, belly: Color
    var eye: Color = ink
    var points: Color? = nil      // siamese: darker ears, mask, tail, paws
    var patch: [Color] = []       // calico patches
    var stripes = false
    var mask: Color? = nil        // pug: black face
}
func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
let pugCoats: [Breed] = [
    Breed(name: "Fawn pug", fur: rgb(226, 190, 140), dark: rgb(70, 56, 48), belly: rgb(240, 214, 176), mask: rgb(40, 32, 30)),
    Breed(name: "Black pug", fur: rgb(40, 38, 40), dark: rgb(18, 18, 20), belly: rgb(58, 56, 58), eye: rgb(120, 80, 50), mask: rgb(14, 14, 16)),
    Breed(name: "Apricot pug", fur: rgb(222, 162, 100), dark: rgb(80, 54, 40), belly: rgb(240, 200, 150), mask: rgb(44, 32, 28)),
    Breed(name: "Silver pug", fur: rgb(200, 196, 188), dark: rgb(70, 68, 66), belly: rgb(226, 222, 214), mask: rgb(36, 34, 34)),
]
let catBreeds: [Breed] = [
    Breed(name: "Ginger tabby", fur: rgb(227, 140, 92), dark: rgb(184, 102, 64), belly: rgb(250, 226, 205), stripes: true),
    Breed(name: "Tuxedo", fur: rgb(38, 38, 44), dark: rgb(20, 20, 24), belly: .white, eye: rgb(170, 220, 90)),
    Breed(name: "Snowball", fur: rgb(246, 244, 240), dark: rgb(214, 210, 204), belly: .white, eye: rgb(70, 140, 220)),
    Breed(name: "Russian Blue", fur: rgb(132, 146, 166), dark: rgb(100, 112, 130), belly: rgb(170, 182, 200), eye: rgb(120, 200, 110)),
    Breed(name: "Siamese", fur: rgb(240, 226, 204), dark: rgb(205, 190, 168), belly: rgb(252, 245, 232), eye: rgb(60, 130, 220), points: rgb(92, 64, 50)),
    Breed(name: "Calico", fur: rgb(250, 247, 240), dark: rgb(220, 214, 204), belly: .white, patch: [rgb(222, 130, 60), rgb(48, 40, 38)]),
    Breed(name: "Midnight", fur: rgb(22, 22, 28), dark: rgb(10, 10, 14), belly: rgb(40, 40, 48), eye: rgb(250, 205, 60)),
]

/// Bears reuse `points` for panda black (ears, legs, eye patches).
let bearCoats: [Breed] = [
    Breed(name: "Grizzly", fur: rgb(140, 98, 66), dark: rgb(96, 64, 42), belly: rgb(196, 160, 120)),
    Breed(name: "Black bear", fur: rgb(36, 32, 32), dark: rgb(18, 16, 16), belly: rgb(170, 130, 96), eye: rgb(150, 100, 60)),
    Breed(name: "Polar bear", fur: rgb(246, 244, 236), dark: rgb(214, 210, 198), belly: rgb(255, 253, 246)),
    Breed(name: "Panda", fur: rgb(248, 248, 244), dark: rgb(214, 214, 210), belly: .white, points: rgb(28, 28, 30)),
]

// after all three arrays: top-level globals initialise in file order
var breeds: [Breed] { isBear ? bearCoats : isPug ? pugCoats : catBreeds }

enum Gesture: CaseIterable { case none, stretch, yawn, spin, wash, loaf, sneeze, zoomies, knock, hop, shimmy, roar, honey, fish, scratch }

struct Particle: Identifiable { let id = UUID(); let glyph: String; let dx: CGFloat; var fall = false }

struct FloatUp: View {
    let p: Particle
    @State private var gone = false
    var body: some View {
        Text(p.glyph).font(.system(size: p.glyph.count > 2 ? 11 : 14, weight: .heavy, design: .rounded)).foregroundColor(.white).shadow(radius: 1)
            .rotationEffect(.degrees(p.fall && gone ? 160 : 0))
            .offset(x: p.dx + (p.fall && gone ? 18 : 0), y: p.fall ? (gone ? 60 : 30) : (gone ? -60 : -10))
            .opacity(gone ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.3)) { gone = true } }
    }
}

struct Tri: Shape {
    var a: CGPoint, b: CGPoint, c: CGPoint
    func path(in r: CGRect) -> Path { Path { $0.move(to: a); $0.addLine(to: b); $0.addLine(to: c); $0.closeSubpath() } }
}

struct TailShape: Shape {
    var curl: CGFloat
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 20, y: 50))
            p.addQuadCurve(to: CGPoint(x: 6 - curl * 4, y: 22 + curl * 18), control: CGPoint(x: 0, y: 50))
        }
    }
}

/// Bit, drawn facing right in an 84×72 box. The view flips it to face left.
struct Cat: View {
    @ObservedObject var m: Model
    @State private var wobble: CGFloat = 0
    @State private var jump: CGFloat = 0
    @State private var particles: [Particle] = []

    var b: Breed { m.breed }
    var dark: Bool { b.name == "Tuxedo" || b.name == "Midnight" || b.name == "Black pug" || b.name == "Black bear" }
    var faceInk: Color { dark ? Color.white : ink }
    var mood: Mood { m.squatting ? .asleep : (m.hovering && m.mood == .asleep && !m.snoozed ? .calm : m.mood) }

    var body: some View {
        TimelineView(.animation(minimumInterval: m.walking || m.zoomies || m.gesture != .none || m.hovering ? 1.0 / 30 : 1.0)) { t in   // 1 fps when idle: 7.6% → 3% CPU, measured
            let s = t.date.timeIntervalSinceReferenceDate
            let asleep = mood == .asleep
            let breathe = 1 + (asleep ? 0.05 : 0.025) * sin(s * (asleep ? 1.4 : 2.4))
            let step = m.walking ? sin(s * 12) : 0
            let wagSpeed: Double = m.hovering ? 9 : mood == .busy ? 4 : mood == .upset ? 14 : 2
            let wag = asleep ? 0 : sin(s * wagSpeed) * (m.hovering ? 16 : 9)
            let blink = !asleep && Int(s * 10) % 37 == 0
            let g = m.gesture, gt = Date().timeIntervalSince(m.gestureAt)
            let k = g == .stretch ? sin(min(gt / 2.4, 1) * .pi) : 0
            let loaf = g == .loaf
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if isBear {
                        Circle().fill(b.points ?? b.dark).frame(width: 9, height: 9).position(x: 13, y: 46 + wag * 0.08)   // stub tail
                    } else if isPug {
                        Circle().trim(from: 0, to: 0.8).stroke(b.fur, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 11, height: 11).rotationEffect(.degrees(wag * 2)).position(x: 13, y: 40)
                    } else {
                        TailShape(curl: asleep ? 1 : 0)
                            .stroke(b.points ?? b.fur, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(wag), anchor: UnitPoint(x: 20 / 84, y: 50 / 72))
                    }
                    ForEach(0..<4) { i in
                        let y = asleep ? 64 : 63 + (i % 2 == 0 ? step : -step) * 2
                        Capsule().fill(drip ? ink : (b.points ?? (i % 2 == 0 ? b.dark : b.fur))).frame(width: isBear ? 10 : 7, height: asleep || loaf ? 4 : 12)
                            .position(x: [22, 32, 46, 56][i], y: y)
                        if drip && !asleep && !loaf {   // sneakers
                            Capsule().fill(Color.white).frame(width: 9, height: 4.5).overlay(Capsule().fill(ink).frame(width: 4, height: 1.1))
                                .position(x: [23, 33, 47, 57][i], y: y + 4.5)
                        }
                    }
                    Ellipse().fill(drip ? ink : b.fur).frame(width: isBear ? 60 : 54, height: asleep ? (isBear ? 30 : 26) : (isBear ? 35 : 30))
                        .scaleEffect(y: breathe, anchor: .bottom)
                        .position(x: 38, y: asleep ? 54 : 50)
                    if drip {
                        // tracksuit: two white stripes down the side, white waistband, white hood round the neck
                        ForEach(0..<2) { i in Capsule().fill(Color.white).frame(width: 30, height: 1.6).rotationEffect(.degrees(-8)).position(x: 34, y: (asleep ? 47 : 43) + CGFloat(i) * 4) }
                        Capsule().fill(Color.white).frame(width: 34, height: 3).position(x: 40, y: asleep ? 63 : 62)
                        ForEach([55.0, 63.0], id: \.self) { x in Capsule().fill(Color.white).frame(width: 1.6, height: 8).position(x: x, y: asleep ? 60 : 54) }   // hoodie strings
                    } else {
                        markings(asleep: asleep)
                        Ellipse().fill(b.belly.opacity(0.85)).frame(width: 26, height: 10).position(x: 46, y: asleep ? 60 : 58)
                    }
                    ZStack {
                        head(s: s, blink: blink, asleep: asleep)
                        poseLayer
                    }
                    .rotationEffect(.degrees(m.pose == .thinking ? -9 : 0), anchor: UnitPoint(x: 0.7, y: 0.6))
                    .offset(y: asleep ? 10 : 0)
                }
                .frame(width: 84, height: 72)
                .shadow(color: .black.opacity(0.45), radius: 0.8)   // outline, so white cats show on white pages
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                .scaleEffect(x: 1 + 0.24 * k, y: 1 - 0.16 * k, anchor: .bottom)
                .offset(y: loaf ? 4 : 0)
                .rotationEffect(.degrees(g == .spin && gt < 1 ? gt * 360 : 0))
                .offset(y: g == .sneeze && gt > 0.7 && gt < 0.9 ? -8 : 0)
                .offset(x: g == .shimmy ? sin(gt * 16) * 3 : 0, y: g == .shimmy ? -abs(sin(gt * 8)) * 3 : 0)
                .rotationEffect(.degrees(g == .shimmy ? sin(gt * 8) * 6 : 0), anchor: .bottom)
                .rotationEffect(.degrees(g == .roar ? -16 * sin(min(gt / 1.8, 1) * .pi) : 0), anchor: UnitPoint(x: 0.3, y: 1))
                .offset(x: g == .scratch ? sin(gt * 6) * 2.5 : 0, y: g == .scratch ? -abs(sin(gt * 6)) * 2 : 0)
                .rotationEffect(.degrees(g == .scratch ? sin(gt * 6) * 4 : 0), anchor: .bottom)
                .scaleEffect(x: m.facingLeft ? -1 : 1, y: 1)
                accessory(s: s).frame(width: 84, height: 20).offset(y: -22)
                if m.badge > 0 && !m.snoozed {
                    Text("\(m.badge)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16).background(Circle().fill(Color.red))
                        .offset(x: 2, y: -2)
                }
                ForEach(particles) { FloatUp(p: $0).frame(width: 84) }
            }
            .offset(x: wobble, y: jump + (m.walking ? -abs(step) * 1.5 : 0))
        }
        .frame(width: 84, height: 72)
        .onChange(of: m.shake) { _ in
            withAnimation(.easeInOut(duration: 0.06).repeatCount(7, autoreverses: true)) { wobble = 5 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { wobble = 0 }
        }
        .onChange(of: m.celebrate) { _ in
            burst(["✨", "🎉", "✨", "⭐️"])
            withAnimation(.spring(response: 0.25, dampingFraction: 0.35)) { jump = -22 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { jump = 0 } }
        }
        .onChange(of: m.hearts) { _ in burst(["💖", "💗", "💖"]) }
        .onChange(of: m.gesture) { g in
            switch g {
            case .sneeze: DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { burst(["achoo!"]) }
            case .knock: burst(["🥛"], fall: true)
            case .zoomies: burst(["💨", "💨"])
            case .spin: burst(["🌀"])
            case .yawn: burst(["yawn"])
            case .wash: burst(["lick lick"])
            case .loaf: burst(["🍞"])
            case .shimmy: burst(["🎵", "🎶"])
            case .roar: burst(["ROAR!"]); shakeSoon()
            case .honey: burst(["🍯", "yum"])
            case .fish: DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burst(["🐟", "💦"]) }
            case .scratch: burst(["scritch"])
            default: break
            }
        }
    }

    @ViewBuilder func markings(asleep: Bool) -> some View {
        let y: CGFloat = asleep ? 54 : 50
        if b.stripes {
            ForEach(0..<3) { i in Capsule().fill(b.dark).frame(width: 4, height: 13).rotationEffect(.degrees(-12)).position(x: 26 + CGFloat(i) * 9, y: y - 6) }
        }
        if b.patch.count == 2 {
            Ellipse().fill(b.patch[0]).frame(width: 20, height: 14).position(x: 28, y: y - 4)
            Ellipse().fill(b.patch[1]).frame(width: 14, height: 11).position(x: 44, y: y - 8)
        }
    }

    @ViewBuilder func head(s: Double, blink: Bool, asleep: Bool) -> some View {
        let look = lookVector()
        if isBear { bearHead(s: s, blink: blink, asleep: asleep, look: look) } else if isPug { pugHead(blink: blink, asleep: asleep, look: look) } else {
        ZStack {
            Tri(a: CGPoint(x: 45, y: 24), b: CGPoint(x: 47, y: 6), c: CGPoint(x: 58, y: 18)).fill(b.fur)
            Tri(a: CGPoint(x: 62, y: 17), b: CGPoint(x: 73, y: 5), c: CGPoint(x: 74, y: 24)).fill(b.fur)
            Tri(a: CGPoint(x: 48, y: 20), b: CGPoint(x: 49, y: 11), c: CGPoint(x: 55, y: 17)).fill(Color.pink.opacity(0.7))
            Tri(a: CGPoint(x: 65, y: 16), b: CGPoint(x: 71, y: 10), c: CGPoint(x: 71, y: 20)).fill(Color.pink.opacity(0.7))
            Circle().fill(b.fur).frame(width: 38, height: 36).position(x: 60, y: 32)
            if let pt = b.points {
                Ellipse().fill(pt.opacity(0.85)).frame(width: 22, height: 18).position(x: 60, y: 38)
                Tri(a: CGPoint(x: 46, y: 22), b: CGPoint(x: 47, y: 7), c: CGPoint(x: 56, y: 17)).fill(pt)
                Tri(a: CGPoint(x: 64, y: 17), b: CGPoint(x: 73, y: 6), c: CGPoint(x: 73, y: 22)).fill(pt)
            }
            if b.patch.count == 2 { Circle().fill(b.patch[0]).frame(width: 16).position(x: 69, y: 24).clipShape(Circle().size(width: 84, height: 72)) }
            if b.name == "Tuxedo" { Ellipse().fill(Color.white).frame(width: 16, height: 12).position(x: 60, y: 42) }
            Capsule().fill(b.dark).frame(width: 3, height: 8).position(x: 60, y: 18)
            if m.hovering && mood != .upset {
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 47, y: 38)
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 73, y: 38)
            }
            eyes(blink: blink, asleep: asleep, look: look)
            Tri(a: CGPoint(x: 58, y: 37), b: CGPoint(x: 62, y: 37), c: CGPoint(x: 60, y: 40)).fill(Color.pink)
            mouth
            Path { p in
                for (y, dy) in [(39.0, -2.0), (42.0, 1.0)] {
                    p.move(to: CGPoint(x: 48, y: y)); p.addLine(to: CGPoint(x: 38, y: y + dy))
                    p.move(to: CGPoint(x: 72, y: y)); p.addLine(to: CGPoint(x: 82, y: y + dy))
                }
            }.stroke(faceInk.opacity(0.35), lineWidth: 0.8)
        }
        }
    }

    /// A pug: round head, folded black ears, black mask, forehead wrinkles, flat nose.
    @ViewBuilder func pugHead(blink: Bool, asleep: Bool, look: CGSize) -> some View {
        let mask = b.mask ?? ink
        ZStack {
            Ellipse().fill(b.fur).frame(width: 42, height: 36).position(x: 60, y: 32)
            Tri(a: CGPoint(x: 41, y: 18), b: CGPoint(x: 51, y: 14), c: CGPoint(x: 43, y: 29)).fill(mask)
            Tri(a: CGPoint(x: 69, y: 14), b: CGPoint(x: 79, y: 18), c: CGPoint(x: 77, y: 29)).fill(mask)
            ForEach(0..<2) { i in
                Path { p in p.move(to: CGPoint(x: 54, y: 21 + CGFloat(i) * 3)); p.addQuadCurve(to: CGPoint(x: 66, y: 21 + CGFloat(i) * 3), control: CGPoint(x: 60, y: 18 + CGFloat(i) * 3)) }
                    .stroke(mask.opacity(0.55), lineWidth: 1.1)
            }
            Ellipse().fill(mask).frame(width: 24, height: 17).position(x: 60, y: 40)
            if m.hovering && mood != .upset {
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 46, y: 37)
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 74, y: 37)
            }
            if drip && !asleep {
                ForEach([52.5, 67.5], id: \.self) { x in
                    RoundedRectangle(cornerRadius: 3.5).fill(Color.black).frame(width: 13, height: 9).position(x: x, y: 31)
                    Capsule().fill(Color.white.opacity(0.55)).frame(width: 4, height: 1.3).rotationEffect(.degrees(-25)).position(x: x - 2.5, y: 29)
                }
                Capsule().fill(Color.black).frame(width: 5, height: 1.8).position(x: 60, y: 29.5)
            } else {
                eyes(blink: blink, asleep: asleep, look: look)
            }
            Ellipse().fill(Color.black).frame(width: 9, height: 5).position(x: 60, y: 37)
            if mood == .happy || m.hovering {
                Capsule().fill(Color(red: 0.95, green: 0.45, blue: 0.55)).frame(width: 5, height: 7).position(x: 61, y: 46)   // tongue out
            }
            mouth
        }
    }

    /// A bear: round ears, broad head, pale muzzle, big nose. Panda: black ears and eye patches.
    @ViewBuilder func bearHead(s: Double, blink: Bool, asleep: Bool, look: CGSize) -> some View {
        let ear = b.points ?? b.fur
        ZStack {
            ForEach([45.0, 75.0], id: \.self) { x in
                Circle().fill(ear).frame(width: 15, height: 15).position(x: x, y: 17)
                Circle().fill(b.points == nil ? b.dark : ear).frame(width: 7, height: 7).position(x: x, y: 18)
            }
            Ellipse().fill(b.fur).frame(width: 42, height: 37).position(x: 60, y: 32)
            if let pt = b.points {
                Ellipse().fill(pt).frame(width: 11, height: 13).rotationEffect(.degrees(-25)).position(x: 52, y: 31)
                Ellipse().fill(pt).frame(width: 11, height: 13).rotationEffect(.degrees(25)).position(x: 68, y: 31)
            }
            Ellipse().fill(b.belly).frame(width: 20, height: 14).position(x: 60, y: 41)
            if m.hovering && mood != .upset {
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 45, y: 38)
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 75, y: 38)
            }
            if b.points != nil && !asleep && !blink {
                // panda eyes sit inside the patches, so draw them light
                ForEach([53.0, 67.0], id: \.self) { x in Circle().fill(Color.white).frame(width: 4.5).overlay(Circle().fill(ink).frame(width: 2.5)).position(x: x, y: 31).offset(look) }
            } else {
                eyes(blink: blink, asleep: asleep, look: look)
            }
            Ellipse().fill(ink).frame(width: 9, height: 6).position(x: 60, y: 37)
            Capsule().fill(Color.white.opacity(0.5)).frame(width: 3, height: 1.2).position(x: 58, y: 35.6)
            if m.gesture == .roar {
                // jaws wide, two fangs
                Ellipse().fill(ink).overlay(Ellipse().fill(Color(red: 0.85, green: 0.35, blue: 0.4)).frame(width: 7, height: 4).offset(y: 3))
                    .frame(width: 12, height: 11).position(x: 60, y: 46)
                Tri(a: CGPoint(x: 55.5, y: 41.5), b: CGPoint(x: 58, y: 41.5), c: CGPoint(x: 56.8, y: 45)).fill(Color.white)
                Tri(a: CGPoint(x: 62, y: 41.5), b: CGPoint(x: 64.5, y: 41.5), c: CGPoint(x: 63.2, y: 45)).fill(Color.white)
            } else if m.gesture == .honey {
                Text("🍯").font(.system(size: 12)).position(x: 72, y: 50 + sin(s * 10) * 1.5)
                Capsule().fill(Color(red: 0.95, green: 0.45, blue: 0.55)).frame(width: 5, height: 5 + abs(sin(s * 10)) * 3).position(x: 61, y: 45)
            } else if m.gesture == .fish {
                // a paw swipes up through the river
                let gt = Date().timeIntervalSince(m.gestureAt)
                Ellipse().fill(b.points ?? b.dark).frame(width: 11, height: 9)
                    .position(x: 76, y: 58 - 22 * sin(min(gt / 0.9, 1) * .pi))
                moodMouth
            } else {
                mouth
            }
        }
    }

    /// Props for what Bit is saying: glasses for quotes, paw-on-chin for questions, trophy, flex, and a crown while #1.
    @ViewBuilder var poseLayer: some View {
        ZStack {
            if m.stats.rank == 1 && m.mood != .asleep {
                Text("👑").font(.system(size: 13, design: .rounded)).position(x: 60, y: 6)
            }
            switch m.pose {
            case .glasses where !drip:
                Group {
                    Circle().stroke(ink, lineWidth: 1.6).frame(width: 11, height: 11).position(x: 53, y: 31)
                    Circle().stroke(ink, lineWidth: 1.6).frame(width: 11, height: 11).position(x: 67, y: 31)
                    Path { p in p.move(to: CGPoint(x: 58.5, y: 30)); p.addLine(to: CGPoint(x: 61.5, y: 30)) }.stroke(ink, lineWidth: 1.4)
                }
            case .thinking:
                Ellipse().fill(b.dark).frame(width: 9, height: 7).position(x: 64, y: 50)
            case .trophy:
                Text("🏆").font(.system(size: 14, design: .rounded)).position(x: 80, y: 46)
            case .flex:
                Text("💪").font(.system(size: 14, design: .rounded)).position(x: 82, y: 40)
            case .none, .glasses:
                EmptyView()
            }
        }
    }

    @ViewBuilder var mouth: some View {
        if m.gesture == .yawn {
            Ellipse().fill(ink).overlay(Ellipse().fill(Color.pink).frame(width: 4, height: 3).offset(y: 2)).frame(width: 7, height: 9).position(x: 60, y: 45)
        } else if m.gesture == .wash {
            TimelineView(.animation) { t in
                Ellipse().fill(b.points ?? b.fur).overlay(Ellipse().stroke(b.dark, lineWidth: 1))
                    .frame(width: 10, height: 8).position(x: 61, y: 44 + sin(t.date.timeIntervalSinceReferenceDate * 14) * 2)
            }
        } else {
            moodMouth
        }
    }

    @ViewBuilder var moodMouth: some View {
        switch mood {
        case .upset:
            Circle().trim(from: 0.55, to: 0.95).stroke(ink.opacity(0.7), lineWidth: 1.6).frame(width: 9, height: 9).position(x: 60, y: 46)
        case .happy:
            Circle().trim(from: 0.05, to: 0.45).fill(ink.opacity(0.8)).frame(width: 10, height: 10).position(x: 60, y: 39)
        case .waiting:
            Circle().stroke(ink.opacity(0.7), lineWidth: 1.4).frame(width: 4, height: 4).position(x: 60, y: 44)
        default:
            Path { p in
                p.move(to: CGPoint(x: 56, y: 41)); p.addQuadCurve(to: CGPoint(x: 60, y: 41), control: CGPoint(x: 58, y: 44))
                p.addQuadCurve(to: CGPoint(x: 64, y: 41), control: CGPoint(x: 62, y: 44))
            }.stroke(faceInk.opacity(0.7), lineWidth: 1.3)
        }
    }

    @ViewBuilder func eyes(blink: Bool, asleep: Bool, look: CGSize) -> some View {
        if asleep || (m.hovering && mood == .calm) || m.gesture == .yawn || m.gesture == .wash {
            ForEach([53.0, 67.0], id: \.self) { x in
                Circle().trim(from: asleep ? 0.05 : 0.55, to: asleep ? 0.45 : 0.95)
                    .stroke(faceInk.opacity(0.8), lineWidth: 1.8).frame(width: 8, height: 8).position(x: x, y: 31)
            }
        } else if mood == .happy {
            ForEach([53.0, 67.0], id: \.self) { x in
                Circle().trim(from: 0.55, to: 0.95).stroke(faceInk.opacity(0.85), lineWidth: 2.2).frame(width: 9, height: 9).position(x: x, y: 33)
            }
        } else {
            let big = mood == .waiting || mood == .upset
            ForEach([53.0, 67.0], id: \.self) { x in
                ZStack {
                    Ellipse().fill(b.eye == ink ? ink : b.eye).overlay(Ellipse().fill(ink).frame(width: 3)).frame(width: big ? 9 : 7.5, height: blink ? 1.5 : (big ? 11 : 9))
                    if !blink { Circle().fill(Color.white).frame(width: 3).offset(x: 1.2, y: -2) }
                }
                .position(x: x, y: 31).offset(look)
            }
        }
    }

    @ViewBuilder func accessory(s: Double) -> some View {
        let bob = sin(s * 5) * 2
        switch mood {
        case .upset:
            Text("!").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Mood.upset.color)).offset(x: m.facingLeft ? -18 : 18, y: bob)
        case .waiting:
            Text("?").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(ink)
                .frame(width: 18, height: 18).background(Circle().fill(Mood.waiting.color)).offset(x: m.facingLeft ? -18 : 18, y: bob)
        case .busy:
            HStack(spacing: 3) {
                ForEach(0..<3) { i in Circle().fill(Mood.busy.color).frame(width: 5).opacity(Int(s * 3) % 3 == i ? 1 : 0.35) }
            }
            .padding(.horizontal, 6).padding(.vertical, 4).background(Capsule().fill(Color.white.opacity(0.9)))
            .offset(x: m.facingLeft ? -16 : 16)
        case .asleep:
            Text("z z").font(.system(size: 10 + CGFloat(Int(s) % 3), weight: .heavy)).foregroundColor(.white.opacity(0.9))
                .shadow(radius: 1).offset(x: m.facingLeft ? -22 : 22, y: -CGFloat(Int(s) % 3) * 2)
        default: EmptyView()
        }
    }

    /// The roar lands a beat after the bear rears up.
    func shakeSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.05).repeatCount(9, autoreverses: true)) { wobble = 3 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { wobble = 0 }
        }
    }

    func burst(_ glyphs: [String], fall: Bool = false) {
        let new = glyphs.enumerated().map { Particle(glyph: $1, dx: CGFloat($0 - glyphs.count / 2) * 14 + (fall ? 26 : 0), fall: fall) }
        particles += new
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { particles.removeAll { p in new.contains { $0.id == p.id } } }
    }

    /// Eyes follow the mouse anywhere on screen.
    func lookVector() -> CGSize {
        let mouse = NSEvent.mouseLocation
        let c = blobCenter()
        let dx = (mouse.x - c.x) * (m.facingLeft ? -1 : 1), dy = mouse.y - c.y
        let d = max(1, sqrt(dx * dx + dy * dy))
        let k = min(1, d / 200) * 2.5
        return CGSize(width: dx / d * k, height: -dy / d * k)
    }
}

// MARK: card


// MARK: themes: right-click → Theme. Burrow (warm, the pet's world), Glass (frosted macOS), Ink (dark, precise)

func hex(_ v: Int) -> Color { Color(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255) }

struct Theme {
    let name: String
    let fg: Color, sub: Color, accent: Color
    let solid: Color          // bubbles and anything that needs an opaque surface
    let design: Font.Design
    let radius: CGFloat
    let light: Bool
}
let themes: [String: Theme] = [
    "burrow": Theme(name: "burrow", fg: hex(0x3a2a1f), sub: hex(0x8b7363), accent: hex(0xd97757), solid: hex(0xfff8ee),
                    design: .rounded, radius: 28, light: true),
    "glass":  Theme(name: "glass", fg: hex(0x1d1d1f), sub: Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.6), accent: hex(0x007aff),
                    solid: Color(red: 246 / 255, green: 246 / 255, blue: 250 / 255), design: .default, radius: 24, light: true),
    "ink":    Theme(name: "ink", fg: hex(0xededef), sub: hex(0x6b6b73), accent: hex(0x7c7ff2), solid: hex(0x0f0f11),
                    design: .default, radius: 12, light: false),
]
/// The current theme. A global because every card view reads it; Model.themeName republishes on change.
_ = _migrated
var T = themes[UserDefaults.standard.string(forKey: "bit.theme") ?? (config["theme"] as? String ?? "ink")] ?? themes["ink"]!

/// Frosted glass needs the real desktop behind the window, so it is an NSVisualEffectView, not a SwiftUI material.
struct Frost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover; v.blendingMode = .behindWindow; v.state = .active
        v.appearance = NSAppearance(named: .aqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
struct ThemeSurface: View {
    var radius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        switch T.name {
        case "glass": Frost().clipShape(shape).overlay(shape.fill(Color(red: 246 / 255, green: 246 / 255, blue: 250 / 255).opacity(0.58)))
        case "burrow": shape.fill(T.solid).shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        default: shape.fill(T.solid)
        }
    }
}

struct Chip: View {
    var label: String
    var primary = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 10.5, weight: .semibold, design: T.design)).foregroundColor(primary ? .white : T.fg)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: T.radius / 2).fill(primary ? T.accent : T.fg.opacity(0.08)))
        }.buttonStyle(.plain)
    }
}

struct PRBlock: View {
    @ObservedObject var m: Model
    var pr: PR
    var body: some View {
        let d = m.details[pr.id]
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(Mood.upset.color).frame(width: 7, height: 7)
                Text(pr.short).font(.system(size: 11, weight: .bold, design: T.design))
                Text(pr.title).font(.system(size: 11, weight: .semibold, design: T.design)).lineLimit(1)
            }
            label("WHAT IT IS", pr.summary, lines: 2)
            if let why = d?.why {
                label("WHAT BROKE", why, lines: 3, color: Color(red: 1, green: 0.62, blue: 0.62))
            } else {
                label("WHAT BROKE", d == nil ? "reading the CI log…" : "✕ " + pr.failing.joined(separator: " · ✕ "), lines: 2, color: Color(red: 1, green: 0.62, blue: 0.62))
            }
            if let s = d?.session {
                Text("Last worked on in \(s.codex ? "Codex · " : "")\((s.cwd as NSString).lastPathComponent) · \(ago(Date().timeIntervalSince(s.when))) ago")
                    .font(.system(size: 9.5, design: T.design)).foregroundColor(T.sub).lineLimit(1)
            }
            HStack(spacing: 6) {
                if d?.session != nil {
                    Chip(label: "▶ Continue that session", primary: true) { m.continueSession(pr) }
                } else {
                    Chip(label: "Copy fix prompt", primary: true) { m.copy(m.fixPrompt(pr)); m.say("Fix prompt copied 📋", .calm, seconds: 4) }
                }
                Chip(label: "Open PR") { NSWorkspace.shared.open(URL(string: pr.url)!) }
                Chip(label: m.busyAction == pr.id ? "Rerunning…" : "Rerun") { m.rerunFailed(pr) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(T.fg.opacity(0.05)))
    }

    func label(_ k: String, _ v: String, lines: Int, color: Color = T.fg) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 8.5, weight: .bold, design: T.design)).kerning(0.8).foregroundColor(T.sub)
            Text(v).font(.system(size: 11, design: T.design)).foregroundColor(color).lineLimit(lines).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Card: View {
    @ObservedObject var m: Model
    var body: some View {
        Group {
            switch T.name { case "burrow": BurrowCard(m: m); case "glass": GlassCard(m: m); default: InkCard(m: m) }
        }
        .frame(width: m.cardWidth, alignment: .topLeading)
        .overlay(alignment: m.leftSide ? .trailing : .leading) { grip }
        .background(ThemeSurface(radius: T.radius))
        .clipShape(RoundedRectangle(cornerRadius: T.radius))
        .overlay(RoundedRectangle(cornerRadius: T.radius).stroke(T.name == "ink" ? Color.white.opacity(0.08) : T.name == "glass" ? Color.white.opacity(0.55) : hex(0x784f28).opacity(0.12), lineWidth: T.name == "glass" ? 0.5 : 1))
    }

    var grip: some View {
        // drag the card's outer edge to resize; screen coordinates, because the window moves under the cursor as it grows
        ZStack(alignment: .top) {
            Color.clear
            Capsule().fill(T.sub.opacity(0.45)).frame(width: 4, height: 36).padding(.top, 64)
        }
        .frame(width: 12).contentShape(Rectangle())
        .onHover { $0 ? NSCursor.resizeLeftRight.set() : NSCursor.arrow.set() }
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { _ in
                let x = NSEvent.mouseLocation.x
                if m.gripFrom == nil { m.gripFrom = (x, m.cardWidth) }
                let dx = (x - m.gripFrom!.mouse) * (m.leftSide ? 1 : -1)
                m.cardWidth = min(max(m.gripFrom!.width + dx, 300), 900)
                m.onExpandChange?()
            }
            .onEnded { _ in m.gripFrom = nil })
        .help("Drag to resize")
    }
}








// MARK: Glass, built to the approved mockup (round 2, direction 1): a frosted macOS widget stack

let gInk = hex(0x1d1d1f), gSub = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.6), gBlue = hex(0x007aff), gGreen = hex(0x34c759)
let gFill = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255)

/// Shared by Glass and Ink: hover state, the short tick animation, and the todo list paging.
final class CardUI: ObservableObject {
    @Published var hover: String?
    @Published var ticking: Set<String> = []
    @Published var showAll = false
    @Published var allPots = false
    func tick(_ t: Todo, _ m: Model) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { _ = ticking.insert(t.id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.ticking.remove(t.id); m.tick(t) }
    }
}
func areaColor(_ a: String?) -> Color { a == "work" ? hex(0x5c9efa) : a == "career" ? hex(0xa78bfa) : hex(0xe38c5c) }
func dueDays(_ d: Date) -> Int { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day ?? 0 }
func stopLeft(_ m: Model) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: Date()), mins = c.hour! * 60 + c.minute!
    let stop = minutes(m.life?.stop ?? config["stop"] as? String) ?? 20 * 60, left = stop - mins
    return left > 0 ? "\(left / 60)h \(left % 60)m till \(stop / 60):\(String(format: "%02d", stop % 60))" : "evening"
}
func ringView(_ size: CGFloat, _ sw: CGFloat, _ k: Double, _ n: Double, _ color: Color, _ track: Color) -> some View {
    ZStack {
        Circle().stroke(track, lineWidth: sw)
        Circle().trim(from: 0, to: n > 0 ? min(1, k / n) : 0).stroke(color, style: StrokeStyle(lineWidth: sw, lineCap: .round)).rotationEffect(.degrees(-90))
    }.frame(width: size - sw, height: size - sw).frame(width: size, height: size).animation(.spring(response: 0.6), value: k)
}

struct GlassCard: View {
    @ObservedObject var m: Model
    @StateObject private var ui = CardUI()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if m.tab == "personal" { personal } else { work }
        }
        .padding(14).foregroundColor(gInk)
    }

    func plat<V: View>(_ pad: CGFloat = 12, @ViewBuilder _ v: () -> V) -> some View {
        v().padding(.vertical, pad).padding(.horizontal, pad + 2).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
    }
    func lab(_ t: String) -> some View { Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.2).foregroundColor(gSub) }
    func btn(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(.system(size: 12, weight: .semibold)).foregroundColor(gInk).padding(.horizontal, 12).padding(.vertical, 7).background(RoundedRectangle(cornerRadius: 9).fill(gFill.opacity(0.14))) }.buttonStyle(.plain)
    }

    var header: some View {
        HStack(spacing: 9) {
            Circle().fill(LinearGradient(colors: [hex(0xf3a877), hex(0xd9764f)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 28, height: 28)
                .overlay(Text(isBear ? "🐻" : isPug ? "🐶" : "🐱").font(.system(size: 15))).shadow(color: hex(0xd9764f).opacity(0.4), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 0) {
                Text("Buddy").font(.system(size: 14, weight: .semibold))
                Text(m.waiting.isEmpty ? (m.working.isEmpty ? "all quiet" : "\(m.working.count) session\(m.working.count == 1 ? "" : "s") cooking") : "\(m.waiting.count) waiting for you")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(m.waiting.isEmpty ? gSub : hex(0xe8590c))
            }
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7).fill(Color.white).frame(width: 73).shadow(color: .black.opacity(0.12), radius: 3, y: 2).offset(x: m.tab == "personal" ? 73 : 0)
                HStack(spacing: 0) {
                    ForEach(["work", "personal"], id: \.self) { t in
                        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { m.tab = t } } label: {
                            Text(t.capitalized).font(.system(size: 12, weight: .semibold)).frame(width: 73).padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.fixedSize().padding(2).background(RoundedRectangle(cornerRadius: 9).fill(gFill.opacity(0.16)))
        }
    }

    // ---- Personal
    var personal: some View {
        let t = m.goal("today"), todos = m.todos, shown = ui.showAll ? todos : Array(todos.prefix(listCap))
        return VStack(alignment: .leading, spacing: 10) {
            plat {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        lab("Today")
                        Button { if t == nil { DispatchQueue.main.async { m.setGoal("today") } } } label: {
                            Text(t?.text ?? "Set today's goal…").font(.system(size: 19, weight: .semibold)).kerning(-0.3).foregroundColor(t == nil ? gSub : gInk)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(.plain)
                        if t != nil {
                            Text(t!.done ? "Done. Nice work." : "Not yet · \(stopLeft(m))").font(.system(size: 12, weight: .medium)).foregroundColor(t!.done ? hex(0x248a3d) : gSub).padding(.top, 1)
                        }
                    }
                    Spacer(minLength: 0)
                    if t != nil {
                        Button { m.bump("today") } label: {
                            ZStack {
                                Circle().fill(t!.done ? gGreen : Color.white.opacity(0.6))
                                Circle().stroke(t!.done ? gGreen : gSub.opacity(0.42), lineWidth: 2)
                                if t!.done { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundColor(.white).transition(.scale) }
                            }.frame(width: 40, height: 40).shadow(color: t!.done ? gGreen.opacity(0.45) : .clear, radius: 8, y: 6)
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ringTile("This week", "week", gBlue, gBlue.opacity(0.15))
                ringTile("This month", "month", hex(0xff9500), hex(0xff9500).opacity(0.17))
            }.fixedSize(horizontal: false, vertical: true)
            if let y = m.life?.goals.first {
                HStack(spacing: 8) { Image(systemName: "house").font(.system(size: 12)); Text(y).lineLimit(1) }
                    .font(.system(size: 12, weight: .medium)).foregroundColor(gSub.opacity(1.15)).padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                ForEach(shown) { row($0) }
                if todos.isEmpty { Text(m.familyTime ? "Nothing due. Enjoy the evening." : "Nothing to do.").font(.system(size: 13, weight: .medium)).foregroundColor(gSub).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                HStack {
                    Text("\(todos.count) open").foregroundColor(gSub)
                    Spacer()
                    if todos.count > listCap { Button(ui.showAll ? "Show less" : "Show \(todos.count - listCap) more") { withAnimation { ui.showAll.toggle() } }.buttonStyle(.plain).foregroundColor(gBlue) }
                    Button("Add…") { DispatchQueue.main.async { m.addTask() } }.buttonStyle(.plain).foregroundColor(gBlue).padding(.leading, 8)
                }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            }
            .padding(6).background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
            if !m.moments.isEmpty {
                HStack(spacing: 8) {
                    ForEach(m.moments) { mo in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mo.when).font(.system(size: 15, weight: .semibold)).kerning(-0.2).lineLimit(1).minimumScaleFactor(0.55)
                            Text(mo.detail).font(.system(size: 11, weight: .medium)).foregroundColor(gSub).lineLimit(2)
                        }.frame(maxWidth: .infinity, alignment: .topLeading).padding(.horizontal, 10).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.45)))
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
            Carousel(m: m)
            HStack {
                Button("Tell Buddy…") { DispatchQueue.main.async { m.tellBuddy() } }.buttonStyle(.plain).foregroundColor(gBlue)
                Spacer()
                Text("Private to this Mac").foregroundColor(gSub.opacity(0.85))
            }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 4)
        }
    }
    func ringTile(_ title: String, _ which: String, _ c: Color, _ track: Color) -> some View {
        let g = m.goal(which), n = g?.n ?? 1, k = g?.n == nil ? (g?.done == true ? 1 : 0) : g!.k
        return Button { g == nil ? DispatchQueue.main.async { m.setGoal(which) } : m.bump(which) } label: {
            VStack(alignment: .leading, spacing: 0) {
                lab(title)
                HStack(spacing: 10) {
                    ringView(50, 7, Double(k), Double(n), c, track)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(k)").font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        Text("/\(n)").font(.system(size: 14)).foregroundColor(gSub.opacity(0.85))
                    }
                }.padding(.top, 6).padding(.bottom, 8)
                Text(g?.text ?? "Set one…").font(.system(size: 12, weight: .medium)).foregroundColor(g == nil ? gSub : gInk)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.vertical, 12).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
        }.buttonStyle(.plain)
    }
    func row(_ t: Todo) -> some View {
        let done = ui.ticking.contains(t.id), hovered = ui.hover == t.id
        return HStack(spacing: 10) {
            Button { ui.tick(t, m) } label: {
                ZStack {
                    Circle().fill(done ? gBlue : .clear)
                    Circle().stroke(done ? gBlue : gSub.opacity(0.58), lineWidth: 1.5)
                    if done { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white) }
                }.frame(width: 18, height: 18)
            }.buttonStyle(.plain)
            Text(t.text).font(.system(size: 13, weight: .medium)).foregroundColor(done ? gSub.opacity(0.67) : gInk).lineLimit(1)
            Spacer(minLength: 4)
            Circle().fill(areaColor(t.area)).frame(width: 6, height: 6).help(t.area ?? "home")
            if hovered && !done {
                Button { withAnimation { m.notToday(t) } } label: {
                    Text("Not today").font(.system(size: 11, weight: .semibold)).foregroundColor(gInk).padding(.horizontal, 8).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 7).fill(gFill.opacity(0.14)))
                }.buttonStyle(.plain)
            } else if let d = t.due {
                let n = dueDays(d)
                Text(dueText(d).0).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundColor(n <= 0 ? hex(0xe8590c) : n <= 6 ? gInk : gSub.opacity(0.92))
            }
        }
        .frame(height: 34).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? Color.white.opacity(0.6) : .clear))
        .contentShape(Rectangle()).onHover { h in ui.hover = h ? t.id : (ui.hover == t.id ? nil : ui.hover) }
    }

    // ---- Work
    var work: some View {
        let s = m.stats, quiet = m.draftRed.count + m.staleRed.count, g = m.goal("today")
        let pots = m.working.map { ($0, false) } + m.yourTurn.map { ($0, true) }, shown = ui.allPots ? pots : Array(pots.prefix(listCap))
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(m.waiting) { w in
                Button { activate(w) } label: {
                    HStack(spacing: 10) {
                        appIcon(w)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(w.repo ?? "?") wants your OK").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(w.activity ?? "").font(.system(size: 11, design: .monospaced)).foregroundColor(hex(0xe8590c)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text("Go ›").font(.system(size: 12, weight: .semibold)).foregroundColor(hex(0xe8590c))
                    }.padding(10).background(RoundedRectangle(cornerRadius: 14).fill(hex(0xff9500).opacity(0.16)))
                }.buttonStyle(.plain)
            }
            ForEach(m.needsYouPRs) { PRBlock(m: m, pr: $0).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.55))) }
            HStack(spacing: 8) {
                if !statsRepos.isEmpty {
                    num("\(s.merged)", "merged", s.yesterdayMerged.map { d in let x = s.merged - d; return x > 0 ? "+\(x)" : nil } ?? nil)
                    num("\(s.opened)", "opened", nil)
                }
                num(hm(m.workedToday), "worked", nil)
                num(m.sinceBreak.map(hm) ?? "now", "since break", nil, hot: (m.sinceBreak ?? 0) >= 90 * 60)
            }
            if !pots.isEmpty || !m.stuck.isEmpty {
                VStack(spacing: 0) {
                    ForEach(m.stuck) { st in
                        Button { activate(st) } label: {
                            Text("⚠︎ \(st.repo ?? "?") quiet \(ago(Date().timeIntervalSince1970 - st.ts)) · \(st.activity ?? "")").font(.system(size: 12, weight: .medium)).foregroundColor(hex(0xe8590c)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 7)
                        }.buttonStyle(.plain)
                    }
                    ForEach(shown, id: \.0.id) { p in
                        Button { activate(p.0) } label: {
                            HStack(spacing: 10) {
                                appIcon(p.0)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Text(p.0.repo ?? "?").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        if !p.1 { Circle().fill(gGreen).frame(width: 6, height: 6) }
                                    }
                                    Text((p.1 ? p.0.prompt : p.0.activity) ?? "").font(.system(size: 11, design: .monospaced)).foregroundColor(gSub).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(p.1 ? "done \(ago(Date().timeIntervalSince1970 - p.0.ts))" : ago(Date().timeIntervalSince1970 - (p.0.turnStart ?? p.0.ts)))
                                    .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundColor(p.1 ? hex(0x248a3d) : gSub)
                            }.padding(.horizontal, 6).padding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if pots.count > listCap { Button(ui.allPots ? "Show less" : "Show \(pots.count - listCap) more") { withAnimation { ui.allPots.toggle() } }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundColor(gBlue).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                }.padding(.vertical, 6).padding(.horizontal, 8).background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
            }
            if !s.team.isEmpty {
                plat(10) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(Array(s.team.prefix(3).enumerated()), id: \.offset) { i, r in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(["🥇", "🥈", "🥉"][i]) \(r.n)").font(.system(size: 15, weight: .semibold))
                                Text(r.login == s.me ? "you" : r.login).font(.system(size: 11, weight: .medium)).foregroundColor(gSub).lineLimit(1).truncationMode(.middle)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.rank.map { "#\($0)" } ?? "–").font(.system(size: 15, weight: .semibold)).foregroundColor(gBlue)
                            Text("you · \(s.myCount)").font(.system(size: 11, weight: .medium)).foregroundColor(gSub).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.help("PRs merged by the team: \(s.teamTotal) in all")
            }
            if !m.limits.isEmpty {
                plat {
                    VStack(alignment: .leading, spacing: 8) {
                        lab("Usage")
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(m.limits) { l in
                                VStack(spacing: 4) {
                                    ZStack {
                                        ringView(44, 5, l.used, 100, l.used >= 80 ? hex(0xff9500) : gGreen, Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.12))
                                        Text("\(Int(l.used))%").font(.system(size: 13, weight: .semibold))
                                    }
                                    Text(l.name.replacingOccurrences(of: "◆ ", with: "")).font(.system(size: 11, weight: .medium)).foregroundColor(gSub).lineLimit(1)
                                    Text(l.resets.map { "resets " + resetText($0) } ?? " ").font(.system(size: 10, weight: .medium)).foregroundColor(gSub.opacity(0.7)).lineLimit(1)
                                }.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                if m.diskFreeGB >= 0 {
                    Button { openWorktreeReport(m.worktrees) } label: {
                        (Text("\(Int(m.diskFreeGB)) GB").fontWeight(.semibold).foregroundColor(m.diskFreeGB < diskLowGB ? hex(0xe8590c) : gInk) + Text(" free · \(m.worktrees.count) worktrees"))
                    }.buttonStyle(.plain)
                }
                Spacer()
                if quiet > 0 { Button("\(quiet) red PRs ignored") { m.showStale.toggle() }.buttonStyle(.plain) }
            }.font(.system(size: 12, weight: .medium)).foregroundColor(gSub.opacity(1.15)).padding(.horizontal, 4)
            if m.showStale {
                ForEach(m.draftRed + m.staleRed) { pr in
                    Button { NSWorkspace.shared.open(URL(string: pr.url)!) } label: { Text("\(pr.short) · \(pr.title)").font(.system(size: 11)).foregroundColor(gSub).lineLimit(1) }.buttonStyle(.plain).padding(.horizontal, 4)
                }
            }
            Button { g == nil ? DispatchQueue.main.async { m.setGoal("today") } : withAnimation(.spring(response: 0.35)) { m.tab = "personal" } } label: {
                HStack(spacing: 10) {
                    Circle().fill(g?.done == true ? gGreen : .clear).overlay(Circle().stroke(g?.done == true ? gGreen : gSub.opacity(0.58), lineWidth: 1.5)).frame(width: 16, height: 16)
                    Text("TODAY").font(.system(size: 11, weight: .semibold)).foregroundColor(gSub.opacity(0.92))
                    Text(g?.text ?? "Set today's goal").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("›").foregroundColor(gSub.opacity(0.67))
                }.padding(.horizontal, 12).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.4)))
            }.buttonStyle(.plain)
            Carousel(m: m)

        }
    }
    func appIcon(_ x: Session) -> some View {
        let codex = (x.source ?? "").hasPrefix("codex")
        return RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: codex ? [hex(0x1fc79c), hex(0x0e8f6f)] : [hex(0xe8906f), hex(0xc9643f)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 28, height: 28).overlay(Text(codex ? ">_" : "✳").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white))
    }
    func num(_ big: String, _ label: String, _ em: String?, hot: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.system(size: 24, weight: .semibold)).kerning(-0.6).monospacedDigit().foregroundColor(hot ? hex(0xe8590c) : gInk).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Text(label).font(.system(size: 11.5, weight: .medium)).foregroundColor(gSub).lineLimit(1).minimumScaleFactor(0.8)
                if let em = em { Text(em).font(.system(size: 11, weight: .semibold)).foregroundColor(hex(0x248a3d)) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
    }
}

// MARK: Ink, built to the approved mockup (round 2, direction 2): a precise dark tool, one indigo accent

let kBg = hex(0x0f0f11), kInk = hex(0xededef), kSub = hex(0x6b6b73), kDim = hex(0x56565e), kMid = hex(0x8a8a93), kLine = hex(0x1a1a1e), kIndigo = hex(0x7c7ff2), kGreen = hex(0x4cc38a)

struct InkCard: View {
    @ObservedObject var m: Model
    @StateObject private var ui = CardUI()
    @Namespace private var tabNS
    @State private var spin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(kIndigo).frame(width: 8, height: 8).shadow(color: kIndigo, radius: 5)
                Text("Buddy").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(Self.stamp.string(from: Date()).uppercased()).font(.system(size: 11.5, weight: .medium, design: .monospaced)).foregroundColor(kSub)
            }.padding(.horizontal, 16).padding(.top, 12)
            HStack(spacing: 18) {
                tabButton("work", "Work", m.working.count + m.waiting.count)
                tabButton("personal", "Personal", m.todos.count)
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 10)
            Rectangle().fill(hex(0x1f1f23)).frame(height: 1)
            Group { if m.tab == "personal" { personal } else { work } }.padding(.horizontal, 16).padding(.vertical, 14)
            HStack(spacing: 6) {
                if m.tab == "personal" {
                    ftb("Tell Buddy…") { DispatchQueue.main.async { m.tellBuddy() } }
                    Spacer()
                    Text("~/.config/buddy").font(.system(size: 11, design: .monospaced)).foregroundColor(hex(0x44444c)).lineLimit(1).help("Private: stays on this Mac")
                } else {
                    ftb(m.snoozed ? "Wake up" : "Nap 1h") { m.toggleSnooze() }
                    ftb("Refresh") { m.loadSessions(); m.loadPRs(); m.loadStats() }
                    Spacer()
                    Text(m.prsCheckedAt.map { "checked \(ago(Date().timeIntervalSince($0))) ago" } ?? "checking…").font(.system(size: 11, design: .monospaced)).foregroundColor(hex(0x44444c))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10).background(hex(0x0c0c0e)).overlay(Rectangle().fill(kLine).frame(height: 1), alignment: .top)
        }
        .foregroundColor(kInk)
    }
    static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE dd MMM · HH:mm"; return f }()

    func tabButton(_ t: String, _ title: String, _ count: Int) -> some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { m.tab = t } } label: {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(m.tab == t ? kInk : kSub)
                    Text("\(count)").font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundColor(kSub)
                }
                ZStack {
                    Color.clear.frame(height: 2)
                    if m.tab == t { RoundedRectangle(cornerRadius: 2).fill(kIndigo).frame(height: 2).matchedGeometryEffect(id: "ul", in: tabNS) }
                }
            }.fixedSize()
        }.buttonStyle(.plain)
    }
    func lb(_ a: String, _ b: String) -> some View {
        HStack { Text(a).font(.system(size: 11.5, weight: .medium)); Spacer(); Text(b).font(.system(size: 11, design: .monospaced)) }.foregroundColor(kSub).padding(.bottom, 8)
    }
    func ftb(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 12, weight: .medium)).foregroundColor(hex(0xbdbdc4)).padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(hex(0x141418))).overlay(RoundedRectangle(cornerRadius: 6).stroke(hex(0x232328), lineWidth: 1))
        }.buttonStyle(.plain)
    }
    func box(_ size: CGFloat, _ r: CGFloat, _ done: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: r).fill(done ? kIndigo : .clear)
            RoundedRectangle(cornerRadius: r).stroke(done ? kIndigo : hex(0x44444c), lineWidth: 1.5)
            if done { Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .heavy)).foregroundColor(.white).transition(.scale) }
        }.frame(width: size, height: size)
    }

    // ---- Personal
    var personal: some View {
        let t = m.goal("today"), todos = m.todos, shown = ui.showAll ? todos : Array(todos.prefix(listCap))
        return VStack(alignment: .leading, spacing: 0) {
            lb("Today's goal", t?.done == true ? "done" : stopLeft(m).replacingOccurrences(of: " till ", with: " left · "))
            HStack(alignment: .top, spacing: 12) {
                Button { t == nil ? DispatchQueue.main.async { m.setGoal("today") } : m.bump("today") } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7).fill(t?.done == true ? kIndigo : .clear)
                        RoundedRectangle(cornerRadius: 7).stroke(t?.done == true ? kIndigo : hex(0x3a3a42), lineWidth: 1.5)
                        if t?.done == true { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.white).transition(.scale) }
                    }.frame(width: 22, height: 22).padding(.top, 2)
                }.buttonStyle(.plain)
                Button { if t == nil { DispatchQueue.main.async { m.setGoal("today") } } } label: {
                    Text(t?.text ?? "Set today's goal…").font(.system(size: 20, weight: .semibold)).kerning(-0.4)
                        .foregroundColor(t == nil || t!.done ? kMid : kInk).strikethrough(t?.done == true, color: kIndigo)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }.buttonStyle(.plain)
            }.padding(.top, 2).padding(.bottom, 16)
            grow("This week", "week"); grow("This month", "month")
            if let y = m.life?.goals.first {
                let yr = y.range(of: #"\d{4}"#, options: .regularExpression).map { String(y[$0]) }
                (Text(yr ?? "Year").foregroundColor(kMid).fontWeight(.medium) + Text(" · \(y)").foregroundColor(kDim)).font(.system(size: 12)).lineLimit(1)
                    .padding(.top, 8).padding(.bottom, 4).frame(maxWidth: .infinity, alignment: .leading).overlay(Rectangle().fill(kLine).frame(height: 1), alignment: .top)
            }
            VStack(alignment: .leading, spacing: 0) {
                lb("Todo", "\(todos.count) open")
                if todos.isEmpty { Text(m.familyTime ? "Nothing due. Enjoy the evening." : "Nothing to do.").font(.system(size: 13)).foregroundColor(kSub) }
                ForEach(shown) { row($0) }
                HStack {
                    if todos.count > listCap { Button(ui.showAll ? "show less" : "+ \(todos.count - listCap) more") { withAnimation { ui.showAll.toggle() } }.buttonStyle(.plain) }
                    Spacer()
                    Button("New task…") { DispatchQueue.main.async { m.addTask() } }.buttonStyle(.plain)
                }.font(.system(size: 12, weight: .medium)).foregroundColor(kMid).padding(.top, 6)
            }.padding(.top, 14)
            if !m.moments.isEmpty {
                Flow(spacing: 6) {
                    ForEach(m.moments) { mo in
                        (Text(mo.when).foregroundColor(kInk) + Text(" \(mo.detail)").foregroundColor(kMid)).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 3).overlay(RoundedRectangle(cornerRadius: 6).stroke(hex(0x222228), lineWidth: 1))
                    }
                }.padding(.top, 12)
            }
            Carousel(m: m).padding(.top, 14)
        }
    }
    func grow(_ title: String, _ which: String) -> some View {
        let g = m.goal(which), n = max(g?.n ?? 1, 1), k = g?.n == nil ? (g?.done == true ? 1 : 0) : g!.k
        return Button { g == nil ? DispatchQueue.main.async { m.setGoal(which) } : m.bump(which) } label: {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(kSub).frame(width: 76, alignment: .leading)
                Text(g?.text ?? "Set one…").font(.system(size: 13, weight: .medium)).foregroundColor(g == nil ? kSub : kInk).lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    ForEach(0..<n, id: \.self) { i in RoundedRectangle(cornerRadius: 2).fill(i < k ? kIndigo : hex(0x26262c)).frame(width: 14, height: i < k ? 7.5 : 6) }
                    Text("\(k)/\(n)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(kMid).frame(minWidth: 26, alignment: .trailing).padding(.leading, 6)
                }.animation(.spring(response: 0.4, dampingFraction: 0.5), value: k)
            }.padding(.vertical, 9).contentShape(Rectangle()).overlay(Rectangle().fill(kLine).frame(height: 1), alignment: .top)
        }.buttonStyle(.plain)
    }
    func row(_ t: Todo) -> some View {
        let done = ui.ticking.contains(t.id), hovered = ui.hover == t.id
        return HStack(spacing: 10) {
            Button { ui.tick(t, m) } label: {
                ZStack {
                    Circle().fill(done ? kIndigo : .clear); Circle().stroke(done ? kIndigo : hex(0x44444c), lineWidth: 1.5)
                    if done { Image(systemName: "checkmark").font(.system(size: 7.5, weight: .heavy)).foregroundColor(.white) }
                }.frame(width: 15, height: 15)
            }.buttonStyle(.plain)
            Text(t.text).font(.system(size: 13)).foregroundColor(done ? kDim : kInk).strikethrough(done, color: kDim).lineLimit(1)
            Spacer(minLength: 4)
            if let a = t.area { HStack(spacing: 4) { Circle().fill(areaColor(a)).frame(width: 6, height: 6); Text(a) }.font(.system(size: 10.5, weight: .medium)).foregroundColor(kSub) }
            if hovered && !done {
                Button { withAnimation { m.notToday(t) } } label: {
                    Text("Not today").font(.system(size: 11, weight: .medium)).foregroundColor(hex(0xbdbdc4)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(hex(0x16161a))).overlay(RoundedRectangle(cornerRadius: 5).stroke(hex(0x2a2a30), lineWidth: 1))
                }.buttonStyle(.plain)
            } else if let d = t.due {
                let n = dueDays(d)
                Text(dueText(d).0).font(.system(size: 11, weight: .medium)).foregroundColor(n <= 0 ? hex(0xf2994a) : n <= 6 ? hex(0xa9abff) : kMid)
                    .frame(minWidth: 40).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(n <= 0 ? hex(0xf2994a).opacity(0.14) : n <= 6 ? kIndigo.opacity(0.14) : hex(0x1c1c21)))
            }
        }
        .frame(height: 32).padding(.horizontal, 6).background(RoundedRectangle(cornerRadius: 6).fill(hovered ? hex(0x18181c) : .clear)).padding(.horizontal, -6)
        .contentShape(Rectangle()).onHover { h in ui.hover = h ? t.id : (ui.hover == t.id ? nil : ui.hover) }
    }

    // ---- Work
    var work: some View {
        let s = m.stats, quiet = m.draftRed.count + m.staleRed.count, g = m.goal("today")
        let pots = m.working.map { ($0, false) } + m.yourTurn.map { ($0, true) }, shown = ui.allPots ? pots : Array(pots.prefix(listCap))
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(m.waiting) { w in
                Button { activate(w) } label: {
                    HStack(spacing: 10) {
                        Circle().fill(hex(0xf2994a)).frame(width: 8, height: 8)
                        Text("\(w.repo ?? "?") wants your OK").font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(w.activity ?? "").font(.system(size: 11.5, design: .monospaced)).foregroundColor(kDim).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("go →").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(hex(0xf2994a))
                    }.padding(.horizontal, 10).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 6).fill(hex(0xf2994a).opacity(0.12))).padding(.bottom, 8)
                }.buttonStyle(.plain)
            }
            ForEach(m.needsYouPRs) { PRBlock(m: m, pr: $0).padding(.bottom, 8) }
            lb("Running", "\(m.working.count)")
            ForEach(m.stuck) { st in
                Button { activate(st) } label: {
                    Text("⚠︎ \(st.repo ?? "?") quiet \(ago(Date().timeIntervalSince1970 - st.ts)) · \(st.activity ?? "")").font(.system(size: 12)).foregroundColor(hex(0xf2994a)).lineLimit(1).frame(height: 30, alignment: .leading)
                }.buttonStyle(.plain)
            }
            ForEach(shown, id: \.0.id) { p in
                let codex = (p.0.source ?? "").hasPrefix("codex"), c = codex ? codexColor : claudeColor
                Button { activate(p.0) } label: {
                    HStack(spacing: 10) {
                        if p.1 { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(kGreen).frame(width: 14, height: 14) }
                        else {
                            ZStack { Circle().stroke(hex(0x2a2a30), lineWidth: 2); Circle().trim(from: 0, to: 0.25).stroke(c, style: StrokeStyle(lineWidth: 2, lineCap: .round)) }
                                .frame(width: 12, height: 12).rotationEffect(.degrees(spin ? 360 : 0))
                        }
                        Text(p.0.repo ?? "?").font(.system(size: 13, weight: .medium)).lineLimit(1).layoutPriority(1)
                        Text((p.1 ? p.0.prompt : p.0.activity) ?? "").font(.system(size: 11.5, design: .monospaced)).foregroundColor(kDim).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(codex ? "Codex" : "Claude").font(.system(size: 10.5, weight: .medium)).foregroundColor(c).fixedSize().padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 4).fill(c.opacity(0.12)))
                        Text(p.1 ? "done" : ago(Date().timeIntervalSince1970 - (p.0.turnStart ?? p.0.ts))).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(p.1 ? kGreen : kSub).fixedSize()
                    }.frame(height: 34).padding(.horizontal, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, -6)
            }
            if pots.isEmpty && m.waiting.isEmpty { Text("Nothing running.").font(.system(size: 13)).foregroundColor(kSub).padding(.vertical, 4) }
            if pots.count > listCap { Button(ui.allPots ? "show less" : "+ \(pots.count - listCap) more") { withAnimation { ui.allPots.toggle() } }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundColor(kMid).padding(.top, 4) }

            HStack(spacing: 0) {
                if !statsRepos.isEmpty {
                    stat("\(s.merged)", "merged", s.yesterdayMerged.map { d in let x = s.merged - d; return x > 0 ? "+\(x)" : nil } ?? nil)
                    Rectangle().fill(hex(0x1f1f23)).frame(width: 1)
                    stat("\(s.opened)", "opened", nil)
                    Rectangle().fill(hex(0x1f1f23)).frame(width: 1)
                }
                stat(hm(m.workedToday), "worked", nil)
                Rectangle().fill(hex(0x1f1f23)).frame(width: 1)
                stat(m.sinceBreak.map(hm) ?? "now", "since break", nil, hot: (m.sinceBreak ?? 0) >= 90 * 60)
            }.fixedSize(horizontal: false, vertical: true).overlay(RoundedRectangle(cornerRadius: 8).stroke(hex(0x1f1f23), lineWidth: 1)).padding(.top, 14)

            if !s.team.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(s.team.prefix(3).enumerated()), id: \.offset) { i, r in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(["🥇", "🥈", "🥉"][i]) \(r.n)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            Text(r.login == s.me ? "you" : r.login).font(.system(size: 11)).foregroundColor(kSub).lineLimit(1).truncationMode(.middle)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.rank.map { "#\($0)" } ?? "–").font(.system(size: 13, weight: .semibold)).foregroundColor(kIndigo)
                        Text("you · \(s.myCount)").font(.system(size: 11)).foregroundColor(kSub).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.top, 12).help("PRs merged by the team: \(s.teamTotal) in all")
            }

            if !m.limits.isEmpty {
                lb("Usage", "").padding(.top, 14)
                ForEach(m.limits) { l in
                    HStack(spacing: 8) {
                        Text(l.name.replacingOccurrences(of: "◆ ", with: "")).font(.system(size: 12)).lineLimit(1).frame(width: 86, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) { Capsule().fill(hex(0x202026)); Capsule().fill(l.used >= 80 ? hex(0xf2994a) : kGreen).frame(width: geo.size.width * min(1, l.used / 100)) }
                        }.frame(height: 3)
                        Text("\(Int(l.used))%").font(.system(size: 11, weight: .medium, design: .monospaced)).frame(width: 34, alignment: .trailing)
                        Text(l.resets.map { "↻ " + resetText($0) } ?? "").font(.system(size: 11)).foregroundColor(kDim).lineLimit(1).frame(width: 76, alignment: .leading)
                    }.frame(height: 24)
                }
            }
            HStack {
                if m.diskFreeGB >= 0 {
                    Button { openWorktreeReport(m.worktrees) } label: {
                        Text("\(Int(m.diskFreeGB)) GB").fontWeight(.medium).foregroundColor(m.diskFreeGB < diskLowGB ? hex(0xf2994a) : kInk) + Text(" free · \(m.worktrees.count) worktrees")
                    }.buttonStyle(.plain)
                }
                Spacer()
                if quiet > 0 { Button("\(quiet) red ignored") { m.showStale.toggle() }.buttonStyle(.plain) }
            }.font(.system(size: 12)).foregroundColor(kSub).padding(.top, 10).frame(maxWidth: .infinity).overlay(Rectangle().fill(kLine).frame(height: 1), alignment: .top).padding(.top, 12)
            if m.showStale {
                ForEach(m.draftRed + m.staleRed) { pr in
                    Button { NSWorkspace.shared.open(URL(string: pr.url)!) } label: { Text("\(pr.short) · \(pr.title)").font(.system(size: 11)).foregroundColor(kSub).lineLimit(1) }.buttonStyle(.plain).padding(.top, 3)
                }
            }
            Button { g == nil ? DispatchQueue.main.async { m.setGoal("today") } : withAnimation(.spring(response: 0.35)) { m.tab = "personal" } } label: {
                HStack(spacing: 10) {
                    box(12, 4, g?.done == true)
                    Text(g?.text ?? "Set today's goal").font(.system(size: 12.5)).foregroundColor(hex(0xbdbdc4)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("TODAY →").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(kDim)
                }.padding(.horizontal, 12).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 8).fill(hex(0x141418))).overlay(RoundedRectangle(cornerRadius: 8).stroke(hex(0x1f1f23), lineWidth: 1))
            }.buttonStyle(.plain).padding(.top, 12)
            Carousel(m: m).padding(.top, 12)
        }
        .onAppear { withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { spin = true } }
    }
    func stat(_ big: String, _ label: String, _ em: String?, hot: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(big).font(.system(size: 20, weight: .semibold)).kerning(-0.5).monospacedDigit().foregroundColor(hot ? hex(0xf2994a) : kInk).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Text(label).font(.system(size: 11.5)).foregroundColor(kSub).lineLimit(1).minimumScaleFactor(0.8)
                if let em = em { Text(em).font(.system(size: 11)).foregroundColor(kGreen) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 9)
    }
}

// MARK: Burrow, built to the approved mockup (round 2, direction 3): the scene IS the card's header

/// Rows shown before "+ N more": three keeps every card short enough to fit above Buddy without scrolling.
let listCap = 3
let bClay = hex(0xd97757), bSage = hex(0x7fa77a), bSageInk = hex(0x5f8a5a), bInk = hex(0x3a2a1f), bSub = hex(0x8b7363)
let bBtn = hex(0xf3e6d6), bBtnInk = hex(0x7a4a30), bChip = hex(0xf6ece0), bChipInk = hex(0x6a4a36)
let bShadow = hex(0x784f28)

/// Chips that wrap like words.
struct Flow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > w { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX && x + s.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

struct BurrowCard: View {
    @ObservedObject var m: Model
    @State private var showAll = false
    @State private var allPots = false
    @State private var hover: String?
    @State private var ticking: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if m.tab == "personal" { BurrowLifeScene(m: m) } else { BurrowWorkScene(m: m) }
                header.padding(.top, 10).padding(.horizontal, 14)
            }
            .frame(height: 118).clipped()
            Group { if m.tab == "personal" { personal } else { work } }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        }
        .foregroundColor(bInk)
    }

    // ---- header on the scene: name, a mood pill, the sliding tab switch
    var pill: String {
        if m.tab == "personal" { return "out for a walk" }
        if !m.waiting.isEmpty { return "needs you" }
        let n = m.working.count
        return n == 0 ? "napping by the stove" : "minding \(n) pot\(n == 1 ? "" : "s")"
    }
    var header: some View {
        HStack(spacing: 8) {
            Text("Buddy").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(hex(0x5a3420))
            Text(pill).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(hex(0x8b5a3c))
                .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Color.white.opacity(0.55)))
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                Capsule().fill(bClay).frame(width: 76).shadow(color: bClay.opacity(0.45), radius: 4, y: 3)
                    .offset(x: m.tab == "personal" ? 76 : 0)
                HStack(spacing: 0) {
                    ForEach(["work", "personal"], id: \.self) { t in
                        Button { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { m.tab = t } } label: {
                            Text(t.capitalized).font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(m.tab == t ? .white : bBtnInk).frame(width: 76).padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .fixedSize().padding(3).background(Capsule().fill(Color.white.opacity(0.6)))
        }
    }

    func card<V: View>(_ r: CGFloat, @ViewBuilder _ v: () -> V) -> some View {
        v().background(RoundedRectangle(cornerRadius: r).fill(Color.white).shadow(color: bShadow.opacity(0.08), radius: 1, y: 1))
    }

    // ---- Personal
    var personal: some View {
        let t = m.goal("today"), w = m.goal("week"), mo = m.goal("month")
        let todos = m.todos, shown = showAll ? todos : Array(todos.prefix(listCap))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY").font(.system(size: 11, weight: .bold, design: .rounded)).kerning(0.4).foregroundColor(bClay)
                    Button { if t == nil { DispatchQueue.main.async { m.setGoal("today") } } } label: {
                        Text(t?.text ?? "What's today's goal?").font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(t == nil ? bSub : bInk).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button { t == nil ? DispatchQueue.main.async { m.setGoal("today") } : m.bump("today") } label: {
                    Text(t == nil ? "Set" : t!.done ? "Done ✓" : "Did it").font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(t?.done == true ? .white : bBtnInk).frame(width: 74).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 16).fill(t?.done == true ? bSage : bBtn))
                        .shadow(color: t?.done == true ? bSage.opacity(0.5) : .clear, radius: 7, y: 5)
                }.buttonStyle(.plain)
            }
            .padding(.vertical, 9).padding(.leading, 16).padding(.trailing, 10)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white).shadow(color: bShadow.opacity(0.08), radius: 9, y: 4))

            HStack(alignment: .top, spacing: 10) {
                goalTile("🪨 THE PATH · WEEK", w, "week", w.map { "\($0.k) of \($0.n ?? 1) stones" }, bClay)
                goalTile("🌱 THE PLANT · MONTH", mo, "month", mo.map { "\($0.k) of \($0.n ?? 1) leaves" }, bSageInk)
            }.fixedSize(horizontal: false, vertical: true).padding(.top, 10)

            if let y = m.life?.goals.first {
                Text("🏡 The house on the hill: \(y)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(bSub)
                    .padding(.top, 10).padding(.horizontal, 4)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Little things").font(.system(size: 14, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(todos.count) left").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(bSub)
            }.padding(.top, 10).padding(.bottom, 5).padding(.horizontal, 4)
            if todos.isEmpty {
                Text(m.familyTime ? "Nothing due. Enjoy the evening." : "Nothing left. Nice.").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(bSub).padding(.horizontal, 4)
            }
            VStack(spacing: 4) { ForEach(shown) { row($0) } }
            HStack {
                if todos.count > listCap { Button(showAll ? "show less" : "+ \(todos.count - listCap) more") { withAnimation { showAll.toggle() } }.buttonStyle(.plain) }
                Spacer()
                Button("Add one…") { DispatchQueue.main.async { m.addTask() } }.buttonStyle(.plain)
            }.font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(bClay).padding(.top, 4).padding(.horizontal, 4)

            if !m.moments.isEmpty {
                Flow(spacing: 6) {
                    ForEach(m.moments.prefix(2)) { mo in
                        Text("\(mo.icon) \(mo.text)").font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundColor(bChipInk)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(bChip))
                    }
                }.padding(.top, 8)
            }
            Carousel(m: m).padding(.top, 10)
            HStack {
                Button("Tell Buddy…") { DispatchQueue.main.async { m.tellBuddy() } }.buttonStyle(.plain).foregroundColor(bClay)
                Spacer()
                Text("stays on this Mac").foregroundColor(bSub)
            }.font(.system(size: 12, weight: .bold, design: .rounded)).padding(.top, 10).padding(.horizontal, 4)
        }
    }

    func goalTile(_ h: String, _ g: Goal?, _ which: String, _ progress: String?, _ c: Color) -> some View {
        Button { g == nil ? DispatchQueue.main.async { m.setGoal(which) } : m.bump(which) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(h).font(.system(size: 11, weight: .bold, design: .rounded)).kerning(0.3).foregroundColor(bSub).fixedSize(horizontal: false, vertical: true)
                Text(g?.text ?? "Set one…").font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundColor(g == nil ? bSub : bInk)
                    .multilineTextAlignment(.leading).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 4).padding(.bottom, 5).help(g?.text ?? "")
                Spacer(minLength: 0)
                if let p = progress { Text(p).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(c) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white).shadow(color: bShadow.opacity(0.06), radius: 1, y: 2))
        }.buttonStyle(.plain).help(g == nil ? "Set it" : "Click: one more")
    }

    func row(_ t: Todo) -> some View {
        let done = ticking.contains(t.id)
        let days = t.due.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: $0).day ?? 0 }
        let (bg, fg): (Color, Color) = days.map { $0 <= 0 ? (hex(0xffe2cf), hex(0xc4542b)) : $0 <= 6 ? (hex(0xe7f0e2), hex(0x4d7a48)) : (bChip, bSub) } ?? (bChip, bSub)
        return HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { _ = ticking.insert(t.id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { ticking.remove(t.id); m.tick(t) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(done ? bSage : hex(0xfffaf4))
                    RoundedRectangle(cornerRadius: 8).stroke(done ? bSage : hex(0xe3c9b0), lineWidth: 2)
                    if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.white).transition(.scale) }
                }.frame(width: 22, height: 22)
            }.buttonStyle(.plain)
            Text(t.text).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(done ? hex(0xb9a597) : bInk)
                .strikethrough(done, color: hex(0xb9a597)).lineLimit(1)
            Spacer(minLength: 4)
            if hover == t.id && !done {
                Button { withAnimation { m.notToday(t) } } label: {
                    Text("☾ tomorrow").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(hex(0x6b4f8a))
                        .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(hex(0xefe4f7)))
                }.buttonStyle(.plain)
            } else if let d = t.due {
                Text(dueText(d).0).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(fg)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(bg))
            }
        }
        .frame(height: 36).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(hover == t.id ? hex(0xfffdf9) : Color.white).shadow(color: bShadow.opacity(hover == t.id ? 0.1 : 0.06), radius: hover == t.id ? 6 : 1, y: hover == t.id ? 4 : 1))
        .contentShape(Rectangle())
        .onHover { h in hover = h ? t.id : (hover == t.id ? nil : hover) }
    }

    // ---- Work
    var work: some View {
        let pots = m.working.map { ($0, false) } + m.yourTurn.map { ($0, true) }
        let shownPots = allPots ? pots : Array(pots.prefix(listCap))
        let s = m.stats, quiet = m.draftRed.count + m.staleRed.count
        let g = m.goal("today")
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 6) {
                ForEach(m.waiting) { w in
                    Button { activate(w) } label: {
                        HStack(spacing: 10) {
                            potIcon(w)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(w.repo ?? "?") wants your OK").font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                                Text(w.activity ?? "").font(.system(size: 11, design: .monospaced)).foregroundColor(hex(0xc4542b)).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text("Go →").font(.system(size: 11.5, weight: .heavy, design: .rounded)).foregroundColor(hex(0xc4542b))
                        }.padding(.horizontal, 12).padding(.vertical, 9).background(RoundedRectangle(cornerRadius: 16).fill(hex(0xffe2cf)))
                    }.buttonStyle(.plain)
                }
                ForEach(m.needsYouPRs) { PRBlock(m: m, pr: $0).background(RoundedRectangle(cornerRadius: 16).fill(Color.white)) }
                ForEach(m.stuck) { st in
                    Button { activate(st) } label: {
                        Text("⚠︎ \(st.repo ?? "?") quiet \(ago(Date().timeIntervalSince1970 - st.ts)) · last: \(st.activity ?? "")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(hex(0xc4542b)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 14).fill(hex(0xfdebd9)))
                    }.buttonStyle(.plain)
                }
                ForEach(shownPots, id: \.0.id) { p in
                    Button { activate(p.0) } label: {
                        HStack(spacing: 10) {
                            potIcon(p.0)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.0.repo ?? "?").font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                                Text((p.1 ? p.0.prompt : p.0.activity) ?? "").font(.system(size: 11, design: .monospaced)).foregroundColor(bSub).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(p.1 ? "done \(ago(Date().timeIntervalSince1970 - p.0.ts))" : ago(Date().timeIntervalSince1970 - (p.0.turnStart ?? p.0.ts)))
                                .font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundColor(p.1 ? bSageInk : bSub)
                        }.padding(.horizontal, 12).padding(.vertical, 7).background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                    }.buttonStyle(.plain)
                }
                if pots.isEmpty && m.waiting.isEmpty {
                    Text("Nothing on the stove. Buddy's napping.").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(bSub)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
                if pots.count > listCap {
                    Button(allPots ? "show less" : "+ \(pots.count - listCap) more") { withAnimation { allPots.toggle() } }.buttonStyle(.plain)
                        .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(bClay).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
            }

            HStack(spacing: 8) {
                if !statsRepos.isEmpty {
                    tile("\(s.merged)", "merged", s.yesterdayMerged.map { d in let x = s.merged - d; return x > 0 ? "+\(x)" : nil } ?? nil)
                    tile("\(s.opened)", "opened", nil)
                }
                tile(hm(m.workedToday), "worked", nil)
                tile(m.sinceBreak.map(hm) ?? "now", "since break", nil, hot: (m.sinceBreak ?? 0) >= 90 * 60)
            }.padding(.top, 10)

            if !s.team.isEmpty {   // the team leaderboard: PRs merged
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(s.team.prefix(3).enumerated()), id: \.offset) { i, r in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(["🥇", "🥈", "🥉"][i]) \(r.n)").font(.system(size: 14, weight: .heavy, design: .rounded))
                            Text(r.login == s.me ? "you" : r.login).font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(r.login == s.me ? bClay : bSub).lineLimit(1).truncationMode(.middle)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.rank.map { "#\($0)" } ?? "–").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(bClay)
                        Text("you · \(s.myCount)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(bSub).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12).padding(.vertical, 7).background(RoundedRectangle(cornerRadius: 16).fill(Color.white)).padding(.top, 8)
                .help("PRs merged by the team: \(s.teamTotal) in all")
            }

            if !m.limits.isEmpty {
                VStack(spacing: 4) {
                    ForEach(m.limits) { l in
                        let c = l.used >= 95 ? hex(0xc4542b) : l.used >= 80 ? hex(0xe0a040) : bSage
                        HStack(spacing: 8) {
                            Text(l.name.replacingOccurrences(of: "◆ ", with: "")).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1).frame(width: 84, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(bBtn)
                                    Capsule().fill(c).frame(width: geo.size.width * min(1, l.used / 100))
                                }
                            }.frame(height: 8)
                            Text("\(Int(l.used))%").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(bSub).monospacedDigit().frame(width: 34, alignment: .trailing)
                        }.frame(height: 18).help(l.resets.map { "resets " + resetText($0) } ?? "")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 16).fill(Color.white)).padding(.top, 8)
            }

            HStack {
                if m.diskFreeGB >= 0 {
                    Button("\(Int(m.diskFreeGB)) GB free · \(m.worktrees.count) worktrees") { openWorktreeReport(m.worktrees) }.buttonStyle(.plain)
                        .foregroundColor(m.diskFreeGB < diskLowGB ? hex(0xc4542b) : bSub).help("Click for the worktree list, oldest first")
                }
                Spacer()
                if quiet > 0 { Button("\(quiet) red ignored") { m.showStale.toggle() }.buttonStyle(.plain).foregroundColor(bSub) }
            }.font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.top, 10).padding(.horizontal, 4)
            if m.showStale {
                ForEach(m.draftRed + m.staleRed) { pr in
                    Button { NSWorkspace.shared.open(URL(string: pr.url)!) } label: {
                        Text("\(pr.short) · \(pr.title)").font(.system(size: 11, design: .rounded)).foregroundColor(bSub).lineLimit(1)
                    }.buttonStyle(.plain).padding(.horizontal, 4).padding(.top, 3)
                }
            }

            Button { g == nil ? DispatchQueue.main.async { m.setGoal("today") } : withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { m.tab = "personal" } } label: {
                HStack(spacing: 10) {
                    Text("🐾")
                    Text(g?.text ?? "Set today's goal").font(.system(size: 12.5, weight: .bold, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(g?.done == true ? "done ✓" : "today →").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(g?.done == true ? hex(0x4d7a48) : hex(0xc4542b))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 16).fill(g?.done == true ? hex(0xe7f0e2) : hex(0xfdebd9)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(g?.done == true ? hex(0xb9d3b2) : hex(0xecc3a2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            }.buttonStyle(.plain).padding(.top, 10)

            Carousel(m: m).padding(.top, 10)

        }
    }
    func potIcon(_ x: Session) -> some View {
        let codex = (x.source ?? "").hasPrefix("codex")
        return RoundedRectangle(cornerRadius: 11).fill(codex ? codexColor : bClay).frame(width: 30, height: 30)
            .overlay(Text(codex ? "Cx" : "Cl").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(.white))
    }
    func tile(_ big: String, _ label: String, _ em: String?, hot: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(hot ? hex(0xc4542b) : bInk)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(bSub).lineLimit(1).minimumScaleFactor(0.8)
                if let em = em { Text(em).font(.system(size: 10.5, weight: .heavy, design: .rounded)).foregroundColor(bSageInk) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
    }
}

/// The mockup's scenes are drawn in a 360×150 box; scale to cover the card's width, like SVG "slice".
func sceneTransform(_ size: CGSize) -> (CGFloat, CGFloat, CGFloat) {
    let s = max(size.width / 360, size.height / 150)
    return (s, (size.width - 360 * s) / 2, size.height - 150 * s)   // bottom-aligned: a shorter scene loses sky, not the path
}
func quad(_ p: inout Path, _ c: CGPoint, _ e: CGPoint) { p.addQuadCurve(to: e, control: c) }

/// Quotes and questions, rotating every 8 s; ‹ › to go back through everything Buddy has said. Drawn in each theme's own look.
struct Carousel: View {
    @ObservedObject var m: Model
    @State private var index = 0
    @State private var paused = false

    var body: some View {
        let items = m.history
        if !m.tight, let b = items.isEmpty ? nil : items[min(index, items.count - 1)] {
            let quote = b.kind == .quote
            let (ink, sub, accent): (Color, Color, Color) = T.name == "burrow" ? (bInk, bSub, bClay) : T.name == "glass" ? (gInk, gSub, gBlue) : (kInk, kSub, kIndigo)
            VStack(alignment: .leading, spacing: 7) {
                Text(quote ? "“\(b.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“” ")))”" : b.text)
                    .font(T.name == "burrow" ? .system(size: 13.5, weight: .semibold, design: .rounded)
                          : T.name == "glass" ? .system(size: 13.5, weight: .medium) : .system(size: 14, design: .serif).italic())
                    .foregroundColor(ink).lineSpacing(1.5).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).id(b.id).transition(.opacity)
                HStack(spacing: 6) {
                    if let f = m.flash { Text(f).foregroundColor(Mood.happy.color) }
                    else if let by = b.byline { Text(by).foregroundColor(T.name == "burrow" ? accent : sub) }
                    Spacer(minLength: 4)
                    icon("chevron.left", sub) { step(+1) }
                    icon("chevron.right", sub) { step(-1) }
                    icon("doc.on.doc", sub) { m.copyBubble(b) }
                    icon(m.favorites.contains(b.text) ? "heart.fill" : "heart", m.favorites.contains(b.text) ? hex(0xe0556b) : sub) { m.toggleFavorite(b) }
                }
                .font(T.name == "ink" ? .system(size: 11, design: .monospaced) : .system(size: 11.5, weight: .semibold, design: T.design)).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Group {
                switch T.name {
                case "burrow": RoundedRectangle(cornerRadius: 18).fill(Color.white).shadow(color: bShadow.opacity(0.06), radius: 1, y: 2)
                case "glass": RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55))
                default: RoundedRectangle(cornerRadius: 8).fill(hex(0x141418)).overlay(RoundedRectangle(cornerRadius: 8).stroke(hex(0x1f1f23), lineWidth: 1))
                }
            })
            .onHover { paused = $0 }
            .onChange(of: m.rotateTick) { _ in if !paused { step(-1) } }
        }
    }

    func icon(_ name: String, _ c: Color, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: name).font(.system(size: 10, weight: .semibold)).foregroundColor(c).frame(width: 22, height: 22)
                .background(Circle().fill(T.name == "burrow" ? bChip : T.name == "glass" ? gFill.opacity(0.14) : hex(0x1c1c21)))
        }.buttonStyle(.plain)
    }

    /// +1 = older, -1 = newer. Past the newest end, pull in a fresh quote.
    func step(_ d: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            let next = index + d
            if next < 0 { m.anotherQuote(); index = 0 }
            else { index = min(next, max(m.history.count - 1, 0)) }
        }
    }
}


/// The pet in the scene, drawn like the mockup's cat; bears get round ears, pugs floppy dark ones.
struct ScenePet: View {
    var fur: Color, dark: Color
    var body: some View {
        Canvas { c, size in
            c.translateBy(x: 26, y: 40)
            var tail = Path(); tail.move(to: CGPoint(x: -10, y: -8)); quad(&tail, CGPoint(x: -20, y: -10), CGPoint(x: -19, y: -22))
            c.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            c.fill(Path(ellipseIn: CGRect(x: -12, y: -17.5, width: 24, height: 17)), with: .color(fur))
            c.fill(Path(ellipseIn: CGRect(x: -4, y: -10, width: 12, height: 8)), with: .color(hex(0xfbe2cd)))
            c.fill(Path(ellipseIn: CGRect(x: 1, y: -28, width: 16, height: 16)), with: .color(fur))
            if isBear {
                c.fill(Path(ellipseIn: CGRect(x: 1, y: -31, width: 6, height: 6)), with: .color(fur))
                c.fill(Path(ellipseIn: CGRect(x: 11, y: -31, width: 6, height: 6)), with: .color(fur))
            } else if isPug {
                c.fill(Path(ellipseIn: CGRect(x: 0, y: -28, width: 5, height: 8)), with: .color(dark))
                c.fill(Path(ellipseIn: CGRect(x: 13, y: -28, width: 5, height: 8)), with: .color(dark))
            } else {
                var ears = Path()
                ears.move(to: CGPoint(x: 3, y: -25)); ears.addLine(to: CGPoint(x: 4, y: -32)); ears.addLine(to: CGPoint(x: 9, y: -28)); ears.closeSubpath()
                ears.move(to: CGPoint(x: 15, y: -25)); ears.addLine(to: CGPoint(x: 14, y: -32)); ears.addLine(to: CGPoint(x: 9, y: -28)); ears.closeSubpath()
                c.fill(ears, with: .color(fur))
            }
            let eye = hex(0x3a1f12)
            c.fill(Path(ellipseIn: CGRect(x: 5.3, y: -21.7, width: 2.4, height: 2.4)), with: .color(eye))
            c.fill(Path(ellipseIn: CGRect(x: 10.8, y: -21.7, width: 2.4, height: 2.4)), with: .color(eye))
            var smile = Path(); smile.move(to: CGPoint(x: 8, y: -16.8)); quad(&smile, CGPoint(x: 9.3, y: -15.8), CGPoint(x: 10.6, y: -16.8))
            c.stroke(smile, with: .color(eye), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            c.fill(Path(roundedRect: CGRect(x: -8, y: -3, width: 4, height: 4), cornerRadius: 2), with: .color(fur))
            c.fill(Path(roundedRect: CGRect(x: 5, y: -3, width: 4, height: 4), cornerRadius: 2), with: .color(fur))
        }.frame(width: 52, height: 44)
    }
}

/// Personal: Buddy walks this week's path stone by stone; the plant grows a leaf per step of the month; the house is the year.
struct BurrowLifeScene: View {
    @ObservedObject var m: Model
    static let stones: [CGPoint] = [CGPoint(x: 40, y: 121), CGPoint(x: 108, y: 111), CGPoint(x: 176, y: 115), CGPoint(x: 244, y: 108)]
    static func stone(_ i: Int, _ n: Int) -> CGPoint {
        let t = Double(i) / Double(max(n, 1)) * 3, j = min(Int(t), 2), f = t - Double(j)
        let a = stones[j], b = stones[j + 1]
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }
    var body: some View {
        let w = m.goal("week"), mo = m.goal("month")
        let n = max(w?.n ?? 3, 1), k = min(w.map { $0.n == nil ? ($0.done ? n : 0) : $0.k } ?? 0, n)
        let ln = max(mo?.n ?? 2, 1), lk = mo.map { $0.n == nil ? ($0.done ? ln : 0) : $0.k } ?? 0
        let year = (m.life?.goals.first).flatMap { g in g.range(of: #"\d{4}"#, options: .regularExpression).map { String(g[$0]) } } ?? ""
        GeometryReader { geo in
            let (sc, ox, oy) = sceneTransform(geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { c, size in
                    c.translateBy(x: ox, y: oy); c.scaleBy(x: sc, y: sc)
                    c.fill(Path(CGRect(x: 0, y: 0, width: 360, height: 150)), with: .linearGradient(Gradient(colors: [hex(0xffcfa3), hex(0xfff2df)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 150)))
                    c.fill(Path(ellipseIn: CGRect(x: 272, y: 32, width: 40, height: 40)), with: .color(hex(0xffb877).opacity(0.75)))
                    var back = Path(); back.move(to: CGPoint(x: 0, y: 98)); quad(&back, CGPoint(x: 80, y: 62), CGPoint(x: 170, y: 86)); quad(&back, CGPoint(x: 260, y: 110), CGPoint(x: 360, y: 70))
                    back.addLine(to: CGPoint(x: 360, y: 150)); back.addLine(to: CGPoint(x: 0, y: 150)); back.closeSubpath()
                    c.fill(back, with: .color(hex(0xecd3b3)))
                    // the house on the hill: the year goal
                    c.fill(Path(CGRect(x: 206, y: 70, width: 16, height: 11)), with: .color(hex(0xc98a6a)))
                    var roof = Path(); roof.move(to: CGPoint(x: 203, y: 71)); roof.addLine(to: CGPoint(x: 214, y: 62)); roof.addLine(to: CGPoint(x: 225, y: 71)); roof.closeSubpath()
                    c.fill(roof, with: .color(hex(0xa96446)))
                    c.fill(Path(CGRect(x: 212, y: 74, width: 4, height: 7)), with: .color(hex(0xfff2df)))
                    if !year.isEmpty { c.draw(Text(year).font(.system(size: 8, weight: .bold, design: .rounded)).foregroundColor(hex(0xa07858)), at: CGPoint(x: 214, y: 93)) }
                    var front = Path(); front.move(to: CGPoint(x: 0, y: 122)); quad(&front, CGPoint(x: 120, y: 92), CGPoint(x: 240, y: 112)); quad(&front, CGPoint(x: 360, y: 132), CGPoint(x: 360, y: 104))
                    front.addLine(to: CGPoint(x: 360, y: 150)); front.addLine(to: CGPoint(x: 0, y: 150)); front.closeSubpath()
                    c.fill(front, with: .color(hex(0xcfe0b6)))
                    var trail = Path(); trail.move(to: CGPoint(x: 40, y: 121)); quad(&trail, CGPoint(x: 74, y: 108), CGPoint(x: 108, y: 111)); quad(&trail, CGPoint(x: 142, y: 114), CGPoint(x: 176, y: 115)); quad(&trail, CGPoint(x: 210, y: 116), CGPoint(x: 244, y: 108))
                    c.stroke(trail, with: .color(hex(0xb98b62)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 5]))
                    for i in 0...n {
                        let p = BurrowLifeScene.stone(i, n), r = CGRect(x: p.x - 10, y: p.y + 1 - 4, width: 20, height: 8)
                        c.fill(Path(ellipseIn: r), with: .color(i <= k ? hex(0xf4b183) : hex(0xefe1cf)))
                        c.stroke(Path(ellipseIn: r), with: .color(hex(0xc8a27e)), lineWidth: 1)
                    }
                    let end = BurrowLifeScene.stone(n, n)
                    var pole = Path(); pole.move(to: end); pole.addLine(to: CGPoint(x: end.x, y: end.y - 20))
                    c.stroke(pole, with: .color(hex(0x8b5a3c)), lineWidth: 1.5)
                    var flag = Path(); flag.move(to: CGPoint(x: end.x, y: end.y - 20)); flag.addLine(to: CGPoint(x: end.x + 11, y: end.y - 16)); flag.addLine(to: CGPoint(x: end.x, y: end.y - 12)); flag.closeSubpath()
                    c.fill(flag, with: .color(bClay))
                    // the plant: a leaf per step of the month goal
                    c.translateBy(x: 315, y: 128)
                    var pot = Path(); pot.move(to: CGPoint(x: -11, y: 0)); pot.addLine(to: CGPoint(x: 11, y: 0)); pot.addLine(to: CGPoint(x: 8, y: 14)); pot.addLine(to: CGPoint(x: -8, y: 14)); pot.closeSubpath()
                    c.fill(pot, with: .color(hex(0xc9764f)))
                    c.fill(Path(roundedRect: CGRect(x: -13, y: -3, width: 26, height: 5), cornerRadius: 2), with: .color(hex(0xb0613e)))
                    let top = -14 - 12 * CGFloat(ln - 1) - 8
                    var stem = Path(); stem.move(to: CGPoint(x: 0, y: -3)); stem.addLine(to: CGPoint(x: 0, y: min(-34, top)))
                    c.stroke(stem, with: .color(bSageInk), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    for i in 0..<ln {
                        let y0 = -14 - 12 * CGFloat(i), left = i % 2 == 0, d: CGFloat = left ? -1 : 1
                        var leaf = Path(); leaf.move(to: CGPoint(x: 0, y: y0))
                        quad(&leaf, CGPoint(x: 16 * d, y: y0 - 2), CGPoint(x: 18 * d, y: y0 - 14)); quad(&leaf, CGPoint(x: 4 * d, y: y0 - 14), CGPoint(x: 0, y: y0)); leaf.closeSubpath()
                        if i < lk { c.fill(leaf, with: .color(left ? bSage : hex(0x8fb98a))) }
                        else { c.fill(Path(ellipseIn: CGRect(x: 2 * d - 2, y: y0 - 4, width: 4, height: 4)), with: .color(bSage.opacity(0.4))) }
                    }
                }
                let p = BurrowLifeScene.stone(k, n)
                ScenePet(fur: m.breed.fur, dark: m.breed.dark)
                    .scaleEffect(sc)
                    .position(x: ox + p.x * sc, y: oy + (p.y - 18) * sc)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: k)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { m.bump("week") }
        .help("Click: Buddy walks one stone further this week")
    }
}

/// Work: a stove with one steaming pot per session that's cooking.
struct BurrowWorkScene: View {
    @ObservedObject var m: Model
    var body: some View {
        let pots = Array(m.working.prefix(3))
        GeometryReader { geo in
            let (sc, ox, oy) = sceneTransform(geo.size)
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: pots.isEmpty ? 60 : 1.0 / 20)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { c, size in
                        c.translateBy(x: ox, y: oy); c.scaleBy(x: sc, y: sc)
                        c.fill(Path(CGRect(x: 0, y: 0, width: 360, height: 150)), with: .color(hex(0xf7e2c6)))
                        c.fill(Path(roundedRect: CGRect(x: 262, y: 34, width: 70, height: 46), cornerRadius: 8), with: .color(hex(0xffd3a3)))
                        var cross = Path(); cross.move(to: CGPoint(x: 297, y: 34)); cross.addLine(to: CGPoint(x: 297, y: 80)); cross.move(to: CGPoint(x: 262, y: 57)); cross.addLine(to: CGPoint(x: 332, y: 57))
                        c.stroke(cross, with: .color(hex(0xf7e2c6)), lineWidth: 3)
                        c.fill(Path(ellipseIn: CGRect(x: 276, y: 42, width: 12, height: 12)), with: .color(hex(0xfff4dc).opacity(0.9)))
                        c.fill(Path(CGRect(x: 0, y: 116, width: 360, height: 34)), with: .color(hex(0xc99c74)))
                        c.fill(Path(CGRect(x: 0, y: 113, width: 360, height: 5)), with: .color(hex(0xb3845d)))
                        c.fill(Path(roundedRect: CGRect(x: 96, y: 112, width: 200, height: 6), cornerRadius: 3), with: .color(hex(0x6b4a36)))
                        for (i, s) in pots.enumerated() {
                            let x = pots.count == 1 ? 196 : 130 + CGFloat(i) * (132 / CGFloat(max(pots.count - 1, 1)))
                            let col = (s.source ?? "").hasPrefix("codex") ? codexColor : bClay
                            var g = c; g.translateBy(x: x, y: 104)
                            for (dx, delay) in [(-4.0, Double(i) * 0.6), (5.0, Double(i) * 0.6 + 1.1)] {
                                let ph = ((t + delay).truncatingRemainder(dividingBy: 2.4)) / 2.4
                                let op = ph < 0.3 ? ph / 0.3 * 0.75 : 0.75 * (1 - (ph - 0.3) / 0.7)
                                var st = Path(); let y0 = -14 + 4 - 20 * ph
                                st.move(to: CGPoint(x: dx, y: y0)); quad(&st, CGPoint(x: dx - 4, y: y0 - 6), CGPoint(x: dx, y: y0 - 12)); quad(&st, CGPoint(x: dx + 4, y: y0 - 18), CGPoint(x: dx, y: y0 - 24))
                                g.stroke(st, with: .color(.white.opacity(op)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            }
                            g.fill(Path(roundedRect: CGRect(x: -17, y: -10, width: 34, height: 22), cornerRadius: 7), with: .color(col))
                            g.fill(Path(roundedRect: CGRect(x: -20, y: -13, width: 40, height: 5), cornerRadius: 2.5), with: .color(col.opacity(0.85)))
                            g.fill(Path(roundedRect: CGRect(x: -24, y: -4, width: 5, height: 3), cornerRadius: 1.5), with: .color(col))
                            g.fill(Path(roundedRect: CGRect(x: 19, y: -4, width: 5, height: 3), cornerRadius: 1.5), with: .color(col))
                        }
                    }
                }
                ScenePet(fur: m.breed.fur, dark: m.breed.dark).scaleEffect(sc).position(x: ox + 50 * sc, y: oy + (116 - 18) * sc)
            }
        }
    }
}

struct BubbleView: View {
    var bubble: Bubble
    var leftSide: Bool
    @ObservedObject var m: Model
    var body: some View {
        // Events get their mood colour; Bit's own chatter gets a neutral border so it never reads as an alert.
        let border = bubble.kind == .event ? bubble.tone.color : T.fg.opacity(0.25)
        let radius: CGFloat = bubble.kind == .thought ? 20 : 12
        VStack(alignment: leftSide ? .leading : .trailing, spacing: 3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bubble.text)
                    .font(.system(size: 12.5, weight: bubble.kind == .quote ? .regular : .medium, design: bubble.kind == .quote ? .serif : .rounded))
                    .italic(bubble.kind == .quote)
                    .foregroundColor(T.fg)
                    .lineLimit(9)
                    .fixedSize(horizontal: false, vertical: true)
                if let r = bubble.react {
                    HStack(spacing: 5) {
                        Chip(label: "👍 Nice") { r(true); m.bubble = nil; m.onExpandChange?() }
                        Chip(label: "👎 Not for me") { r(false); m.bubble = nil; m.onExpandChange?() }
                    }.padding(.top, 2)
                }
                if let b = bubble.byline {
                    Text(b).font(.system(size: 10.5, weight: .semibold, design: T.design)).foregroundColor(T.sub)
                }
                if bubble.kind == .quote || bubble.kind == .thought {
                    HStack(spacing: 5) {
                        Chip(label: "Copy") { m.copyBubble(bubble) }
                        Chip(label: m.favorites.contains(bubble.text) ? "♥ Saved" : "♡ Save") { m.toggleFavorite(bubble) }
                        if bubble.text.contains("Write it down once?"), let rule = m.scoldRule {
                            Chip(label: "Copy rule", primary: true) { m.copy(rule); m.flash = "Rule copied 📋" }
                        } else {
                            Chip(label: "More") { m.bubble = nil; m.showCard = true; m.onExpandChange?() }
                        }
                        if let f = m.flash { Text(f).font(.system(size: 10, weight: .semibold, design: T.design)).foregroundColor(Mood.happy.color) }
                    }.padding(.top, 2)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: radius).fill(T.solid))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(border, lineWidth: 1.5))
            if bubble.kind == .thought {
                // thought-cloud tail: two little circles stepping down to the cat
                HStack(spacing: 0) {
                    Circle().fill(T.solid).overlay(Circle().stroke(border, lineWidth: 1.2)).frame(width: 9, height: 9)
                }.padding(.horizontal, 22)
                Circle().fill(T.solid).overlay(Circle().stroke(border, lineWidth: 1)).frame(width: 5, height: 5).padding(.horizontal, 30)
            }
        }
        .frame(maxWidth: 270, alignment: leftSide ? .leading : .trailing)
    }
}

/// One tiny kitten per Claude session waiting for your OK. Asleep after 10 minutes of waiting.
struct LitterView: View {
    @ObservedObject var m: Model
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(m.waiting.enumerated()), id: \.element.id) { i, s in
                Kitten(breed: breeds[(i + 2) % breeds.count], asleep: Date().timeIntervalSince1970 - s.ts > 600, codex: (s.source ?? "").hasPrefix("codex"))
                    .help("\(s.repo ?? "A session") is waiting for your OK · \(ago(Date().timeIntervalSince1970 - s.ts))\n\(s.activity ?? "")\nclick to go to Claude")
                    .onTapGesture { activate(s) }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

struct Kitten: View {
    var breed: Breed
    var asleep: Bool
    var codex = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10)) { t in
            let s = t.date.timeIntervalSinceReferenceDate
            ZStack {
                Ellipse().fill(breed.fur).frame(width: 26, height: 15).position(x: 15, y: 33)
                if isBear {
                    ForEach([7.0, 23.0], id: \.self) { x in Circle().fill(breed.points ?? breed.fur).frame(width: 8, height: 8).position(x: x, y: 9) }
                } else if !isPug {
                    Tri(a: CGPoint(x: 6, y: 12), b: CGPoint(x: 7, y: 2), c: CGPoint(x: 13, y: 8)).fill(breed.points ?? breed.fur)
                    Tri(a: CGPoint(x: 17, y: 8), b: CGPoint(x: 23, y: 2), c: CGPoint(x: 24, y: 12)).fill(breed.points ?? breed.fur)
                }
                Circle().fill(breed.fur).frame(width: 20, height: 19).position(x: 15, y: 17)
                if isBear { Ellipse().fill(breed.belly).frame(width: 10, height: 7).position(x: 15, y: 21) }
                if isPug, let mk = breed.mask {
                    Tri(a: CGPoint(x: 4, y: 11), b: CGPoint(x: 10, y: 9), c: CGPoint(x: 6, y: 18)).fill(mk)
                    Tri(a: CGPoint(x: 20, y: 9), b: CGPoint(x: 26, y: 11), c: CGPoint(x: 24, y: 18)).fill(mk)
                    Ellipse().fill(mk).frame(width: 11, height: 8).position(x: 15, y: 21)
                }
                if codex {
                    Text("◆").font(.system(size: 7, weight: .black, design: .rounded)).foregroundColor(.white)
                        .frame(width: 10, height: 10).background(Circle().fill(Color(red: 0.06, green: 0.64, blue: 0.5))).position(x: 15, y: 29)
                }
                if asleep {
                    HStack(spacing: 5) { Capsule().frame(width: 4, height: 1.2); Capsule().frame(width: 4, height: 1.2) }
                        .foregroundColor(ink.opacity(0.7)).position(x: 15, y: 17)
                    Text("z").font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundColor(.white).position(x: 27, y: 4 - CGFloat(Int(s) % 2) * 2)
                } else {
                    HStack(spacing: 5) { Circle().fill(breed.eye == ink ? ink : breed.eye).frame(width: 4); Circle().fill(breed.eye == ink ? ink : breed.eye).frame(width: 4) }
                        .position(x: 15, y: 16)
                    Text("?").font(.system(size: 9, weight: .black, design: .rounded)).foregroundColor(ink)
                        .frame(width: 11, height: 11).background(Circle().fill(Mood.waiting.color))
                        .position(x: 27, y: 3 + sin(s * 5) * 1.5)
                }
            }
            .frame(width: 30, height: 42)
            .shadow(color: .black.opacity(0.4), radius: 0.8)
            .rotationEffect(.degrees(asleep ? 0 : sin(s * 3) * 4), anchor: .bottom)
        }
        .frame(width: 30, height: 42)
    }
}


/// The celebration clip, 15 fps, mirrored to face the way Buddy walks.
struct DanceView: View {
    @ObservedObject var m: Model
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { t in
            let i = min(danceFrames.count - 1, max(0, Int((t.date.timeIntervalSince(m.dancingUntil) + Double(danceFrames.count) / 15) * 15)))
            Image(nsImage: danceFrames[i]).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 84, height: 92).offset(y: -10)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        }
        .frame(width: 84, height: 72)
    }
}



struct CardHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PetView: View {
    @ObservedObject var m: Model
    @State private var catHover = false
    @State private var cardHover = false
    @State private var petTimer: Timer?

    var body: some View {
        VStack(alignment: m.leftSide ? .leading : .trailing, spacing: 6) {
            Spacer(minLength: 0)
            if m.showCard {
                ScrollView(showsIndicators: false) {
                    Card(m: m).fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in Color.clear.preference(key: CardHeight.self, value: g.size.height) })
                }
                .frame(maxHeight: m.cardHeight > 0 ? m.cardHeight : nil)
                .onPreferenceChange(CardHeight.self) { h in
                    if abs(h - m.cardHeight) > 1 { m.cardHeight = h; m.onExpandChange?() }
                    if CommandLine.arguments.contains("--card") { FileHandle.standardError.write("card height \(Int(h))\n".data(using: .utf8)!) }
                }
                .onHover { cardHover = $0; settle() }
            } else if let b = m.bubble, !m.squatting {
                BubbleView(bubble: b, leftSide: m.leftSide, m: m)
                    .onHover { m.holdBubble($0) }
                    .onTapGesture { if b.kind != .quote && b.kind != .thought { b.action?(); m.bubble = nil; m.onExpandChange?() } }
            }
            Group { if m.dancing { DanceView(m: m) } else { Cat(m: m) } }
                .padding(.top, 20)
                .overlay(alignment: .top) {   // CI weather: rain while a PR is red, sun after a merge
                    if m.sunUntil > Date() { Text("☀️").font(.system(size: 18)) }
                    else if !m.needsYouPRs.isEmpty { Text("🌧️").font(.system(size: 18)).help("\(m.needsYouPRs.count) red PR") }
                }
                .contentShape(Rectangle())
                .onHover { h in
                    catHover = h
                    m.hovering = h
                    settle()
                    petTimer?.invalidate()
                    if h { petTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in m.hearts += 1 } }
                }
                .contextMenu {
                    Button(m.snoozed ? "Wake up" : "Nap 1h") { m.toggleSnooze() }
                    Divider()
                    Menu("Theme") {
                        ForEach(["burrow", "glass", "ink"], id: \.self) { n in
                            Button((m.themeName == n ? "✓ " : "    ") + n.capitalized) { m.setTheme(n) }
                        }
                    }
                    Button("Set goals…") { DispatchQueue.main.async { m.setGoals() } }
                    Button("Tell Buddy…") { DispatchQueue.main.async { m.tellBuddy() } }
                    Button("Add task…") { DispatchQueue.main.async { m.addTask() } }
                    Button("Open task list") { openText(tasksPath) }
                    Divider()
                    Button(m.life == nil ? "Set up my profile…" : "Update my profile…") { DispatchQueue.main.async { onboard(m) } }
                    if m.life != nil { Button("Edit profile file") { openText(lifePath) } }
                    Divider()
                    Button("Close Buddy") { NSApp.terminate(nil) }   // exit 0: launchd leaves it closed until next login
                }
                .onTapGesture(count: 2) { m.nextBreed() }
                .onTapGesture { m.doGesture() }
                .help("Hover for what needs you · click for a trick · double-click for a new breed · drag to move")
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: m.leftSide ? .bottomLeading : .bottomTrailing)
    }

    func settle() {
        if cardHover || (catHover && m.showCard) { return }
        if catHover {
            // dwell: a cat walking under a resting cursor must not pop the card open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard catHover, !m.showCard else { return }
                m.bubble = nil; m.pose = .none; m.tab = m.familyTime ? "personal" : "work"; m.showCard = true; m.onExpandChange?()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !catHover && !cardHover && m.showCard && !mouseInPet() { m.showCard = false; m.showStale = false; m.hoverEnded(); m.onExpandChange?() }
            }
        }
    }
}

// MARK: window + wandering

final class Panel: NSPanel {
    override var canBecomeKey: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var panel: Panel!
    let small = NSSize(width: 100, height: 108)
    let big = NSSize(width: 360, height: 660)
    var target: CGFloat?
    var litter: Panel!
    var homeY: CGFloat = 0
    var squatHoldUntil = Date.distantPast
    var forcedSquat = CommandLine.arguments.contains("--squat-now")          // the floor Bit walks on, restored after squatting

    var screen: NSRect { (panel.screen ?? NSScreen.main!).visibleFrame }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let s = NSScreen.main!.visibleFrame
        panel = Panel(contentRect: NSRect(x: s.maxX - small.width - 12, y: s.minY + 110, width: small.width, height: small.height),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: PetView(m: model))
        host.sizingOptions = []   // we size the window ourselves; SwiftUI must not grow it
        panel.contentView = host
        panel.orderFrontRegardless()
        homeY = panel.frame.minY

        litter = Panel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 50), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        litter.isOpaque = false; litter.backgroundColor = .clear; litter.hasShadow = false; litter.level = .floating
        litter.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        litter.contentView = NSHostingView(rootView: LitterView(m: model))

        blobCenter = { [weak self] in
            guard let self = self else { return .zero }
            let f = self.panel.frame
            let x = self.model.leftSide && self.model.expanded ? f.minX + 8 + 42 : f.maxX - 8 - 42
            return CGPoint(x: x, y: f.minY + 8 + 36)
        }
        mouseInPet = { [weak self] in
            guard let self = self else { return false }
            // the card's own rectangle: the window minus its transparent margin above the card
            return self.panel.frame.contains(NSEvent.mouseLocation)
        }
        model.onExpandChange = { [weak self] in self?.resize() }
        model.loadSessions()
        model.loadPRs()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.model.loadSessions() }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.model.loadPRs() }
        model.loadStats()
        model.anotherQuote()   // so the wisdom box is never empty
        if let i = CommandLine.arguments.firstIndex(of: "--theme"), i + 1 < CommandLine.arguments.count { T = themes[CommandLine.arguments[i + 1]] ?? T; model.themeName = T.name }
        if CommandLine.arguments.contains("--personal") { model.tab = "personal" }
        if CommandLine.arguments.contains("--card") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.model.bubble = nil; self.model.showCard = true; self.model.onExpandChange?() }
        }
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.model.loadStats() }
        Timer.scheduledTimer(withTimeInterval: CommandLine.arguments.contains("--demo") ? 3 : 30, repeats: true) { [weak self] _ in self?.model.ambientTick() }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.wander() }
        // a new breed every 15 min (quietly: no bubble while something needs you or the card is open)
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            guard let m = self?.model, !m.snoozed else { return }
            m.nextBreed(quiet: m.hasP0 || m.expanded)
        }
        model.scanScoldings()
        model.loadLimits()
        if model.life == nil, !UserDefaults.standard.bool(forKey: "bit.onboardOffered") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let m = self?.model else { return }
                UserDefaults.standard.set(true, forKey: "bit.onboardOffered")
                m.say("Hi! I can look out for your people, goals and tasks too, not just code. Tap to set me up 💛", .calm, seconds: 30, kind: .event, sound: "Pop") { onboard(m) }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.model.loadLimits() }
        Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in if self?.model.showCard == true { self?.model.rotateTick += 1 } }
        Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.model.scanScoldings() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.squatter() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.model.dayCare() }
        model.checkDisk()
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.model.checkDisk() }
        if CommandLine.arguments.contains("--tricks") {
            Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in self?.model.doGesture() }
            Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in self?.model.nextBreed() }
        }
    }

    /// Stroll along the bottom of the screen when nothing needs you; stop and sit when something does.
    /// Keep the litter of waiting kittens just beside Bit.
    func placeLitter() {
        let n = model.waiting.count
        guard n > 0, !model.squatting else { if litter.isVisible { litter.orderOut(nil) }; return }
        let w = CGFloat(n) * 36 + 8, f = panel.frame
        let catX = model.leftSide && model.expanded ? f.minX + 8 : f.maxX - 8 - 84
        let x = catX - w >= screen.minX ? catX - w : catX + 84   // the side with room
        let want = NSRect(x: max(screen.minX, min(x, screen.maxX - w)), y: f.minY + 4, width: w, height: 50)
        if litter.frame != want { litter.setFrame(want, display: true) }   // runs 30×/s; touch the window only when it moves
        if !litter.isVisible { litter.orderFrontRegardless() }
    }

    /// Squatter: after 5 idle minutes, sleep on top of the front window. Jump down, annoyed, when you're back.
    func squatter() {
        let m = model
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if m.squatting {
            if idle < 2 && Date() > squatHoldUntil {
                m.squatting = false
                m.zoomies = false
                panel.level = .floating
                var f = panel.frame
                f.origin.y = homeY
                panel.setFrame(f, display: true, animate: true)
                m.say(["hmph. I was comfy.", "oh, you're back 😾", "fine. FINE."].randomElement()!, .calm, seconds: 4, kind: .ambient)
            }
            return
        }
        let after = CommandLine.arguments.firstIndex(of: "--squat").flatMap { Double(CommandLine.arguments[$0 + 1]) } ?? 300
        let forced = forcedSquat
        guard forced || idle > after, !m.expanded, !m.snoozed,
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let full = NSScreen.screens.first?.frame,
              let win = wins.first(where: { w in
                  guard (w[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier, (w[kCGWindowLayer as String] as? Int) == 0,
                        let b = w[kCGWindowBounds as String] as? [String: CGFloat], let y = b["Y"], let h = b["Height"] else { return false }
                  return y >= 0 && y < full.height - 120 && h > 100   // title bar on screen, a real window
              }),
              let b = win[kCGWindowBounds as String] as? [String: CGFloat], let wy = b["Y"], let wx = b["X"], let ww = b["Width"],
              let screenH = NSScreen.screens.first?.frame.height else { return }
        let top = screenH - wy                       // window's top edge, in Cocoa coordinates
        var f = panel.frame
        f.origin.x = min(max(wx + ww - 150, screen.minX), screen.maxX - f.width)
        f.size = small
        f.origin.y = top - 10   // feet on the title bar; the rest may overhang the menu bar
        panel.level = .statusBar
        if forced { forcedSquat = false; squatHoldUntil = Date().addingTimeInterval(8) }
        m.squatting = true
        m.walking = false
        panel.setFrame(f, display: true, animate: true)
    }

    var tick = 0
    func wander() {
        let m = model
        // 30 Hz only while walking; 2 Hz otherwise
        tick += 1
        let moving = m.walking || m.zoomies || target != nil
        if !moving && tick % 15 != 0 { return }
        placeLitter()
        if m.squatting { return }
        // never lose Buddy: if the window ended up off every screen, put it back on the floor
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            let v = NSScreen.main!.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - panel.frame.width - 12, y: v.minY + 110))
        }
        homeY = panel.frame.minY   // follow wherever you dragged Buddy
        let idle = !m.expanded && !m.hovering && m.gesture == .none && m.mood != .asleep
        if idle && Int.random(in: 0..<180) == 0 { m.doGesture() }   // ~every 90 s at 2 Hz   // a trick every ~90 s on average
        if m.zoomies {
            var f = panel.frame
            if target == nil || abs((target ?? 0) - f.minX) < 8 {
                target = f.midX < screen.midX ? screen.maxX - small.width - 10 : screen.minX + 10
            }
            let dx = target! - f.minX
            if !m.walking { m.walking = true }
            if m.facingLeft != (dx < 0) { m.facingLeft = dx < 0 }
            f.origin.x += dx > 0 ? min(9, dx) : max(-9, dx)
            panel.setFrameOrigin(f.origin)
            return
        }
        let canWalk = !m.expanded && !m.hovering && (m.mood == .calm || m.mood == .busy)
        guard canWalk else { if m.walking { m.walking = false }; target = nil; return }
        var f = panel.frame
        if target == nil {
            guard Int.random(in: 0..<16) == 0 else { return }  // ~every 8 s at 2 Hz, decide to stroll
            target = CGFloat.random(in: (screen.minX + 10)...(screen.maxX - small.width - 10))
        }
        guard let t = target else { return }
        let dx = t - f.minX
        if abs(dx) < 2 { target = nil; m.walking = false; return }
        if !m.walking { m.walking = true }
        if m.facingLeft != (dx < 0) { m.facingLeft = dx < 0 }
        f.origin.x += dx > 0 ? min(1.3, dx) : max(-1.3, dx)
        panel.setFrameOrigin(f.origin)
    }

    /// Grow the window away from the nearer screen edge, keeping the cat where it is.
    func resize() {
        let f = panel.frame
        if f.width <= small.width + 1 { model.leftSide = f.midX < screen.midX }
        var size = model.expanded && !model.squatting ? big : small
        if model.showCard && !model.squatting {
            let want = (model.cardHeight > 0 ? model.cardHeight : big.height - small.height) + small.height + 22
            let room = screen.maxY - f.minY - small.height - 22
            if model.cardHeight > room && !model.tight { model.tight = true }                 // too tall: the quote goes
            else if model.tight && model.cardHeight + 140 < room { model.tight = false }       // plenty of room again (140 ≈ a quote, so no flip-flop)
            size = NSSize(width: max(big.width, model.cardWidth + 30), height: min(want, screen.maxY - f.minY))
            if CommandLine.arguments.contains("--card") { FileHandle.standardError.write("room for card \(Int(screen.maxY - f.minY - small.height - 22))\n".data(using: .utf8)!) }
        }
        let x = model.leftSide ? f.minX : f.maxX - size.width
        panel.setFrame(NSRect(x: x, y: f.minY, width: size.width, height: size.height), display: true, animate: false)
    }
}


// MARK: disk space and git worktrees (every 10 min). Buddy only reports; it never deletes anything.

var diskLowGB: Double { config["diskGB"] as? Double ?? Double(config["diskGB"] as? Int ?? 25) }

struct Worktree: Hashable { var path: String; var repo: String; var idleDays: Int; var inUse: Bool }

func freeGB() -> Double {
    let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey])
    return Double(v?.volumeAvailableCapacity ?? -1) / 1e9
}

func git(_ args: [String]) -> String {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p.arguments = args
    p.standardOutput = out; p.standardError = Pipe()
    guard (try? p.run()) != nil else { return "" }
    let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return String(data: d, encoding: .utf8) ?? ""
}

/// Every linked worktree of every repo Buddy has seen a session in (remembered across restarts).
func listWorktrees(cwds: [String]) -> [Worktree] {
    var repos = Set(UserDefaults.standard.stringArray(forKey: "bit.repos") ?? [])
    for c in Set(cwds) {
        let common = git(["-C", c, "rev-parse", "--path-format=absolute", "--git-common-dir"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !common.isEmpty { repos.insert(common) }
    }
    repos = repos.filter { FileManager.default.fileExists(atPath: $0) }
    UserDefaults.standard.set(Array(repos), forKey: "bit.repos")
    var out: [Worktree] = []
    for common in repos {
        let paths = git(["--git-dir", common, "worktree", "list", "--porcelain"]).split(separator: "\n")
            .filter { $0.hasPrefix("worktree ") }.map { String($0.dropFirst(9)) }.dropFirst()   // the first is the main checkout
        let repo = ((common as NSString).deletingLastPathComponent as NSString).lastPathComponent
        for p in paths {
            // last touched: the worktree's own index in <repo>/.git/worktrees/<name>/, updated by every git status/add
            let gitdir = ((try? String(contentsOfFile: p + "/.git", encoding: .utf8)) ?? "").replacingOccurrences(of: "gitdir: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let touched = (try? FileManager.default.attributesOfItem(atPath: gitdir + "/index"))?[.modificationDate] as? Date
                ?? (try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date ?? Date()
            out.append(Worktree(path: p, repo: repo, idleDays: Int(Date().timeIntervalSince(touched) / 86400), inUse: cwds.contains { $0.hasPrefix(p) }))
        }
    }
    return out.sorted { $0.idleDays > $1.idleDays }
}

func openWorktreeReport(_ wts: [Worktree]) {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("buddy-worktrees.txt")
    let lines = wts.map { String(format: "%4dd  %@  %@  %@", $0.idleDays, $0.inUse ? "IN USE" : "idle  ", $0.repo, $0.path) }
    let text = """
    \(Int(freeGB())) GB free · \(wts.count) worktrees, oldest first. Buddy never deletes anything.

    \(lines.joined(separator: "\n"))

    Before removing one:
      git -C <dir> status --porcelain -uno                 # tracked edits?
      git -C <dir> ls-files --others --exclude-standard    # untracked files?
      (cd <dir> && docker compose down -v)                 # if it ran a stack
    Then: git -C <dir> worktree remove <dir>   and   git worktree prune
    """
    try? text.write(toFile: path, atomically: true, encoding: .utf8)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-t", path]; try? p.run()
}

extension Model {
    func checkDisk() {
        let cwds = sessions.compactMap(\.cwd)
        DispatchQueue.global(qos: .utility).async {
            let gb = freeGB(), wts = listWorktrees(cwds: cwds)
            DispatchQueue.main.async {
                self.diskFreeGB = gb
                if wts != self.worktrees { self.worktrees = wts }
                guard gb >= 0, gb < diskLowGB, Date().timeIntervalSince(self.lastDiskNudge) > 3600 else { return }
                self.lastDiskNudge = Date()
                let idle = wts.filter { $0.idleDays >= 7 && !$0.inUse }.count
                self.say("Disk low: \(Int(gb)) GB free. \(wts.count) worktrees open, \(idle) untouched for a week. Tap for the list.",
                         gb < diskLowGB / 2 ? .upset : .waiting, seconds: 30) { openWorktreeReport(wts) }
            }
        }
    }
}

// MARK: `buddy say`: any agent (Claude, Codex, a scheduled job) can put a message in front of you

let inboxDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/pet/inbox")
extension Model {
    /// One message per 2-s tick, oldest first. Urgent ones interrupt; others wait for the current bubble. Older than 2 h: dropped.
    func readInbox(_ sessions: [Session]) {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: inboxDir)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        for f in files {
            let path = (inboxDir as NSString).appendingPathComponent(f)
            guard let d = fm.contents(atPath: path), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let text = j["text"] as? String else { try? fm.removeItem(atPath: path); continue }
            if Date().timeIntervalSince1970 - (j["ts"] as? Double ?? 0) > 7200 { try? fm.removeItem(atPath: path); continue }
            let urgent = j["urgent"] as? Bool ?? false, cwd = j["cwd"] as? String ?? ""
            if snoozed || showCard || (bubble?.kind == .event && !urgent) { return }   // napping: keep it for later; never yank the card away; let the current alert finish
            try? fm.removeItem(atPath: path)
            let from = sessions.first { s in s.cwd.map { cwd == $0 || cwd.hasPrefix($0 + "/") } ?? false }
            let who = from?.repo ?? (cwd as NSString).lastPathComponent
            say("\(who): \(text)", urgent ? .waiting : .calm, seconds: urgent ? 40 : 20, kind: .event, sound: urgent ? nil : "Pop",
                action: from.map { s in { activate(s) } })
            return
        }
    }
}

// MARK: your life, privately: ~/.config/buddy/life.json (people, goals) and tasks.md. Never in the repo, never sent anywhere
// (except a person's name and likes to your own Claude, for gift ideas, if you said yes).

var buddyDir: String { (NSHomeDirectory() as NSString).appendingPathComponent(".config/buddy") }
var lifePath: String { (buddyDir as NSString).appendingPathComponent("life.json") }
var tasksPath: String { (buddyDir as NSString).appendingPathComponent("tasks.md") }

struct Person: Codable {
    var name: String
    var relation: String            // wife | husband | partner | child | family
    var birthday: String? = nil     // "14 Feb"
    var anniversary: String? = nil
    var likes: String? = nil
    var bedtime: String? = nil      // "21:00", children
    var call: String? = nil         // "Sunday" or "Wednesday, Sunday"
    var callTime: String? = nil     // "09:30": a time that suits both (e.g. someone abroad)
}
struct Event: Codable { var name: String; var date: String; var note: String? = nil; var gifts: String? = nil }   // date "8 Nov"; gifts "Mom, Dad"
/// A goal for one horizon. n = nil: done or not; n = 3: "k of 3". `set` is the day it was set (yyyy-MM-dd).
struct Goal: Codable, Equatable {
    var text: String; var n: Int? = nil; var k = 0; var done = false; var set: String
    init(text: String, n: Int? = nil, k: Int = 0, done: Bool = false, set: String) { self.text = text; self.n = n; self.k = k; self.done = done; self.set = set }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text); set = try c.decode(String.self, forKey: .set)
        n = try c.decodeIfPresent(Int.self, forKey: .n); k = try c.decodeIfPresent(Int.self, forKey: .k) ?? 0; done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}
struct Horizons: Codable { var today: Goal? = nil; var week: Goal? = nil; var month: Goal? = nil }
struct Life: Codable {
    var me: String? = nil
    var people: [Person] = []
    var kindPerWeek: Int? = nil
    var goals: [String] = []
    var stop: String? = nil         // "20:00"
    var resume: String? = nil       // "22:00": back at work after family time; the stop nudges end here
    var events: [Event] = []        // big dates that aren't anyone's birthday: a trip, a move
    var notes: [String] = []        // what you told Buddy ("Asha liked the green tote"); used for gift ideas
    var liked: [String] = []        // ideas you gave 👍
    var horizons: Horizons? = nil   // today / week / month goals
    var disliked: [String] = []     // ideas you gave 👎: never suggested again
    var giftIdeas: Bool? = nil
    var partner: Person? { people.first { ["wife", "husband", "partner"].contains($0.relation) } }

    init() {}
    /// Missing keys fall back to defaults. Synthesized Codable would reject the whole file, so a field added later blanks the profile.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        me = try c.decodeIfPresent(String.self, forKey: .me)
        people = try c.decodeIfPresent([Person].self, forKey: .people) ?? []
        kindPerWeek = try c.decodeIfPresent(Int.self, forKey: .kindPerWeek)
        goals = try c.decodeIfPresent([String].self, forKey: .goals) ?? []
        stop = try c.decodeIfPresent(String.self, forKey: .stop)
        resume = try c.decodeIfPresent(String.self, forKey: .resume)
        events = try c.decodeIfPresent([Event].self, forKey: .events) ?? []
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        liked = try c.decodeIfPresent([String].self, forKey: .liked) ?? []
        horizons = try c.decodeIfPresent(Horizons.self, forKey: .horizons)
        disliked = try c.decodeIfPresent([String].self, forKey: .disliked) ?? []
        giftIdeas = try c.decodeIfPresent(Bool.self, forKey: .giftIdeas)
    }
}

func loadLife() -> Life? { FileManager.default.contents(atPath: lifePath).flatMap { try? JSONDecoder().decode(Life.self, from: $0) } }
func saveLife(_ l: Life) {
    try? FileManager.default.createDirectory(atPath: buddyDir, withIntermediateDirectories: true)
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let d = try? e.encode(l) { FileManager.default.createFile(atPath: lifePath, contents: d, attributes: [.posixPermissions: 0o600]) }
}
/// One todo. From tasks.md ("- [ ] Diwali gifts #home due:1 Nov snooze:2026-10-07") or made by Buddy from a birthday.
struct Moment: Identifiable { var icon, who, when, detail: String; var id: String { detail + when }; var text: String { "\(who) · \(when.lowercased())" } }

struct Todo: Identifiable, Equatable {
    var id: String { line.isEmpty ? "auto:" + text : line }
    var text: String
    var area: String?        // home | work | career
    var due: Date?
    var line = ""            // the exact tasks.md line; empty for Buddy's own
}
func tokenValue(_ s: String, _ key: String) -> String? {
    guard let r = s.range(of: key + #":(\d{4}-\d{2}-\d{2}|\d{1,2} [A-Za-z]{3,9})"#, options: .regularExpression) else { return nil }
    return String(s[r].dropFirst(key.count + 1))
}
/// "25 Oct" → the nearest such date: up to ~2 months back counts as overdue, otherwise the next one.
func nearestDate(_ dm: String) -> Date? {
    guard let d = dayMonth(dm), let n = daysUntil(d) else { return nil }
    let today = Calendar.current.startOfDay(for: Date())
    return Calendar.current.date(byAdding: .day, value: n > 300 ? n - 365 : n, to: today)
}
let isoDay: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
func loadTasks() -> [Todo] {
    let today = isoDay.string(from: Date())
    return ((try? String(contentsOfFile: tasksPath, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { l -> Todo? in
        guard l.hasPrefix("- [ ] ") else { return nil }
        let raw = String(l.dropFirst(6))
        if let sn = tokenValue(raw, "snooze"), sn > today { return nil }   // "not today"
        let area = ["home", "work", "career"].first { raw.contains("#" + $0) }
        let text = raw.replacingOccurrences(of: #"\s*(#\w+|due:(\d{4}-\d{2}-\d{2}|\d{1,2} [A-Za-z]{3,9})|snooze:\d{4}-\d{2}-\d{2})"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return Todo(text: text, area: area, due: tokenValue(raw, "due").flatMap(nearestDate), line: String(l))
    }
}
/// "2d late" · "today" · "tomorrow" · "Fri" · "15 Oct"
func dueText(_ d: Date) -> (String, Bool) {
    let n = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day ?? 0
    let f = DateFormatter(); f.dateFormat = n < 7 ? "EEE" : "d MMM"
    return n < 0 ? ("\(-n)d late", true) : n == 0 ? ("today", true) : n == 1 ? ("tomorrow", false) : (f.string(from: d), false)
}
func openText(_ path: String) {
    if !FileManager.default.fileExists(atPath: path) {
        try? FileManager.default.createDirectory(atPath: buddyDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: (path == tasksPath ? "# Tasks  (- [ ] open, - [x] done; tag #home or #work)\n" : "{}\n").data(using: .utf8))
    }
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-t", path]; try? p.run()
}

/// "14 Feb", "Feb 14", "14/02", "2026-02-14"… → "14 Feb"
func dayMonth(_ s: String) -> String? {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    for fmt in ["d MMM", "MMM d", "d MMMM", "MMMM d", "d/M", "d-M", "yyyy-MM-dd", "d MMM yyyy", "MMMM d, yyyy", "d/M/yyyy", "d.M"] {
        f.dateFormat = fmt
        if let d = f.date(from: s.trimmingCharacters(in: .whitespaces)) { f.dateFormat = "d MMM"; return f.string(from: d) }
    }
    return nil
}
func daysUntil(_ dm: String) -> Int? {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"
    guard let d = f.date(from: dm) else { return nil }
    let cal = Calendar.current, c = cal.dateComponents([.month, .day], from: d)
    guard let next = cal.nextDate(after: cal.startOfDay(for: Date()).addingTimeInterval(-1), matching: c, matchingPolicy: .nextTime) else { return nil }
    return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: next).day
}
func minutes(_ hm: String?) -> Int? {
    let p = (hm ?? "").split(separator: ":").compactMap { Int($0) }
    return p.count == 2 && (0..<24).contains(p[0]) && (0..<60).contains(p[1]) ? p[0] * 60 + p[1] : nil
}
/// 6h40 · 35m
func hm(_ t: TimeInterval) -> String { let m = Int(t) / 60; return m >= 60 ? "\(m / 60)h\(String(format: "%02d", m % 60))" : "\(m)m" }
let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

extension Model {
    var familyTime: Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date()), mins = c.hour! * 60 + c.minute!
        return mins >= (minutes(life?.stop ?? config["stop"] as? String) ?? 20 * 60) && mins < (minutes(life?.resume) ?? 24 * 60)
    }
    /// Everything to do, one list: tasks.md plus gifts Buddy adds 21 days before a birthday. Late first, then by due date, then undated.
    var todos: [Todo] {
        let year = Calendar.current.component(.year, from: Date())
        var auto: [Todo] = []
        for p in life?.people ?? [] {
            for (what, d) in [("birthday", p.birthday), ("anniversary", p.anniversary)] {
                guard let d = d, let n = daysUntil(d), n <= 21 else { continue }
                let text = what == "anniversary" ? "Anniversary plan with \(p.name)" : "\(p.name)'s birthday gift"
                if UserDefaults.standard.bool(forKey: "bit.autodone.\(year).\(text)") || (UserDefaults.standard.string(forKey: "bit.autosnooze.\(text)") ?? "") > isoDay.string(from: Date()) { continue }
                auto.append(Todo(text: text, area: "home", due: nearestDate(d)))
            }
        }
        let all = tasks + auto
        return all.enumerated().sorted { a, b in
            switch (a.element.due, b.element.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    func tick(_ t: Todo) {
        if t.line.isEmpty {
            UserDefaults.standard.set(true, forKey: "bit.autodone.\(Calendar.current.component(.year, from: Date())).\(t.text)")
        } else if var text = try? String(contentsOfFile: tasksPath, encoding: .utf8), let r = text.range(of: t.line) {
            text.replaceSubrange(r, with: "- [x] " + t.line.dropFirst(6))
            try? text.write(toFile: tasksPath, atomically: true, encoding: .utf8)
        }
        tasks = loadTasks(); objectWillChange.send(); celebrate += 1
    }

    /// Hide it until tomorrow.
    func notToday(_ t: Todo) {
        let tomorrow = isoDay.string(from: Date().addingTimeInterval(86400))
        if t.line.isEmpty {
            UserDefaults.standard.set(tomorrow, forKey: "bit.autosnooze.\(t.text)")
        } else if var text = try? String(contentsOfFile: tasksPath, encoding: .utf8), let r = text.range(of: t.line) {
            let clean = t.line.replacingOccurrences(of: #"\s*snooze:\d{4}-\d{2}-\d{2}"#, with: "", options: .regularExpression)
            text.replaceSubrange(r, with: clean + " snooze:" + tomorrow)
            try? text.write(toFile: tasksPath, atomically: true, encoding: .utf8)
        }
        tasks = loadTasks(); objectWillChange.send()
    }

    /// The goal for "today" | "week" | "month", only while it's still that day / week / month.
    func goal(_ which: String) -> Goal? {
        guard let h = life?.horizons, let g = which == "today" ? h.today : which == "week" ? h.week : h.month, let set = isoDay.date(from: g.set) else { return nil }
        let cal = Calendar.current
        switch which {
        case "today": return cal.isDateInToday(set) ? g : nil
        case "week": return cal.isDate(set, equalTo: Date(), toGranularity: .weekOfYear) ? g : nil
        default: return cal.isDate(set, equalTo: Date(), toGranularity: .month) ? g : nil
        }
    }
    func updateGoal(_ which: String, _ change: (inout Goal) -> Void) {
        guard var g = goal(which) else { setGoal(which); return }
        change(&g)
        var l = loadLife() ?? Life(), h = l.horizons ?? Horizons()
        switch which { case "today": h.today = g; case "week": h.week = g; default: h.month = g }
        l.horizons = h; saveLife(l); life = l; objectWillChange.send()
        if g.done || (g.n != nil && g.k == g.n) { celebrate += 1; doGesture(.hop) }
    }
    /// Click: today toggles done; week/month count up one (wrapping back to 0).
    func bump(_ which: String) {
        updateGoal(which) { g in if let n = g.n { g.k = (g.k + 1) % (n + 1); g.done = g.k == n } else { g.done.toggle() } }
    }
    /// Ask for one goal. Ending with "/3" makes it a count: "3 real conversations /3".
    func setGoal(_ which: String) {
        let label = ["today": "today", "week": "this week", "month": "this month"][which]!
        guard let a = try? ask("Your goal for \(label)?" + (which == "today" ? "" : "\nEnd with /3 to count it, like \"3 customer calls /3\"."),
                               which == "today" ? "Ship the onboarding PR" : "3 customer calls /3", goal(which).map { g in g.text + (g.n.map { " /\($0)" } ?? "") } ?? ""),
              !a.isEmpty else { return }
        var text = a, n: Int? = nil
        if let r = a.range(of: #"\s*/\s*(\d+)\s*$"#, options: .regularExpression) { n = Int(a[r].filter(\.isNumber)); text = String(a[..<r.lowerBound]) }
        var l = loadLife() ?? Life(), h = l.horizons ?? Horizons()
        let g = Goal(text: text, n: n, set: isoDay.string(from: Date()))
        switch which { case "today": h.today = g; case "week": h.week = g; default: h.month = g }
        l.horizons = h; saveLife(l); life = l; objectWillChange.send()
    }
    func setGoals() { for w in ["today", "week", "month"] { setGoal(w) } }

    /// Next few people moments: the next call, then dates within 30 days.
    var moments: [Moment] {
        var out: [(Int, Moment)] = []   // (minutes from now, moment)
        let cal = Calendar.current, now = Date()
        for p in life?.people ?? [] where p.call != nil {
            for d in 0..<8 {
                let day = cal.date(byAdding: .day, value: d, to: now)!, wd = weekdays[cal.component(.weekday, from: day) - 1]
                guard p.call!.contains(wd) else { continue }
                let at = minutes(p.callTime) ?? 18 * 60
                let c = cal.dateComponents([.hour, .minute], from: now)
                if d == 0 && at < c.hour! * 60 + c.minute! { continue }
                let when = "\(d == 0 ? "Today" : d == 1 ? "Tomorrow" : String(wd.prefix(3))) \(p.callTime ?? "")".trimmingCharacters(in: .whitespaces)
                out.append((d * 1440 + at, Moment(icon: "📞", who: p.name, when: when, detail: "Call \(p.name)")))
                break
            }
        }
        func add(_ date: String?, _ icon: String, _ who: String, _ detail: String) {
            guard let date = date, let n = daysUntil(date), n <= 30 else { return }
            out.append((n * 1440 + 1, Moment(icon: icon, who: who, when: n == 0 ? "Today" : date, detail: detail + (n > 0 && n <= 21 ? " · \(n)d" : ""))))
        }
        for p in life?.people ?? [] {
            add(p.birthday, "🎂", p.name, "\(p.name)'s birthday")
            add(p.anniversary, "💛", "Anniversary", "Anniversary")
        }
        for e in life?.events ?? [] {
            let name = e.name.components(separatedBy: " (").first ?? e.name
            add(e.date, e.name.contains("Diwali") ? "🪔" : "🗓", name, name)
        }
        return out.sorted { $0.0 < $1.0 }.prefix(3).map(\.1)
    }

    func setTheme(_ name: String) {
        UserDefaults.standard.set(name, forKey: "bit.theme")
        T = themes[name] ?? T; themeName = name; onExpandChange?()
    }

    func addTask() {
        guard let t = try? ask("New task? Tag it #home, #work or #career, and add due:12 Oct if it has a date.", "e.g. book the dentist #home due:12 Oct"), !t.isEmpty else { return }
        if !FileManager.default.fileExists(atPath: tasksPath) { openText(tasksPath) }   // creates it with a header
        if let h = FileHandle(forWritingAtPath: tasksPath) {
            h.seekToEndOfFile()
            let text = (try? String(contentsOfFile: tasksPath, encoding: .utf8)) ?? ""
            h.write(((text.hasSuffix("\n") || text.isEmpty ? "" : "\n") + "- [ ] \(t)\n").data(using: .utf8)!); h.closeFile()
        }
        tasks = loadTasks()
    }

    /// People first: bedtimes and dates are time-critical; calls, kindness and goals share one slot a day.
    func lifeNudge(_ now: Date) -> Bool {
        guard let life = life else { return false }
        let c = Calendar.current.dateComponents([.hour, .minute, .weekday], from: now)
        let mins = c.hour! * 60 + c.minute!, today = weekdays[c.weekday! - 1]
        for p in life.people {
            if let b = minutes(p.bedtime), (2...6).contains(c.weekday!), (b - 35...b - 20).contains(mins), Day.once("bed.\(p.name)") {
                say("\(p.name)'s bedtime is in \(b - mins) min. Go say goodnight? 🌙", .calm, seconds: 30, sound: "Purr")
                return true
            }
            for (what, date) in [("birthday", p.birthday), ("anniversary", p.anniversary)] {
                guard let date = date, let n = daysUntil(date), [14, 7, 2, 0].contains(n), mins >= 10 * 60, Day.once("\(what).\(p.name).\(n)") else { continue }
                let whose = what == "anniversary" ? "Your anniversary" : "\(p.name)'s birthday"
                let gift = n > 0 && life.giftIdeas == true
                let tail = n == 0 ? " Call, wish, celebrate 💛" : gift ? " Tap for gift ideas 🎁" : " Got a gift sorted? 🎁"
                say("\(whose) is \(n == 0 ? "today 🎉" : "in \(n) days").\(tail)", .calm, seconds: 30, sound: "Glass") { if gift { self.ideas(for: p.name, "Suggest 3 thoughtful \(what) gift ideas for my \(p.relation) \(p.name)\(p.likes.map { ", who loves \($0)" } ?? ""). The \(what) is in \(n) days, shopping in India.") } }
                return true
            }
        }
        for e in life.events {
            guard let n = daysUntil(e.date), [14, 7, 2, 0].contains(n), mins >= 10 * 60, Day.once("event.\(e.name).\(n)") else { continue }
            let gift = n > 0 && e.gifts != nil && life.giftIdeas == true
            say("\(e.name) \(n == 0 ? "is today 🎉" : "is in \(n) days").\(e.note.map { " \($0)" } ?? "")\(gift ? " Tap for gift ideas 🎁" : "")", .calm, seconds: 30, sound: "Glass") {
                if gift { self.ideas(for: e.gifts!, "Suggest one thoughtful gift each for: \(e.gifts!). Occasion: \(e.name), in \(n) days, shopping in India.") }
            }
            return true
        }
        for p in life.people where (p.call ?? "").contains(today) {
            let at = minutes(p.callTime)
            guard at.map({ (($0 - 10)...($0 + 60)).contains(mins) }) ?? (11 * 60..<21 * 60).contains(mins), Day.once("call.\(p.name)") else { continue }
            say("It's \(today). Call \(p.name)? 📞", .calm, seconds: 30, sound: "Purr")
            return true
        }
        // today's goal: ask in the morning if there is none; check in 30 min before your stop time
        let stopAt = minutes(life.stop ?? config["stop"] as? String) ?? 20 * 60
        if goal("today") == nil, (9 * 60..<12 * 60).contains(mins), Day.once("ask-goal") {
            say("What's today's goal? Tap to set it 🎯", .calm, seconds: 30, kind: .ambient) { self.setGoal("today") }
            return true
        }
        if let g = goal("today"), !g.done, (stopAt - 30..<stopAt).contains(mins), Day.once("checkin") {
            say("Today's goal: \(g.text)\nDid it happen?", .calm, seconds: 60, kind: .ambient, react: { yes in
                if yes { self.updateGoal("today") { $0.done = true } } else { self.say("Tomorrow, then. Keep it small 💛", .calm, seconds: 4, kind: .ambient) }
            })
            return true
        }
        // one gentle personal nudge a day, between 11:00 and 21:00
        let key = "bit.\(Day.key).personal"
        guard (11 * 60..<21 * 60).contains(mins), !UserDefaults.standard.bool(forKey: key) else { return false }
        func once(_ text: String, _ kind: BubbleKind = .ambient) -> Bool {
            UserDefaults.standard.set(true, forKey: key); say(text, .calm, seconds: 25, kind: kind); return true
        }
        func onceIdea(_ text: String, _ idea: String) -> Bool {
            UserDefaults.standard.set(true, forKey: key)
            say(text, .calm, seconds: 40, kind: .ambient, react: { self.react(idea, $0) }); return true
        }
        if let p = life.partner, mins >= 16 * 60 {
            let n = max(1, min(7, life.kindPerWeek ?? 2))
            if Set((0..<n).map { ($0 * 7 / n + 3) % 7 }).contains(c.weekday! - 1) {   // n days spread over the week
                let likes = (p.likes ?? "").split(separator: ",").map { "surprise \(p.name) with \($0.trimmingCharacters(in: .whitespaces))" }
                let pool = (likes + ["send \(p.name) a sweet message, no reason needed", "ask \(p.name) how the day really went",
                                     "plan a date night this week", "take one thing off \(p.name)'s plate", "leave \(p.name) a handwritten note"]).filter { !life.disliked.contains($0) }
                guard let idea = (pool + pool.filter { life.liked.contains($0) }).randomElement() else { return false }   // 👍 ideas come up twice as often
                return onceIdea("Small thing for \(p.name) today: \(idea) 💛", idea)
            }
        }
        if c.weekday == 2, !life.goals.isEmpty, mins >= 10 * 60 {
            return once("This year's goals:\n" + life.goals.map { "• \($0)" }.joined(separator: "\n") + "\nWhich one gets time this week?", .thought)
        }
        return false
    }

    /// Ask your own Claude (haiku) for ideas, with what you've told Buddy. Runs in ~/.config/buddy so Buddy's hook ignores it.
    func ideas(for who: String, _ ask: String) {
        say("Thinking of ideas for \(who)… 🎁", .calm, seconds: 20, kind: .ambient)
        let l = life ?? Life()
        let notes = (l.notes.suffix(30) + l.liked.suffix(15).map { "I liked: \($0)" } + l.disliked.suffix(15).map { "Not for me: \($0)" }).joined(separator: "\n")
        DispatchQueue.global().async {
            let pr = Process(), out = Pipe()
            pr.executableURL = URL(fileURLWithPath: tool("claude"))
            pr.currentDirectoryURL = URL(fileURLWithPath: buddyDir)
            pr.arguments = ["-p", ask + (notes.isEmpty ? "" : "\nThings I've noted (use if relevant):\n" + notes) + "\nUnder 12 words per idea, one per line, no preamble.", "--model", "haiku"]
            pr.standardOutput = out; pr.standardError = Pipe()
            try? pr.run(); pr.waitUntilExit()
            let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                self.bubble = nil
                if text.isEmpty { self.say("Couldn't reach Claude for ideas just now.", .calm, seconds: 10, kind: .ambient); return }
                self.say("Ideas for \(who):\n\(text)", .calm, seconds: 60, kind: .ambient, react: { self.react("\(who): " + text.replacingOccurrences(of: "\n", with: "; "), $0) })
            }
        }
    }

    func react(_ idea: String, _ liked: Bool) {
        var l = loadLife() ?? Life()
        if liked { l.liked.append(idea) } else { l.disliked.append(idea) }
        saveLife(l); life = l
        say(liked ? "More like that, got it 💛" : "Noted, I won't suggest that again.", .calm, seconds: 3, kind: .ambient)
    }

    /// Right-click → Tell Buddy…: a note about your people, kept in your profile.
    func tellBuddy() {
        guard let t = try? ask("Tell me something worth remembering. A gift hint, what someone's into, a date.", "e.g. Asha liked the green tote at Zara"), !t.isEmpty else { return }
        var l = loadLife() ?? Life()
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
        l.notes.append("\(f.string(from: Date())): \(t)")
        saveLife(l); life = l
        say("Noted 💛", .happy, seconds: 3, kind: .ambient)
    }
}

struct StopOnboarding: Error {}
/// One question at a time. Next saves the answer, Skip leaves it blank, Stop ends (what you gave so far is kept).
func ask(_ question: String, _ placeholder: String = "", _ value: String = "") throws -> String {
    let a = NSAlert()
    a.messageText = "Buddy 🐾"
    a.informativeText = question
    a.addButton(withTitle: "Next"); a.addButton(withTitle: "Skip"); a.addButton(withTitle: "Stop")
    let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    f.placeholderString = placeholder; f.stringValue = value
    a.accessoryView = f
    a.window.initialFirstResponder = f
    NSApp.activate(ignoringOtherApps: true)
    switch a.runModal() {
    case .alertFirstButtonReturn: return f.stringValue.trimmingCharacters(in: .whitespaces)
    case .alertSecondButtonReturn: return ""
    default: throw StopOnboarding()
    }
}
func askDate(_ q: String, _ old: String?) throws -> String? {
    var prompt = q
    while true {
        let a = try ask(prompt, "e.g. 14 Feb", old ?? "")
        if a.isEmpty { return nil }
        if let d = dayMonth(a) { return d }
        prompt = q + "\n(I couldn't read \"\(a)\". Try like 14 Feb.)"
    }
}
func askTime(_ q: String, _ def: String) throws -> String? {
    var prompt = q
    while true {
        let a = try ask(prompt, def, def)
        if a.isEmpty { return nil }
        if minutes(a) != nil { return a }
        prompt = q + "\n(Use 24-hour time, like \(def).)"
    }
}

func onboard(_ m: Model) {
    let old = loadLife() ?? Life()
    var life = old
    defer { saveLife(life); m.life = life }
    do {
        life.me = try ask("Hi! I'm Buddy 🐾 I'd like to help with more than code: your people, your goals and your tasks.\nEverything stays in a private file on this Mac (~/.config/buddy/life.json).\n\nWhat should I call you?", "Your name", old.me ?? "").nilIfBlank
        var people: [Person] = []
        let op = old.partner
        let partner = try ask("Your partner's name? (Skip if none)", "e.g. Asha", op?.name ?? "")
        if !partner.isEmpty {
            let rel = try ask("Is \(partner) your wife, husband or partner?", "wife", op?.relation ?? "wife").lowercased()
            var p = Person(name: partner, relation: ["wife", "husband"].contains(rel) ? rel : "partner")
            p.birthday = try askDate("\(partner)'s birthday?", op?.birthday)
            p.anniversary = try askDate("Your anniversary?", op?.anniversary)
            p.likes = try ask("What does \(partner) love? I'll use it for small gestures and gift ideas.", "filter coffee, orchids, Kindle books", op?.likes ?? "").nilIfBlank
            people.append(p)
            life.kindPerWeek = Int(try ask("How many times a week should I suggest something kind for \(partner)?", "2", "\(old.kindPerWeek ?? 2)")) ?? 2
        }
        var oldKids = old.people.filter { $0.relation == "child" }
        while true {
            let ok = oldKids.isEmpty ? nil : oldKids.removeFirst()
            let kid = try ask(people.contains { $0.relation == "child" } ? "Another child? (Skip when done)" : "Your child's name? (Skip if none)", "e.g. Meera", ok?.name ?? "")
            if kid.isEmpty { break }
            var p = Person(name: kid, relation: "child")
            p.birthday = try askDate("\(kid)'s birthday?", ok?.birthday)
            p.bedtime = try askTime("\(kid)'s bedtime? I'll remind you 30 min before, on weekdays.", ok?.bedtime ?? "21:00")
            p.likes = try ask("What is \(kid) into right now?", "dinosaurs, drawing", ok?.likes ?? "").nilIfBlank
            people.append(p)
        }
        var oldFamily = old.people.filter { $0.relation == "family" }
        while true {
            let of = oldFamily.isEmpty ? nil : oldFamily.removeFirst()
            let who = try ask("Anyone else you want to stay close to? Parents, siblings, a friend. (Skip when done)", "e.g. Mom", of?.name ?? "")
            if who.isEmpty { break }
            var p = Person(name: who, relation: "family")
            p.birthday = try askDate("\(who)'s birthday?", of?.birthday)
            var day = try ask("Which day should I remind you to call \(who)? (Skip for no reminder)", "Sunday", of?.call ?? "")
            day = weekdays.first { $0.lowercased().hasPrefix(day.lowercased().prefix(3)) && !day.isEmpty } ?? ""
            p.call = day.nilIfBlank
            p.likes = try ask("What does \(who) love?", "gardening, old songs", of?.likes ?? "").nilIfBlank
            people.append(p)
        }
        if !people.isEmpty { life.people = people }
        let goals = try ask("Your top 2–3 goals for this year? Separate them with commas.", "home by 8 three days a week, read 12 books, run 3x a week", old.goals.joined(separator: ", "))
        if !goals.isEmpty { life.goals = goals.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        life.stop = try askTime("When do you want to stop work each day?", old.stop ?? (config["stop"] as? String ?? "20:00")) ?? life.stop
        life.giftIdeas = try ask("Before birthdays and anniversaries, should I ask your Claude for gift ideas? (yes / no)\nThat sends the person's name and likes to Claude, like any prompt.", "yes", old.giftIdeas == false ? "no" : "yes").lowercased().hasPrefix("y")
    } catch {}
    m.say("Got it\(life.me.map { ", \($0)" } ?? ""). I'll look out for your people too 💛\nRight-click me to add tasks or update this.", .happy, seconds: 8, kind: .ambient)
}

extension String { var nilIfBlank: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self } }

if let i = CommandLine.arguments.firstIndex(of: "--focus"), i + 2 < CommandLine.arguments.count {   // test: --focus <app> <tty>
    focusTerminal(CommandLine.arguments[i + 1], tty: CommandLine.arguments[i + 2]); sleep(2); exit(0)
}
if CommandLine.arguments.contains("--selftest") {   // the date and time parsing behind birthdays and bedtimes
    precondition(dayMonth("14 Feb") == "14 Feb" && dayMonth("Feb 14") == "14 Feb" && dayMonth("14/02") == "14 Feb" && dayMonth("2019-02-14") == "14 Feb" && dayMonth("June 3") == "3 Jun")
    precondition(dayMonth("banana") == nil)
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"
    precondition(daysUntil(f.string(from: Date())) == 0)
    precondition(daysUntil(f.string(from: Date().addingTimeInterval(7 * 86400))) == 7)
    precondition(daysUntil(f.string(from: Date().addingTimeInterval(-86400)))! >= 364)
    precondition(minutes("21:00") == 1260 && minutes("25:00") == nil && minutes("9") == nil)
    precondition(tokenValue("Diwali gifts #home due:1 Nov snooze:2026-10-07", "due") == "1 Nov")
    precondition(tokenValue("x snooze:2026-10-07", "snooze") == "2026-10-07" && tokenValue("x #home", "due") == nil)
    let today0 = Calendar.current.startOfDay(for: Date())
    precondition(nearestDate(f.string(from: Date().addingTimeInterval(-2 * 86400))) == Calendar.current.date(byAdding: .day, value: -2, to: today0))   // overdue, not next year
    precondition(dueText(today0).0 == "today" && dueText(today0.addingTimeInterval(-86400)).0 == "1d late" && dueText(today0.addingTimeInterval(86400)).0 == "tomorrow")
    let old = try! JSONDecoder().decode(Life.self, from: #"{"me":"x","people":[{"name":"A","relation":"child"}],"horizons":{"today":{"text":"t","set":"2026-10-06"}}}"#.data(using: .utf8)!)
    precondition(old.people.count == 1 && old.liked.isEmpty && old.horizons?.today?.k == 0)
    precondition(hm(400 * 60) == "6h40" && hm(35 * 60) == "35m" && hm(60 * 60) == "1h00")
    print("selftest ok"); exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    // test: render the card in every theme and tab to PNGs, from a fixed made-up profile (never your real one), for before/after checks
    let dir = CommandLine.arguments[i + 1], now = Date().timeIntervalSince1970
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"
    let m = Model()
    m.sessions = [
        Session(id: "a", cwd: "/x/pricing-page", repo: "pricing-page", branch: "main", state: "waiting", activity: "Bash: npm test", prompt: "fix the test", ts: now - 120),
        Session(id: "b", cwd: "/x/onboarding", repo: "onboarding", branch: "copy", state: "working", activity: "Edit: email2.md", prompt: "shorter emails", ts: now - 60, turnStart: now - 300, source: "codex-cli"),
        Session(id: "c", cwd: "/x/blog", repo: "blog", branch: "main", state: "working", activity: "Read: post.md", prompt: "draft", ts: now - 3600),
        Session(id: "d", cwd: "/x/site", repo: "site", branch: "main", state: "finished", activity: "", prompt: "launch", ts: now - 900, said: "Rewrote email 2: shorter, one clear call to action."),
    ]
    var st = Stats(); st.merged = 3; st.opened = 5; st.me = "you"; st.team = [("ana", 9), ("you", 5), ("raj", 4), ("lee", 2)]; st.teamTotal = 20; st.yesterdayMerged = 2
    m.stats = st; m.statsLoaded = true
    m.limits = [Limit(name: "Claude 5h", used: 42, resets: Date(timeIntervalSince1970: now + 7200)), Limit(name: "Codex week", used: 81, resets: nil)]
    m.workedToday = 4 * 3600 + 20 * 60; m.workingSince = Date(timeIntervalSince1970: now - 50 * 60)
    var l = Life(); l.me = "Sam"; l.stop = "20:00"; l.resume = "22:00"
    l.people = [Person(name: "Alex", relation: "partner", birthday: f.string(from: Date().addingTimeInterval(9 * 86400)), likes: "flowers"),
                Person(name: "Mia", relation: "child", birthday: f.string(from: Date().addingTimeInterval(30 * 86400)), bedtime: "21:00")]
    l.events = [Event(name: "Beach trip", date: f.string(from: Date().addingTimeInterval(20 * 86400)))]
    l.horizons = Horizons(today: Goal(text: "Ship the pricing page", set: isoDay.string(from: Date())),
                          week: Goal(text: "Talk to 5 customers", n: 5, k: 2, set: isoDay.string(from: Date())),
                          month: Goal(text: "Run 4 times", n: 4, k: 1, set: isoDay.string(from: Date())))
    m.life = l
    m.tasks = [Todo(text: "Book the dentist", area: "home", due: Calendar.current.startOfDay(for: Date()), line: "- [ ] a"),
               Todo(text: "Reply to the design review", area: "work", line: "- [ ] b"),
               Todo(text: "Update CV", area: "career", line: "- [ ] c")]
    m.history = [Bubble(text: "“Waste no more time arguing what a good man should be. Be one.”", tone: .calm, kind: .quote, byline: "— Marcus Aurelius")]
    m.breedIndex = 0; m.cardWidth = 360
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    MainActor.assumeIsolated { for th in ["burrow", "glass", "ink"] { for tab in ["work", "personal"] {
        T = themes[th]!; m.themeName = th; m.tab = tab
        let r = ImageRenderer(content: Card(m: m).fixedSize(horizontal: false, vertical: true).environment(\.colorScheme, .light))
        r.scale = 2
        if let img = r.nsImage, let t = img.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(th)-\(tab).png"))
        }
    } } }
    print("snapshots in \(dir)"); exit(0)
}
if CommandLine.arguments.contains("--dump") {
    let t = codexToday()
    print("today: \(t.sessions) Codex sessions, \(t.prompts) Codex prompts")
    print("mic in use:", micInUse())
    if CommandLine.arguments.contains("--stats") {   // the numbers the card shows, for checking against GitHub
        let m = Model(); m.loadStats(); let end = Date().addingTimeInterval(60)
        while !m.statsLoaded && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
        let s = m.stats
        print("me \(s.me): merged \(s.merged), opened \(s.opened), yesterday \(s.yesterdayMerged ?? -1); team \(s.teamTotal), counted \(s.team.reduce(0) { $0 + $1.n })")
        for r in s.team.prefix(5) { print("  \(r.login) \(r.n)") }
        print("rank", s.rank ?? -1)
    }
    if let l = loadLife() { print("profile: \(l.people.count) people, \(l.events.count) events, \(l.goals.count) goals, stop \(l.stop ?? "-")–\(l.resume ?? "-")") } else { print("profile: none or unreadable") }
    print("tasks open:", loadTasks().count)
    let cwds = ((try? FileManager.default.contentsOfDirectory(atPath: home + "/.claude/pet/sessions")) ?? []).compactMap { f -> String? in
        (FileManager.default.contents(atPath: home + "/.claude/pet/sessions/" + f).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["cwd"] as? String }
    let wts = listWorktrees(cwds: cwds)
    print(String(format: "disk: %.1f GB free", freeGB()))
    for (r, n) in Dictionary(grouping: wts, by: \.repo).mapValues(\.count).sorted(by: { $0.key < $1.key }) { print("worktrees \(r): \(n)") }
    print("idle 7d+: \(wts.filter { $0.idleDays >= 7 && !$0.inUse }.count), in use: \(wts.filter(\.inUse).count)")
    for e in loadLife()?.events ?? [] { print("event \(e.name): in \(daysUntil(e.date).map(String.init) ?? "?") days") }
    for p in loadLife()?.people ?? [] { if let b = p.birthday { print("birthday \(p.name): in \(daysUntil(b).map(String.init) ?? "?") days") } }
    for l in claudeLimits() + codexLimits() { print("limit \(l.name): \(Int(l.used))%, resets \(l.resets.map(resetText) ?? "?")") }
    if CommandLine.arguments.count > 2 { print("link:", ccdLink(CommandLine.arguments[2])?.absoluteString ?? "none") }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
