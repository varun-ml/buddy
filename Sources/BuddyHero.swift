import AppKit
import SwiftUI

// MARK: the caped hero: an original hero (not any studio's), cape and domino mask, who walks on two legs.
// Merges get a hero landing, red PRs a fly-off, and now and then it grapples to the top of the screen (Costume.swift).

let heroBuddy = PetKind(
    name: "hero", emoji: "🦸", hello: "🦸", coats: heroSuits,
    tricks: [.stretch, .hop, .capeSwirl, .capeSwirl, .capeSwirl, .grapple, .zoomies],
    onRed: .flyOff, onMerge: .heroLanding, biped: true,
    sceneEars: { _, _, _ in })

let heroSuits: [Breed] = [
    Breed(name: "Midnight hero", fur: hex(0x1f2a44), dark: hex(0xb3263b), belly: hex(0xf1c7a3), points: hex(0xe0b03a), mask: hex(0x16161c)),
    Breed(name: "Crimson hero", fur: hex(0xb3263b), dark: hex(0x1f2a44), belly: hex(0xc68642), points: hex(0xe0b03a), mask: hex(0x16161c)),
    Breed(name: "Emerald hero", fur: hex(0x1e7a4c), dark: hex(0x1b1b1f), belly: hex(0x8d5524), points: hex(0xdfe3e8), mask: hex(0x1b1b1f)),
    Breed(name: "Storm hero", fur: hex(0x5b6472), dark: hex(0x2563eb), belly: hex(0xe0ac69), points: hex(0xfacc15), mask: hex(0x1f2a44)),
    Breed(name: "Solar hero", fur: hex(0xe9a23b), dark: hex(0x6d28d9), belly: hex(0xffdbac), points: hex(0xb45309), mask: hex(0x3b1f0e)),
]

extension Cat {
    func heroAvatar(_ p: AvatarPose) -> some View {
        let b = p.b, swing = p.step * 22, flutter = sin(p.s * (p.flying || p.step != 0 ? 14 : 3)) * (p.flying ? 3 : 1.5)
        let swirl = p.g == .capeSwirl && p.gt < 1.2 ? cos(p.gt / 1.2 * 2 * .pi) : 1
        let landing = p.g == .heroLanding && p.gt > 0.5 && p.gt < 1.3   // fist on the ground
        return ZStack {
            // cape, behind everything: from the shoulders, streaming back; flat out when flying
            Path { c in
                let st: CGFloat = p.flying ? 1 : p.step != 0 ? 0.6 : 0.2, f = CGFloat(flutter)
                c.move(to: CGPoint(x: 42, y: 34)); c.addLine(to: CGPoint(x: 52, y: 34))
                c.addQuadCurve(to: CGPoint(x: 34 - 14 * st, y: 66 - 18 * st + f), control: CGPoint(x: 44, y: 56))
                c.addQuadCurve(to: CGPoint(x: 26 - 18 * st, y: 60 - 22 * st - f), control: CGPoint(x: 26 - 8 * st, y: 68 - 14 * st))
                c.addQuadCurve(to: CGPoint(x: 42, y: 34), control: CGPoint(x: 30 - 6 * st, y: 42 - 6 * st))
            }.fill(b.dark).scaleEffect(x: swirl, y: 1, anchor: UnitPoint(x: 47 / 84, y: 0.5))
            // back arm and leg
            Capsule().fill(b.fur).frame(width: 5, height: 15).rotationEffect(.degrees(p.flying ? -40 : -swing), anchor: .top).position(x: 41, y: 44)
            Capsule().fill(b.fur).frame(width: 6, height: 14).rotationEffect(.degrees(p.flying ? 25 : swing), anchor: .top).position(x: 44, y: 60)
            Capsule().fill(b.dark).frame(width: 8, height: 5).rotationEffect(.degrees(p.flying ? 25 : swing), anchor: UnitPoint(x: 0.5, y: -1.6)).position(x: 45, y: 66)
            // torso, belt, emblem
            RoundedRectangle(cornerRadius: 6).fill(b.fur).frame(width: 18, height: 21).position(x: 47, y: 45)
            Capsule().fill(b.points ?? kurtaGold).frame(width: 18, height: 3).position(x: 47, y: 54)
            Circle().fill(b.points ?? kurtaGold).frame(width: 8, height: 8).overlay(Text("★").font(.system(size: 6, weight: .black)).foregroundColor(b.dark)).position(x: 49, y: 42)
            // front leg and arm
            Capsule().fill(b.fur).frame(width: 6, height: 14).rotationEffect(.degrees(p.flying ? 15 : -swing), anchor: .top).position(x: 50, y: 60)
            Capsule().fill(b.dark).frame(width: 8, height: 5).rotationEffect(.degrees(p.flying ? 15 : -swing), anchor: UnitPoint(x: 0.5, y: -1.6)).position(x: 51, y: 66)
            Capsule().fill(b.fur).frame(width: 5, height: 15)
                .overlay(Circle().fill(b.dark).frame(width: 6, height: 6).offset(y: 7))
                .rotationEffect(.degrees(p.flying ? -160 : landing ? -10 : swing), anchor: .top).position(x: 54, y: 44)   // fist forward when flying
            // head: skin, hair, mask with white lenses, a small smile
            Circle().fill(b.belly).frame(width: 25, height: 25).position(x: 52, y: 24)
            Path { c in c.addArc(center: CGPoint(x: 52, y: 22), radius: 13, startAngle: .degrees(195), endAngle: .degrees(345), clockwise: false); c.closeSubpath() }
                .fill(hex(0x2b1d14))
            Capsule().fill(b.mask ?? maskInk).frame(width: 22, height: 7).position(x: 54, y: 24)
            ForEach([50.0, 59.0], id: \.self) { x in
                Ellipse().fill(Color.white).frame(width: 5.5, height: p.blink || p.asleep ? 1 : 3.4).position(x: x, y: 24)
            }
            Path { c in c.move(to: CGPoint(x: 54, y: 30)); c.addQuadCurve(to: CGPoint(x: 59, y: 29.5), control: CGPoint(x: 56.5, y: 32)) }
                .stroke(hex(0x5a2d1a), lineWidth: 1.1)
        }
    }
}
