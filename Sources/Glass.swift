import AppKit
import SwiftUI

// MARK: Glass, built to the approved mockup (round 2, direction 1): a frosted macOS widget stack

let gInk = hex(0x1d1d1f), gSub = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.6), gBlue = hex(0x007aff), gGreen = hex(0x34c759)
let gFill = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255)


struct GlassCard: View {
    @ObservedObject var m: Model
    @StateObject private var ui = CardUI()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if m.tab == "personal" { personal } else { work }
        }
        .padding(14).foregroundColor(gInk)
    }

    func plat<V: View>(_ pad: CGFloat = 12, @ViewBuilder _ v: () -> V) -> some View {
        v().padding(.vertical, pad).padding(.horizontal, pad + 2).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
    }
    func lab(_ t: String) -> some View { Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(0.2).foregroundColor(gSub) }
    func btn(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(.system(size: 12, weight: .semibold)).foregroundColor(gInk).padding(.horizontal, 12).padding(.vertical, 7).background(RoundedRectangle(cornerRadius: 9).fill(gFill.opacity(0.14))) }.buttonStyle(.plain)
    }

    var header: some View {
        HStack(spacing: 9) {
            Circle().fill(LinearGradient(colors: [hex(0xf3a877), hex(0xd9764f)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 28, height: 28)
                .overlay(Text(isBear ? "🐻" : isPug ? "🐶" : "🐱").font(.system(size: 15))).shadow(color: hex(0xd9764f).opacity(0.4), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 0) {
                Text("Buddy").font(.system(size: 14, weight: .semibold))
                Text(m.waiting.isEmpty ? (m.working.isEmpty ? "all quiet" : "\(m.working.count) session\(m.working.count == 1 ? "" : "s") cooking") : "\(m.waiting.count) waiting for you")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(m.waiting.isEmpty ? gSub : hex(0xe8590c))
            }
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7).fill(Color.white).frame(width: 73).shadow(color: .black.opacity(0.12), radius: 3, y: 2).offset(x: m.tab == "personal" ? 73 : 0)
                HStack(spacing: 0) {
                    ForEach(["work", "personal"], id: \.self) { t in
                        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { m.tab = t } } label: {
                            Text(t.capitalized).font(.system(size: 12, weight: .semibold)).frame(width: 73).padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.fixedSize().padding(2).background(RoundedRectangle(cornerRadius: 9).fill(gFill.opacity(0.16)))
        }
    }

    // ---- Personal
    var personal: some View {
        let t = m.goal("today"), todos = m.todos, shown = ui.showAll ? todos : Array(todos.prefix(listCap))
        return VStack(alignment: .leading, spacing: 10) {
            plat {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        lab("Today")
                        Button { if t == nil { DispatchQueue.main.async { m.setGoal("today") } } } label: {
                            Text(t?.text ?? "Set today's goal…").font(.system(size: 19, weight: .semibold)).kerning(-0.3).foregroundColor(t == nil ? gSub : gInk)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }.buttonStyle(.plain)
                        if t != nil {
                            Text(t!.done ? "Done. Nice work." : "Not yet · \(stopLeft(m))").font(.system(size: 12, weight: .medium)).foregroundColor(t!.done ? hex(0x248a3d) : gSub).padding(.top, 1)
                        }
                    }
                    Spacer(minLength: 0)
                    if t != nil {
                        Button { m.bump("today") } label: {
                            ZStack {
                                Circle().fill(t!.done ? gGreen : Color.white.opacity(0.6))
                                Circle().stroke(t!.done ? gGreen : gSub.opacity(0.42), lineWidth: 2)
                                if t!.done { Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundColor(.white).transition(.scale) }
                            }.frame(width: 40, height: 40).shadow(color: t!.done ? gGreen.opacity(0.45) : .clear, radius: 8, y: 6)
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ringTile("This week", "week", gBlue, gBlue.opacity(0.15))
                ringTile("This month", "month", hex(0xff9500), hex(0xff9500).opacity(0.17))
            }.fixedSize(horizontal: false, vertical: true)
            if let y = m.life?.goals.first {
                HStack(spacing: 8) { Image(systemName: "house").font(.system(size: 12)); Text(y).lineLimit(1) }
                    .font(.system(size: 12, weight: .medium)).foregroundColor(gSub.opacity(1.15)).padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                ForEach(shown) { row($0) }
                if todos.isEmpty { Text(m.familyTime ? "Nothing due. Enjoy the evening." : "Nothing to do.").font(.system(size: 13, weight: .medium)).foregroundColor(gSub).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                HStack {
                    Text("\(todos.count) open").foregroundColor(gSub)
                    Spacer()
                    if todos.count > listCap { Button(ui.showAll ? "Show less" : "Show \(todos.count - listCap) more") { withAnimation { ui.showAll.toggle() } }.buttonStyle(.plain).foregroundColor(gBlue) }
                    Button("Add…") { DispatchQueue.main.async { m.addTask() } }.buttonStyle(.plain).foregroundColor(gBlue).padding(.leading, 8)
                }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            }
            .padding(6).background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
            if !m.moments.isEmpty {
                HStack(spacing: 8) {
                    ForEach(m.moments) { mo in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mo.when).font(.system(size: 15, weight: .semibold)).kerning(-0.2).lineLimit(1).minimumScaleFactor(0.55)
                            Text(mo.detail).font(.system(size: 11, weight: .medium)).foregroundColor(gSub).lineLimit(2)
                        }.frame(maxWidth: .infinity, alignment: .topLeading).padding(.horizontal, 10).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.45)))
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
            Carousel(m: m)
            HStack {
                Button("Tell Buddy…") { DispatchQueue.main.async { m.tellBuddy() } }.buttonStyle(.plain).foregroundColor(gBlue)
                Spacer()
                Text("Private to this Mac").foregroundColor(gSub.opacity(0.85))
            }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 4)
        }
    }
    func ringTile(_ title: String, _ which: String, _ c: Color, _ track: Color) -> some View {
        let g = m.goal(which), (k, n) = m.progress(which)
        return Button { g == nil ? DispatchQueue.main.async { m.setGoal(which) } : m.bump(which) } label: {
            VStack(alignment: .leading, spacing: 0) {
                lab(title)
                HStack(spacing: 10) {
                    ringView(50, 7, Double(k), Double(n), c, track)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(k)").font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        Text("/\(n)").font(.system(size: 14)).foregroundColor(gSub.opacity(0.85))
                    }
                }.padding(.top, 6).padding(.bottom, 8)
                Text(g?.text ?? "Set one…").font(.system(size: 12, weight: .medium)).foregroundColor(g == nil ? gSub : gInk)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.vertical, 12).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
        }.buttonStyle(.plain)
    }
    func row(_ t: Todo) -> some View {
        let done = ui.ticking.contains(t.id), hovered = ui.hover == t.id
        return HStack(spacing: 10) {
            Button { ui.tick(t, m) } label: {
                ZStack {
                    Circle().fill(done ? gBlue : .clear)
                    Circle().stroke(done ? gBlue : gSub.opacity(0.58), lineWidth: 1.5)
                    if done { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white) }
                }.frame(width: 18, height: 18)
            }.buttonStyle(.plain)
            Text(t.text).font(.system(size: 13, weight: .medium)).foregroundColor(done ? gSub.opacity(0.67) : gInk).lineLimit(1)
            Spacer(minLength: 4)
            Circle().fill(areaColor(t.area)).frame(width: 6, height: 6).help(t.area ?? "home")
            if hovered && !done {
                Button { withAnimation { m.notToday(t) } } label: {
                    Text("Not today").font(.system(size: 11, weight: .semibold)).foregroundColor(gInk).padding(.horizontal, 8).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 7).fill(gFill.opacity(0.14)))
                }.buttonStyle(.plain)
            } else if let d = t.due {
                let n = dueDays(d)
                Text(dueText(d).0).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundColor(n <= 0 ? hex(0xe8590c) : n <= 6 ? gInk : gSub.opacity(0.92))
            }
        }
        .frame(height: 34).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? Color.white.opacity(0.6) : .clear))
        .contentShape(Rectangle()).onHover { h in ui.hover = h ? t.id : (ui.hover == t.id ? nil : ui.hover) }
    }

    // ---- Work
    var work: some View {
        let s = m.stats, quiet = m.ignoredRed.count, g = m.goal("today")
        let pots = m.pots, shown = ui.allPots ? pots : Array(pots.prefix(listCap))
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(m.waiting) { w in
                Button { activate(w) } label: {
                    HStack(spacing: 10) {
                        appIcon(w)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(w.repo ?? "?") wants your OK").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(w.activity ?? "").font(.system(size: 11, design: .monospaced)).foregroundColor(hex(0xe8590c)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text("Go ›").font(.system(size: 12, weight: .semibold)).foregroundColor(hex(0xe8590c))
                    }.padding(10).background(RoundedRectangle(cornerRadius: 14).fill(hex(0xff9500).opacity(0.16)))
                }.buttonStyle(.plain)
            }
            ForEach(m.needsYouPRs) { PRBlock(m: m, pr: $0).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.55))) }
            HStack(spacing: 8) {
                if !statsRepos.isEmpty {
                    num("\(s.merged)", "merged", s.gain)
                    num("\(s.opened)", "opened", nil)
                }
                num(hm(m.workedToday), "worked", nil)
                num(m.sinceBreak.map(hm) ?? "now", "since break", nil, hot: (m.sinceBreak ?? 0) >= 90 * 60)
            }
            if !pots.isEmpty || !m.stuck.isEmpty {
                VStack(spacing: 0) {
                    ForEach(m.stuck) { st in
                        Button { activate(st) } label: {
                            Text("⚠︎ \(st.repo ?? "?") quiet \(st.quietFor) · \(st.activity ?? "")").font(.system(size: 12, weight: .medium)).foregroundColor(hex(0xe8590c)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).padding(.vertical, 7)
                        }.buttonStyle(.plain)
                    }
                    ForEach(shown, ) { p in
                        Button { activate(p.s) } label: {
                            HStack(spacing: 10) {
                                appIcon(p.s)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Text(p.s.repo ?? "?").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                        if !p.done { Circle().fill(gGreen).frame(width: 6, height: 6) }
                                    }
                                    Text(p.line).font(.system(size: 11, design: .monospaced)).foregroundColor(gSub).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(p.done ? "done \(p.age)" : p.age)
                                    .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundColor(p.done ? hex(0x248a3d) : gSub)
                            }.padding(.horizontal, 6).padding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if pots.count > listCap { Button(ui.allPots ? "Show less" : "Show \(pots.count - listCap) more") { withAnimation { ui.allPots.toggle() } }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundColor(gBlue).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
                }.padding(.vertical, 6).padding(.horizontal, 8).background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
            }
            if !s.team.isEmpty {
                plat(10) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(s.podium, id: \.medal) { r in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(r.medal) \(r.n)").font(.system(size: 15, weight: .semibold))
                                Text(r.who).font(.system(size: 11, weight: .medium)).foregroundColor(gSub).lineLimit(1).truncationMode(.middle)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.rankText).font(.system(size: 15, weight: .semibold)).foregroundColor(gBlue)
                            Text("you · \(s.myCount)").font(.system(size: 11, weight: .medium)).foregroundColor(gSub).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.help("PRs merged by the team: \(s.teamTotal) in all")
            }
            if !m.limits.isEmpty {
                plat {
                    VStack(alignment: .leading, spacing: 8) {
                        lab("Usage")
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(m.limits) { l in
                                VStack(spacing: 4) {
                                    ZStack {
                                        ringView(44, 5, l.used, 100, l.used >= 80 ? hex(0xff9500) : gGreen, Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.12))
                                        Text("\(Int(l.used))%").font(.system(size: 13, weight: .semibold))
                                    }
                                    Text(l.name.replacingOccurrences(of: "◆ ", with: "")).font(.system(size: 11, weight: .medium)).foregroundColor(gSub).lineLimit(1)
                                    Text(l.resets.map { "resets " + resetText($0) } ?? " ").font(.system(size: 10, weight: .medium)).foregroundColor(gSub.opacity(0.7)).lineLimit(1)
                                }.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                if m.diskFreeGB >= 0 {
                    Button { openWorktreeReport(m.worktrees) } label: {
                        (Text("\(Int(m.diskFreeGB)) GB").fontWeight(.semibold).foregroundColor(m.diskFreeGB < diskLowGB ? hex(0xe8590c) : gInk) + Text(" free · \(m.worktrees.count) worktrees"))
                    }.buttonStyle(.plain)
                }
                Spacer()
                if quiet > 0 { Button("\(quiet) red PRs ignored") { m.showStale.toggle() }.buttonStyle(.plain) }
            }.font(.system(size: 12, weight: .medium)).foregroundColor(gSub.opacity(1.15)).padding(.horizontal, 4)
            if m.showStale {
                ForEach(m.ignoredRed) { pr in
                    Button { NSWorkspace.shared.open(URL(string: pr.url)!) } label: { Text("\(pr.short) · \(pr.title)").font(.system(size: 11)).foregroundColor(gSub).lineLimit(1) }.buttonStyle(.plain).padding(.horizontal, 4)
                }
            }
            Button { g == nil ? DispatchQueue.main.async { m.setGoal("today") } : withAnimation(.spring(response: 0.35)) { m.tab = "personal" } } label: {
                HStack(spacing: 10) {
                    Circle().fill(g?.done == true ? gGreen : .clear).overlay(Circle().stroke(g?.done == true ? gGreen : gSub.opacity(0.58), lineWidth: 1.5)).frame(width: 16, height: 16)
                    Text("TODAY").font(.system(size: 11, weight: .semibold)).foregroundColor(gSub.opacity(0.92))
                    Text(g?.text ?? "Set today's goal").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("›").foregroundColor(gSub.opacity(0.67))
                }.padding(.horizontal, 12).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.4)))
            }.buttonStyle(.plain)
            Carousel(m: m)

        }
    }
    func appIcon(_ x: Session) -> some View {
        RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: x.agent.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 28, height: 28).overlay(Text(x.agent.glyph).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white))
    }
    func num(_ big: String, _ label: String, _ em: String?, hot: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.system(size: 24, weight: .semibold)).kerning(-0.6).monospacedDigit().foregroundColor(hot ? hex(0xe8590c) : gInk).lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Text(label).font(.system(size: 11.5, weight: .medium)).foregroundColor(gSub).lineLimit(1).minimumScaleFactor(0.8)
                if let em = em { Text(em).font(.system(size: 11, weight: .semibold)).foregroundColor(hex(0x248a3d)) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55)))
    }
}
