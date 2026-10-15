import AppKit
import SwiftUI

// MARK: the chemist: a chemistry teacher in the style of Breaking Bad's Heisenberg: bald, goatee and moustache,
// dark sunglasses and a black pork-pie hat (the teacher and lab looks wear clear glasses), never without a flask. Swirls it now and then, holds it up to the light for "eureka!" on a merge, and it fizzes over in a puff
// of smoke when a PR goes red (soot on the face, hat knocked up).

let chemistBuddy = PetKind(
    name: "chemist", emoji: "🧑‍🔬", hello: "⚗️", coats: labCoats,
    // the idle swirl rides on .stretch, so "eureka!" (.capeSwirl) is kept for merges only
    tricks: [.stretch, .stretch, .stretch, .hop],
    onRed: .sneeze, onMerge: .capeSwirl, biped: true,
    bursts: [.capeSwirl: ["eureka!", "⚗️"], .stretch: ["🫧"], .hop: ["🧪"], .sneeze: ["💥", "pfft"]],
    sceneEars: { _, _, _ in })

// fur = jacket, coat or suit, dark = hat and trousers, belly = skin, eye = glasses frames, points = what's in the flask.
// Which coats wear the hat, sunglasses or respirator is decided by name in chemistAvatar.
let labCoats: [Breed] = [
    Breed(name: "Heisenberg", fur: hex(0x26272b), dark: hex(0x111113), belly: hex(0xf1c7a3), eye: hex(0x111113), points: hex(0x34d399)),
    Breed(name: "Cook", fur: hex(0xf2c94c), dark: hex(0x2f2f2f), belly: hex(0xf1c7a3), eye: hex(0x2f2f2f), points: hex(0xef4444)),
    Breed(name: "Teacher", fur: hex(0xc2b280), dark: hex(0x6b5a45), belly: hex(0xf1c7a3), eye: hex(0x3b2a1e), points: hex(0xf59e0b)),
    Breed(name: "Lab chemist", fur: hex(0xf3f4f1), dark: hex(0x111113), belly: hex(0xe0ac69), eye: hex(0x2b2b2e), points: hex(0xa78bfa)),
    Breed(name: "Night chemist", fur: hex(0x1f2a44), dark: hex(0x111113), belly: hex(0x8d5524), eye: hex(0x111113), points: hex(0xf472b6)),
]

/// An Erlenmeyer flask, neck at the top, filling its frame.
private struct ChemFlask: Shape {
    func path(in r: CGRect) -> Path {
        Path { c in
            let neck = r.width * 0.18
            c.move(to: CGPoint(x: r.midX - neck, y: r.minY))
            c.addLine(to: CGPoint(x: r.midX + neck, y: r.minY))
            c.addLine(to: CGPoint(x: r.midX + neck, y: r.minY + r.height * 0.35))
            c.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 1))
            c.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 1), control: CGPoint(x: r.midX, y: r.maxY + 1))
            c.addLine(to: CGPoint(x: r.midX - neck, y: r.minY + r.height * 0.35))
            c.closeSubpath()
        }
    }
}

extension Cat {
    func chemistAvatar(_ p: AvatarPose) -> some View {
        let b = p.b, liquid = b.points ?? hex(0x34d399), frames = b.eye
        let hat = !["Cook", "Teacher"].contains(b.name), shades = ["Heisenberg", "Night chemist"].contains(b.name)
        let respirator = b.name == "Cook", labCoat = ["Lab chemist", "Teacher"].contains(b.name)
        let shirt = labCoat ? hex(0x9fb7c9) : b.name == "Cook" ? hex(0xe0b43a) : hex(0x5f6b5a)
        let beard = hex(0x45372c)   // dark brown; the mouth gap keeps it from reading as a hole at pet size
        let swing = p.step * 22
        let walkBob = -CGFloat(abs(p.step)) * 1.6
        let hop: CGFloat = p.g == .hop && p.gt < 0.6 ? -CGFloat(sin(p.gt / 0.6 * .pi)) * 8 : 0
        let swirling = p.g == .stretch && p.gt < 2.4
        let eureka = p.g == .capeSwirl && p.gt < 1.6
        let fizz = p.g == .sneeze && p.gt < 1.6
        let raise = eureka ? ease(p.gt / 0.3) * (1 - ease((p.gt - 1.3) / 0.3)) : 0   // up, hold, down
        let swirl = swirling ? sin(p.gt * 9) * 14 : 0
        let puff = fizz ? sin(min(p.gt / 1.6, 1) * .pi) : 0
        let hatLift: CGFloat = fizz && p.gt < 0.6 ? -CGFloat(sin(p.gt / 0.6 * .pi)) * 6 : 0
        // the flask hand: at the hip while walking, held out to swirl, overhead for eureka
        let armAngle: Double = eureka ? -150 * Double(raise) + (1 - Double(raise)) * swing : swirling || fizz ? -70 : p.asleep ? 10 : swing
        let hand = CGPoint(x: 54 + 15 * sin(-armAngle * .pi / 180), y: 44 + 15 * cos(-armAngle * .pi / 180))
        return ZStack {
            // back arm and leg
            Capsule().fill(b.fur).frame(width: 5, height: 15).rotationEffect(.degrees(-swing), anchor: .top).position(x: 41, y: 44)
            Capsule().fill(b.dark).frame(width: 6, height: 13).rotationEffect(.degrees(swing), anchor: .top).position(x: 44, y: 61)
            Capsule().fill(hex(0x1b1b1f)).frame(width: 8, height: 4).rotationEffect(.degrees(swing), anchor: UnitPoint(x: 0.5, y: -1.8)).position(x: 45, y: 66)
            // front leg
            Capsule().fill(b.dark).frame(width: 6, height: 13).rotationEffect(.degrees(-swing), anchor: .top).position(x: 50, y: 61)
            Capsule().fill(hex(0x1b1b1f)).frame(width: 8, height: 4).rotationEffect(.degrees(-swing), anchor: UnitPoint(x: 0.5, y: -1.8)).position(x: 51, y: 66)
            // lab coat down to the knees: shirt in the V, lapels, a pocket with a pen
            RoundedRectangle(cornerRadius: 5).fill(b.fur).frame(width: 20, height: 27).position(x: 47, y: 47)
            RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.18), lineWidth: 0.8).frame(width: 20, height: 27).position(x: 47, y: 47)
            Path { c in c.move(to: CGPoint(x: 45, y: 34)); c.addLine(to: CGPoint(x: 49, y: 42)); c.addLine(to: CGPoint(x: 53, y: 34)); c.closeSubpath() }
                .fill(shirt)
            Path { c in
                c.move(to: CGPoint(x: 45, y: 34)); c.addLine(to: CGPoint(x: 49, y: 42))
                c.move(to: CGPoint(x: 53, y: 34)); c.addLine(to: CGPoint(x: 49, y: 42)); c.addLine(to: CGPoint(x: 49, y: 60))
            }.stroke(Color.black.opacity(0.25), lineWidth: 0.8)
            if labCoat {
                RoundedRectangle(cornerRadius: 1).stroke(Color.black.opacity(0.25), lineWidth: 0.7).frame(width: 5, height: 4).position(x: 53, y: 46)
                Capsule().fill(hex(0x2563eb)).frame(width: 1.2, height: 4).position(x: 52.5, y: 44)
            }
            // front arm, sleeve and hand
            Capsule().fill(b.fur).frame(width: 5, height: 15)
                .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.6))
                .rotationEffect(.degrees(armAngle), anchor: .top).position(x: 54, y: 44)
            Circle().fill(b.belly).frame(width: 4.5, height: 4.5).position(hand)
            // the flask, in the hand: swirls, glows when held up, fizzes over on a red PR
            ZStack {
                if eureka { Circle().fill(liquid.opacity(0.35 * Double(raise))).frame(width: 18, height: 18).blur(radius: 3) }
                ChemFlask().fill(Color.white.opacity(0.55)).frame(width: 10, height: 12)
                ChemFlask().fill(liquid).frame(width: 10, height: 12).mask(Rectangle().frame(width: 10, height: 6).offset(y: 3))
                ChemFlask().stroke(Color.black.opacity(0.45), lineWidth: 0.8).frame(width: 10, height: 12)
                if swirling || eureka {
                    ForEach(0..<3) { i in
                        let t = (p.s * 1.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle().fill(liquid.opacity(1 - t)).frame(width: 2.2, height: 2.2).offset(x: CGFloat(i - 1) * 1.5, y: -6 - CGFloat(t) * 10)
                    }
                }
            }
            .rotationEffect(.degrees(swirl))
            .position(x: hand.x + 1, y: hand.y - 5)
            if fizz {   // a puff of smoke from the flask's neck
                ForEach(0..<4) { i in
                    Circle().fill(Color.gray.opacity(0.55 * puff)).frame(width: 7 + CGFloat(i) * 2.5, height: 7 + CGFloat(i) * 2.5)
                        .position(x: hand.x + 1 + CGFloat(i % 2 == 0 ? -3 : 3), y: hand.y - 12 - CGFloat(i) * 4 * CGFloat(puff))
                }
            }
            // head: bald with a shine, moustache and goatee joined round the mouth; soot after a fizz
            Circle().fill(b.belly).frame(width: 25, height: 25).position(x: 52, y: 24)
            if !hat { Ellipse().fill(Color.white.opacity(0.35)).frame(width: 7, height: 3.5).rotationEffect(.degrees(-20)).position(x: 48, y: 15) }
            if !respirator {
                // the French beard: moustache joined down both sides to a pointed chin beard, with the mouth cut out as
                // a gap of skin. A dark line for the mouth closed that gap at pet size and read as an open mouth.
                Path { c in
                    c.move(to: CGPoint(x: 53.5, y: 29.4)); c.addQuadCurve(to: CGPoint(x: 62, y: 29.2), control: CGPoint(x: 57.8, y: 26.6))
                    c.addLine(to: CGPoint(x: 61.8, y: 32.6)); c.addQuadCurve(to: CGPoint(x: 58, y: 37.8), control: CGPoint(x: 61.6, y: 36.2))
                    c.addQuadCurve(to: CGPoint(x: 53.9, y: 32.6), control: CGPoint(x: 54.2, y: 36.2)); c.closeSubpath()
                    c.addEllipse(in: CGRect(x: 54.9, y: 30.0, width: 5.9, height: 2.9))   // the mouth gap
                }.fill(beard, style: FillStyle(eoFill: true))
            }
            if fizz { Ellipse().fill(Color.black.opacity(0.35 * puff)).frame(width: 14, height: 7).position(x: 56, y: 26) }
            if shades {   // dark sunglasses: closed eyes don't show behind them
                ForEach([51.0, 59.0], id: \.self) { x in
                    RoundedRectangle(cornerRadius: 2.2).fill(hex(0x141416)).frame(width: 7.5, height: 5.2).position(x: x, y: 23.5)
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 3, height: 0.9).rotationEffect(.degrees(-20)).position(x: x + 1, y: 22.2)
                }
            } else {
                ForEach([51.0, 59.0], id: \.self) { x in
                    if p.blink || p.asleep {
                        Capsule().fill(ink).frame(width: 3.2, height: 0.9).position(x: x, y: 23.5)
                    } else {
                        Circle().fill(ink).frame(width: 2.2, height: 2.2).position(x: x, y: 23.5)
                    }
                    RoundedRectangle(cornerRadius: 1.5).stroke(frames, lineWidth: 1.1).frame(width: 7, height: 5).position(x: x, y: 23.5)
                }
            }
            Path { c in c.move(to: CGPoint(x: 54.7, y: 23)); c.addLine(to: CGPoint(x: 55.3, y: 23)); c.move(to: CGPoint(x: 47.3, y: 23)); c.addLine(to: CGPoint(x: 41, y: 21.5)) }
                .stroke(shades ? hex(0x141416) : frames, lineWidth: 1)
            if respirator {   // half-face respirator with two pink filters, over the nose and mouth
                RoundedRectangle(cornerRadius: 3.5).fill(hex(0x3a3a3c)).frame(width: 11, height: 8).position(x: 57.5, y: 30.5)
                Capsule().fill(hex(0x3a3a3c)).frame(width: 15, height: 1.6).position(x: 47, y: 29)
                ForEach([53.5, 61.5], id: \.self) { x in
                    Circle().fill(hex(0xc0587a)).frame(width: 5, height: 5).overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 0.6)).position(x: x, y: 32)
                }
            }
            if hat {   // the black pork-pie: flat crown with the pinched top, a band, a short brim, worn low
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(b.dark).frame(width: 20, height: 7.5).position(x: 51, y: 11.5)
                    Capsule().fill(Color.white.opacity(0.16)).frame(width: 14, height: 1.3).position(x: 51, y: 8.6)
                    Rectangle().fill(Color.black.opacity(0.55)).frame(width: 20, height: 2.2).position(x: 51, y: 14)
                    Path { c in   // the brim, its edges turned up a little
                        c.move(to: CGPoint(x: 36, y: 14.6)); c.addQuadCurve(to: CGPoint(x: 66, y: 14.6), control: CGPoint(x: 51, y: 18.4))
                        c.addLine(to: CGPoint(x: 66, y: 16)); c.addQuadCurve(to: CGPoint(x: 36, y: 16), control: CGPoint(x: 51, y: 20.2)); c.closeSubpath()
                    }.fill(b.dark)
                }
                .offset(y: hatLift)
                .rotationEffect(.degrees(fizz ? -8 * puff : 0), anchor: UnitPoint(x: 51 / 84, y: 16 / 72))
            }
        }
        .offset(y: walkBob + hop)
    }
}
