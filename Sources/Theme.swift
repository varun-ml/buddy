import AppKit
import SwiftUI

// MARK: card


// MARK: themes: right-click → Theme. Burrow (warm, the pet's world), Glass (frosted macOS), Ink (dark, precise)

func hex(_ v: Int) -> Color { Color(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255) }

struct Theme {
    let name: String
    let fg: Color, sub: Color, accent: Color
    let solid: Color          // bubbles and anything that needs an opaque surface
    let design: Font.Design
    let radius: CGFloat
    let light: Bool
}
let themes: [String: Theme] = [
    "burrow": Theme(name: "burrow", fg: hex(0x3a2a1f), sub: hex(0x8b7363), accent: hex(0xd97757), solid: hex(0xfff8ee),
                    design: .rounded, radius: 28, light: true),
    "glass":  Theme(name: "glass", fg: hex(0x1d1d1f), sub: Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.6), accent: hex(0x007aff),
                    solid: Color(red: 246 / 255, green: 246 / 255, blue: 250 / 255), design: .default, radius: 24, light: true),
    "ink":    Theme(name: "ink", fg: hex(0xededef), sub: hex(0x6b6b73), accent: hex(0x7c7ff2), solid: hex(0x0f0f11),
                    design: .default, radius: 12, light: false),
]
/// The current theme. A global because every card view reads it; Model.themeName republishes on change.
var T = themes[UserDefaults.standard.string(forKey: "bit.theme") ?? (config["theme"] as? String ?? "ink")] ?? themes["ink"]!

// MARK: what every card shows, shaped once. A theme decides only how it looks.

let listCap = 3   // rows per list before "+ N more", so the card never scrolls

/// A session row: running, or finished in the last hour (your turn).
struct Pot: Identifiable {
    let s: Session, done: Bool
    var id: String { s.id }
    var line: String { (done ? s.prompt : s.activity) ?? "" }
    /// How long it has run, or how long ago it finished.
    var age: String { ago(Date().timeIntervalSince1970 - (done ? s.ts : s.turnStart ?? s.ts)) }
}
extension Session {
    var quietFor: String { ago(Date().timeIntervalSince1970 - ts) }
}
extension Model {
    var pots: [Pot] { working.map { Pot(s: $0, done: false) } + yourTurn.map { Pot(s: $0, done: true) } }
    var ignoredRed: [PR] { draftRed + staleRed }
    /// Goal progress as k of n; a yes/no goal counts as 0 or 1 of 1.
    func progress(_ which: String) -> (k: Int, n: Int) {
        let g = goal(which)
        return g?.n == nil ? (g?.done == true ? 1 : 0, 1) : (g!.k, max(g!.n!, 1))
    }
}
extension Stats {
    /// "+2" when you've merged more than yesterday.
    var gain: String? { yesterdayMerged.flatMap { d in merged - d > 0 ? "+\(merged - d)" : nil } }
    var podium: [(medal: String, n: Int, who: String, me: Bool)] { team.prefix(3).enumerated().map { (["🥇", "🥈", "🥉"][$0], $1.n, $1.login == me ? "you" : $1.login, $1.login == me) } }
    var rankText: String { rank.map { "#\($0)" } ?? "–" }
}

/// Frosted glass needs the real desktop behind the window, so it is an NSVisualEffectView, not a SwiftUI material.
struct Frost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover; v.blendingMode = .behindWindow; v.state = .active
        v.appearance = NSAppearance(named: .aqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
struct ThemeSurface: View {
    var radius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        switch T.name {
        case "glass": Frost().clipShape(shape).overlay(shape.fill(Color(red: 246 / 255, green: 246 / 255, blue: 250 / 255).opacity(0.58)))
        case "burrow": shape.fill(T.solid).shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        default: shape.fill(T.solid)
        }
    }
}

/// The ✕ on a stuck row: clears a session that ended without telling Buddy.
struct ClearX: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text("✕").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary).padding(.horizontal, 8).frame(maxHeight: .infinity) }
            .buttonStyle(.plain).help("Clear this session")
    }
}

struct Chip: View {
    var label: String
    var primary = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 10.5, weight: .semibold, design: T.design)).foregroundColor(primary ? .white : T.fg)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: T.radius / 2).fill(primary ? T.accent : T.fg.opacity(0.08)))
        }.buttonStyle(.plain)
    }
}

struct PRBlock: View {
    @ObservedObject var m: Model
    var pr: PR
    var body: some View {
        let d = m.details[pr.id]
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(Mood.upset.color).frame(width: 7, height: 7)
                Text(pr.short).font(.system(size: 11, weight: .bold, design: T.design))
                Text(pr.title).font(.system(size: 11, weight: .semibold, design: T.design)).lineLimit(1)
            }
            label("WHAT IT IS", pr.summary, lines: 2)
            if let why = d?.why {
                label("WHAT BROKE", why, lines: 3, color: Color(red: 1, green: 0.62, blue: 0.62))
            } else {
                label("WHAT BROKE", d == nil ? "reading the CI log…" : "✕ " + pr.failing.joined(separator: " · ✕ "), lines: 2, color: Color(red: 1, green: 0.62, blue: 0.62))
            }
            if let s = d?.session {
                Text("Last worked on in \(s.codex ? "Codex · " : "")\((s.cwd as NSString).lastPathComponent) · \(ago(Date().timeIntervalSince(s.when))) ago")
                    .font(.system(size: 9.5, design: T.design)).foregroundColor(T.sub).lineLimit(1)
            }
            HStack(spacing: 6) {
                if d?.session != nil {
                    Chip(label: "▶ Continue that session", primary: true) { m.continueSession(pr) }
                } else {
                    Chip(label: "Copy fix prompt", primary: true) { m.copy(m.fixPrompt(pr)); m.say("Fix prompt copied 📋", .calm, seconds: 4, kind: .ambient) }
                }
                Chip(label: "Open PR") { NSWorkspace.shared.open(URL(string: pr.url)!) }
                Chip(label: m.busyAction == pr.id ? "Rerunning…" : "Rerun") { m.rerunFailed(pr) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(T.fg.opacity(0.05)))
    }

    func label(_ k: String, _ v: String, lines: Int, color: Color = T.fg) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 8.5, weight: .bold, design: T.design)).kerning(0.8).foregroundColor(T.sub)
            Text(v).font(.system(size: 11, design: T.design)).foregroundColor(color).lineLimit(lines).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Card: View {
    @ObservedObject var m: Model
    var body: some View {
        Group {
            switch T.name { case "burrow": BurrowCard(m: m); case "glass": GlassCard(m: m); default: InkCard(m: m) }
        }
        .frame(width: m.cardWidth, alignment: .topLeading)
        .overlay(alignment: m.leftSide ? .trailing : .leading) { grip }
        .background(ThemeSurface(radius: T.radius))
        .clipShape(RoundedRectangle(cornerRadius: T.radius))
        .overlay(RoundedRectangle(cornerRadius: T.radius).stroke(T.name == "ink" ? Color.white.opacity(0.08) : T.name == "glass" ? Color.white.opacity(0.55) : hex(0x784f28).opacity(0.12), lineWidth: T.name == "glass" ? 0.5 : 1))
    }

    var grip: some View {
        // drag the card's outer edge to resize; screen coordinates, because the window moves under the cursor as it grows
        ZStack(alignment: .top) {
            Color.clear
            Capsule().fill(T.sub.opacity(0.45)).frame(width: 4, height: 36).padding(.top, 64)
        }
        .frame(width: 12).contentShape(Rectangle())
        .onHover { $0 ? NSCursor.resizeLeftRight.set() : NSCursor.arrow.set() }
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { _ in
                let x = NSEvent.mouseLocation.x
                if m.gripFrom == nil { m.gripFrom = (x, m.cardWidth) }
                let dx = (x - m.gripFrom!.mouse) * (m.leftSide ? 1 : -1)
                m.cardWidth = min(max(m.gripFrom!.width + dx, 300), 900)
                m.onExpandChange?()
            }
            .onEnded { _ in m.gripFrom = nil })
        .help("Drag to resize")
    }
}








/// Shared by Glass and Ink: hover state, the short tick animation, and the todo list paging.
final class CardUI: ObservableObject {
    @Published var hover: String?
    @Published var ticking: Set<String> = []
    @Published var showAll = false
    @Published var allPots = false
    func tick(_ t: Todo, _ m: Model) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { _ = ticking.insert(t.id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.ticking.remove(t.id); m.tick(t) }
    }
}
func areaColor(_ a: String?) -> Color { a == "work" ? hex(0x5c9efa) : a == "career" ? hex(0xa78bfa) : hex(0xe38c5c) }
func dueDays(_ d: Date) -> Int { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: d).day ?? 0 }
func stopLeft(_ m: Model) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: Date()), mins = c.hour! * 60 + c.minute!
    let stop = minutes(m.life?.stop ?? config["stop"] as? String) ?? 20 * 60, left = stop - mins
    return left > 0 ? "\(left / 60)h \(left % 60)m till \(stop / 60):\(String(format: "%02d", stop % 60))" : "evening"
}
func ringView(_ size: CGFloat, _ sw: CGFloat, _ k: Double, _ n: Double, _ color: Color, _ track: Color) -> some View {
    ZStack {
        Circle().stroke(track, lineWidth: sw)
        Circle().trim(from: 0, to: n > 0 ? min(1, k / n) : 0).stroke(color, style: StrokeStyle(lineWidth: sw, lineCap: .round)).rotationEffect(.degrees(-90))
    }.frame(width: size - sw, height: size - sw).frame(width: size, height: size).animation(.spring(response: 0.6), value: k)
}
/// Quotes and questions, rotating every 8 s; ‹ › to go back through everything Buddy has said. Drawn in each theme's own look.
struct Carousel: View {
    @ObservedObject var m: Model
    @State private var index = 0
    @State private var paused = false

    var body: some View {
        let items = m.history
        if !m.tight, let b = items.isEmpty ? nil : items[min(index, items.count - 1)] {
            let quote = b.kind == .quote
            let (ink, sub, accent): (Color, Color, Color) = T.name == "burrow" ? (bInk, bSub, bClay) : T.name == "glass" ? (gInk, gSub, gBlue) : (kInk, kSub, kIndigo)
            VStack(alignment: .leading, spacing: 7) {
                Text(quote ? "“\(b.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“” ")))”" : b.text)
                    .font(T.name == "burrow" ? .system(size: 13.5, weight: .semibold, design: .rounded)
                          : T.name == "glass" ? .system(size: 13.5, weight: .medium) : .system(size: 14, design: .serif).italic())
                    .foregroundColor(ink).lineSpacing(1.5).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).id(b.id).transition(.opacity)
                HStack(spacing: 6) {
                    if let f = m.flash { Text(f).foregroundColor(Mood.happy.color) }
                    else if let by = b.byline { Text(by).foregroundColor(T.name == "burrow" ? accent : sub) }
                    Spacer(minLength: 4)
                    icon("chevron.left", sub) { step(+1) }
                    icon("chevron.right", sub) { step(-1) }
                    icon("doc.on.doc", sub) { m.copyBubble(b) }
                    icon(m.favorites.contains(b.text) ? "heart.fill" : "heart", m.favorites.contains(b.text) ? hex(0xe0556b) : sub) { m.toggleFavorite(b) }
                }
                .font(T.name == "ink" ? .system(size: 11, design: .monospaced) : .system(size: 11.5, weight: .semibold, design: T.design)).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Group {
                switch T.name {
                case "burrow": RoundedRectangle(cornerRadius: 18).fill(Color.white).shadow(color: bShadow.opacity(0.06), radius: 1, y: 2)
                case "glass": RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.55))
                default: RoundedRectangle(cornerRadius: 8).fill(hex(0x141418)).overlay(RoundedRectangle(cornerRadius: 8).stroke(hex(0x1f1f23), lineWidth: 1))
                }
            })
            .onHover { paused = $0 }
            .onChange(of: m.rotateTick) { _ in if !paused { step(-1) } }
        }
    }

    func icon(_ name: String, _ c: Color, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: name).font(.system(size: 10, weight: .semibold)).foregroundColor(c).frame(width: 22, height: 22)
                .background(Circle().fill(T.name == "burrow" ? bChip : T.name == "glass" ? gFill.opacity(0.14) : hex(0x1c1c21)))
        }.buttonStyle(.plain)
    }

    /// +1 = older, -1 = newer. Past the newest end, pull in a fresh quote.
    func step(_ d: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            let next = index + d
            if next < 0 { m.anotherQuote(); index = 0 }
            else { index = min(next, max(m.history.count - 1, 0)) }
        }
    }
}
