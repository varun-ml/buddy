import AppKit
import SwiftUI

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
