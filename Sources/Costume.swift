import AppKit
import SwiftUI

// MARK: costumes, drawn over whichever pet and coat you have. Right-click → Costume, or "costume" in buddy.json.
// A costume brings a look, a way of walking, and its own moves (the hero cases in `Gesture`).

/// nil = none. Read once; the right-click menu changes it through Model.setCostume.
var costume: String? = {
    let c = UserDefaults.standard.string(forKey: "bit.costume") ?? config["costume"] as? String
    return c == "none" ? nil : c
}()
var hero: Bool { costume == "hero" }
let costumes = [("none", "No costume"), ("hero", "Caped hero")]

// The caped hero: a crimson cape with a gold edge, a black domino mask, a gold star. An original hero, not any studio's.
let capeRed = hex(0xb3263b), capeGold = hex(0xe0b03a), maskInk = hex(0x16161c)

/// Hangs from the neck and streams back; `stream` 0 = hanging, 1 = flying flat out behind.
struct Cape: Shape {
    var stream: CGFloat, flutter: CGFloat
    func path(in r: CGRect) -> Path {
        Path { p in
            let f = flutter, st = stream
            p.move(to: CGPoint(x: 52, y: 30))   // tied at the neck, drapes over the back to the tail; stays inside the 84×72 box (outside it gets cut off)
            p.addQuadCurve(to: CGPoint(x: 3, y: 34 - 8 * st + f), control: CGPoint(x: 26, y: 18 - 4 * st))
            p.addQuadCurve(to: CGPoint(x: 4, y: 66 - 16 * st + f * 0.6), control: CGPoint(x: 1, y: 50 - 12 * st - f))
            p.addQuadCurve(to: CGPoint(x: 34, y: 64 - 4 * st), control: CGPoint(x: 16, y: 74 - 12 * st + f))
            p.addLine(to: CGPoint(x: 50, y: 42))
            p.closeSubpath()
        }
    }
}

extension Cat {
    /// Behind the body. Flutters a little standing, streams out while gliding or flying, flips round on a swirl.
    func cape(s: Double, moving: Bool, gt: Double) -> some View {
        let stream: CGFloat = moving ? 1 : 0.25
        let flutter = CGFloat(sin(s * (moving ? 14 : 3)) * (moving ? 3 : 1.2))
        let swirl = m.gesture == .capeSwirl && gt < 1.2 ? cos(gt / 1.2 * 2 * .pi) : 1
        return Cape(stream: stream, flutter: flutter).fill(capeRed)
            .overlay(Cape(stream: stream, flutter: flutter).stroke(capeGold, lineWidth: 1.2))
            .scaleEffect(x: swirl, y: 1, anchor: UnitPoint(x: 50 / 84, y: 0.5))
    }

    /// Over the eyes: a black band with white lenses that blink with the pet.
    func mask(blink: Bool, asleep: Bool) -> some View {
        ZStack {
            Capsule().fill(maskInk).frame(width: 32, height: 8.5).position(x: 60, y: 31)
            ForEach([53.0, 67.0], id: \.self) { x in
                Ellipse().fill(Color.white).frame(width: 7, height: blink || asleep ? 1.2 : 4.2).position(x: x, y: 31)
            }
        }
    }

    func emblem() -> some View {
        Circle().fill(capeGold).frame(width: 9, height: 9)
            .overlay(Text("★").font(.system(size: 6.5, weight: .black)).foregroundColor(capeRed))
            .position(x: 48, y: 47)
    }
}

/// Where the hero's moves put the body, for a move that began `gt` seconds ago: (lift, squash, tilt).
func heroMotion(_ g: Gesture, _ gt: Double) -> (y: CGFloat, squash: CGFloat, tilt: Double) {
    switch g {
    case .heroLanding:   // leap up out of view, slam down, hold the crouch, stand
        if gt < 0.35 { return (-64 * sin(gt / 0.35 * .pi / 2), 1, -10) }
        if gt < 0.5 { let p = (gt - 0.35) / 0.15; return (-64 * (1 - p * p), 1, 8) }
        if gt < 1.3 { return (0, 0.8, 6) }
        return (0, 1, 0)
    case .flyOff, .grapple:   // flying: lean up into the climb
        return (-4, 1, -18)
    default: return (0, 1, 0)
    }
}

func ease(_ p: Double) -> CGFloat { CGFloat((1 - cos(min(max(p, 0), 1) * .pi)) / 2) }

extension AppDelegate {
    /// The hero's flights move the whole window: off the top of the screen and back (a red PR), or up to the top edge to pose (rare).
    /// Never while a bubble or the card is open: the flight waits for them, up to 2 minutes. True while flying.
    func heroFlight() -> Bool {
        let m = model, g = m.gesture
        guard g == .flyOff || g == .grapple else {
            if let y = flightFloor { panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: y)); flightFloor = nil }
            if let (w, at) = heroLater, !m.expanded, !m.hovering, !m.squatting {
                heroLater = nil
                if Date().timeIntervalSince(at) < 120 { m.doGesture(w) }
            }
            return false
        }
        if m.expanded || m.squatting {   // something needs the window: land now, fly later
            heroLater = (g, Date()); m.gesture = .none
            if let y = flightFloor { panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: y)); flightFloor = nil }
            return false
        }
        if flightFloor == nil { flightFloor = panel.frame.minY; m.walking = false; target = nil }
        let floor = flightFloor!, gt = Date().timeIntervalSince(m.gestureAt)
        let y: CGFloat
        if g == .flyOff {   // up 0.9 s, away 2 s, back down 0.9 s
            let away = screen.maxY + 40
            y = gt < 0.9 ? floor + (away - floor) * ease(gt / 0.9) : gt < 2.9 ? away : floor + (away - floor) * (1 - ease((gt - 2.9) / 0.9))
        } else {            // up 0.7 s, pose on the top edge 4 s, glide down 1.3 s
            let top = screen.maxY - small.height
            y = gt < 0.7 ? floor + (top - floor) * ease(gt / 0.7) : gt < 4.7 ? top : floor + (top - floor) * (1 - ease((gt - 4.7) / 1.3))
        }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: max(floor, y)))
        return true
    }
}
