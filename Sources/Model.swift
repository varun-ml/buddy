import AppKit
import SwiftUI

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
    var lastSwitchNudge = Date.distantPast
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
    @Published var relaxUntil = UserDefaults.standard.object(forKey: "bit.relax") as? Date   // relax mode (Relax.swift), until midnight
    @Published var breakUntil: Date?   // a 2-minute breathing break
    @Published var privacy = UserDefaults.standard.bool(forKey: "bit.privacy")   // privacy mode: no names on screen, no card
    @Published var leaves = 0
    @Published var notices: [Bubble] = []          // the card's inbox: every event today, newest first
    var noticesSeenAt = Date()                       // inbox items after this are new (set when the card closes)          // a leaf drifts past (relax mode walk)
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
        guard petKind.dances, !danceFrames.isEmpty, !squatting, Date().timeIntervalSince(lastDance) > 60 else { return }
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
        if !quiet { say("I'm a \(breed.name) now \(petKind.hello)", .happy, seconds: 3, kind: .ambient) }
    }

    /// A little bit of business: stretch, yawn, chase tail, wash, loaf, sneeze, zoomies, knock something off, hop.
    /// Bears: rear up and roar, eat honey, swipe a fish out of the air, scratch their back.
    func doGesture(_ g: Gesture? = nil) {
        let calm: [Gesture] = petKind.biped ? [.stretch] : [.loaf, .yawn, .stretch]   // relax mode: slow, sleepy tricks
        let pick = g ?? (relaxing ? calm : petKind.tricks + (drip ? [.shimmy, .shimmy] : []) + costumeTricks).randomElement()!
        gesture = pick
        gestureAt = Date()
        if pick == .zoomies { zoomies = true }
        if pick == .hop { celebrate += 1 }
        let dur: Double = [.loaf: 6, .zoomies: 3, .honey: 3, .scratch: 3, .heroLanding: 1.5, .flyOff: 3.9, .grapple: 6.1, .capeSwirl: 1.3, .dhunuchi: 3, .quietDhak: 2, .diyas: 3, .phuljhari: 2, .anaar: 1.8, .rangoli: 4.5, .kandil: 4][pick] ?? 2.4
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak self] in
            if self?.gesture == pick { self?.gesture = .none; self?.zoomies = false }
        }
    }
    @Published var todayQuote = wisdom.stoic.randomElement()!
    private var nextSlot = Date().addingTimeInterval(CommandLine.arguments.contains("--demo") ? 4 : 90)
    private var lastEventAt = Date.distantPast
    private var hoverEndedAt = Date.distantPast
    private var lastRank: Int?
    var lastAmbient = ""
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

    /// Ignore a session (✕ on an alert row, or right-click any row): hidden until it's forgotten (12 h quiet), even if it keeps posting.
    func ignore(_ s: Session) {
        var ig = ignored.filter { Date().timeIntervalSince1970 - $0.value < forgetAfter }
        ig[s.id] = Date().timeIntervalSince1970
        UserDefaults.standard.set(ig, forKey: "bit.ignored")
        loadSessions()
    }
    var ignored: [String: Double] { UserDefaults.standard.dictionary(forKey: "bit.ignored") as? [String: Double] ?? [:] }
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
        return .calm   // asleep only when you put it down for a nap
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

    /// Events wait here while you nap, the card is open, or another alert is up. Every event is also in `notices` (the card's
    /// inbox), so nothing that happened is lost even if its bubble never shows; chatter (quotes, thoughts) is only worth saying now.
    private var waitingToSay: [(b: Bubble, seconds: Double, pose: Pose, at: Date)] = []

    func say(_ text: String, _ tone: Mood, seconds: Double = 10, kind: BubbleKind = .event, byline: String? = nil,
             pose: Pose = .none, sound: String? = nil, react: ((Bool) -> Void)? = nil, cue: Cue? = nil,
             sticky: String? = nil, group: String? = nil, action: (() -> Void)? = nil) {
        // privacy mode (screen sharing): events say only what kind of thing happened; chatter that names people or work stays quiet
        if privacy && (kind == .ambient || kind == .thought) { return }
        let text = privacy && kind == .event ? privateText(tone) : text
        let napping = snoozed && tone != .happy
        if (napping || squatting) && kind != .event { return }
        if !napping {
            if kind == .event && (tone == .upset || tone == .waiting) { lastEventAt = Date() }
            // a sound when something needs you: approval or limit (Glass), red PR (Basso), a session done (Pop)
            if kind == .event && tone == .happy { dance() }
            if kind == .event && tone == .upset, let g = costumeMove(.red) ?? petKind.onRed { doGesture(g) }   // the hero flies off to fix it     // a bear roars at a red PR
            if kind == .event && tone == .happy, let g = costumeMove(cue ?? .merge) ?? petKind.onMerge { doGesture(g) }   // and catches a salmon on good news
            if let name = sound ?? (kind != .event ? nil : tone == .waiting ? "Glass" : tone == .upset ? "Basso" : nil) { NSSound(named: name)?.play() }
            if showCard && tone == .happy { celebrate += 1 }
        }
        let b = Bubble(text: text, tone: tone, kind: kind, byline: byline, action: action, react: react, sticky: sticky, group: group)
        if kind == .event { notice(b) }
        if kind == .event && relaxing && group != nil { return }   // relax mode: "done" goes to the inbox only; needs-you still shows
        if kind == .event && (napping || showCard || bubble?.kind == .event) {
            waitingToSay.removeAll { $0.b.text == text }
            let item = (b: b, seconds: seconds, pose: pose, at: Date())
            if tone == .waiting || tone == .upset { waitingToSay.insert(item, at: 0) } else { waitingToSay.append(item) }   // needs-you first
            return
        }
        if showCard { return }   // chatter never covers the card
        show(b, seconds: seconds, pose: pose)
    }

    /// The next waiting event, once nothing is in the way. Called every 2 s. Several finished sessions waiting at once
    /// become one bubble ("3 done: a, b, c") that opens the inbox; nothing is dropped, the inbox has each one.
    func sayNext() {
        guard !snoozed, !showCard, bubble == nil, !waitingToSay.isEmpty else { return }
        let w = waitingToSay.removeFirst()
        let done = w.b.group == nil ? [] : waitingToSay.filter { $0.b.group != nil }
        guard !done.isEmpty else { show(w.b, seconds: w.seconds, pose: w.pose); return }
        waitingToSay.removeAll { $0.b.group != nil }
        let names = ([w] + done).compactMap(\.b.group)
        let text = privacy ? "\(names.count) done" : "\(names.count) done: " + names.joined(separator: ", ")
        show(Bubble(text: text, tone: .happy, action: { [weak self] in self?.showCard = true; self?.onExpandChange?() }), seconds: 25, pose: .none)
    }

    private func show(_ b: Bubble, seconds: Double, pose: Pose) {
        bubble = b
        said[b.text] = Date()
        if b.kind == .quote || b.kind == .thought {
            history.insert(b, at: 0)
            if history.count > 60 { history.removeLast() }
        }
        if let h = FileHandle(forWritingAtPath: "/tmp/buddy.said.log") ?? { FileManager.default.createFile(atPath: "/tmp/buddy.said.log", contents: nil); return FileHandle(forWritingAtPath: "/tmp/buddy.said.log") }() {
            h.seekToEndOfFile()
            h.write("\(ISO8601DateFormatter().string(from: Date())) [\(b.kind)] \(b.text.replacingOccurrences(of: "\n", with: " / "))\n".data(using: .utf8)!)
            h.closeFile()
        }
        self.pose = pose
        if b.kind == .event && (b.tone == .upset || b.tone == .waiting) { shake += 1 }
        if b.tone == .happy { celebrate += 1 }
        onExpandChange?()
        armTimer(b, seconds: seconds, pose: pose)
    }

    private func armTimer(_ b: Bubble, seconds: Double, pose: Pose) {
        bubbleTimer?.invalidate()
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.bubble?.id == b.id else { return }
            // needs you: stays until it resolves or you click it, but takes turns with anything waiting behind it
            if b.sticky != nil {
                if self.waitingToSay.isEmpty { self.armTimer(b, seconds: seconds, pose: pose); return }
                self.waitingToSay.append((b: b, seconds: seconds, pose: pose, at: Date()))
            }
            self.bubble = nil
            self.pose = .none
            self.onExpandChange?()
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
            // which repos count: ~/.config/buddy.json "statsRepos": ["owner/repo", ...]; none set → every repo, and no tiles or leaderboard
            let repos = statsRepos.map { "repo:\($0)" }.joined(separator: " ")
            let q = """
            query{ viewer{login}
             merged: search(query:"is:pr author:@me is:merged merged:>=\(from) \(repos)",type:ISSUE){issueCount}
             opened: search(query:"is:pr author:@me created:>=\(from) \(repos)",type:ISSUE){issueCount}
             yest: search(query:"is:pr author:@me is:merged merged:\(yFrom)..\(from) \(repos)",type:ISSUE){issueCount} }
            """
            var s = Stats(), okMe = false, okTeam = statsRepos.isEmpty
            if let d = gh(["api", "graphql", "-f", "query=\(q)"]),
               let root = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["data"] as? [String: Any] {
                let count = { (k: String) in (root[k] as? [String: Any])?["issueCount"] as? Int }
                s.me = (root["viewer"] as? [String: Any])?["login"] as? String ?? ""
                s.merged = count("merged") ?? 0
                s.opened = count("opened") ?? 0
                s.yesterdayMerged = count("yest")
                okMe = root["merged"] != nil
            }
            // the team: every merged PR today, 100 per page (a busy day is 150+; one page dropped the rest)
            var by: [String: Int] = [:], after = "", total = 0
            for _ in 0..<(statsRepos.isEmpty ? 0 : 10) {
                let tq = "query{ search(query:\"is:pr is:merged merged:>=\(from) \(repos)\",type:ISSUE,first:100\(after)){issueCount pageInfo{hasNextPage endCursor} nodes{... on PullRequest{author{login}}}} }"
                guard let d = gh(["api", "graphql", "-f", "query=\(tq)"]),
                      let r = ((try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["data"] as? [String: Any])?["search"] as? [String: Any] else { break }
                total = r["issueCount"] as? Int ?? total
                for n in (r["nodes"] as? [[String: Any]]) ?? [] { if let l = (n["author"] as? [String: Any])?["login"] as? String { by[l, default: 0] += 1 } }
                guard let pi = r["pageInfo"] as? [String: Any], pi["hasNextPage"] as? Bool == true, let c = pi["endCursor"] as? String else { okTeam = true; break }
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
            DispatchQueue.main.async {
                // a failed GitHub call keeps the last good numbers instead of blanking the tiles and the leaderboard; try again in a minute
                self.applyStats(keepGood(s, old: self.stats, okMe: okMe, okTeam: okTeam))
                if !okMe || !okTeam { DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.loadStats() } }
            }
        }
    }

    private func applyStats(_ s: Stats) {
        let first = !statsLoaded
        let prevMerged = stats.merged
        stats = s
        statsLoaded = true
        // the one place the merge count changes, so the bubble always says what the card shows
        if !first, !relaxing, s.merged > prevMerged { say(line("merged", "Merged! That's \(s.merged) today 🏆", ["n": "\(s.merged)"]), .happy, seconds: 8) }
        mergedToday = s.merged
        if first && Calendar.current.component(.hour, from: Date()) >= 6 && Day.once("greeted") {
            let y = s.yesterdayMerged.map { "Yesterday you merged \($0)." } ?? ""
            say("Morning! \(y)\n\(todayQuote[0])", .happy, seconds: 12, kind: .quote, byline: "— \(todayQuote[1])", pose: .glasses)
        }
        // milestones and taking #1: once each per day
        // ponytail: on launch, milestones already passed are marked silently; only new crossings celebrate
        for m in [5, 10, 15, 20] where !relaxing && s.merged >= m && Day.once("milestone\(m)") && !first && prevMerged < m {
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
        if relaxing { relaxQuote(); return }   // calm lines only, no work chatter
        let hour = Calendar.current.component(.hour, from: now)
        if costume != "off", let hi = festivalGreetings[isoDay.string(from: now)], Day.once("festival") { say(hi, .happy, seconds: 12, kind: .ambient); return }
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
        if lifeNudge(now) || relaxNudge(now) || switchNudge(now) { return }

        // break nudge: 90 min straight (buddy.json "breakMins"), then every 30 min until you take one
        if !relaxing, now.timeIntervalSince(workingSince!) >= Double(config["breakMins"] as? Int ?? 90) * 60, now.timeIntervalSince(lastBreakNudge) >= 30 * 60 {
            lastBreakNudge = now
            doGesture(.stretch)
            say(line("break", "\(ago(now.timeIntervalSince(workingSince!))) without a break. 10-minute walk? 🚶", ["t": ago(now.timeIntervalSince(workingSince!))]), .calm, seconds: 20, kind: .ambient)
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
            say(line("stop", "It's past \(stop[0]):\(String(format: "%02d", stop[1])). Time to stop 🌙", ["time": "\(stop[0]):\(String(format: "%02d", stop[1]))"]) + "\n\(open.count) sessions and \(needsYouPRs.count) red PRs still open. Tap to copy a note for tomorrow.",
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
        let ig = ignored
        for f in (try? fm.contentsOfDirectory(atPath: sessionsDir)) ?? [] where f.hasSuffix(".json") {
            let p = (sessionsDir as NSString).appendingPathComponent(f)
            guard let data = fm.contents(atPath: p), let s = try? JSONDecoder().decode(Session.self, from: data) else { continue }
            if now - s.ts > forgetAfter { try? fm.removeItem(atPath: p); continue }
            if let c = s.cwd, !c.isEmpty, !fm.fileExists(atPath: c) { try? fm.removeItem(atPath: p); continue }   // its folder is gone (a deleted worktree): it can never finish
            if ig[s.id] != nil { continue }
            if isStuck(s), s.id.hasPrefix("codex-"), codexArchived(String(s.id.dropFirst(6))) { try? fm.removeItem(atPath: p); continue }   // archived mid-turn: no Stop ever comes
            out.append(s)
        }
        // Codex threads with no typed prompt (automations like "Guardian review") show their thread title
        if out.contains(where: { $0.prompt == nil && $0.id.hasPrefix("codex-") }) {
            let titles = codexTitles()
            for i in out.indices where out[i].prompt == nil && out[i].id.hasPrefix("codex-") { out[i].prompt = titles[String(out[i].id.dropFirst(6))] }
        }
        out.sort { $0.ts > $1.ts }
        readInbox(out)
        sayNext()
        for s in out {
            let prev = lastStates[s.id]
            let name = s.repo ?? "A session"
            if prev != nil, prev != s.state {
                if s.state == "waiting" {
                    say("\(s.agent.mark.isEmpty ? "" : s.agent.mark + " ")" + line("waiting", "\(name) wants your OK", ["repo": name]) + "\n\(s.activity ?? "")", .waiting, seconds: 25, sticky: "s:\(s.id)", action: { activate(s) })
                } else if s.state == "finished", prev == "working" {
                    let took = s.turnStart.map { " in \(ago(now - $0))" } ?? ""
                    let mark = s.agent.mark.isEmpty ? "" : s.agent.mark + " "
                    say(mark + line("done", "\(name) is done\(took). Tap to open ✨", ["repo": name]) + "\n\(s.said ?? s.prompt ?? "")", .happy, seconds: 20, sound: "Pop", cue: .done, group: name, action: { activate(s) })
                }
            }
            lastStates[s.id] = s.state
        }
        if out != sessions { sessions = out }   // publishing redraws everything; only when something changed
        resolveSticky()
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
            DispatchQueue.main.async { self.apply(prs) }
        }
    }

    private func apply(_ new: [PR]) {
        let first = prsCheckedAt == nil
        // one of your PRs left the open list: count again in a minute (GitHub's search lags), not at the next 10-minute tick
        if !first, !Set(prs.map(\.id)).subtracting(new.map(\.id)).isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.loadStats() }
        }
        for pr in new where pr.recent {
            let prev = lastCI[pr.id]
            if !first, prev != pr.ci {
                if pr.needsYou {
                    say(line("red", "Oh no, \(pr.short) broke\nhover me to see why", ["pr": pr.short]), .upset, seconds: 30, sticky: "pr:\(pr.id)")
                } else if pr.ci == "green", prev == "red" || prev == "pending" {
                    say("\(pr.short) is green ✨", .happy, seconds: 8) { NSWorkspace.shared.open(URL(string: pr.url)!) }
                }
            }
            lastCI[pr.id] = pr.ci
        }
        prs = new
        prsCheckedAt = Date()
        resolveSticky()
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
            copy(fixPrompt(pr)); say("That session's folder is gone\nI copied the fix prompt instead 📋", .waiting, seconds: 8, kind: .ambient); return
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
        say("Reopening that session in Terminal 🐾", .happy, seconds: 5, kind: .ambient)
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

    func togglePrivacy() {
        privacy.toggle()
        UserDefaults.standard.set(privacy, forKey: "bit.privacy")
        bubble = nil; waitingToSay.removeAll()   // nothing already queued shows its words
        if privacy { showCard = false; onExpandChange?() }
    }

    func toggleSnooze() {
        if breathing { endBreak(quiet: true); return }
        snoozedUntil = snoozed ? nil : Date().addingTimeInterval(3600)
        if snoozed { bubble = nil }
        onExpandChange?()
    }
}

/// What an event bubble says in privacy mode: the kind of thing, never a repo, a prompt or a PR title.
func privateText(_ tone: Mood) -> String {
    switch tone {
    case .waiting: return "A session needs your OK"
    case .upset: return "Something needs a fix"
    case .happy: return "Done ✨"
    default: return "🔒"
    }
}

extension Model {
    /// Keep every event for the card's inbox: newest first, today only, the last 100.
    func notice(_ b: Bubble) {
        notices = [b] + notices.filter { Calendar.current.isDateInToday($0.at) }.prefix(99)
    }
    var unreadNotices: Int { notices.filter { $0.at > noticesSeenAt }.count }

    /// A sticky bubble goes once its reason is gone: the session stopped waiting, or the PR stopped being red.
    func resolveSticky() {
        let waitingIds = Set(waiting.map { "s:\($0.id)" }), redIds = Set(needsYouPRs.map { "pr:\($0.id)" })
        let live = { (k: String) in k.hasPrefix("s:") ? waitingIds.contains(k) : redIds.contains(k) }
        waitingToSay.removeAll { $0.b.sticky.map { !live($0) } ?? false }
        if let k = bubble?.sticky, !live(k) { bubble = nil; pose = .none; onExpandChange?() }
    }
}

/// New stats, except the parts whose GitHub call failed, which keep their last good values.
func keepGood(_ new: Stats, old: Stats, okMe: Bool, okTeam: Bool) -> Stats {
    var s = new
    if !okMe { s.me = old.me; s.merged = old.merged; s.opened = old.opened; s.yesterdayMerged = old.yesterdayMerged }
    if !okTeam { s.team = old.team; s.teamTotal = old.teamTotal }
    return s
}
