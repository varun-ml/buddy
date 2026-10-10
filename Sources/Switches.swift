import AppKit

// MARK: switch tracking (opt-in: right-click → Personal → Track app switching). Counts how often the front app changes, and
// between which two apps, per hour, kept 7 days in UserDefaults. App names only: no window titles, no timestamps finer than the hour.
// It feeds one nudge an hour at most: too many switches (and the pair to tame), or too many agent sessions touched.

/// "yyyy-MM-dd HH" → ["_n": switches that hour, "Slack ↔ Chrome": switches between those two]
typealias SwitchLog = [String: [String: Int]]

let switchHour: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH"; return f }()

/// Add one switch from `from` to `to` in the hour of `at`, and drop hours older than 7 days.
func logSwitch(_ log: SwitchLog, from: String, to: String, at: Date) -> SwitchLog {
    var l = log.filter { (switchHour.date(from: $0.key) ?? .distantPast) > at.addingTimeInterval(-7 * 86400) }
    let h = switchHour.string(from: at), pair = [from, to].sorted().joined(separator: " ↔ ")
    l[h, default: [:]]["_n", default: 0] += 1
    l[h, default: [:]][pair, default: 0] += 1
    return l
}

/// Switches in the last hour (this hour and the one before, weighted by how much of it falls in the window), and the busiest pair.
func lastHour(_ log: SwitchLog, at: Date) -> (n: Int, pair: String?) {
    let now = log[switchHour.string(from: at)] ?? [:], prev = log[switchHour.string(from: at.addingTimeInterval(-3600))] ?? [:]
    let into = Double(Calendar.current.component(.minute, from: at)) / 60   // how far into this hour we are
    // ponytail: hourly buckets, so "the last hour" is an estimate; exact would need timestamps, which we don't keep on purpose
    let n = Int(Double(now["_n"] ?? 0) + Double(prev["_n"] ?? 0) * (1 - into))
    var pairs = now; for (k, v) in prev { pairs[k, default: 0] += v }
    let pair = pairs.filter { $0.key != "_n" }.max { $0.value < $1.value }?.key
    return (n, pair)
}

extension Model {
    var trackingSwitches: Bool { UserDefaults.standard.bool(forKey: "bit.switchTracking") }

    func toggleSwitchTracking() {
        let on = !trackingSwitches
        UserDefaults.standard.set(on, forKey: "bit.switchTracking")
        if !on { UserDefaults.standard.removeObject(forKey: "bit.switches") }   // off means forgotten
        say(on ? "I'll count app switches (names only, kept 7 days) and tell you if it gets hectic." : "Stopped counting app switches, and forgot them.", .calm, seconds: 6, kind: .ambient)
        objectWillChange.send()
    }

    /// Listen for the front app changing. Counts only while tracking is on.
    func watchSwitches() {
        var last = NSWorkspace.shared.frontmostApplication?.localizedName
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName else { return }
            defer { last = app }
            guard let self, self.trackingSwitches, let from = last, from != app, app != "Buddy", from != "Buddy" else { return }
            let log = UserDefaults.standard.dictionary(forKey: "bit.switches") as? SwitchLog ?? [:]
            UserDefaults.standard.set(logSwitch(log, from: from, to: app, at: Date()), forKey: "bit.switches")
        }
    }

    /// At most once an hour: hectic switching, or too many agent sessions touched in 2 hours. True if it spoke.
    func switchNudge(_ now: Date) -> Bool {
        guard trackingSwitches, now.timeIntervalSince(lastSwitchNudge) >= 3600 else { return false }
        let h = lastHour(UserDefaults.standard.dictionary(forKey: "bit.switches") as? SwitchLog ?? [:], at: now)
        let limit = config["switchesPerHour"] as? Int ?? 120   // two a minute, every minute
        if h.n >= limit {
            lastSwitchNudge = now
            let tame = h.pair.map { " Mostly \($0). Close or mute one of them for 30 minutes?" } ?? " Try one window for the next 30 minutes?"
            say("You switched apps \(h.n) times in the last hour." + tame, .calm, seconds: 20, kind: .ambient)
            return true
        }
        let touched = sessions.filter { ($0.turnStart ?? 0) > now.timeIntervalSince1970 - 2 * 3600 }.count
        if touched >= (config["sessionsPer2h"] as? Int ?? 6) {
            lastSwitchNudge = now
            say("You've jumped between \(touched) agent sessions in 2 hours. Finish two before you start another?", .calm, seconds: 20, kind: .ambient)
            return true
        }
        return false
    }
}
