import AppKit
import SwiftUI

struct BubbleView: View {
    var bubble: Bubble
    var leftSide: Bool
    @ObservedObject var m: Model
    var body: some View {
        // Events get their mood colour; Bit's own chatter gets a neutral border so it never reads as an alert.
        let border = bubble.kind == .event ? bubble.tone.color : T.fg.opacity(0.25)
        let radius: CGFloat = bubble.kind == .thought ? 20 : 12
        VStack(alignment: leftSide ? .leading : .trailing, spacing: 3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(bubble.text)
                    .font(.system(size: 12.5, weight: bubble.kind == .quote ? .regular : .medium, design: bubble.kind == .quote ? .serif : .rounded))
                    .italic(bubble.kind == .quote)
                    .foregroundColor(T.fg)
                    .lineLimit(9)
                    .fixedSize(horizontal: false, vertical: true)
                if let r = bubble.react {
                    HStack(spacing: 5) {
                        Chip(label: "👍 Nice") { r(true); m.bubble = nil; m.onExpandChange?() }
                        Chip(label: "👎 Not for me") { r(false); m.bubble = nil; m.onExpandChange?() }
                    }.padding(.top, 2)
                }
                if let b = bubble.byline {
                    Text(b).font(.system(size: 10.5, weight: .semibold, design: T.design)).foregroundColor(T.sub)
                }
                if bubble.kind == .quote || bubble.kind == .thought {
                    HStack(spacing: 5) {
                        Chip(label: "Copy") { m.copyBubble(bubble) }
                        Chip(label: m.favorites.contains(bubble.text) ? "♥ Saved" : "♡ Save") { m.toggleFavorite(bubble) }
                        if bubble.text.contains("Write it down once?"), let rule = m.scoldRule {
                            Chip(label: "Copy rule", primary: true) { m.copy(rule); m.flash = "Rule copied 📋" }
                        } else {
                            Chip(label: "More") { m.bubble = nil; m.showCard = true; m.onExpandChange?() }
                        }
                        if let f = m.flash { Text(f).font(.system(size: 10, weight: .semibold, design: T.design)).foregroundColor(Mood.happy.color) }
                    }.padding(.top, 2)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: radius).fill(T.solid))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(border, lineWidth: 1.5))
            if bubble.kind == .thought {
                // thought-cloud tail: two little circles stepping down to the cat
                HStack(spacing: 0) {
                    Circle().fill(T.solid).overlay(Circle().stroke(border, lineWidth: 1.2)).frame(width: 9, height: 9)
                }.padding(.horizontal, 22)
                Circle().fill(T.solid).overlay(Circle().stroke(border, lineWidth: 1)).frame(width: 5, height: 5).padding(.horizontal, 30)
            }
        }
        .frame(maxWidth: 270, alignment: leftSide ? .leading : .trailing)
    }
}

/// One tiny kitten per Claude session waiting for your OK. Asleep after 10 minutes of waiting.
struct LitterView: View {
    @ObservedObject var m: Model
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(m.waiting.enumerated()), id: \.element.id) { i, s in
                Kitten(breed: breeds[(i + 2) % breeds.count], asleep: Date().timeIntervalSince1970 - s.ts > 600, agent: s.agent)
                    .help("\(s.repo ?? "A session") is waiting for your OK · \(ago(Date().timeIntervalSince1970 - s.ts))\n\(s.activity ?? "")\nclick to go to Claude")
                    .onTapGesture { activate(s) }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}

struct Kitten: View {
    var breed: Breed
    var asleep: Bool
    var agent = agents.last!
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10)) { t in
            let s = (frozenTime ?? t.date.timeIntervalSinceReferenceDate)
            ZStack {
                if !petKind.biped { Ellipse().fill(breed.fur).frame(width: 26, height: 15).position(x: 15, y: 33) }
                if petKind.biped { avatarKitten(breed) } else {
                    kittenEars(breed)
                    Circle().fill(breed.fur).frame(width: 20, height: 19).position(x: 15, y: 17)
                    kittenFace(breed)
                }
                if !agent.mark.isEmpty {
                    Text(agent.mark).font(.system(size: 7, weight: .black, design: .rounded)).foregroundColor(.white)
                        .frame(width: 10, height: 10).background(Circle().fill(agent.color)).position(x: 15, y: 29)
                }
                if asleep {
                    HStack(spacing: 5) { Capsule().frame(width: 4, height: 1.2); Capsule().frame(width: 4, height: 1.2) }
                        .foregroundColor(ink.opacity(0.7)).position(x: 15, y: 17)
                    Text("z").font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundColor(.white).position(x: 27, y: 4 - CGFloat(Int(s) % 2) * 2)
                } else {
                    HStack(spacing: 5) { Circle().fill(breed.eye == ink ? ink : breed.eye).frame(width: 4); Circle().fill(breed.eye == ink ? ink : breed.eye).frame(width: 4) }
                        .position(x: 15, y: 16)
                    Text("?").font(.system(size: 9, weight: .black, design: .rounded)).foregroundColor(ink)
                        .frame(width: 11, height: 11).background(Circle().fill(Mood.waiting.color))
                        .position(x: 27, y: 3 + sin(s * 5) * 1.5)
                }
            }
            .frame(width: 30, height: 42)
            .shadow(color: .black.opacity(0.4), radius: 0.8)
            .rotationEffect(.degrees(asleep ? 0 : sin(s * 3) * 4), anchor: .bottom)
        }
        .frame(width: 30, height: 42)
    }
}


/// The celebration clip, 15 fps, mirrored to face the way Buddy walks.
struct DanceView: View {
    @ObservedObject var m: Model
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { t in
            let i = min(danceFrames.count - 1, max(0, Int((t.date.timeIntervalSince(m.dancingUntil) + Double(danceFrames.count) / 15) * 15)))
            Image(nsImage: danceFrames[i]).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 84, height: 92).offset(y: -10)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        }
        .frame(width: 84, height: 72)
    }
}



struct CardHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PetView: View {
    @ObservedObject var m: Model
    @State private var catHover = false
    @State private var cardHover = false
    @State private var petTimer: Timer?

    var body: some View {
        VStack(alignment: m.leftSide ? .leading : .trailing, spacing: 6) {
            Spacer(minLength: 0)
            if m.showCard {
                ScrollView(showsIndicators: false) {
                    Card(m: m).fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { g in Color.clear.preference(key: CardHeight.self, value: g.size.height) })
                }
                .frame(maxHeight: m.cardHeight > 0 ? m.cardHeight : nil)
                .onPreferenceChange(CardHeight.self) { h in
                    if abs(h - m.cardHeight) > 1 { m.cardHeight = h; m.onExpandChange?() }
                    if CommandLine.arguments.contains("--card") { FileHandle.standardError.write("card height \(Int(h))\n".data(using: .utf8)!) }
                }
                .onHover { cardHover = $0; settle() }
            } else if let b = m.bubble, !m.squatting {
                BubbleView(bubble: b, leftSide: m.leftSide, m: m)
                    .onHover { m.holdBubble($0) }
                    .onTapGesture { if b.kind != .quote && b.kind != .thought { b.action?(); m.bubble = nil; m.onExpandChange?() } }
            }
            Group { if m.dancing { DanceView(m: m) } else { Cat(m: m) } }
                .padding(.top, 20)
                .overlay(alignment: .top) {   // CI weather: rain while a PR is red, sun after a merge
                    if m.sunUntil > Date() { Text("☀️").font(.system(size: 18)) }
                    else if !m.needsYouPRs.isEmpty { Text("🌧️").font(.system(size: 18)).help("\(m.needsYouPRs.count) red PR") }
                }
                .contentShape(Rectangle())
                .onHover { h in
                    catHover = h
                    m.hovering = h
                    settle()
                    petTimer?.invalidate()
                    if h { petTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in m.hearts += 1 } }
                }
                .contextMenu {
                    Button(m.snoozed ? "Wake up" : "Nap 1h") { m.toggleSnooze() }
                    Divider()
                    Menu("Theme") {
                        ForEach(["burrow", "glass", "ink"], id: \.self) { n in
                            Button((m.themeName == n ? "✓ " : "    ") + n.capitalized) { m.setTheme(n) }
                        }
                    }
                    Button("🎲 Shuffle buddy") { m.shuffle() }
                    Menu("Buddy") {
                        ForEach(pets.map(\.name) + ["random"], id: \.self) { n in
                            Button((petChoice == n ? "✓ " : "    ") + n.capitalized) { m.setPet(n) }
                        }
                    }
                    Menu("Costume") {
                        ForEach(costumes, id: \.0) { c in
                            Button(((costume ?? "none") == c.0 ? "✓ " : "    ") + c.1) { m.setCostume(c.0) }
                        }
                    }
                    Button("Set goals…") { DispatchQueue.main.async { m.setGoals() } }
                    Button("Tell Buddy…") { DispatchQueue.main.async { m.tellBuddy() } }
                    Button("Add task…") { DispatchQueue.main.async { m.addTask() } }
                    Button("Open task list") { openText(tasksPath) }
                    Divider()
                    Button(m.life == nil ? "Set up my profile…" : "Update my profile…") { DispatchQueue.main.async { onboard(m) } }
                    if m.life != nil { Button("Edit profile file") { openText(lifePath) } }
                    Divider()
                    Button("Close Buddy") { NSApp.terminate(nil) }   // exit 0: launchd leaves it closed until next login
                }
                .onTapGesture(count: 2) { m.nextBreed() }
                .onTapGesture { m.doGesture() }
                .help("Hover for what needs you · click for a trick · double-click for a new breed · drag to move")
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: m.leftSide ? .bottomLeading : .bottomTrailing)
    }

    func settle() {
        if cardHover || (catHover && m.showCard) { return }
        if catHover {
            // dwell: a cat walking under a resting cursor must not pop the card open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard catHover, !m.showCard else { return }
                m.bubble = nil; m.pose = .none; m.tab = "work"; m.showCard = true; m.onExpandChange?()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !catHover && !cardHover && m.showCard && !mouseInPet() { m.showCard = false; m.showStale = false; m.hoverEnded(); m.onExpandChange?() }
            }
        }
    }
}

// MARK: window + wandering

final class Panel: NSPanel {
    override var canBecomeKey: Bool { false }
    /// The hero's fly-off leaves the screen; macOS would otherwise stop the window at the top edge. wander() brings Buddy back if it's ever lost.
    override func constrainFrameRect(_ r: NSRect, to screen: NSScreen?) -> NSRect { r }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var panel: Panel!
    let small = NSSize(width: 100, height: 108)
    let big = NSSize(width: 360, height: 660)
    var target: CGFloat?
    var litter: Panel!
    var flightFloor: CGFloat?                    // the hero's floor while it flies (Costume.swift)
    var heroLater: (Gesture, Date)?               // a flight that waits for a bubble or the card to close
    var homeY: CGFloat = 0
    var squatHoldUntil = Date.distantPast
    var forcedSquat = CommandLine.arguments.contains("--squat-now")          // the floor Bit walks on, restored after squatting

    var screen: NSRect { (panel.screen ?? NSScreen.main!).visibleFrame }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let s = NSScreen.main!.visibleFrame
        panel = Panel(contentRect: NSRect(x: s.maxX - small.width - 12, y: s.minY + 110, width: small.width, height: small.height),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        let host = NSHostingView(rootView: PetView(m: model))
        host.sizingOptions = []   // we size the window ourselves; SwiftUI must not grow it
        panel.contentView = host
        panel.orderFrontRegardless()
        homeY = panel.frame.minY

        litter = Panel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 50), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        litter.isOpaque = false; litter.backgroundColor = .clear; litter.hasShadow = false; litter.level = .floating
        litter.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        litter.contentView = NSHostingView(rootView: LitterView(m: model))

        blobCenter = { [weak self] in
            guard let self = self else { return .zero }
            let f = self.panel.frame
            let x = self.model.leftSide && self.model.expanded ? f.minX + 8 + 42 : f.maxX - 8 - 42
            return CGPoint(x: x, y: f.minY + 8 + 36)
        }
        mouseInPet = { [weak self] in
            guard let self = self else { return false }
            // the card's own rectangle: the window minus its transparent margin above the card
            return self.panel.frame.contains(NSEvent.mouseLocation)
        }
        model.onExpandChange = { [weak self] in self?.resize() }
        model.loadSessions()
        model.loadPRs()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.model.loadSessions() }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.model.loadPRs() }
        model.loadStats()
        model.anotherQuote()   // so the wisdom box is never empty
        if let i = CommandLine.arguments.firstIndex(of: "--theme"), i + 1 < CommandLine.arguments.count { T = themes[CommandLine.arguments[i + 1]] ?? T; model.themeName = T.name }
        if CommandLine.arguments.contains("--personal") { model.tab = "personal" }
        if let i = CommandLine.arguments.firstIndex(of: "--costume"), i + 1 < CommandLine.arguments.count { costume = CommandLine.arguments[i + 1] }   // test: wear it without saving
        if let i = CommandLine.arguments.firstIndex(of: "--trick"), i + 1 < CommandLine.arguments.count,   // test: --trick flyOff, 6 s after launch
           let g = Gesture.allCases.first(where: { "\($0)" == CommandLine.arguments[i + 1] }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.model.bubble = nil; self.model.doGesture(g) }
        }
        if CommandLine.arguments.contains("--card") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.model.bubble = nil; self.model.showCard = true; self.model.onExpandChange?() }
        }
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.model.loadStats() }
        Timer.scheduledTimer(withTimeInterval: CommandLine.arguments.contains("--demo") ? 3 : 30, repeats: true) { [weak self] _ in self?.model.ambientTick() }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.wander() }
        // a new breed every 15 min (quietly: no bubble while something needs you or the card is open)
        Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            guard let m = self?.model, !m.snoozed else { return }
            m.nextBreed(quiet: m.hasP0 || m.expanded)
        }
        model.scanScoldings()
        model.loadLimits()
        if model.life == nil, !UserDefaults.standard.bool(forKey: "bit.onboardOffered") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let m = self?.model else { return }
                UserDefaults.standard.set(true, forKey: "bit.onboardOffered")
                m.say("Hi! I can look out for your people, goals and tasks too, not just code. Tap to set me up 💛", .calm, seconds: 30, kind: .event, sound: "Pop") { onboard(m) }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.model.loadLimits() }
        Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in if self?.model.showCard == true { self?.model.rotateTick += 1 } }
        Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.model.scanScoldings() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.squatter() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.model.dayCare() }
        model.checkDisk()
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.model.checkDisk() }
        if CommandLine.arguments.contains("--tricks") {
            Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in self?.model.doGesture() }
            Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in self?.model.nextBreed() }
        }
    }

    /// Stroll along the bottom of the screen when nothing needs you; stop and sit when something does.
    /// Keep the litter of waiting kittens just beside Bit.
    func placeLitter() {
        let n = model.waiting.count
        guard n > 0, !model.squatting else { if litter.isVisible { litter.orderOut(nil) }; return }
        let w = CGFloat(n) * 36 + 8, f = panel.frame
        let catX = model.leftSide && model.expanded ? f.minX + 8 : f.maxX - 8 - 84
        let x = catX - w >= screen.minX ? catX - w : catX + 84   // the side with room
        let want = NSRect(x: max(screen.minX, min(x, screen.maxX - w)), y: f.minY + 4, width: w, height: 50)
        if litter.frame != want { litter.setFrame(want, display: true) }   // runs 30×/s; touch the window only when it moves
        if !litter.isVisible { litter.orderFrontRegardless() }
    }

    /// Squatter: after 5 idle minutes, sleep on top of the front window. Jump down, annoyed, when you're back.
    func squatter() {
        let m = model
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if m.squatting {
            if idle < 2 && Date() > squatHoldUntil {
                m.squatting = false
                m.zoomies = false
                panel.level = .floating
                var f = panel.frame
                f.origin.y = homeY
                panel.setFrame(f, display: true, animate: true)
                m.say(["hmph. I was comfy.", "oh, you're back 😾", "fine. FINE."].randomElement()!, .calm, seconds: 4, kind: .ambient)
            }
            return
        }
        let after = CommandLine.arguments.firstIndex(of: "--squat").flatMap { Double(CommandLine.arguments[$0 + 1]) } ?? 300
        let forced = forcedSquat
        guard forced || idle > after, !m.expanded, !m.snoozed,
              let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier,
              let wins = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let full = NSScreen.screens.first?.frame,
              let win = wins.first(where: { w in
                  guard (w[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier, (w[kCGWindowLayer as String] as? Int) == 0,
                        let b = w[kCGWindowBounds as String] as? [String: CGFloat], let y = b["Y"], let h = b["Height"] else { return false }
                  return y >= 0 && y < full.height - 120 && h > 100   // title bar on screen, a real window
              }),
              let b = win[kCGWindowBounds as String] as? [String: CGFloat], let wy = b["Y"], let wx = b["X"], let ww = b["Width"],
              let screenH = NSScreen.screens.first?.frame.height else { return }
        let top = screenH - wy                       // window's top edge, in Cocoa coordinates
        var f = panel.frame
        f.origin.x = min(max(wx + ww - 150, screen.minX), screen.maxX - f.width)
        f.size = small
        f.origin.y = top - 10   // feet on the title bar; the rest may overhang the menu bar
        panel.level = .statusBar
        if forced { forcedSquat = false; squatHoldUntil = Date().addingTimeInterval(8) }
        m.squatting = true
        m.walking = false
        panel.setFrame(f, display: true, animate: true)
    }

    var tick = 0
    func wander() {
        let m = model
        // 30 Hz only while walking; 2 Hz otherwise
        tick += 1
        if heroFlight() { return }
        let moving = m.walking || m.zoomies || target != nil
        if !moving && tick % 15 != 0 { return }
        placeLitter()
        if m.squatting { return }
        // never lose Buddy: if the window ended up off every screen, put it back on the floor
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            let v = NSScreen.main!.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - panel.frame.width - 12, y: v.minY + 110))
        }
        homeY = panel.frame.minY   // follow wherever you dragged Buddy
        let idle = !m.expanded && !m.hovering && m.gesture == .none && m.mood != .asleep
        if idle && Int.random(in: 0..<180) == 0 { m.doGesture() }   // ~every 90 s at 2 Hz   // a trick every ~90 s on average
        if m.zoomies {
            var f = panel.frame
            if target == nil || abs((target ?? 0) - f.minX) < 8 {
                target = f.midX < screen.midX ? screen.maxX - small.width - 10 : screen.minX + 10
            }
            let dx = target! - f.minX
            if !m.walking { m.walking = true }
            if m.facingLeft != (dx < 0) { m.facingLeft = dx < 0 }
            f.origin.x += dx > 0 ? min(9, dx) : max(-9, dx)
            panel.setFrameOrigin(f.origin)
            return
        }
        let canWalk = !m.expanded && !m.hovering && m.mood != .asleep && m.mood != .upset && m.waiting.isEmpty   // stays put only for a real need (your OK, a red PR); a quiet session alone is often just a long task
        guard canWalk else { if m.walking { m.walking = false }; target = nil; return }
        var f = panel.frame
        if target == nil {
            guard Int.random(in: 0..<16) == 0 else { return }  // ~every 8 s at 2 Hz, decide to stroll
            target = CGFloat.random(in: (screen.minX + 10)...(screen.maxX - small.width - 10))
        }
        guard let t = target else { return }
        let dx = t - f.minX
        if abs(dx) < 2 { target = nil; m.walking = false; return }
        if !m.walking { m.walking = true }
        if m.facingLeft != (dx < 0) { m.facingLeft = dx < 0 }
        let pace: CGFloat = wearing == "diwali" && evening ? 0.9 : 1.3   // careful steps with a lit diya
        f.origin.x += dx > 0 ? min(pace, dx) : max(-pace, dx)
        panel.setFrameOrigin(f.origin)
    }

    /// Grow the window away from the nearer screen edge, keeping the cat where it is.
    func resize() {
        let f = panel.frame
        if f.width <= small.width + 1 { model.leftSide = f.midX < screen.midX }
        var size = model.expanded && !model.squatting ? big : small
        if model.showCard && !model.squatting {
            let want = (model.cardHeight > 0 ? model.cardHeight : big.height - small.height) + small.height + 22
            let room = screen.maxY - f.minY - small.height - 22
            if model.cardHeight > room && !model.tight { model.tight = true }                 // too tall: the quote goes
            else if model.tight && model.cardHeight + 140 < room { model.tight = false }       // plenty of room again (140 ≈ a quote, so no flip-flop)
            size = NSSize(width: max(big.width, model.cardWidth + 30), height: min(want, screen.maxY - f.minY))
            if CommandLine.arguments.contains("--card") { FileHandle.standardError.write("room for card \(Int(screen.maxY - f.minY - small.height - 22))\n".data(using: .utf8)!) }
        }
        let x = model.leftSide ? f.minX : f.maxX - size.width
        panel.setFrame(NSRect(x: x, y: f.minY, width: size.width, height: size.height), display: true, animate: false)
    }
}
