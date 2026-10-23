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
                            if !m.privacy { Chip(label: "More") { m.bubble = nil; m.showCard = true; m.onExpandChange?() } }
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
        Group {
            if m.showCard && m.cardBeside {
                // too little room above Buddy: the card stands beside it, on the side away from the screen edge, as tall as the
                // screen allows. The pet keeps its spot: the window may reach below it, so the pet is lifted by petLift.
                HStack(alignment: .bottom, spacing: 6) {
                    if m.cardOnLeft { card; pet.padding(.bottom, m.petLift) } else { pet.padding(.bottom, m.petLift); card }
                }
            } else {
                VStack(alignment: (m.showCard ? !m.cardOnLeft : m.leftSide) ? .leading : .trailing, spacing: 6) {
                    Spacer(minLength: 0)
                    if m.showCard {
                        card
                    } else if let b = m.bubble, !m.squatting, m.carry == .none {
                        BubbleView(bubble: b, leftSide: m.leftSide, m: m)
                            .onHover { m.holdBubble($0) }
                            .onTapGesture { if b.kind != .quote && b.kind != .thought { b.action?(); m.bubble = nil; m.onExpandChange?() } }
                    }
                    pet
                }
            }
        }
        .padding(m.carry == .none ? EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)   // held: the pet sits at carryBox in the bigger window
                 : EdgeInsets(top: 0, leading: carryBox.x, bottom: carryBox.y, trailing: carrySize.width - carryBox.x - 84))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: (m.showCard ? !m.cardOnLeft : m.leftSide) ? .bottomLeading : .bottomTrailing)   // the pet stays on its edge of the window
    }

    /// The card: measured at full height (CardHeight), scrolling only if even the whole screen is too short for it.
    var card: some View {
        ScrollView(showsIndicators: false) {
            Card(m: m).fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { g in Color.clear.preference(key: CardHeight.self, value: g.size.height) })
        }
        .frame(maxHeight: m.cardHeight > 0 ? m.cardHeight : nil)
        .overlay(alignment: m.cardOnLeft ? .topLeading : .topTrailing) {
            // close the card now; bubbles held back while it was open come straight through. Hover opens it again.
            Button { m.closeCard(); m.sayNext() } label: {
                Image(systemName: "minus").font(.system(size: 9, weight: .bold)).foregroundColor(T.fg)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(T.solid))
                    .overlay(Circle().stroke(T.sub.opacity(0.4), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).help("Close the card")
            .offset(x: m.cardOnLeft ? -6 : 6, y: -6)   // on the corner away from the resize grip
        }
        .onPreferenceChange(CardHeight.self) { h in
            if abs(h - m.cardHeight) > 1 { m.cardHeight = h; m.onExpandChange?() }
            if CommandLine.arguments.contains("--card") { FileHandle.standardError.write("card height \(Int(h))\n".data(using: .utf8)!) }
        }
        .onHover { cardHover = $0; settle() }
    }

    /// Bit, with its hover, menu and clicks.
    var pet: some View {
    Group { if m.dancing && m.carry == .none { DanceView(m: m) } else { Cat(m: m) } }
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
            if h { petTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { _ in if m.carry == .none { m.hearts += 1 } } }   // a pat, not a lift
        }
        .contextMenu {
            // pet actions (docs/pet-actions-prd.md): the pet's verb, then what it means
            Button(m.stayPut ? "🐾 Walkies · roam again" : "🪑 Sit · stay in one spot") { m.toggleStayPut() }
            if m.breathing || m.snoozed { Button(m.breathing ? "End the break" : "☀️ Wake up") { m.toggleSnooze() } }
            else { Menu("💤 Nap · quiet for a while") {
                Button("30 minutes") { m.nap(30) }; Button("1 hour") { m.nap(60) }; Button("Until I wake it") { m.nap(nil) }
            } }
            Menu("🏠 Den · off the screen") {
                Button("30 minutes") { m.goToDen(30) }; Button("1 hour") { m.goToDen(60) }; Button("2 hours") { m.goToDen(120) }
            }
            Button((m.relaxing ? "✓ " : "") + "🌿 Lazy day · calm until midnight") { m.toggleRelax() }
            Button((m.privacy ? "✓ " : "") + "🔒 Privacy mode") { m.togglePrivacy() }
            if m.relaxing && !m.breathing { Button("Breathe for 2 minutes") { m.startBreak() } }
            Divider()
            Button("🎲 Shuffle buddy") { m.shuffle() }
            Menu("Look") {
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
                Menu("Walk") {
                    ForEach([("bottom", "Along the bottom"), ("side", "Up and down the side")], id: \.0) { w in
                        Button((m.walk == w.0 ? "✓ " : "    ") + w.1) { m.setWalk(w.0) }
                    }
                }
                Menu("Theme") {
                    ForEach(["burrow", "glass", "ink"], id: \.self) { n in
                        Button((m.themeName == n ? "✓ " : "    ") + n.capitalized) { m.setTheme(n) }
                    }
                }
            }
            Menu("Personal") {
                Button("Set goals…") { DispatchQueue.main.async { m.setGoals() } }
                Button("Add task…") { DispatchQueue.main.async { m.addTask() } }
                Button("Open task list") { openText(tasksPath) }
                Divider()
                Button("Tell Buddy…") { DispatchQueue.main.async { m.tellBuddy() } }
                Button((m.trackingSwitches ? "✓ " : "") + "Track app switching") { m.toggleSwitchTracking() }
                if m.googleSignedIn { Button("Sign out of Google Tasks") { m.signOutGoogle() } } else { Button("Connect Google Tasks…") { DispatchQueue.main.async { m.connectGoogle() } } }
                if !m.googleSignedIn && m.googleHasClient { Button("Forget my Google client") { m.signOutGoogle() } }
                Button(m.life == nil ? "Set up my profile…" : "Update my profile…") { DispatchQueue.main.async { onboard(m) } }
            }
            if config["phone"] as? Bool == true { Button("📱 Pair phone…") { pairPhone() } }
            Divider()
            if let v = m.updateTo { Button("⬆️ Update Buddy to \(v)") { m.update() } }
            Button("Close Buddy") { NSApp.terminate(nil) }   // exit 0: launchd leaves it closed until next login
        }
        .gesture(DragGesture(minimumDistance: 4).onChanged { _ in m.onCarry?(true) }.onEnded { _ in m.onCarry?(false) })
        .onTapGesture(count: 2) { m.nextBreed() }
        .onTapGesture { m.doGesture() }
        .help("Hover for what needs you · click for a trick · double-click for a new breed · drag to move")
    }

    func settle() {
        if cardHover || (catHover && m.showCard) { return }
        if catHover {
            // dwell: a cat walking under a resting cursor must not pop the card open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard catHover, !m.showCard, !m.privacy, m.carry == .none else { return }   // privacy mode: the card stays closed
                m.bubble = nil; m.pose = .none; m.tab = "work"; m.showCard = true; m.onExpandChange?()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !catHover && !cardHover && m.showCard && !mouseInPet() { m.closeCard() }
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
    var sideTarget: CGPoint?                     // the next spot up or down the side edge ("walk": "side")
    var litter: Panel!
    var flightFloor: CGFloat?                    // the hero's floor while it flies (Costume.swift)
    var heroLater: (Gesture, Date)?               // a flight that waits for a bubble or the card to close
    var homeY: CGFloat = 0
    var petSpot: NSPoint?   // where the pet stands while the card is open (the window may then reach below or beside it)
    var placed: NSRect?     // the frame resize() last set: if the window moved since (a drag), the pet moved with it
    var cardRect: NSRect?   // the card's own rectangle on screen while it stands beside the pet
    var hold: Hold?         // Buddy is held, falling or landing (Carry.swift)
    /// Dragged with the card open: the pet went along, so its remembered spot moves by the same amount.
    func followDrag() {
        guard let sp = petSpot, let pl = placed, panel.frame.origin != pl.origin else { return }
        petSpot = NSPoint(x: sp.x + panel.frame.minX - pl.minX, y: sp.y + panel.frame.minY - pl.minY)
        cardRect = cardRect.map { $0.offsetBy(dx: panel.frame.minX - pl.minX, dy: panel.frame.minY - pl.minY) }
        placed = panel.frame
    }
    /// The pet's own 100×108 rectangle on screen, wherever the card is.
    var petFrame: NSRect {
        let f = panel.frame
        if let s = petSpot { return NSRect(origin: s, size: small) }
        return NSRect(x: model.leftSide ? f.minX : f.maxX - small.width, y: f.minY, width: small.width, height: small.height)
    }
    var squatHoldUntil = Date.distantPast
    var forcedSquat = CommandLine.arguments.contains("--squat-now")          // the floor Bit walks on, restored after squatting

    var screen: NSRect { (panel.screen ?? NSScreen.main!).visibleFrame }

    func applicationDidFinishLaunching(_ n: Notification) {
        model.watchSwitches()
        MainActor.assumeIsolated { model.exportAvatars() }
        NSApp.setActivationPolicy(.accessory)
        let s = NSScreen.main!.visibleFrame
        panel = Panel(contentRect: NSRect(x: s.maxX - small.width - 12, y: s.minY + 110, width: small.width, height: small.height),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false   // Buddy moves by being picked up (Carry.swift)
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
            let b = self.petBox   // also right while carried
            return CGPoint(x: b.midX, y: b.midY)
        }
        mouseInPet = { [weak self] in
            guard let self = self else { return false }
            // the pet, or the card itself: not the window's empty corner above the pet when the card stands beside it
            let at = NSEvent.mouseLocation
            return self.petFrame.contains(at) || (self.model.showCard && (self.cardRect ?? self.panel.frame).contains(at))
        }
        model.onExpandChange = { [weak self] in self?.resize() }
        model.onCarry = { [weak self] in self?.carry($0) }
        model.loadSessions()
        model.loadPRs()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.model.loadSessions() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.model.checkForUpdate() }   // a new release? (Update.swift)
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.model.checkForUpdate() }
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
        Timer.scheduledTimer(withTimeInterval: 1 / walkHz, repeats: true) { [weak self] _ in self?.wander() }
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
        guard n > 0, !model.squatting, !model.showCard else { if litter.isVisible { litter.orderOut(nil) }; return }   // the open card lists them
        let w = CGFloat(n) * 36 + 8, f = petFrame
        let catX = f.minX + 8
        let x = catX - w >= screen.minX ? catX - w : catX + 84   // the side with room
        let want = NSRect(x: max(screen.minX, min(x, screen.maxX - w)), y: f.minY + 4, width: w, height: 50)
        if litter.frame != want { litter.setFrame(want, display: true) }   // runs 30×/s; touch the window only when it moves
        if !litter.isVisible { litter.orderFrontRegardless() }
    }

    /// Squatter: after 5 idle minutes, sleep on top of the front window. Jump down, annoyed, when you're back.
    func squatter() {
        let m = model
        if hold != nil { return }
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
        guard forced || idle > after, !m.expanded, !m.snoozed, !m.stayPut,
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
    var denShownAt: Date?   // when Buddy said where it was going, so the line shows a moment before it leaves

    func wander() {
        let m = model
        // walkHz while moving; ~2 Hz otherwise
        tick += 1
        if hold != nil { return }   // held, falling or landing: the carry moves the window (Carry.swift)
        // the den: say where it's going, fade out, stay hidden; back on screen when the time is up or `buddy back`
        if m.inDen {
            if denShownAt == nil { denShownAt = Date() }
            if panel.isVisible && panel.alphaValue > 0.99 && Date().timeIntervalSince(denShownAt!) > 3 {
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.6; panel.animator().alphaValue = 0 }) { [weak self] in
                    if self?.model.inDen == true { self?.panel.orderOut(nil) }
                }
            }
            return
        }
        if denShownAt != nil || !panel.isVisible { denShownAt = nil; panel.alphaValue = 1; panel.orderFrontRegardless() }
        if heroFlight() { return }
        let moving = m.walking || m.zoomies || target != nil
        if !moving && tick % 8 != 0 { return }
        placeLitter()
        if m.squatting { return }
        // never lose Buddy: if the window ended up mostly off every screen (or behind the menu bar), put it back on the floor
        if !mostlyVisible(panel.frame, on: NSScreen.screens.map(\.visibleFrame)) {
            let v = NSScreen.main!.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - panel.frame.width - 12, y: v.minY + 110))
        }
        followDrag()
        homeY = petFrame.minY   // follow wherever you dragged Buddy
        let idle = !m.expanded && !m.hovering && m.gesture == .none && m.mood != .asleep
        if idle && !m.stayPut && tick % 8 == 0 && Int.random(in: 0..<180) == 0 { m.doGesture() }   // ~every 90 s at 2 Hz   // a trick every ~90 s on average
        if m.zoomies && !m.stayPut {
            var f = panel.frame
            if m.walk == "side" {   // dash to the far end of the edge and back
                let (low, high) = sideRange(in: screen, size: small)
                if target == nil || abs((target ?? 0) - f.minY) < 8 || !(low...high).contains(target!) {   // a target left from walking the floor is an x
                    target = f.midY < (low + high) / 2 + small.height / 2 ? high : low
                }
                let dy = target! - f.minY
                if !m.walking { m.walking = true }
                f.origin.y += dy > 0 ? min(9 * stepScale, dy) : max(-9 * stepScale, dy)
                panel.setFrameOrigin(f.origin)
                return
            }
            if target == nil || abs((target ?? 0) - f.minX) < 8 {
                target = f.midX < screen.midX ? screen.maxX - small.width - 10 : screen.minX + 10
            }
            let dx = target! - f.minX
            if !m.walking { m.walking = true }
            if m.facingLeft != (dx < 0) { m.facingLeft = dx < 0 }
            f.origin.x += dx > 0 ? min(9 * stepScale, dx) : max(-9 * stepScale, dx)
            panel.setFrameOrigin(f.origin)
            return
        }
        let quiet = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let canWalk = shouldWalk(expanded: m.expanded, hovering: m.hovering, snoozed: m.snoozed, idle: quiet, stayPut: m.stayPut)
        guard canWalk else { if m.walking { m.walking = false }; target = nil; sideTarget = nil; return }
        var f = panel.frame
        let pace: CGFloat = m.relaxing ? 0.7 : wearing == "diwali" && evening ? 0.9 : 1.3   // an amble in relax mode; careful steps with a lit diya
        if m.walk == "side" {
            if sideTarget == nil { sideTarget = strollTarget(side: true, from: f, in: screen, size: small, roll: .random(in: 0...1)) }
            let t = sideTarget!, dx = t.x - f.minX, dy = t.y - f.minY, d = hypot(dx, dy)
            if d < 2 { sideTarget = nil; return }
            if !m.walking { m.walking = true }
            let facing = abs(dx) >= 2 ? dx < 0 : f.midX > screen.midX   // on the edge: face into the screen
            if m.facingLeft != facing { m.facingLeft = facing }
            let k = min(1, pace * stepScale / d)
            f.origin.x += dx * k; f.origin.y += dy * k
            if m.relaxing && Int.random(in: 0..<300) == 0 { m.leaves += 1 }
            panel.setFrameOrigin(f.origin)
            return
        }
        if target == nil {
            target = CGFloat.random(in: (screen.minX + 10)...(screen.maxX - small.width - 10))
        }
        guard let t = target else { return }
        let dx = t - f.minX
        if abs(dx) < 2 { target = nil; return }   // straight on to the next spot, no standing around
        if !m.walking { m.walking = true }
        if m.facingLeft != (dx < 0) { m.facingLeft = dx < 0 }
        if m.relaxing && Int.random(in: 0..<300) == 0 { m.leaves += 1 }   // ~every 20 s of walking, a leaf drifts past
        f.origin.x += dx > 0 ? min(pace * stepScale, dx) : max(-pace * stepScale, dx)
        panel.setFrameOrigin(f.origin)
    }

    /// Grow the window away from the nearer screen edge, keeping the cat where it is. The card opens above Buddy when it fits,
    /// otherwise beside it (never over it, never with blocks dropped). `petSpot` remembers where the pet stood while the card is open.
    func resize() {
        if hold != nil { return }   // the carry sizes the window until Buddy is put down
        followDrag()
        let f = panel.frame
        let spot = petSpot ?? NSPoint(x: model.leftSide || f.width <= small.width + 1 ? f.minX : f.maxX - small.width, y: f.minY)
        if f.width <= small.width + 1 { model.leftSide = f.midX < screen.midX }
        guard model.showCard && !model.squatting else {
            petSpot = nil; placed = nil; cardRect = nil
            if model.cardBeside { model.cardBeside = false; model.petLift = 0 }
            let size = model.expanded && !model.squatting ? big : small
            panel.setFrame(NSRect(x: model.leftSide ? spot.x : spot.x + small.width - size.width, y: spot.y, width: size.width, height: size.height), display: true, animate: false)
            return
        }
        petSpot = spot
        let card = model.cardHeight > 0 ? model.cardHeight : big.height - small.height, width = max(big.width, model.cardWidth + 30)
        let p = cardPlacement(card: card, cardWidth: width, pet: NSRect(origin: spot, size: small), leftSide: model.leftSide, in: screen)
        if model.cardBeside != p.beside { model.cardBeside = p.beside }
        if model.cardOnLeft != p.cardOnLeft { model.cardOnLeft = p.cardOnLeft }
        if abs(model.petLift - p.lift) > 1 { model.petLift = p.lift }
        panel.setFrame(p.frame, display: true, animate: false); placed = p.frame; cardRect = p.beside ? p.card : nil
    }
}

/// Where the open card goes. Above the pet when the whole card fits there; otherwise beside it, on the side away from the
/// screen edge, as tall as the screen allows and reaching below the pet if it must (`lift` raises the pet back to its spot).
/// The pet's rectangle never changes and the card never covers it. Selftested.
func cardPlacement(card: CGFloat, cardWidth: CGFloat, pet: NSRect, leftSide: Bool, in s: NSRect)
    -> (frame: NSRect, beside: Bool, lift: CGFloat, cardOnLeft: Bool, card: NSRect) {
    let above = card + pet.height + 22   // the card, the stack spacing, the pet, the outer padding
    let w = cardWidth + 6 + pet.width
    let fitsLeft = pet.maxX - w >= s.minX, fitsRight = pet.minX + w <= s.maxX
    if pet.minY + above <= s.maxY || !(fitsLeft || fitsRight) {   // fits above, or no room beside either: above, scrolling if it must
        // ponytail: a card wider than the room on both sides of a mid-screen pet still runs off; only past ~780 pt wide on a laptop
        let rightOK = pet.minX + cardWidth <= s.maxX, leftOK = pet.maxX - cardWidth >= s.minX
        let onLeft = leftOK && rightOK ? !leftSide : leftOK || !rightOK && pet.midX > s.midX
        let f = NSRect(x: onLeft ? pet.maxX - cardWidth : pet.minX, y: pet.minY, width: cardWidth, height: min(above, s.maxY - pet.minY))
        return (f, false, 0, onLeft, f)
    }
    let h = min(card + 16, s.height)                      // the card plus the outer padding, at most the whole screen
    let y = max(s.minY, min(pet.minY, s.maxY - h))         // as low as it must go, never off the screen
    let lift = pet.minY - y
    let onLeft = fitsLeft && fitsRight ? !leftSide : fitsLeft   // away from the near screen edge, or the side it fits on
    let x = onLeft ? pet.maxX - w : pet.minX
    let f = NSRect(x: x, y: y, width: w, height: max(h, lift + pet.height))
    let c = NSRect(x: onLeft ? x : x + pet.width, y: y, width: w - pet.width, height: h)   // the window minus the pet's column
    return (f, true, lift, onLeft, c)
}

/// How high up the side edge Buddy strolls: from just above the bottom to low enough that the card,
/// which opens above Buddy, still has room for its main blocks.
func sideRange(in s: NSRect, size: NSSize) -> (low: CGFloat, high: CGFloat) {
    let low = s.minY + 10
    return (low, max(low, s.maxY - size.height - 360))
}

/// Where to stroll next, `roll` in 0…1. Along the bottom: anywhere across, at the current height.
/// Up and down the side: on the nearer side edge, anywhere in `sideRange`. Selftested.
func strollTarget(side: Bool, from f: NSRect, in s: NSRect, size: NSSize, roll: CGFloat) -> CGPoint {
    guard side else { return CGPoint(x: s.minX + 10 + roll * (s.width - size.width - 20), y: f.minY) }
    let (low, high) = sideRange(in: s, size: size)
    return CGPoint(x: f.midX < s.midX ? s.minX + 10 : s.maxX - size.width - 10, y: low + roll * (high - low))
}

/// Always on the move while you're at the desk. Stands still only under your cursor, with the card open, napping,
/// told to stay in place, or when nobody has touched the mouse or keyboard for 2 min (you're away; it saves the battery). Selftested.
/// At least half of Buddy is inside one screen's usable area. A sliver peeking out below the menu bar does not count.
func mostlyVisible(_ f: NSRect, on screens: [NSRect]) -> Bool {
    screens.contains { let i = $0.intersection(f); return i.width >= f.width / 2 && i.height >= f.height / 2 }
}

func shouldWalk(expanded: Bool, hovering: Bool, snoozed: Bool, idle: Double, stayPut: Bool = false) -> Bool {
    !expanded && !hovering && !snoozed && !stayPut && idle <= 120
}
