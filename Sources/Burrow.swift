import AppKit
import SwiftUI

// MARK: Burrow, built to the approved mockup (round 2, direction 3): the scene IS the card's header

/// Rows shown before "+ N more": three keeps every card short enough to fit above Buddy without scrolling.
let bClay = hex(0xd97757), bSage = hex(0x7fa77a), bSageInk = hex(0x5f8a5a), bInk = hex(0x3a2a1f), bSub = hex(0x8b7363)
let bBtn = hex(0xf3e6d6), bBtnInk = hex(0x7a4a30), bChip = hex(0xf6ece0), bChipInk = hex(0x6a4a36)
let bShadow = hex(0x784f28)

/// Chips that wrap like words.
struct Flow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > w { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX && x + s.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

struct BurrowCard: View {
    @ObservedObject var m: Model
    @State private var showAll = false
    @State private var allPots = false
    @State private var hover: String?
    @State private var ticking: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if m.tab == "personal" { BurrowLifeScene(m: m) } else { BurrowWorkScene(m: m) }
                header.padding(.top, 10).padding(.horizontal, 14)
            }
            .frame(height: 118).clipped()
            Group { if m.tab == "personal" { personal } else { work } }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        }
        .foregroundColor(bInk)
    }

    // ---- header on the scene: name, a mood pill, the sliding tab switch
    var pill: String {
        if m.tab == "personal" { return "out for a walk" }
        if !m.waiting.isEmpty { return "needs you" }
        let n = m.working.count
        return n == 0 ? "napping by the stove" : "minding \(n) pot\(n == 1 ? "" : "s")"
    }
    var header: some View {
        HStack(spacing: 8) {
            Text("Buddy").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(hex(0x5a3420))
            Text(pill).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(hex(0x8b5a3c))
                .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Color.white.opacity(0.55)))
            Spacer(minLength: 0)
            ZStack(alignment: .leading) {
                Capsule().fill(bClay).frame(width: 76).shadow(color: bClay.opacity(0.45), radius: 4, y: 3)
                    .offset(x: m.tab == "personal" ? 76 : 0)
                HStack(spacing: 0) {
                    ForEach(["work", "personal"], id: \.self) { t in
                        Button { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { m.tab = t } } label: {
                            Text(t.capitalized).font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(m.tab == t ? .white : bBtnInk).frame(width: 76).padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            .fixedSize().padding(3).background(Capsule().fill(Color.white.opacity(0.6)))
        }
    }

    func card<V: View>(_ r: CGFloat, @ViewBuilder _ v: () -> V) -> some View {
        v().background(RoundedRectangle(cornerRadius: r).fill(Color.white).shadow(color: bShadow.opacity(0.08), radius: 1, y: 1))
    }

    // ---- Personal
    var personal: some View {
        let t = m.goal("today"), w = m.goal("week"), mo = m.goal("month")
        let todos = m.todos, shown = showAll ? todos : Array(todos.prefix(listCap))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY").font(.system(size: 11, weight: .bold, design: .rounded)).kerning(0.4).foregroundColor(bClay)
                    Button { if t == nil { DispatchQueue.main.async { m.setGoal("today") } } } label: {
                        Text(t?.text ?? "What's today's goal?").font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(t == nil ? bSub : bInk).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button { t == nil ? DispatchQueue.main.async { m.setGoal("today") } : m.bump("today") } label: {
                    Text(t == nil ? "Set" : t!.done ? "Done ✓" : "Did it").font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(t?.done == true ? .white : bBtnInk).frame(width: 74).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 16).fill(t?.done == true ? bSage : bBtn))
                        .shadow(color: t?.done == true ? bSage.opacity(0.5) : .clear, radius: 7, y: 5)
                }.buttonStyle(.plain)
            }
            .padding(.vertical, 9).padding(.leading, 16).padding(.trailing, 10)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white).shadow(color: bShadow.opacity(0.08), radius: 9, y: 4))

            HStack(alignment: .top, spacing: 10) {
                goalTile("🪨 THE PATH · WEEK", w, "week", w.map { "\($0.k) of \($0.n ?? 1) stones" }, bClay)
                goalTile("🌱 THE PLANT · MONTH", mo, "month", mo.map { "\($0.k) of \($0.n ?? 1) leaves" }, bSageInk)
            }.fixedSize(horizontal: false, vertical: true).padding(.top, 10)

            if let y = m.life?.goals.first {
                Text("🏡 The house on the hill: \(y)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(bSub)
                    .padding(.top, 10).padding(.horizontal, 4)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Little things").font(.system(size: 14, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(todos.count) left").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(bSub)
            }.padding(.top, 10).padding(.bottom, 5).padding(.horizontal, 4)
            if todos.isEmpty {
                Text(m.familyTime ? "Nothing due. Enjoy the evening." : "Nothing left. Nice.").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(bSub).padding(.horizontal, 4)
            }
            VStack(spacing: 4) { ForEach(shown) { row($0) } }
            HStack {
                if todos.count > listCap { Button(showAll ? "show less" : "+ \(todos.count - listCap) more") { withAnimation { showAll.toggle() } }.buttonStyle(.plain) }
                Spacer()
                Button("Add one…") { DispatchQueue.main.async { m.addTask() } }.buttonStyle(.plain)
            }.font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(bClay).padding(.top, 4).padding(.horizontal, 4)

            if !m.moments.isEmpty {
                Flow(spacing: 6) {
                    ForEach(m.moments.prefix(2)) { mo in
                        Text("\(mo.icon) \(mo.text)").font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundColor(bChipInk)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(bChip))
                    }
                }.padding(.top, 8)
            }
            Carousel(m: m).padding(.top, 10)
            HStack {
                Button("Tell Buddy…") { DispatchQueue.main.async { m.tellBuddy() } }.buttonStyle(.plain).foregroundColor(bClay)
                Spacer()
                Text("stays on this Mac").foregroundColor(bSub)
            }.font(.system(size: 12, weight: .bold, design: .rounded)).padding(.top, 10).padding(.horizontal, 4)
        }
    }

    func goalTile(_ h: String, _ g: Goal?, _ which: String, _ progress: String?, _ c: Color) -> some View {
        Button { g == nil ? DispatchQueue.main.async { m.setGoal(which) } : m.bump(which) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(h).font(.system(size: 11, weight: .bold, design: .rounded)).kerning(0.3).foregroundColor(bSub).fixedSize(horizontal: false, vertical: true)
                Text(g?.text ?? "Set one…").font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundColor(g == nil ? bSub : bInk)
                    .multilineTextAlignment(.leading).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 4).padding(.bottom, 5).help(g?.text ?? "")
                Spacer(minLength: 0)
                if let p = progress { Text(p).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(c) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white).shadow(color: bShadow.opacity(0.06), radius: 1, y: 2))
        }.buttonStyle(.plain).help(g == nil ? "Set it" : "Click: one more")
    }

    func row(_ t: Todo) -> some View {
        let done = ticking.contains(t.id)
        let days = t.due.map { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: $0).day ?? 0 }
        let (bg, fg): (Color, Color) = days.map { $0 <= 0 ? (hex(0xffe2cf), hex(0xc4542b)) : $0 <= 6 ? (hex(0xe7f0e2), hex(0x4d7a48)) : (bChip, bSub) } ?? (bChip, bSub)
        return HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { _ = ticking.insert(t.id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { ticking.remove(t.id); m.tick(t) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(done ? bSage : hex(0xfffaf4))
                    RoundedRectangle(cornerRadius: 8).stroke(done ? bSage : hex(0xe3c9b0), lineWidth: 2)
                    if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.white).transition(.scale) }
                }.frame(width: 22, height: 22)
            }.buttonStyle(.plain)
            Text(t.text).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(done ? hex(0xb9a597) : bInk)
                .strikethrough(done, color: hex(0xb9a597)).lineLimit(1)
            Spacer(minLength: 4)
            if hover == t.id && !done {
                Button { withAnimation { m.notToday(t) } } label: {
                    Text("☾ tomorrow").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(hex(0x6b4f8a))
                        .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(hex(0xefe4f7)))
                }.buttonStyle(.plain)
            } else if let d = t.due {
                Text(dueText(d).0).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(fg)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(bg))
            }
        }
        .frame(height: 36).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(hover == t.id ? hex(0xfffdf9) : Color.white).shadow(color: bShadow.opacity(hover == t.id ? 0.1 : 0.06), radius: hover == t.id ? 6 : 1, y: hover == t.id ? 4 : 1))
        .contentShape(Rectangle())
        .onHover { h in hover = h ? t.id : (hover == t.id ? nil : hover) }
    }

    // ---- Work
    var work: some View {
        let pots = m.pots
        let shownPots = allPots ? pots : Array(pots.prefix(listCap))
        let s = m.stats, quiet = m.ignoredRed.count
        let g = m.goal("today")
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 6) {
                ForEach(m.waiting) { w in
                    Button { activate(w) } label: {
                        HStack(spacing: 10) {
                            potIcon(w)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(w.repo ?? "?") wants your OK").font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                                Text(w.activity ?? "").font(.system(size: 11, design: .monospaced)).foregroundColor(hex(0xc4542b)).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text("Go →").font(.system(size: 11.5, weight: .heavy, design: .rounded)).foregroundColor(hex(0xc4542b))
                        }.padding(.horizontal, 12).padding(.vertical, 9).background(RoundedRectangle(cornerRadius: 16).fill(hex(0xffe2cf)))
                    }.buttonStyle(.plain)
                }
                ForEach(m.needsYouPRs) { PRBlock(m: m, pr: $0).background(RoundedRectangle(cornerRadius: 16).fill(Color.white)) }
                ForEach(m.stuck) { st in
                    Button { activate(st) } label: {
                        Text("⚠︎ \(st.repo ?? "?") quiet \(st.quietFor) · last: \(st.activity ?? "")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(hex(0xc4542b)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 14).fill(hex(0xfdebd9)))
                    }.buttonStyle(.plain)
                }
                ForEach(shownPots, ) { p in
                    Button { activate(p.s) } label: {
                        HStack(spacing: 10) {
                            potIcon(p.s)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.s.repo ?? "?").font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                                Text(p.line).font(.system(size: 11, design: .monospaced)).foregroundColor(bSub).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(p.done ? "done \(p.age)" : p.age)
                                .font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundColor(p.done ? bSageInk : bSub)
                        }.padding(.horizontal, 12).padding(.vertical, 7).background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                    }.buttonStyle(.plain)
                }
                if pots.isEmpty && m.waiting.isEmpty {
                    Text("Nothing on the stove. Buddy's napping.").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(bSub)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
                if pots.count > listCap {
                    Button(allPots ? "show less" : "+ \(pots.count - listCap) more") { withAnimation { allPots.toggle() } }.buttonStyle(.plain)
                        .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(bClay).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
            }

            HStack(spacing: 8) {
                if !statsRepos.isEmpty {
                    tile("\(s.merged)", "merged", s.gain)
                    tile("\(s.opened)", "opened", nil)
                }
                tile(hm(m.workedToday), "worked", nil)
                tile(m.sinceBreak.map(hm) ?? "now", "since break", nil, hot: (m.sinceBreak ?? 0) >= 90 * 60)
            }.padding(.top, 10)

            if !s.team.isEmpty {   // the team leaderboard: PRs merged
                HStack(alignment: .top, spacing: 6) {
                    ForEach(s.podium, id: \.medal) { r in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(r.medal) \(r.n)").font(.system(size: 14, weight: .heavy, design: .rounded))
                            Text(r.who).font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(r.me ? bClay : bSub).lineLimit(1).truncationMode(.middle)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.rankText).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(bClay)
                        Text("you · \(s.myCount)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(bSub).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12).padding(.vertical, 7).background(RoundedRectangle(cornerRadius: 16).fill(Color.white)).padding(.top, 8)
                .help("PRs merged by the team: \(s.teamTotal) in all")
            }

            if !m.limits.isEmpty {
                VStack(spacing: 4) {
                    ForEach(m.limits) { l in
                        let c = l.used >= 95 ? hex(0xc4542b) : l.used >= 80 ? hex(0xe0a040) : bSage
                        HStack(spacing: 8) {
                            Text(l.name.replacingOccurrences(of: "◆ ", with: "")).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1).frame(width: 84, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(bBtn)
                                    Capsule().fill(c).frame(width: geo.size.width * min(1, l.used / 100))
                                }
                            }.frame(height: 8)
                            Text("\(Int(l.used))%").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(bSub).monospacedDigit().frame(width: 34, alignment: .trailing)
                        }.frame(height: 18).help(l.resets.map { "resets " + resetText($0) } ?? "")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 16).fill(Color.white)).padding(.top, 8)
            }

            HStack {
                if m.diskFreeGB >= 0 {
                    Button("\(Int(m.diskFreeGB)) GB free · \(m.worktrees.count) worktrees") { openWorktreeReport(m.worktrees) }.buttonStyle(.plain)
                        .foregroundColor(m.diskFreeGB < diskLowGB ? hex(0xc4542b) : bSub).help("Click for the worktree list, oldest first")
                }
                Spacer()
                if quiet > 0 { Button("\(quiet) red ignored") { m.showStale.toggle() }.buttonStyle(.plain).foregroundColor(bSub) }
            }.font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.top, 10).padding(.horizontal, 4)
            if m.showStale {
                ForEach(m.ignoredRed) { pr in
                    Button { NSWorkspace.shared.open(URL(string: pr.url)!) } label: {
                        Text("\(pr.short) · \(pr.title)").font(.system(size: 11, design: .rounded)).foregroundColor(bSub).lineLimit(1)
                    }.buttonStyle(.plain).padding(.horizontal, 4).padding(.top, 3)
                }
            }

            Button { g == nil ? DispatchQueue.main.async { m.setGoal("today") } : withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { m.tab = "personal" } } label: {
                HStack(spacing: 10) {
                    Text("🐾")
                    Text(g?.text ?? "Set today's goal").font(.system(size: 12.5, weight: .bold, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(g?.done == true ? "done ✓" : "today →").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(g?.done == true ? hex(0x4d7a48) : hex(0xc4542b))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 16).fill(g?.done == true ? hex(0xe7f0e2) : hex(0xfdebd9)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(g?.done == true ? hex(0xb9d3b2) : hex(0xecc3a2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            }.buttonStyle(.plain).padding(.top, 10)

            Carousel(m: m).padding(.top, 10)

        }
    }
    func potIcon(_ x: Session) -> some View {
        RoundedRectangle(cornerRadius: 11).fill(x.agent.color).frame(width: 30, height: 30)
            .overlay(Text(x.agent.badge).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(.white))
    }
    func tile(_ big: String, _ label: String, _ em: String?, hot: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(hot ? hex(0xc4542b) : bInk)
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(bSub).lineLimit(1).minimumScaleFactor(0.8)
                if let em = em { Text(em).font(.system(size: 10.5, weight: .heavy, design: .rounded)).foregroundColor(bSageInk) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
    }
}

/// The mockup's scenes are drawn in a 360×150 box; scale to cover the card's width, like SVG "slice".
func sceneTransform(_ size: CGSize) -> (CGFloat, CGFloat, CGFloat) {
    let s = max(size.width / 360, size.height / 150)
    return (s, (size.width - 360 * s) / 2, size.height - 150 * s)   // bottom-aligned: a shorter scene loses sky, not the path
}
func quad(_ p: inout Path, _ c: CGPoint, _ e: CGPoint) { p.addQuadCurve(to: e, control: c) }

/// The pet in the scene, drawn like the mockup's cat; bears get round ears, pugs floppy dark ones.
struct ScenePet: View {
    var fur: Color, dark: Color
    var body: some View {
        Canvas { c, size in
            c.translateBy(x: 26, y: 40)
            var tail = Path(); tail.move(to: CGPoint(x: -10, y: -8)); quad(&tail, CGPoint(x: -20, y: -10), CGPoint(x: -19, y: -22))
            c.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            c.fill(Path(ellipseIn: CGRect(x: -12, y: -17.5, width: 24, height: 17)), with: .color(fur))
            c.fill(Path(ellipseIn: CGRect(x: -4, y: -10, width: 12, height: 8)), with: .color(hex(0xfbe2cd)))
            c.fill(Path(ellipseIn: CGRect(x: 1, y: -28, width: 16, height: 16)), with: .color(fur))
            if isBear {
                c.fill(Path(ellipseIn: CGRect(x: 1, y: -31, width: 6, height: 6)), with: .color(fur))
                c.fill(Path(ellipseIn: CGRect(x: 11, y: -31, width: 6, height: 6)), with: .color(fur))
            } else if isPug {
                c.fill(Path(ellipseIn: CGRect(x: 0, y: -28, width: 5, height: 8)), with: .color(dark))
                c.fill(Path(ellipseIn: CGRect(x: 13, y: -28, width: 5, height: 8)), with: .color(dark))
            } else {
                var ears = Path()
                ears.move(to: CGPoint(x: 3, y: -25)); ears.addLine(to: CGPoint(x: 4, y: -32)); ears.addLine(to: CGPoint(x: 9, y: -28)); ears.closeSubpath()
                ears.move(to: CGPoint(x: 15, y: -25)); ears.addLine(to: CGPoint(x: 14, y: -32)); ears.addLine(to: CGPoint(x: 9, y: -28)); ears.closeSubpath()
                c.fill(ears, with: .color(fur))
            }
            let eye = hex(0x3a1f12)
            c.fill(Path(ellipseIn: CGRect(x: 5.3, y: -21.7, width: 2.4, height: 2.4)), with: .color(eye))
            c.fill(Path(ellipseIn: CGRect(x: 10.8, y: -21.7, width: 2.4, height: 2.4)), with: .color(eye))
            var smile = Path(); smile.move(to: CGPoint(x: 8, y: -16.8)); quad(&smile, CGPoint(x: 9.3, y: -15.8), CGPoint(x: 10.6, y: -16.8))
            c.stroke(smile, with: .color(eye), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            c.fill(Path(roundedRect: CGRect(x: -8, y: -3, width: 4, height: 4), cornerRadius: 2), with: .color(fur))
            c.fill(Path(roundedRect: CGRect(x: 5, y: -3, width: 4, height: 4), cornerRadius: 2), with: .color(fur))
        }.frame(width: 52, height: 44)
    }
}

/// Personal: Buddy walks this week's path stone by stone; the plant grows a leaf per step of the month; the house is the year.
struct BurrowLifeScene: View {
    @ObservedObject var m: Model
    static let stones: [CGPoint] = [CGPoint(x: 40, y: 121), CGPoint(x: 108, y: 111), CGPoint(x: 176, y: 115), CGPoint(x: 244, y: 108)]
    static func stone(_ i: Int, _ n: Int) -> CGPoint {
        let t = Double(i) / Double(max(n, 1)) * 3, j = min(Int(t), 2), f = t - Double(j)
        let a = stones[j], b = stones[j + 1]
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }
    var body: some View {
        let w = m.goal("week"), mo = m.goal("month")
        let n = max(w?.n ?? 3, 1), k = min(w.map { $0.n == nil ? ($0.done ? n : 0) : $0.k } ?? 0, n)
        let ln = max(mo?.n ?? 2, 1), lk = mo.map { $0.n == nil ? ($0.done ? ln : 0) : $0.k } ?? 0
        let year = (m.life?.goals.first).flatMap { g in g.range(of: #"\d{4}"#, options: .regularExpression).map { String(g[$0]) } } ?? ""
        GeometryReader { geo in
            let (sc, ox, oy) = sceneTransform(geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { c, size in
                    c.translateBy(x: ox, y: oy); c.scaleBy(x: sc, y: sc)
                    c.fill(Path(CGRect(x: 0, y: 0, width: 360, height: 150)), with: .linearGradient(Gradient(colors: [hex(0xffcfa3), hex(0xfff2df)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 150)))
                    c.fill(Path(ellipseIn: CGRect(x: 272, y: 32, width: 40, height: 40)), with: .color(hex(0xffb877).opacity(0.75)))
                    var back = Path(); back.move(to: CGPoint(x: 0, y: 98)); quad(&back, CGPoint(x: 80, y: 62), CGPoint(x: 170, y: 86)); quad(&back, CGPoint(x: 260, y: 110), CGPoint(x: 360, y: 70))
                    back.addLine(to: CGPoint(x: 360, y: 150)); back.addLine(to: CGPoint(x: 0, y: 150)); back.closeSubpath()
                    c.fill(back, with: .color(hex(0xecd3b3)))
                    // the house on the hill: the year goal
                    c.fill(Path(CGRect(x: 206, y: 70, width: 16, height: 11)), with: .color(hex(0xc98a6a)))
                    var roof = Path(); roof.move(to: CGPoint(x: 203, y: 71)); roof.addLine(to: CGPoint(x: 214, y: 62)); roof.addLine(to: CGPoint(x: 225, y: 71)); roof.closeSubpath()
                    c.fill(roof, with: .color(hex(0xa96446)))
                    c.fill(Path(CGRect(x: 212, y: 74, width: 4, height: 7)), with: .color(hex(0xfff2df)))
                    if !year.isEmpty { c.draw(Text(year).font(.system(size: 8, weight: .bold, design: .rounded)).foregroundColor(hex(0xa07858)), at: CGPoint(x: 214, y: 93)) }
                    var front = Path(); front.move(to: CGPoint(x: 0, y: 122)); quad(&front, CGPoint(x: 120, y: 92), CGPoint(x: 240, y: 112)); quad(&front, CGPoint(x: 360, y: 132), CGPoint(x: 360, y: 104))
                    front.addLine(to: CGPoint(x: 360, y: 150)); front.addLine(to: CGPoint(x: 0, y: 150)); front.closeSubpath()
                    c.fill(front, with: .color(hex(0xcfe0b6)))
                    var trail = Path(); trail.move(to: CGPoint(x: 40, y: 121)); quad(&trail, CGPoint(x: 74, y: 108), CGPoint(x: 108, y: 111)); quad(&trail, CGPoint(x: 142, y: 114), CGPoint(x: 176, y: 115)); quad(&trail, CGPoint(x: 210, y: 116), CGPoint(x: 244, y: 108))
                    c.stroke(trail, with: .color(hex(0xb98b62)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 5]))
                    for i in 0...n {
                        let p = BurrowLifeScene.stone(i, n), r = CGRect(x: p.x - 10, y: p.y + 1 - 4, width: 20, height: 8)
                        c.fill(Path(ellipseIn: r), with: .color(i <= k ? hex(0xf4b183) : hex(0xefe1cf)))
                        c.stroke(Path(ellipseIn: r), with: .color(hex(0xc8a27e)), lineWidth: 1)
                    }
                    let end = BurrowLifeScene.stone(n, n)
                    var pole = Path(); pole.move(to: end); pole.addLine(to: CGPoint(x: end.x, y: end.y - 20))
                    c.stroke(pole, with: .color(hex(0x8b5a3c)), lineWidth: 1.5)
                    var flag = Path(); flag.move(to: CGPoint(x: end.x, y: end.y - 20)); flag.addLine(to: CGPoint(x: end.x + 11, y: end.y - 16)); flag.addLine(to: CGPoint(x: end.x, y: end.y - 12)); flag.closeSubpath()
                    c.fill(flag, with: .color(bClay))
                    // the plant: a leaf per step of the month goal
                    c.translateBy(x: 315, y: 128)
                    var pot = Path(); pot.move(to: CGPoint(x: -11, y: 0)); pot.addLine(to: CGPoint(x: 11, y: 0)); pot.addLine(to: CGPoint(x: 8, y: 14)); pot.addLine(to: CGPoint(x: -8, y: 14)); pot.closeSubpath()
                    c.fill(pot, with: .color(hex(0xc9764f)))
                    c.fill(Path(roundedRect: CGRect(x: -13, y: -3, width: 26, height: 5), cornerRadius: 2), with: .color(hex(0xb0613e)))
                    let top = -14 - 12 * CGFloat(ln - 1) - 8
                    var stem = Path(); stem.move(to: CGPoint(x: 0, y: -3)); stem.addLine(to: CGPoint(x: 0, y: min(-34, top)))
                    c.stroke(stem, with: .color(bSageInk), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    for i in 0..<ln {
                        let y0 = -14 - 12 * CGFloat(i), left = i % 2 == 0, d: CGFloat = left ? -1 : 1
                        var leaf = Path(); leaf.move(to: CGPoint(x: 0, y: y0))
                        quad(&leaf, CGPoint(x: 16 * d, y: y0 - 2), CGPoint(x: 18 * d, y: y0 - 14)); quad(&leaf, CGPoint(x: 4 * d, y: y0 - 14), CGPoint(x: 0, y: y0)); leaf.closeSubpath()
                        if i < lk { c.fill(leaf, with: .color(left ? bSage : hex(0x8fb98a))) }
                        else { c.fill(Path(ellipseIn: CGRect(x: 2 * d - 2, y: y0 - 4, width: 4, height: 4)), with: .color(bSage.opacity(0.4))) }
                    }
                }
                let p = BurrowLifeScene.stone(k, n)
                ScenePet(fur: m.breed.fur, dark: m.breed.dark)
                    .scaleEffect(sc)
                    .position(x: ox + p.x * sc, y: oy + (p.y - 18) * sc)
                    .animation(.spring(response: 0.8, dampingFraction: 0.6), value: k)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { m.bump("week") }
        .help("Click: Buddy walks one stone further this week")
    }
}

/// Work: a stove with one steaming pot per session that's cooking.
struct BurrowWorkScene: View {
    @ObservedObject var m: Model
    var body: some View {
        let pots = Array(m.working.prefix(3))
        GeometryReader { geo in
            let (sc, ox, oy) = sceneTransform(geo.size)
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: pots.isEmpty ? 60 : 1.0 / 20)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { c, size in
                        c.translateBy(x: ox, y: oy); c.scaleBy(x: sc, y: sc)
                        c.fill(Path(CGRect(x: 0, y: 0, width: 360, height: 150)), with: .color(hex(0xf7e2c6)))
                        c.fill(Path(roundedRect: CGRect(x: 262, y: 34, width: 70, height: 46), cornerRadius: 8), with: .color(hex(0xffd3a3)))
                        var cross = Path(); cross.move(to: CGPoint(x: 297, y: 34)); cross.addLine(to: CGPoint(x: 297, y: 80)); cross.move(to: CGPoint(x: 262, y: 57)); cross.addLine(to: CGPoint(x: 332, y: 57))
                        c.stroke(cross, with: .color(hex(0xf7e2c6)), lineWidth: 3)
                        c.fill(Path(ellipseIn: CGRect(x: 276, y: 42, width: 12, height: 12)), with: .color(hex(0xfff4dc).opacity(0.9)))
                        c.fill(Path(CGRect(x: 0, y: 116, width: 360, height: 34)), with: .color(hex(0xc99c74)))
                        c.fill(Path(CGRect(x: 0, y: 113, width: 360, height: 5)), with: .color(hex(0xb3845d)))
                        c.fill(Path(roundedRect: CGRect(x: 96, y: 112, width: 200, height: 6), cornerRadius: 3), with: .color(hex(0x6b4a36)))
                        for (i, s) in pots.enumerated() {
                            let x = pots.count == 1 ? 196 : 130 + CGFloat(i) * (132 / CGFloat(max(pots.count - 1, 1)))
                            let col = s.agent.color
                            var g = c; g.translateBy(x: x, y: 104)
                            for (dx, delay) in [(-4.0, Double(i) * 0.6), (5.0, Double(i) * 0.6 + 1.1)] {
                                let ph = ((t + delay).truncatingRemainder(dividingBy: 2.4)) / 2.4
                                let op = ph < 0.3 ? ph / 0.3 * 0.75 : 0.75 * (1 - (ph - 0.3) / 0.7)
                                var st = Path(); let y0 = -14 + 4 - 20 * ph
                                st.move(to: CGPoint(x: dx, y: y0)); quad(&st, CGPoint(x: dx - 4, y: y0 - 6), CGPoint(x: dx, y: y0 - 12)); quad(&st, CGPoint(x: dx + 4, y: y0 - 18), CGPoint(x: dx, y: y0 - 24))
                                g.stroke(st, with: .color(.white.opacity(op)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            }
                            g.fill(Path(roundedRect: CGRect(x: -17, y: -10, width: 34, height: 22), cornerRadius: 7), with: .color(col))
                            g.fill(Path(roundedRect: CGRect(x: -20, y: -13, width: 40, height: 5), cornerRadius: 2.5), with: .color(col.opacity(0.85)))
                            g.fill(Path(roundedRect: CGRect(x: -24, y: -4, width: 5, height: 3), cornerRadius: 1.5), with: .color(col))
                            g.fill(Path(roundedRect: CGRect(x: 19, y: -4, width: 5, height: 3), cornerRadius: 1.5), with: .color(col))
                        }
                    }
                }
                ScenePet(fur: m.breed.fur, dark: m.breed.dark).scaleEffect(sc).position(x: ox + 50 * sc, y: oy + (116 - 18) * sc)
            }
        }
    }
}
