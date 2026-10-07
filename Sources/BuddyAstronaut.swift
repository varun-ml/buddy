import AppKit
import SwiftUI

// MARK: the astronaut: an original little spacefarer in a white suit, round helmet with a tinted visor, backpack and chest panel.
// It walks with a floaty low-gravity bob. Merges plant a flag (heroLanding), red PRs blast off on the jetpack (flyOff),
// now and then it floats up (grapple) or drifts through a slow somersault (stretch).

let astronautBuddy = PetKind(
    name: "astronaut", emoji: "🧑‍🚀", hello: "🚀", coats: astronautSuits,
    tricks: [.stretch, .stretch, .hop, .grapple, .zoomies, .heroLanding],
    onRed: .flyOff, onMerge: .heroLanding, biped: true,
    bursts: [.heroLanding: ["🚩"], .flyOff: ["Houston…", "🔥"], .grapple: ["🌙"], .stretch: ["wheee"]],
    sceneEars: { _, _, _ in })

// fur = suit, dark = backpack and boots, belly = skin (behind the visor), points = trim, mask = visor
let astronautSuits: [Breed] = [
    Breed(name: "Orange astronaut", fur: hex(0xf2f4f7), dark: hex(0x8a94a3), belly: hex(0xc68642), points: hex(0xf97316), mask: hex(0x1e3a5f)),
    Breed(name: "Blue astronaut", fur: hex(0xf2f4f7), dark: hex(0x7c8796), belly: hex(0xffdbac), points: hex(0x2563eb), mask: hex(0x3b2a12)),
    Breed(name: "Red astronaut", fur: hex(0xf2f4f7), dark: hex(0x6b7280), belly: hex(0x8d5524), points: hex(0xdc2626), mask: hex(0x0f3b3a)),
    Breed(name: "Teal astronaut", fur: hex(0xf2f4f7), dark: hex(0x8a94a3), belly: hex(0xe0ac69), points: hex(0x0d9488), mask: hex(0x3b1d5c)),
    Breed(name: "Purple astronaut", fur: hex(0xf2f4f7), dark: hex(0x737b8a), belly: hex(0x5c3a21), points: hex(0x7c3aed), mask: hex(0x7a4a0c)),
]

extension Cat {
    func astronautAvatar(_ p: AvatarPose) -> some View {
        let b = p.b, trim = b.points ?? kurtaGold, visor = b.mask ?? maskInk
        let swing = p.step * 16
        let bob = -abs(p.step) * 4                                         // low gravity: up on every step
        let fly = p.g == .flyOff, float = p.g == .grapple
        let flag = p.g == .heroLanding && p.gt > 0.45                      // pole in the ground after the landing
        let plant = p.g == .heroLanding && p.gt > 0.45 && p.gt < 1.3       // arm pushing it in
        let roll = p.g == .stretch ? Double(ease(p.gt / 2.4)) * 360 : 0     // slow somersault
        let drift: CGFloat = p.g == .stretch ? -10 * CGFloat(sin(min(p.gt / 2.4, 1) * .pi)) : 0
        let wave = sin(p.s * 6)
        let hover: CGFloat = float ? CGFloat(sin(p.s * 2) * 2) : 0
        let lift: CGFloat = CGFloat(bob) + drift + hover
        let flicker = CGFloat(sin(p.s * 47) * 0.5 + 0.5)
        let hm = costumeMotion(p.g, p.gt)                                  // the crouch the whole pet gets; the planted flag undoes it
        let edge = b.dark.opacity(0.6)                                     // outline so a white arm reads against the white suit
        return ZStack {
            ZStack {
                // jetpack flame out of a nozzle on the bottom of the backpack, while blasting off (pale yellow, unlike any trim)
                if fly {
                    Ellipse().fill(hex(0xfde047)).frame(width: 7, height: 10 + 5 * flicker).position(x: 35, y: 63 + 2.5 * flicker)
                    Ellipse().fill(hex(0xfffbeb)).frame(width: 3.5, height: 5 + 3 * flicker).position(x: 35, y: 61 + flicker)
                }
                // backpack
                RoundedRectangle(cornerRadius: 3).fill(b.dark).frame(width: 10, height: 19).position(x: 35, y: 46)
                Capsule().fill(trim).frame(width: 10, height: 2.5).position(x: 35, y: 41)
                RoundedRectangle(cornerRadius: 1).fill(hex(0x374151)).frame(width: 6, height: 3).position(x: 35, y: 57)   // nozzle
                // back arm (raised and splayed clear of the helmet while floating) and leg
                Capsule().fill(b.fur).frame(width: 7, height: 15)
                    .overlay(Capsule().stroke(edge, lineWidth: 0.8))
                    .overlay(Circle().fill(trim).frame(width: 6.5, height: 6.5).offset(y: 6.5))
                    .rotationEffect(.degrees(fly ? 15 : float ? 130 : -swing), anchor: .top).position(x: 44, y: 44)
                Capsule().fill(b.fur).frame(width: 8, height: 13)
                    .rotationEffect(.degrees(fly || float ? 20 : swing), anchor: .top).position(x: 45, y: 59)
                Capsule().fill(b.dark).frame(width: 10, height: 5)
                    .rotationEffect(.degrees(fly || float ? 20 : swing), anchor: UnitPoint(x: 0.5, y: -1.5)).position(x: 46, y: 65)
                // torso, chest panel with three lights, trim belt
                RoundedRectangle(cornerRadius: 7).fill(b.fur).frame(width: 22, height: 22).position(x: 49, y: 47)
                RoundedRectangle(cornerRadius: 1.5).fill(b.dark).frame(width: 11, height: 6).position(x: 47, y: 46)
                ForEach(0..<3, id: \.self) { i in
                    let on = !p.asleep && (Int(p.s * 3) + i) % 3 != 0
                    Circle().fill([hex(0xef4444), hex(0x22c55e), hex(0xfacc15)][i].opacity(on ? 1 : 0.3))
                        .frame(width: 2.2, height: 2.2).position(x: 44 + CGFloat(i) * 3, y: 46)
                }
                Capsule().fill(trim).frame(width: 22, height: 3).position(x: 49, y: 55)
                // front leg and boot
                Capsule().fill(b.fur).frame(width: 8, height: 13)
                    .rotationEffect(.degrees(fly || float ? 5 : -swing), anchor: .top).position(x: 53, y: 59)
                Capsule().fill(b.dark).frame(width: 10, height: 5)
                    .rotationEffect(.degrees(fly || float ? 5 : -swing), anchor: UnitPoint(x: 0.5, y: -1.5)).position(x: 54, y: 65)
                // flag, planted in front: undo the landing crouch and tilt so the pole stands upright in the ground
                if flag {
                    ZStack {
                        Capsule().fill(hex(0x9ca3af)).frame(width: 1.8, height: 32).position(x: 68, y: 52)
                        Path { c in
                            let w = CGFloat(wave) * 1.5
                            c.move(to: CGPoint(x: 69, y: 37)); c.addQuadCurve(to: CGPoint(x: 80, y: 39 + w), control: CGPoint(x: 74, y: 36 - w))
                            c.addLine(to: CGPoint(x: 80, y: 46 + w)); c.addQuadCurve(to: CGPoint(x: 69, y: 45), control: CGPoint(x: 74, y: 44 - w))
                            c.closeSubpath()
                        }.fill(trim)
                        Circle().fill(Color.white).frame(width: 3, height: 3).position(x: 74, y: 41)
                    }
                    .rotationEffect(.degrees(-hm.tilt), anchor: .center)
                    .scaleEffect(x: hm.squash * (hm.squash < 1 ? 1 / 0.9 : 1), y: 1 / hm.squash, anchor: .bottom)
                }
                // front arm, outlined, glove in the trim colour hanging below the belt (raised and splayed while floating)
                Capsule().fill(b.fur).frame(width: 7, height: 20)
                    .overlay(Capsule().stroke(edge, lineWidth: 0.9))
                    .overlay(Circle().fill(trim).frame(width: 6.5, height: 6.5).offset(y: 9))
                    .rotationEffect(.degrees(fly ? 10 : float ? -112 : plant ? -60 : swing), anchor: .top).position(x: 55, y: 49)   // shoulder at y 39
                // helmet: white shell, trim collar, antenna, skin behind a tinted visor, highlight
                Capsule().fill(trim).frame(width: 22, height: 5).position(x: 51, y: 37)
                Capsule().fill(b.dark).frame(width: 1.6, height: 7).position(x: 46, y: 7)
                Circle().fill(trim.opacity(p.asleep ? 0.25 : 1)).frame(width: 4, height: 4).position(x: 46, y: 4)   // antenna light off while asleep
                Circle().fill(b.fur).frame(width: 30, height: 30).position(x: 51, y: 22)
                RoundedRectangle(cornerRadius: 9).fill(b.belly).frame(width: 21, height: 16).position(x: 56, y: 23)
                ForEach([53.0, 60.0], id: \.self) { x in
                    if p.asleep {   // closed eyes, little downward arcs
                        Path { c in c.move(to: CGPoint(x: x - 2, y: 22)); c.addQuadCurve(to: CGPoint(x: x + 2, y: 22), control: CGPoint(x: x, y: 24.5)) }
                            .stroke(b.eye, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                    } else {
                        Capsule().fill(b.eye).frame(width: 2.4, height: p.blink ? 0.8 : 3).position(x: x, y: 22)
                    }
                }
                RoundedRectangle(cornerRadius: 9).fill(visor.opacity(p.asleep ? 0.35 : 0.78)).frame(width: 22, height: 17).position(x: 56, y: 23)   // visor up while asleep
                RoundedRectangle(cornerRadius: 9).stroke(trim, lineWidth: 1.2).frame(width: 22, height: 17).position(x: 56, y: 23)
                Capsule().fill(Color.white.opacity(0.75)).frame(width: 7, height: 2.4).rotationEffect(.degrees(-25)).position(x: 51, y: 18)
                Circle().fill(Color.white.opacity(0.6)).frame(width: 2, height: 2).position(x: 63, y: 18)
            }
            .rotationEffect(.degrees(roll), anchor: UnitPoint(x: 50 / 84, y: 38 / 72))
            .scaleEffect(p.g == .stretch ? 0.86 : 1, anchor: UnitPoint(x: 50 / 84, y: 38 / 72))
            .offset(y: lift)
        }
    }
}
