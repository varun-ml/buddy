import AppKit
import SwiftUI

// MARK: Codex — sessions live in ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl (CLI and the ChatGPT desktop app)

let codexDir = ProcessInfo.processInfo.environment["BIT_CODEX_DIR"] ?? (NSHomeDirectory() as NSString).appendingPathComponent(".codex/sessions")

/// Rollout files touched in the last `hours`, from today's and yesterday's folders.
/// Codex moves an archived thread's rollout to ~/.codex/archived_sessions.
func codexArchived(_ id: String) -> Bool {
    let dir = (home as NSString).appendingPathComponent(".codex/archived_sessions")
    return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).contains { $0.contains(id) }
}

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
