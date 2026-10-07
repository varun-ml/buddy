import AppKit
import SwiftUI

_ = _migrated   // copy old settings before anything reads them

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
    let sx = Session(id: "x", ts: 0)   // each session finds its agent by source; unknown agents look like Claude Code
    precondition(sx.agent.label == "Claude" && Session(id: "x", ts: 0, source: "codex-cli").agent.label == "Codex" && Session(id: "x", ts: 0, source: "cursor").agent.label == "Claude")
    let q = Model()   // events wait for the card, the current alert and a nap, then show in order; none are dropped
    q.showCard = true; q.say("selftest a", .calm); precondition(q.bubble == nil)
    q.showCard = false; q.sayNext(); precondition(q.bubble?.text == "selftest a")
    q.say("selftest b", .calm); precondition(q.bubble?.text == "selftest a")
    q.bubble = nil; q.snoozedUntil = Date().addingTimeInterval(60); q.sayNext(); precondition(q.bubble == nil)
    q.snoozedUntil = nil; q.sayNext(); precondition(q.bubble?.text == "selftest b")
    q.bubble = nil; q.sayNext(); precondition(q.bubble == nil)
    print("selftest ok"); exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    // test: render the card in every theme and tab to PNGs, from a fixed made-up profile (never your real one), for before/after checks
    let dir = CommandLine.arguments[i + 1], now = Date().timeIntervalSince1970
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"
    statsRepos = ["you/demo"]   // the card shows PR tiles only when repos are set; never your own settings
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
