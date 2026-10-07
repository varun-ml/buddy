import AppKit
import SwiftUI

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
        let g = m.goal(which), (k, n) = m.progress(which)
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
        let s = m.stats, quiet = m.ignoredRed.count, g = m.goal("today")
        let pots = m.pots, shown = ui.allPots ? pots : Array(pots.prefix(listCap))
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
                    Text("⚠︎ \(st.repo ?? "?") quiet \(st.quietFor) · \(st.activity ?? "")").font(.system(size: 12)).foregroundColor(hex(0xf2994a)).lineLimit(1).frame(height: 30, alignment: .leading)
                }.buttonStyle(.plain)
            }
            ForEach(shown, ) { p in
                let c = p.s.agent.color
                Button { activate(p.s) } label: {
                    HStack(spacing: 10) {
                        if p.done { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(kGreen).frame(width: 14, height: 14) }
                        else {
                            ZStack { Circle().stroke(hex(0x2a2a30), lineWidth: 2); Circle().trim(from: 0, to: 0.25).stroke(c, style: StrokeStyle(lineWidth: 2, lineCap: .round)) }
                                .frame(width: 12, height: 12).rotationEffect(.degrees(spin ? 360 : 0))
                        }
                        Text(p.s.repo ?? "?").font(.system(size: 13, weight: .medium)).lineLimit(1).layoutPriority(1)
                        Text(p.line).font(.system(size: 11.5, design: .monospaced)).foregroundColor(kDim).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(p.s.agent.label).font(.system(size: 10.5, weight: .medium)).foregroundColor(c).fixedSize().padding(.horizontal, 6).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 4).fill(c.opacity(0.12)))
                        Text(p.done ? "done" : p.age).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(p.done ? kGreen : kSub).fixedSize()
                    }.frame(height: 34).padding(.horizontal, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, -6)
            }
            if pots.isEmpty && m.waiting.isEmpty { Text("Nothing running.").font(.system(size: 13)).foregroundColor(kSub).padding(.vertical, 4) }
            if pots.count > listCap { Button(ui.allPots ? "show less" : "+ \(pots.count - listCap) more") { withAnimation { ui.allPots.toggle() } }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundColor(kMid).padding(.top, 4) }

            HStack(spacing: 0) {
                if !statsRepos.isEmpty {
                    stat("\(s.merged)", "merged", s.gain)
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
                    ForEach(s.podium, id: \.medal) { r in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(r.medal) \(r.n)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            Text(r.who).font(.system(size: 11)).foregroundColor(kSub).lineLimit(1).truncationMode(.middle)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.rankText).font(.system(size: 13, weight: .semibold)).foregroundColor(kIndigo)
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
                ForEach(m.ignoredRed) { pr in
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
