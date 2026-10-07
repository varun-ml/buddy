import AppKit
import SwiftUI

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

    func setPet(_ name: String) {
        UserDefaults.standard.set(name, forKey: "bit.pet")
        petChoice = name; randomDay.at = .distantPast
        breedIndex = 0; gesture = .none
        objectWillChange.send(); onExpandChange?()
        if petKind.biped, let g = petKind.onMerge { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.doGesture(g) } }   // an entrance
    }

    func setCostume(_ name: String) {
        UserDefaults.standard.set(name, forKey: "bit.costume")
        costume = name == "none" ? nil : name
        objectWillChange.send()
        if hero { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.doGesture(.heroLanding) } }   // suit up with an entrance
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
