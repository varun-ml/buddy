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
    precondition(Set(pets.map(\.name)).count == pets.count && pets.allSatisfy { !$0.coats.isEmpty && !$0.tricks.isEmpty })   // every pet: a unique name, coats, tricks
    precondition(ease(0) == 0 && ease(1) == 1 && ease(2) == 1 && costumeMotion(.heroLanding, 0.45).y < 0 && costumeMotion(.heroLanding, 2) == (0, 1, 0))   // the hero lands back on the floor
    let fd = { (d: String) in festival(on: isoDay.date(from: d)!) }   // a week before the festival days to three days after
    precondition(fd("2026-10-09") == nil && fd("2026-10-10") == "durga" && fd("2026-10-24") == "durga" && fd("2026-10-25") == nil)
    precondition(fd("2026-10-29") == nil && fd("2026-10-30") == "diwali" && fd("2026-11-14") == "diwali" && fd("2026-11-15") == nil)
    precondition(breath(0) == (0, true) && abs(breath(3.99).fill - 1) < 0.01 && !breath(5).inhaling && breath(9.99).fill < 0.01 && breath(10) == (0, true))   // 4 s in, 6 s out
    precondition(Set((0..<pets.count).map { randomPet(day: $0) }) == Set(shufflePool))   // random visits every buddy in the pool
    let t0 = switchHour.date(from: "2026-10-10 14")!.addingTimeInterval(30 * 60)   // switch tracking: hourly counts, unordered pairs, 7 days
    var sl = logSwitch([:], from: "Slack", to: "Chrome", at: t0); sl = logSwitch(sl, from: "Chrome", to: "Slack", at: t0); sl = logSwitch(sl, from: "Mail", to: "Chrome", at: t0)
    precondition(sl["2026-10-10 14"]?["_n"] == 3 && sl["2026-10-10 14"]?["Chrome ↔ Slack"] == 2 && lastHour(sl, at: t0) == (3, "Chrome ↔ Slack"))
    precondition(lastHour(sl, at: t0.addingTimeInterval(3600)).n == 1 && logSwitch(sl, from: "A", to: "B", at: t0.addingTimeInterval(8 * 86400)).count == 1)
    let pv = Model(); pv.privacy = true   // privacy mode: an event keeps only its kind, chatter stays quiet
    pv.say("st-pauls is done", .calm); precondition(pv.bubble?.text == "🔒" && privateText(.waiting) == "A session needs your OK")
    pv.bubble = nil; pv.say("Call your mum", .calm, kind: .ambient); precondition(pv.bubble == nil)
    let q = Model()   // events wait for the card, the current alert and a nap, then show in order; none are dropped
    q.showCard = true; q.say("selftest a", .calm); precondition(q.bubble == nil)
    q.showCard = false; q.sayNext(); precondition(q.bubble?.text == "selftest a")
    q.say("selftest b", .calm); precondition(q.bubble?.text == "selftest a")
    q.bubble = nil; q.snoozedUntil = Date().addingTimeInterval(60); q.sayNext(); precondition(q.bubble == nil)
    q.snoozedUntil = nil; q.sayNext(); precondition(q.bubble?.text == "selftest b")
    q.bubble = nil; q.sayNext(); precondition(q.bubble == nil)
    var good = Stats(); good.me = "me"; good.merged = 4; good.team = [("ana", 9)]; good.teamTotal = 12   // a failed GitHub call keeps the last good numbers
    let kept = keepGood(Stats(), old: good, okMe: false, okTeam: false)
    precondition(kept.merged == 4 && kept.teamTotal == 12 && kept.team.count == 1 && keepGood(Stats(), old: good, okMe: true, okTeam: true).teamTotal == 0)
    let co = Model(); co.relaxUntil = nil; co.privacy = false   // several "done" waiting at once: one bubble; the inbox keeps each (your own relax/privacy settings would change that)
    co.say("selftest x", .calm); co.say("a is done", .calm, group: "a"); co.say("b is done", .calm, group: "b"); co.say("c is done", .calm, group: "c")
    co.bubble = nil; co.sayNext(); precondition(co.bubble?.text == "3 done: a, b, c" && co.notices.count == 4 && co.unreadNotices == 4)
    let st = Model()   // a sticky bubble goes when its reason does (here: no session is waiting)
    st.say("selftest waits", .calm, sticky: "s:gone"); precondition(st.bubble?.sticky == "s:gone"); st.resolveSticky(); precondition(st.bubble == nil)
    print("selftest ok"); exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    // test: render the card in every theme and tab to PNGs, from a fixed made-up profile (never your real one), for before/after checks
    let dir = CommandLine.arguments[i + 1], now = Date().timeIntervalSince1970
    costume = "off"; forcedPet = "cat"   // the same pictures on any day and any Mac, whatever costume or buddy you picked
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
    m.notices = [Bubble(text: "onboarding is done in 4m. Tap to open ✨", tone: .happy), Bubble(text: "pricing-page wants your OK", tone: .waiting)]
    m.noticesSeenAt = .distantPast
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    MainActor.assumeIsolated { for th in ["burrow", "glass", "ink"] { for tab in ["work", "personal"] {
        T = themes[th]!; m.themeName = th; m.tab = tab
        let r = ImageRenderer(content: Card(m: m).fixedSize(horizontal: false, vertical: true).environment(\.colorScheme, .light))
        r.scale = 2
        if let img = r.nsImage, let t = img.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(th)-\(tab).png"))
        }
    } } }
    frozenTime = 800_000_000
    MainActor.assumeIsolated { for p in pets.map(\.name) {   // every coat of every pet, awake, plus a sleeping one, a kitten and the Burrow scene pet
        forcedPet = p
        let models: [Model] = (0..<breeds.count + 1).map { i in
            let pm = Model(); pm.breedIndex = i % breeds.count
            if i < breeds.count { pm.sessions = [Session(id: "w", state: "working", ts: now)] }
            return pm
        }
        let row = HStack(spacing: 6) {
            ForEach(models.indices, id: \.self) { i in Cat(m: models[i]).frame(width: 96, height: 84) }
            Kitten(breed: breeds[0], asleep: false, agent: agents[0]).frame(width: 30, height: 40)
            ScenePet(fur: breeds[0].fur, dark: breeds[0].dark).frame(width: 60, height: 50)
        }.padding(8).background(Color.white).environment(\.colorScheme, .light)
        let r = ImageRenderer(content: row); r.scale = 2
        if let img = r.nsImage, let t = img.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "\(dir)/pet-\(p).png"))
        }
    } }
    // each costume on each pet: standing, walking, and its moves part-way through (seconds in)
    frozenNow = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date())!   // evening, so Diwali carries its diya
    let poses: [(String, [(Gesture, Double)?])] = [
        ("hero", [nil, (.none, -1), (.heroLanding, 0.8), (.grapple, 2)]),
        ("durga", [nil, (.none, -1), (.dhak, 0.5), (.dhunuchi, 1.2), (.quietDhak, 1)]),
        ("diwali", [nil, (.diyas, 2), (.phuljhari, 0.7), (.anaar, 0.9), (.rangoli, 3), (.kandil, 1.5)]),
    ]
    MainActor.assumeIsolated {
        for (c, ps) in poses { for p in pets.filter({ !$0.biped }).map(\.name) {
            costume = c; forcedPet = p
            let models: [Model] = ps.map { pose in
                let pm = Model(); pm.breedIndex = 0; pm.sessions = [Session(id: "w", state: "working", ts: now)]
                if let (g, t) = pose { if t < 0 { pm.walking = true } else { pm.gesture = g; pm.gestureAt = frozenNow!.addingTimeInterval(-t) } }
                return pm
            }
            let row = HStack(spacing: 6) { ForEach(models.indices, id: \.self) { i in Cat(m: models[i]).frame(width: 96, height: 84) } }
                .padding(8).background(Color.white).environment(\.colorScheme, .light)
            let r = ImageRenderer(content: row); r.scale = 2
            if let img = r.nsImage, let t = img.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/costume-\(c)-\(p).png"))
            }
        } }
        // every avatar: standing, walking, hero landing, flying, cape swirl, asleep
        for kind in pets.filter(\.biped) {
            let p = kind.name
            let own = [kind.onMerge, kind.onRed].compactMap { $0 }.filter { ![.heroLanding, .grapple, .capeSwirl].contains($0) }.map { ($0, 1.0) }   // its own big moves too
            let moves: [(Gesture, Double)?] = [nil, (.none, -1), (.heroLanding, 0.8), (.grapple, 2), (.capeSwirl, 0.6)] + own + [(.none, -2)]
            costume = "off"; forcedPet = p
            let models: [Model] = moves.map { pose in
                let pm = Model(); pm.breedIndex = 0
                if let (_, t) = pose, t == -2 { pm.snoozedUntil = Date().addingTimeInterval(3600); return pm }   // napping
                pm.sessions = [Session(id: "w", state: "working", ts: now)]
                if let (g, t) = pose { if t < 0 { pm.walking = true } else { pm.gesture = g; pm.gestureAt = frozenNow!.addingTimeInterval(-t) } }
                return pm
            }
            let row = HStack(spacing: 6) { ForEach(models.indices, id: \.self) { i in Cat(m: models[i]).frame(width: 96, height: 84) } }
                .padding(8).background(Color.white).environment(\.colorScheme, .light)
            let r = ImageRenderer(content: row); r.scale = 2
            if let img = r.nsImage, let t = img.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/moves-\(p).png"))
            }
        }
        // every buddy's walk: 6 frames across one step, so a walk that doesn't read shows up (a still frame can't show it)
        for p in pets.map(\.name) {
            costume = "off"; forcedPet = p
            let pm = Model(); pm.breedIndex = 0; pm.sessions = [Session(id: "w", state: "working", ts: now)]; pm.walking = true
            var frames: [NSImage] = []
            for k in 0..<6 {
                frozenTime = 800_000_000 + Double(k) * (2 * .pi / 12) / 6   // the walk's step is sin(12 s)
                let r = ImageRenderer(content: Cat(m: pm).frame(width: 96, height: 84).background(Color.white).environment(\.colorScheme, .light)); r.scale = 2
                if let img = r.nsImage { frames.append(img) }
            }
            frozenTime = 800_000_000
            guard let first = frames.first else { continue }
            let strip = NSImage(size: NSSize(width: first.size.width * CGFloat(frames.count), height: first.size.height))
            strip.lockFocus()
            for (i, f) in frames.enumerated() { f.draw(at: NSPoint(x: CGFloat(i) * first.size.width, y: 0), from: .zero, operation: .copy, fraction: 1) }
            strip.unlockFocus()
            if let t = strip.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/walk-\(p).png"))
            }
        }
        costume = "off"; forcedPet = nil; frozenNow = nil
    }
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
