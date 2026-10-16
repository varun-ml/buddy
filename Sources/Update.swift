import AppKit

/// Updates. A minute after launch and every 6 hours, Buddy asks GitHub for the newest release tag (`git ls-remote`, read-only:
/// nothing is downloaded). If it is newer than this copy, Buddy says so once and right-click shows "Update Buddy to vX".
/// The update is `git pull --ff-only && ./install.sh`, the same as updating by hand. "updates": false in buddy.json turns it off.
extension Model {
    func checkForUpdate() {
        guard config["updates"] as? Bool != false else { return }
        DispatchQueue.global(qos: .utility).async {
            let local = runGit(["describe", "--tags", "--abbrev=0"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remote = runGit(["ls-remote", "--tags", "--refs", "origin"]).split(separator: "\n")
                .compactMap { $0.components(separatedBy: "refs/tags/").last }
            guard let newer = newerTag(local: local.isEmpty ? nil : local, remote: remote) else { return }
            DispatchQueue.main.async {
                self.updateTo = newer
                if UserDefaults.standard.string(forKey: "bit.updateTold") != newer {   // once per release
                    UserDefaults.standard.set(newer, forKey: "bit.updateTold")
                    self.say("Buddy \(newer) is out ✨\nRight-click me → Update.", .happy, seconds: 12, kind: .ambient)
                }
            }
        }
    }

    /// Runs in its own process session (python's fork + setsid): install.sh restarts Buddy, and launchd stops everything in
    /// Buddy's process group with it. If anything fails (local changes in the folder, no network), Buddy keeps running
    /// and says why; the log is /tmp/buddy.update.log.
    func update() {
        let dir = petDir.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = "cd '\(dir)' && git pull --ff-only && ./install.sh || ./buddy-cli say \"The update didn't finish. See /tmp/buddy.update.log\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        // fork first: Process makes python a process-group leader, and a leader may not setsid (EPERM, seen 16 Oct)
        p.arguments = ["-c", "import os,subprocess,sys\nif os.fork(): sys.exit(0)\nos.setsid(); subprocess.run(['/bin/sh','-c',sys.argv[1]], stdout=open(sys.argv[2],'w'), stderr=subprocess.STDOUT)",
                       cmd, "/tmp/buddy.update.log"]
        try? p.run()
        showCard = false; bubble = nil   // the card would hide the bubble
        say("Updating to \(updateTo ?? "the new version")… back in a minute 🐾", .calm, seconds: 8, kind: .ambient)
    }
}

/// `git` in Buddy's own folder, no prompts, at most 20 s (an offline Mac must not hang the check).
func runGit(_ args: [String]) -> String {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", petDir] + args
    p.environment = ProcessInfo.processInfo.environment.merging(["GIT_TERMINAL_PROMPT": "0"]) { $1 }
    p.standardOutput = out; p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let t = DispatchWorkItem { p.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: t)
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit(); t.cancel()
    return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : ""
}

/// The newest "vX.Y.Z" tag above `local`, or nil. Tags that aren't versions are ignored. Selftested.
func newerTag(local: String?, remote: [String]) -> String? {
    func version(_ t: String) -> [Int]? {
        guard t.hasPrefix("v") else { return nil }
        let n = t.dropFirst().split(separator: ".").map { Int($0) }
        return n.isEmpty || n.contains(nil) ? nil : Array((n.map { $0! } + [0, 0, 0]).prefix(3))   // v1.2 == v1.2.0
    }
    let mine = local.flatMap(version) ?? []
    let best = remote.compactMap { t in version(t).map { (t, $0) } }.max { $0.1.lexicographicallyPrecedes($1.1) }
    guard let best, mine.lexicographicallyPrecedes(best.1) else { return nil }
    return best.0
}
