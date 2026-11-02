import AppKit
import SwiftUI

// MARK: Ink, built to the approved mockup (round 2, direction 2): a precise dark tool, one indigo accent.
// Graphite is the same card in a second palette: lifted off a dark terminal, every text step at 4.5:1 or better.

struct InkPalette {
    let bg, foot, panel, chip, hover: Color          // surfaces: the card, its footer, raised blocks, small chips, a hovered row
    let ink, ink2, mid, sub, dim, faint: Color       // text, strongest first
    let line, rule, btnLine, track, control: Color   // dividers, outlines, empty bars, checkbox borders
    let accent, warn, good: Color
    let edge: Color                                  // the card's outline: what separates it from a dark desktop
    let refined: Bool                                // Graphite's layout: medallion leaderboard, neutral agent pills, counts as chips
}
let inkPalette = InkPalette(bg: hex(0x0f0f11), foot: hex(0x0c0c0e), panel: hex(0x141418), chip: hex(0x1c1c21), hover: hex(0x18181c),
                            ink: hex(0xededef), ink2: hex(0xbdbdc4), mid: hex(0x8a8a93), sub: hex(0x6b6b73), dim: hex(0x56565e), faint: hex(0x44444c),
                            line: hex(0x1a1a1e), rule: hex(0x1f1f23), btnLine: hex(0x232328), track: hex(0x26262c), control: hex(0x44444c),
                            accent: hex(0x7c7ff2), warn: hex(0xf2994a), good: hex(0x4cc38a), edge: Color.white.opacity(0.08), refined: false)
let graphitePalette = InkPalette(bg: hex(0x18181c), foot: hex(0x1c1c21), panel: hex(0x202026), chip: hex(0x26262d), hover: hex(0x1f1f24),
                                 ink: hex(0xececf1), ink2: hex(0xb9b9c3), mid: hex(0xb9b9c3), sub: hex(0x9d9da8), dim: hex(0x878792), faint: hex(0x878792),
                                 line: hex(0x2c2c33), rule: hex(0x2c2c33), btnLine: hex(0x36363e), track: hex(0x34343c), control: hex(0x6e6e79),
                                 accent: hex(0x9396fa), warn: hex(0xf2a65a), good: hex(0x5fd29b), edge: Color.white.opacity(0.15), refined: true)
/// The current theme's palette: Ink and Graphite draw the same card.
var K: InkPalette { T.name == "graphite" ? graphitePalette : inkPalette }

struct InkCard: View {
    @ObservedObject var m: Model
    @StateObject private var ui = CardUI()
    @Namespace private var tabNS
    @State private var spin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(K.accent).frame(width: 8, height: 8).shadow(color: K.accent, radius: 5)
                Text("Buddy").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(Self.stamp.string(from: Date()).uppercased()).font(.system(size: 11.5, weight: .medium, design: .monospaced)).foregroundColor(K.sub)
            }.padding(.horizontal, 16).padding(.top, 12)
            HStack(spacing: 18) {
                tabButton("work", "Work", m.working.count + m.waiting.count)
                tabButton("personal", "Personal", m.todos.count)
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 10)
            Rectangle().fill(K.rule).frame(height: 1)
            Group { if m.tab == "personal" { personal } else { work } }.padding(.horizontal, 16).padding(.vertical, 14)
            HStack(spacing: 6) {
                if m.tab == "personal" {
                    ftb("Tell Buddy…") { DispatchQueue.main.async { m.tellBuddy() } }
                    Spacer()
                    Text("~/.config/buddy").font(.system(size: 11, design: .monospaced)).foregroundColor(K.faint).lineLimit(1).help("Private: stays on this Mac")
                } else {
                    ftb(m.snoozed ? "Wake up" : "Nap 1h") { m.toggleSnooze() }
                    ftb("Refresh") { m.loadSessions(); m.loadPRs(); m.loadStats() }
                    Spacer()
                    Text(m.prsCheckedAt.map { "checked \(ago(Date().timeIntervalSince($0))) ago" } ?? "checking…").font(.system(size: 11, design: .monospaced)).foregroundColor(K.faint)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10).background(K.foot).overlay(Rectangle().fill(K.line).frame(height: 1), alignment: .top)
        }
        .foregroundColor(K.ink)
    }
    static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE dd MMM · HH:mm"; return f }()

    func tabButton(_ t: String, _ title: String, _ count: Int) -> some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { m.tab = t } } label: {
            VStack(spacing: 7) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(m.tab == t ? K.ink : K.sub)
                    if K.refined {   // the count as a small chip, tinted on the open tab
                        Text("\(count)").font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundColor(m.tab == t ? K.ink2 : K.sub)   // dim was 4.2:1 on the chip; sub is 5.6:1
                            .padding(.horizontal, 5).background(RoundedRectangle(cornerRadius: 4).fill(m.tab == t ? K.accent.opacity(0.18) : K.chip))
                    } else {
                        Text("\(count)").font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundColor(K.sub)
                    }
                }
                ZStack {
                    Color.clear.frame(height: 2)
                    if m.tab == t { RoundedRectangle(cornerRadius: 2).fill(K.accent).frame(height: 2).matchedGeometryEffect(id: "ul", in: tabNS) }
                }
            }.fixedSize()
        }.buttonStyle(.plain)
    }
    func lb(_ a: String, _ b: String) -> some View {
        HStack { Text(a).font(.system(size: 11.5, weight: .medium)); Spacer(); Text(b).font(.system(size: 11, design: .monospaced)) }.foregroundColor(K.sub).padding(.bottom, 8)
    }
    func ftb(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 12, weight: .medium)).foregroundColor(K.ink2).padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(K.panel)).overlay(RoundedRectangle(cornerRadius: 6).stroke(K.btnLine, lineWidth: 1))
        }.buttonStyle(.plain)
    }
    func box(_ size: CGFloat, _ r: CGFloat, _ done: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: r).fill(done ? K.accent : .clear)
            RoundedRectangle(cornerRadius: r).stroke(done ? K.accent : K.control, lineWidth: 1.5)
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
                        RoundedRectangle(cornerRadius: 7).fill(t?.done == true ? K.accent : .clear)
                        RoundedRectangle(cornerRadius: 7).stroke(t?.done == true ? K.accent : K.control, lineWidth: 1.5)
                        if t?.done == true { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.white).transition(.scale) }
                    }.frame(width: 22, height: 22).padding(.top, 2)
                }.buttonStyle(.plain)
                Button { if t == nil { DispatchQueue.main.async { m.setGoal("today") } } } label: {
                    Text(t?.text ?? "Set today's goal…").font(.system(size: 20, weight: .semibold)).kerning(-0.4)
                        .foregroundColor(t == nil || t!.done ? K.mid : K.ink).strikethrough(t?.done == true, color: K.accent)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }.buttonStyle(.plain)
            }.padding(.top, 2).padding(.bottom, 16)
            grow("This week", "week"); grow("This month", "month")
            if let y = m.life?.goals.first {
                let yr = y.range(of: #"\d{4}"#, options: .regularExpression).map { String(y[$0]) }
                (Text(yr ?? "Year").foregroundColor(K.mid).fontWeight(.medium) + Text(" · \(y)").foregroundColor(K.dim)).font(.system(size: 12)).lineLimit(1)
                    .padding(.top, 8).padding(.bottom, 4).frame(maxWidth: .infinity, alignment: .leading).overlay(Rectangle().fill(K.line).frame(height: 1), alignment: .top)
            }
            VStack(alignment: .leading, spacing: 0) {
                lb("Todo", "\(todos.count) open")
                if todos.isEmpty { Text(m.familyTime ? "Nothing due. Enjoy the evening." : "Nothing to do.").font(.system(size: 13)).foregroundColor(K.sub) }
                ForEach(shown) { row($0) }
                HStack {
                    if todos.count > listCap { Button(ui.showAll ? "show less" : "+ \(todos.count - listCap) more") { withAnimation { ui.showAll.toggle() } }.buttonStyle(.plain) }
                    Spacer()
                    Button("New task…") { DispatchQueue.main.async { m.addTask() } }.buttonStyle(.plain)
                }.font(.system(size: 12, weight: .medium)).foregroundColor(K.mid).padding(.top, 6)
            }.padding(.top, 14)
            if !m.moments.isEmpty {
                Flow(spacing: 6) {
                    ForEach(m.moments) { mo in
                        (Text(mo.when).foregroundColor(K.ink) + Text(" \(mo.detail)").foregroundColor(K.mid)).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 3).overlay(RoundedRectangle(cornerRadius: 6).stroke(K.btnLine, lineWidth: 1))
                    }
                }.padding(.top, 12)
            }
            Carousel(m: m).padding(.top, 14)
        }
    }
    func grow(_ title: String, _ which: String) -> some View {
        let g = m.goal(which), (k, n) = m.progress(which)
        return Button { g == nil ? DispatchQueue.main.async { m.setGoal(which) } : m.bump(which) } label: {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(K.sub).frame(width: 76, alignment: .leading)
                Text(g?.text ?? "Set one…").font(.system(size: 13, weight: .medium)).foregroundColor(g == nil ? K.sub : K.ink).lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    ForEach(0..<n, id: \.self) { i in RoundedRectangle(cornerRadius: 2).fill(i < k ? K.accent : K.track).frame(width: 14, height: i < k ? 7.5 : 6) }
                    Text("\(k)/\(n)").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(K.mid).frame(minWidth: 26, alignment: .trailing).padding(.leading, 6)
                }.animation(.spring(response: 0.4, dampingFraction: 0.5), value: k)
            }.padding(.vertical, 9).contentShape(Rectangle()).overlay(Rectangle().fill(K.line).frame(height: 1), alignment: .top)
        }.buttonStyle(.plain)
    }
    func row(_ t: Todo) -> some View {
        let done = ui.ticking.contains(t.id), hovered = ui.hover == t.id
        return HStack(spacing: 10) {
            Button { ui.tick(t, m) } label: {
                ZStack {
                    Circle().fill(done ? K.accent : .clear); Circle().stroke(done ? K.accent : K.control, lineWidth: 1.5)
                    if done { Image(systemName: "checkmark").font(.system(size: 7.5, weight: .heavy)).foregroundColor(.white) }
                }.frame(width: 15, height: 15)
            }.buttonStyle(.plain)
            Text(t.text).font(.system(size: 13)).foregroundColor(done ? K.dim : K.ink).strikethrough(done, color: K.dim).lineLimit(1)
            Spacer(minLength: 4)
            if t.gid != nil { googleMark(K.sub) }
            if let a = t.area { HStack(spacing: 4) { Circle().fill(areaColor(a)).frame(width: 6, height: 6); Text(a) }.font(.system(size: 10.5, weight: .medium)).foregroundColor(K.sub) }
            if hovered && !done {
                Button { withAnimation { m.notToday(t) } } label: {
                    Text("Not today").font(.system(size: 11, weight: .medium)).foregroundColor(K.ink2).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(K.panel)).overlay(RoundedRectangle(cornerRadius: 5).stroke(K.btnLine, lineWidth: 1))
                }.buttonStyle(.plain)
            } else if let d = t.due {
                let n = dueDays(d)
                Text(dueText(d).0).font(.system(size: 11, weight: .medium)).foregroundColor(n <= 0 ? K.warn : n <= 6 ? hex(0xa9abff) : K.mid)
                    .frame(minWidth: 40).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(n <= 0 ? K.warn.opacity(0.14) : n <= 6 ? K.accent.opacity(0.14) : K.chip))
            }
        }
        .frame(height: 32).padding(.horizontal, 6).background(RoundedRectangle(cornerRadius: 6).fill(hovered ? K.hover : .clear)).padding(.horizontal, -6)
        .contentShape(Rectangle()).onHover { h in ui.hover = h ? t.id : (ui.hover == t.id ? nil : ui.hover) }
    }

    // ---- Work
    var work: some View {
        let s = m.stats, quiet = m.ignoredRed.count, g = m.goal("today")
        let pots = m.pots, shown = pots.filter { !$0.done }
        return VStack(alignment: .leading, spacing: 0) {
            NoticeList(m: m, fg: Color.white.opacity(0.92), dim: Color.white.opacity(0.5))
            ForEach(m.waiting) { w in
                HStack(spacing: 0) { Button { activate(w) } label: {
                    HStack(spacing: 10) {
                        Circle().fill(K.warn).frame(width: 8, height: 8)
                        Text("\(w.repo ?? "?") wants your OK").font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(w.activity ?? "").font(.system(size: 11.5, design: .monospaced)).foregroundColor(K.refined ? K.sub : K.dim).lineLimit(1)   // Graphite: 5.3:1 on the orange tint (dim was 4.0)
                        Spacer(minLength: 4)
                        Text("go →").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(K.warn)
                    }.padding(.horizontal, 10).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 6).fill(K.warn.opacity(0.12))).padding(.bottom, 8)
                }.buttonStyle(.plain); Spacer(minLength: 0); ClearX { m.ignore(w) } }.contextMenu { Button("Ignore this session") { m.ignore(w) } }
            }
            ForEach(m.needsYouPRs) { PRBlock(m: m, pr: $0).padding(.bottom, 8) }
            lb("Running", "\(m.working.count)")
            ForEach(m.stuck) { st in
                HStack(spacing: 0) { Button { activate(st) } label: {
                    Text("⚠︎ \(st.repo ?? "?") quiet \(st.quietFor) · \(st.activity ?? "")").font(.system(size: 12)).foregroundColor(K.warn).lineLimit(1).frame(height: 30, alignment: .leading)
                }.buttonStyle(.plain); Spacer(minLength: 0); ClearX { m.ignore(st) } }.contextMenu { Button("Ignore this session") { m.ignore(st) } }
            }
            ForEach(shown, ) { p in
                let c = p.s.agent.color
                Button { activate(p.s) } label: {
                    HStack(spacing: 10) {
                        if p.done { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(K.good).frame(width: 14, height: 14) }
                        else {
                            ZStack { Circle().stroke(K.track, lineWidth: 2); Circle().trim(from: 0, to: 0.25).stroke(c, style: StrokeStyle(lineWidth: 2, lineCap: .round)) }
                                .frame(width: 12, height: 12).rotationEffect(.degrees(spin ? 360 : 0))
                        }
                        Text(p.s.repo ?? "?").font(.system(size: 13, weight: .medium)).lineLimit(1).layoutPriority(1)
                        Text(p.line).font(.system(size: 11.5, design: .monospaced)).foregroundColor(K.dim).lineLimit(1)
                        Spacer(minLength: 4)
                        if K.refined {   // neutral, with the agent's colour as a dot: orange stays the colour of a warning
                            HStack(spacing: 5) { Circle().fill(c).frame(width: 6, height: 6); Text(p.s.agent.label).foregroundColor(K.ink2) }
                                .font(.system(size: 10.5, weight: .medium)).fixedSize().padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 4).fill(K.chip))
                        } else {
                            Text(p.s.agent.label).font(.system(size: 10.5, weight: .medium)).foregroundColor(c).fixedSize().padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 4).fill(c.opacity(0.12)))
                        }
                        Text(p.done ? "done" : p.age).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(p.done ? K.good : K.sub).fixedSize()
                    }.frame(height: 34).padding(.horizontal, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).contextMenu { Button("Ignore this session") { m.ignore(p.s) } }.padding(.horizontal, -6)
            }
            if pots.isEmpty && m.waiting.isEmpty { Text("Nothing running.").font(.system(size: 13)).foregroundColor(K.sub).padding(.vertical, 4) }
            DoneChips(m: m, pots: pots, fg: Color.white.opacity(0.75), sub: K.sub)

            HStack(spacing: 0) {
                if !statsRepos.isEmpty {
                    stat("\(s.merged)", "merged", s.gain)
                    Rectangle().fill(K.rule).frame(width: 1)
                    stat("\(s.opened)", "opened", nil)
                    Rectangle().fill(K.rule).frame(width: 1)
                }
                stat(hm(m.workedToday), "worked", nil)
                Rectangle().fill(K.rule).frame(width: 1)
                stat(m.sinceBreak.map(hm) ?? "now", K.refined ? "no break" : "since break", nil, hot: (m.sinceBreak ?? 0) >= 90 * 60)
            }.fixedSize(horizontal: false, vertical: true).overlay(RoundedRectangle(cornerRadius: 8).stroke(K.rule, lineWidth: 1)).padding(.top, 14)

            if !s.team.isEmpty && K.refined { leaderboard(s) }
            else if !s.team.isEmpty {
                HStack(spacing: 0) {
                    ForEach(s.podium, id: \.medal) { r in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(r.medal) \(r.n)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            Text(r.who).font(.system(size: 11)).foregroundColor(K.sub).lineLimit(1).truncationMode(.middle)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.rankText).font(.system(size: 13, weight: .semibold)).foregroundColor(K.accent)
                        Text("you · \(s.myCount)").font(.system(size: 11)).foregroundColor(K.sub).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {   // the team's total today, all authors
                        Text("👥 \(s.teamTotal)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        Text("team").font(.system(size: 11)).foregroundColor(K.sub).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.top, 12).help("PRs merged by the team: \(s.teamTotal) in all")
            }

            if !m.limits.isEmpty {
                lb("Usage", "").padding(.top, 14)
                ForEach(m.limits) { l in
                    HStack(spacing: 8) {
                        Text(l.name.replacingOccurrences(of: "◆ ", with: "")).font(.system(size: 12)).lineLimit(1).frame(width: 86, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) { Capsule().fill(K.track); Capsule().fill(l.used >= 80 ? K.warn : K.good).frame(width: geo.size.width * min(1, l.used / 100)) }
                        }.frame(height: 3)
                        Text("\(Int(l.used))%").font(.system(size: 11, weight: .medium, design: .monospaced)).frame(width: 34, alignment: .trailing)
                        Text(l.resets.map { "↻ " + resetText($0) } ?? "").font(.system(size: 11)).foregroundColor(K.dim).lineLimit(1).frame(width: 76, alignment: .leading)
                    }.frame(height: 24)
                }
            }
            HStack {
                if m.diskFreeGB >= 0 {
                    Button { openWorktreeReport(m.worktrees) } label: {
                        Text("\(Int(m.diskFreeGB)) GB").fontWeight(.medium).foregroundColor(m.diskFreeGB < diskLowGB ? K.warn : K.ink) + Text(" free · \(m.worktrees.count) worktrees")
                    }.buttonStyle(.plain)
                }
                Spacer()
                if quiet > 0 { Button("\(quiet) red ignored") { m.showStale.toggle() }.buttonStyle(.plain) }
            }.font(.system(size: 12)).foregroundColor(K.sub).padding(.top, 10).frame(maxWidth: .infinity).overlay(Rectangle().fill(K.line).frame(height: 1), alignment: .top).padding(.top, 12)
            if m.showStale {
                ForEach(m.ignoredRed) { pr in
                    Button { NSWorkspace.shared.open(URL(string: pr.url)!) } label: { Text("\(pr.short) · \(pr.title)").font(.system(size: 11)).foregroundColor(K.sub).lineLimit(1) }.buttonStyle(.plain).padding(.top, 3)
                }
            }
            Button { g == nil ? DispatchQueue.main.async { m.setGoal("today") } : withAnimation(.spring(response: 0.35)) { m.tab = "personal" } } label: {
                HStack(spacing: 10) {
                    box(12, 4, g?.done == true)
                    Text(g?.text ?? "Set today's goal").font(.system(size: 12.5)).foregroundColor(K.ink2).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("TODAY →").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(K.refined ? K.accent : K.dim)
                }.padding(.horizontal, 12).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 8).fill(K.panel)).overlay(RoundedRectangle(cornerRadius: 8).stroke(K.rule, lineWidth: 1))
            }.buttonStyle(.plain).padding(.top, 12)
            Carousel(m: m).padding(.top, 12)
        }
        .onAppear { withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { spin = true } }
    }
    /// Graphite's leaderboard: the three podium spots get the width, so names fit. Team total and, off the podium, your rank sit in the label row.
    func leaderboard(_ s: Stats) -> some View {
        let podium = s.podium, onPodium = podium.contains { $0.me }
        let you = onPodium || s.rank == nil ? Text("") : Text(s.rankText).foregroundColor(K.accent).fontWeight(.semibold) + Text(" you · \(s.myCount)  ·  ")
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Merged today")
                Spacer(minLength: 8)
                you + Text("team ") + Text("\(s.teamTotal)").foregroundColor(K.ink).fontWeight(.semibold)
            }.font(.system(size: 11.5, weight: .medium)).foregroundColor(K.sub).lineLimit(1)
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    if i < podium.count {
                        let r = podium[i]
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) { medallion(i); Text("\(r.n)").font(.system(size: 13, weight: .semibold)).monospacedDigit() }
                            Text(r.who).font(.system(size: 11, weight: r.me ? .medium : .regular)).foregroundColor(r.me ? K.accent : K.sub).lineLimit(1).truncationMode(.tail)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }   // fewer than three: the columns keep their width
                }
            }
        }.padding(.top, 14).help("PRs merged by the team: \(s.teamTotal) in all")
    }
    /// A round gold, silver or bronze medal with its place on it.
    func medallion(_ i: Int) -> some View {
        let metal: [[Color]] = [[hex(0xf7dd8a), hex(0xe6c15a), hex(0xc9a03c)], [hex(0xe4e6ec), hex(0xb9bcc6), hex(0x969aa6)], [hex(0xe8b48a), hex(0xc98a5a), hex(0xa86c40)]]
        return Circle().fill(RadialGradient(colors: metal[i], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 9))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .overlay(Text("\(i + 1)").font(.system(size: 9.5, weight: .bold)).foregroundColor(K.bg))
            .frame(width: 15, height: 15)
    }
    func stat(_ big: String, _ label: String, _ em: String?, hot: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(big).font(.system(size: 20, weight: .semibold)).kerning(-0.5).monospacedDigit().foregroundColor(hot ? K.warn : K.ink).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Text(label).font(.system(size: 11.5)).foregroundColor(K.sub).lineLimit(1).minimumScaleFactor(0.8)
                if let em = em { Text(em).font(.system(size: 11)).foregroundColor(K.good) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 9)
    }
}
