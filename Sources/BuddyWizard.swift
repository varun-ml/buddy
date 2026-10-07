import AppKit
import SwiftUI

// MARK: the wizard: an original friendly wizard (not any book's or film's), starry robe, tall pointy hat, a staff with a glowing tip.
// The robe hides the legs, so it glides as it walks. Waves the staff for sparkles, vanishes in a poof, floats up on a cloud,
// and zips off the top of the screen when a PR goes red.

let wizardBuddy = PetKind(
    name: "wizard", emoji: "🧙", hello: "🪄", coats: wizardRobes,
    // the idle staff wave rides on .stretch, so "ta-da!" (.capeSwirl) is kept for merges only
    tricks: [.stretch, .stretch, .spin, .spin, .grapple, .hop],
    onRed: .flyOff, onMerge: .capeSwirl, biped: true,
    bursts: [.capeSwirl: ["✨", "ta-da!", "✨"], .stretch: ["✨"], .spin: ["poof!"], .grapple: ["☁️"], .flyOff: ["💫", "whoosh"]],
    sceneEars: { _, _, _ in })

// fur = robe, dark = hat and sleeves' cuffs, belly = skin, points = stars, sash and the staff's glow.
let wizardRobes: [Breed] = [
    Breed(name: "Indigo wizard", fur: hex(0x3d43a8), dark: hex(0x262a73), belly: hex(0xf1c7a3), points: hex(0xf5c542)),
    Breed(name: "Emerald wizard", fur: hex(0x1f7f50), dark: hex(0x134f33), belly: hex(0x8d5524), points: hex(0xf0d878)),
    Breed(name: "Plum wizard", fur: hex(0x7d3f8f), dark: hex(0x4f2560), belly: hex(0xc68642), points: hex(0xf6c96b)),
    Breed(name: "Crimson wizard", fur: hex(0xa8283d), dark: hex(0x6a1424), belly: hex(0xffdbac), points: hex(0xf5c542)),
    Breed(name: "Teal wizard", fur: hex(0x168891), dark: hex(0x0d5559), belly: hex(0x5c3a21), points: hex(0xe3ecf2)),
]

/// A four-pointed sparkle centred in its frame.
private struct WizardTwinkle: Shape {
    func path(in r: CGRect) -> Path {
        Path { c in
            let x = r.midX, y = r.midY, w = r.width / 2, h = r.height / 2, k: CGFloat = 0.22
            c.move(to: CGPoint(x: x, y: y - h))
            c.addLine(to: CGPoint(x: x + w * k, y: y - h * k)); c.addLine(to: CGPoint(x: x + w, y: y))
            c.addLine(to: CGPoint(x: x + w * k, y: y + h * k)); c.addLine(to: CGPoint(x: x, y: y + h))
            c.addLine(to: CGPoint(x: x - w * k, y: y + h * k)); c.addLine(to: CGPoint(x: x - w, y: y))
            c.addLine(to: CGPoint(x: x - w * k, y: y - h * k)); c.closeSubpath()
        }
    }
}

extension Cat {
    func wizardAvatar(_ p: AvatarPose) -> some View {
        let b = p.b, gold = b.points ?? kurtaGold, wood = hex(0x8a5a2e)
        // beards differ by coat: long grey, short dark, short white, or a clean-shaven apprentice
        let beard: (color: Color, long: Bool)? = switch b.name {
            case "Emerald wizard": nil
            case "Plum wizard": (hex(0x4a2e1c), false)
            case "Teal wizard": (hex(0xdcd8cf), false)
            default: (hex(0xeeebe4), true)
        }
        let darkSkin = (NSColor(b.belly).usingColorSpace(.sRGB)?.brightnessComponent ?? 1) < 0.6
        let mouth = darkSkin ? hex(0xf2b8a2) : hex(0x6b3420)
        let waving = (p.g == .capeSwirl || p.g == .stretch) && p.gt < 1.3
        let fly: CGFloat = p.g == .flyOff ? 1 : 0
        let sway = CGFloat(p.step) * 5 + (fly > 0 ? CGFloat(sin(p.s * 16)) * 1.5 : 0)   // the hem swings with each step
        let walkBob = -CGFloat(abs(p.step)) * 2.2   // up on each step, so the walk reads at pet size
        let bob = CGFloat(sin(p.s * 2.4)) * 0.6
        let wave = waving ? sin(p.gt / 1.3 * .pi) : 0   // staff raised forward, waggled twice
        let staffTilt = waving ? wave * (20 + 10 * sin(p.gt / 1.3 * 4 * .pi)) : fly > 0 ? 30 : p.asleep ? -6 : p.step * 9   // plants the staff in time
        // teleport: shrink away into a puff of smoke, then pop back
        let poof = p.g == .spin ? (p.gt < 0.35 ? 1 - p.gt / 0.35 : p.gt < 0.75 ? 0 : min(1, (p.gt - 0.75) / 0.3)) : 1
        let smoke = p.g == .spin && p.gt > 0.15 && p.gt < 1.1 ? sin((p.gt - 0.15) / 0.95 * .pi) : 0
        let cloud = p.g == .grapple
        return ZStack {
            ZStack {
                // back sleeve
                Capsule().fill(b.fur).frame(width: 8, height: 16)
                    .rotationEffect(.degrees(fly > 0 ? 40 : 12 - Double(sway) * 4), anchor: .top).position(x: 46, y: 43)
                Circle().fill(b.belly).frame(width: 5, height: 5).position(x: fly > 0 ? 42 : 44, y: 51)
                // feet peeking out under the hem
                if fly == 0 && !cloud {
                    ForEach([0, 1], id: \.self) { i in
                        let fwd = CGFloat(p.step) * (i == 0 ? 1 : -1)   // boots step out from under the hem, one lifting
                        Capsule().fill(b.dark).frame(width: 8, height: 4.5)
                            .position(x: (i == 0 ? 45 : 56) + fwd * 6, y: 69 - max(0, fwd) * 2.5)
                    }
                }
                // robe: shoulders to a wide hem that sways as it glides; streams back when flying
                Path { c in
                    c.move(to: CGPoint(x: 45, y: 34)); c.addLine(to: CGPoint(x: 59, y: 34))
                    c.addQuadCurve(to: CGPoint(x: 66 + sway - 6 * fly, y: 66 - 4 * fly), control: CGPoint(x: 62, y: 48))
                    c.addQuadCurve(to: CGPoint(x: 37 + sway - 16 * fly, y: 66 - 12 * fly + sway), control: CGPoint(x: 51 + sway, y: 69))
                    c.addQuadCurve(to: CGPoint(x: 45, y: 34), control: CGPoint(x: 40 - 6 * fly, y: 48))
                }.fill(b.fur)
                // hem of stars
                ForEach(0..<4, id: \.self) { i in
                    let f = CGFloat(i) / 3, x = 40 + 23 * f + sway - (16 - 10 * f) * fly, y = 63 - (12 - 8 * f) * fly
                    WizardTwinkle().fill(gold).frame(width: 5, height: 5).position(x: x, y: y)
                }
                WizardTwinkle().fill(gold.opacity(0.85)).frame(width: 4, height: 4).position(x: 49, y: 54)
                // sash
                Capsule().fill(gold).frame(width: 18, height: 2.6).rotationEffect(.degrees(-6)).position(x: 52, y: 46)
                // head and beard
                Circle().fill(b.belly).frame(width: 22, height: 22).position(x: 52, y: 26 + bob)
                if let beard {
                    Path { c in
                        let tip: CGFloat = beard.long ? 42 + sway * 0.3 : 36.5
                        c.move(to: CGPoint(x: 44, y: 28)); c.addQuadCurve(to: CGPoint(x: 55, y: tip), control: CGPoint(x: 45, y: beard.long ? 39 : 35))
                        c.addQuadCurve(to: CGPoint(x: 63, y: 28), control: CGPoint(x: 62, y: beard.long ? 37 : 34)); c.closeSubpath()
                    }.fill(beard.color).offset(y: bob)
                    Capsule().fill(b.belly).frame(width: 7, height: 2.4).position(x: 57, y: 31 + bob)   // mouth gap under the moustache
                }
                Path { c in c.move(to: CGPoint(x: 54.5, y: 31.2)); c.addQuadCurve(to: CGPoint(x: 59.5, y: 31.2), control: CGPoint(x: 57, y: 33.4)) }
                    .stroke(mouth, lineWidth: 1.1).offset(y: bob)
                Circle().fill(hex(0xe8806b).opacity(0.45)).frame(width: 4, height: 4).position(x: 61, y: 28 + bob)
                ForEach([54.5, 60.0], id: \.self) { x in
                    if p.blink || p.asleep {
                        Capsule().fill(ink).frame(width: 3.6, height: 1.1).position(x: x, y: 25 + bob)
                    } else {
                        Ellipse().fill(b.eye).frame(width: 2.8, height: 3.4).position(x: x, y: 24.5 + bob)
                    }
                }
                // hat: wide brim, tall cone bending back, a band and a gold star
                ZStack {
                    Path { c in
                        c.move(to: CGPoint(x: 41, y: 16))
                        c.addQuadCurve(to: CGPoint(x: 41 - 6 * fly, y: 1 + 3 * fly), control: CGPoint(x: 44, y: 6))
                        c.addQuadCurve(to: CGPoint(x: 63, y: 16), control: CGPoint(x: 59, y: 5))
                        c.closeSubpath()
                    }.fill(b.dark)
                    Capsule().fill(gold).frame(width: 21, height: 2.6).position(x: 52, y: 14)
                    Ellipse().fill(b.dark).frame(width: 34, height: 6).position(x: 52, y: 17)
                    WizardTwinkle().fill(gold).frame(width: 7, height: 7).position(x: 53, y: 8.5)
                }.offset(y: bob).rotationEffect(.degrees(p.asleep ? -6 : 0), anchor: UnitPoint(x: 52 / 84, y: 17 / 72))
                // front sleeve, hand and staff; the staff swings from the hand
                Capsule().fill(b.fur).frame(width: 8, height: 15)
                    .overlay(Capsule().fill(b.dark).frame(width: 9, height: 3).offset(y: 6))
                    .rotationEffect(.degrees(-41), anchor: .top).position(x: 58, y: 42)   // the cuff ends on the hand
                ZStack {
                    // a long staff, so the orb and its glow clear the hat brim (which reaches x≈69, y 14…20)
                    Capsule().fill(wood).frame(width: 3, height: 60).position(x: 68, y: 38)
                    Circle().fill(gold.opacity(0.35)).frame(width: 12 + 3 * abs(wave), height: 12 + 3 * abs(wave)).position(x: 68, y: 8)
                    Circle().fill(Color.white).overlay(Circle().fill(gold.opacity(0.6)).frame(width: 4)).frame(width: 7, height: 7).position(x: 68, y: 8)
                    Circle().fill(b.belly).frame(width: 6, height: 6).position(x: 67.5, y: 45.5)
                }.rotationEffect(.degrees(staffTilt), anchor: UnitPoint(x: 67.5 / 84, y: 45.5 / 72))
                // sparkles thrown off the staff tip while it waves
                if (p.g == .capeSwirl || p.g == .stretch) && p.gt < 1.4 {
                    ForEach(0..<4, id: \.self) { i in
                        let a = p.gt * 3 + Double(i) * 1.6, r = 6 + p.gt * 10
                        WizardTwinkle().fill(i % 2 == 0 ? gold : Color.white).frame(width: 5, height: 5)
                            .position(x: min(80, max(4, 67.5 + 37.5 * sin(staffTilt * .pi / 180) + cos(a) * r)),
                                      y: min(60, max(3, 45.5 - 37.5 * cos(staffTilt * .pi / 180) + sin(a) * r * 0.7)))
                    }
                }
            }
            .scaleEffect(poof, anchor: UnitPoint(x: 52 / 84, y: 0.6))
            .opacity(poof)
            .offset(y: walkBob)
            // speed streaks while zipping off
            if fly > 0 {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(gold.opacity(0.7)).frame(width: 14 - CGFloat(i) * 3, height: 2)
                        .position(x: 14 + CGFloat(i) * 4 + CGFloat(sin(p.s * 20 + Double(i))) * 2, y: 42 + CGFloat(i) * 9)
                }
            }
            // a little cloud to stand on
            if cloud {
                ZStack {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(Color.white).frame(width: [12, 16, 14, 11][i], height: [12, 16, 14, 11][i])
                            .position(x: [39, 48, 58, 66][i], y: [65, 63, 64, 66][i])
                    }
                    Capsule().fill(Color.white).frame(width: 34, height: 7).position(x: 52, y: 67)
                }.offset(y: CGFloat(sin(p.s * 3)) * 1)
            }
            // the poof: a ring of smoke puffs
            if smoke > 0 {
                ForEach(0..<6, id: \.self) { i in
                    let a = Double(i) / 6 * 2 * .pi, r = 6 + 12 * smoke
                    Circle().fill(Color(white: 0.9).opacity(0.95 * smoke)).frame(width: 10 + 6 * smoke, height: 10 + 6 * smoke)
                        .position(x: 52 + cos(a) * r, y: 44 + sin(a) * r * 0.8)
                }
                WizardTwinkle().fill(gold.opacity(smoke)).frame(width: 9, height: 9).position(x: 52, y: 44)
            }
        }
    }
}
