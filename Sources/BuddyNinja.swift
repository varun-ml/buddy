import AppKit
import SwiftUI

// MARK: the shadow ninja: an original ninja (not any show's), wrap suit, hood with an eye slit, a coloured sash and headband
// whose tails flutter behind, split-toe boots. Vanishes in a smoke poof, dashes, backflips, climbs a rope, throws a soft toy star.

let ninjaBuddy = PetKind(
    name: "ninja", emoji: "🥷", hello: "🥷", coats: ninjaSuits,
    tricks: [.stretch, .spin, .spin, .zoomies, .hop, .knock, .knock, .grapple],
    onRed: .flyOff, onMerge: .hop, biped: true,
    bursts: [.spin: ["poof!"], .hop: ["HAI-YA!"], .zoomies: ["💨", "💨"], .knock: ["thwip!"], .grapple: ["🧗"], .flyOff: ["💨"]],
    sceneEars: { _, _, _ in })

// fur = suit, dark = boots, gloves and folds, belly = skin round the eyes, points = sash and headband
let ninjaSuits: [Breed] = [
    Breed(name: "Midnight ninja", fur: hex(0x22263a), dark: hex(0x0e1018), belly: hex(0xf1c7a3), points: hex(0xd23a3a)),
    Breed(name: "Indigo ninja", fur: hex(0x312c66), dark: hex(0x17153a), belly: hex(0x8d5524), points: hex(0xf2b632)),
    Breed(name: "Charcoal ninja", fur: hex(0x3b3e45), dark: hex(0x1c1d21), belly: hex(0xe0ac69), points: hex(0x2fae6e)),
    Breed(name: "Crimson ninja", fur: hex(0x7a1f2b), dark: hex(0x34090f), belly: hex(0x5c3a21), points: hex(0xf3ede0)),
    Breed(name: "Teal ninja", fur: hex(0x1d4f57), dark: hex(0x0c2a2f), belly: hex(0xc68642), points: hex(0xff8a5c)),
]

extension Cat {
    /// One leg from the hip, with a split-toe boot; `a` is degrees from hanging straight down (negative = forward).
    func ninjaLeg(_ b: Breed, _ a: Double, x: CGFloat, y: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Capsule().fill(b.fur).frame(width: 6, height: 13)
            Capsule().fill(b.dark).frame(width: 9, height: 5).offset(x: 1.5, y: 11)
            Capsule().fill(b.fur.opacity(0.9)).frame(width: 0.9, height: 3).offset(x: 4, y: 12)   // the split toe
        }
        .frame(width: 12, height: 17, alignment: .top)
        .rotationEffect(.degrees(a), anchor: .top)
        .position(x: x, y: y + 8.5)
    }

    /// One arm from the shoulder, with a wrapped fist.
    func ninjaArm(_ b: Breed, _ a: Double, x: CGFloat, y: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Capsule().fill(b.fur).frame(width: 5, height: 13)
            Circle().fill(b.dark).frame(width: 5.5, height: 5.5).offset(y: 10)
        }
        .frame(width: 8, height: 16, alignment: .top)
        .rotationEffect(.degrees(a), anchor: .top)
        .position(x: x, y: y + 8)
    }

    /// The soft toy star: five fat rounded points in bright plastic yellow, a pink button in the middle.
    func ninjaToyStar() -> some View {
        ZStack {
            ForEach(0..<5) { i in
                Capsule().fill(hex(0xffd23f)).frame(width: 5.5, height: 8).offset(y: -3.5).rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(hex(0xffd23f)).frame(width: 7.5, height: 7.5)
            Circle().fill(hex(0xff7aa8)).frame(width: 3.4, height: 3.4)
        }
    }

    func ninjaAvatar(_ p: AvatarPose) -> some View {
        let b = p.b, g = p.g, gt = p.gt
        let sash = b.points ?? kurtaGold
        let dash = g == .zoomies, climb = g == .grapple, leap = g == .flyOff
        let flip = g == .hop && gt < 0.7, smoke = g == .spin && gt < 1.3, toss = g == .knock && gt < 1.2
        let run = dash ? sin(p.s * 22) : p.step
        let swing = run * (dash ? 45 : 30)
        let moving = p.step != 0 || dash || climb || leap || flip
        let f = CGFloat(sin(p.s * (moving ? 16 : 3)) * (moving ? 2.5 : 1.2))   // flutter of the tails
        let st: CGFloat = moving ? 1 : 0                                         // how far the tails stream out
        // vanish: shrink into the smoke, hang there unseen, pop back
        let gone: CGFloat = !smoke ? 1 : gt < 0.25 ? 1 - CGFloat(gt / 0.25) : gt < 0.8 ? 0 : min(1, CGFloat((gt - 0.8) / 0.35))
        let puff = smoke ? sin(min(gt / 1.3, 1) * .pi) : 0
        let flipDeg = flip ? -360 * Double(ease(gt / 0.7)) : 0
        let lean: Double = dash ? 14 : 0
        let climbA = sin(p.s * 9)
        // arms and legs for the pose under way
        let tuck = flip || leap
        let backLeg = climb ? 10 + climbA * 30 : tuck ? -70 : swing
        let frontLeg = climb ? 10 - climbA * 30 : tuck ? -95 : -swing
        let throwA: Double = gt < 0.25 ? 110 * Double(ease(gt / 0.25)) : gt < 0.4 ? 110 - 210 * Double(ease((gt - 0.25) / 0.15)) : -100 + 100 * Double(ease((gt - 0.4) / 0.5))
        let frontArm = climb ? 175 + climbA * 18 : leap ? 50 : flip ? -60 : toss ? throwA : -swing * 0.9
        let backArm = climb ? -175 + climbA * 18 : leap ? 60 : flip ? -40 : swing * 0.9
        // climbing: the rope hangs just in front of the face; one fist grips it above the hood, one below the eyes, hand over hand
        let ropeX: CGFloat = 67
        let gripHi = CGFloat(12 - 3 * climbA), gripLo = CGFloat(27 + 3 * climbA)
        // throwing: where the front fist is, so the toy star can sit in it during the wind-up
        let throwR = throwA * .pi / 180
        let fist = CGPoint(x: 52 - 12.75 * CGFloat(sin(throwR)), y: 37 + 12.75 * CGFloat(cos(throwR)))
        let headDrop: CGFloat = p.asleep ? 3 : 0
        let breathe = CGFloat(sin(p.s * 2.4) * 0.4)
        return ZStack {
            if climb {   // the rope it climbs
                Path { c in c.move(to: CGPoint(x: ropeX, y: 0)); c.addLine(to: CGPoint(x: ropeX, y: 62)) }
                    .stroke(hex(0xb08a5a), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if dash {   // speed lines behind
                ForEach(0..<3) { i in
                    Capsule().fill(Color.gray.opacity(0.55)).frame(width: 14 - CGFloat(i) * 2, height: 1.6)
                        .position(x: 18 - CGFloat(i) * 4 + CGFloat(sin(p.s * 30 + Double(i)) * 2), y: 36 + CGFloat(i) * 9)
                }
            }
            ZStack {
                // sash tails, behind everything: from the knot at the back of the waist
                ForEach(0..<2) { i in
                    let k = CGFloat(i)
                    Path { c in
                        c.move(to: CGPoint(x: 40, y: 52))
                        // standing: two short ends hang just under the knot; moving: they stream out behind
                        c.addQuadCurve(to: CGPoint(x: 38.5 - 1.5 * k - 16.5 * st, y: 56.5 + 1.5 * k - 5.5 * st + f * st * (k == 0 ? 1 : -1)),
                                       control: CGPoint(x: 39.5 - 3.5 * st, y: 55 + k + f * st))
                    }.stroke(sash, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
                // headband tails from the back of the hood
                ForEach(0..<2) { i in
                    let k = CGFloat(i)
                    Path { c in
                        c.move(to: CGPoint(x: 41, y: 19 + headDrop))
                        c.addQuadCurve(to: CGPoint(x: 31 - 6 * st, y: 22 + 3 * k - 4 * st + f * (k == 0 ? -1 : 1) + headDrop),
                                       control: CGPoint(x: 35, y: 19 + 2 * k - f + headDrop))
                    }.stroke(sash, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
                // back arm and leg
                if climb {   // the high arm reaches up behind the hood to the rope
                    Path { c in c.move(to: CGPoint(x: 46, y: 38)); c.addLine(to: CGPoint(x: ropeX - 1, y: gripHi)) }
                        .stroke(b.fur, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                } else {
                    ninjaArm(b, backArm, x: 43, y: 37 + breathe)
                }
                ninjaLeg(b, backLeg, x: 44, y: 53)
                // torso: wrap suit with a crossed collar, sash belt and knot
                RoundedRectangle(cornerRadius: 5).fill(b.fur).frame(width: 16, height: 20).position(x: 47, y: 45 + breathe)
                Path { c in
                    c.move(to: CGPoint(x: 41, y: 36 + breathe)); c.addLine(to: CGPoint(x: 50, y: 47 + breathe))
                    c.move(to: CGPoint(x: 54, y: 36 + breathe)); c.addLine(to: CGPoint(x: 48, y: 43 + breathe))
                }.stroke(b.dark, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                Capsule().fill(sash).frame(width: 17, height: 4).position(x: 47, y: 52)
                Circle().fill(sash).frame(width: 5, height: 5).position(x: 40, y: 52)
                // front leg and arm
                ninjaLeg(b, frontLeg, x: 50, y: 53)
                if !climb && !toss { ninjaArm(b, frontArm, x: 52, y: 37 + breathe) }
                // head: hood, headband, eye slit with the skin showing, two bright eyes
                ZStack {
                    Circle().fill(b.fur).frame(width: 24, height: 24).position(x: 52, y: 24)
                    Path { c in c.addArc(center: CGPoint(x: 52, y: 24), radius: 12, startAngle: .degrees(40), endAngle: .degrees(140), clockwise: false) }
                        .stroke(b.dark.opacity(0.7), lineWidth: 1.2)   // the wrap under the chin
                    Capsule().fill(sash).frame(width: 24, height: 3.2).position(x: 52, y: 17.5)
                    Capsule().fill(b.belly).frame(width: 19, height: 7).position(x: 56, y: 24)
                    ForEach([52.5, 60.0], id: \.self) { x in
                        if p.blink || p.asleep {
                            Capsule().fill(ink).frame(width: 4, height: 1).position(x: x, y: 24.5)
                        } else {
                            Ellipse().fill(Color.white).frame(width: 4.2, height: 3.6).position(x: x, y: 24)
                            Circle().fill(b.eye).frame(width: 2.3, height: 2.3).position(x: x + 0.6, y: 24)
                        }
                    }
                }.offset(y: headDrop)
                if toss {   // the throwing arm swings in front of the body, so the wind-up reads
                    ninjaArm(b, frontArm, x: 52, y: 37 + breathe)
                    if gt < 0.3 { ninjaToyStar().scaleEffect(0.8).position(x: fist.x, y: fist.y - 2) }
                }
                if climb {   // the low arm crosses in front under the chin; both fists close on the rope
                    Path { c in c.move(to: CGPoint(x: 53, y: 39)); c.addLine(to: CGPoint(x: ropeX - 1, y: gripLo)) }
                        .stroke(b.fur, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    Circle().fill(b.dark).frame(width: 6.5, height: 6.5).position(x: ropeX, y: gripHi)
                    Circle().fill(b.dark).frame(width: 6.5, height: 6.5).position(x: ropeX, y: gripLo)
                }
            }
            .scaleEffect(gone, anchor: UnitPoint(x: 48 / 84, y: 46 / 72))
            .rotationEffect(.degrees(flipDeg), anchor: UnitPoint(x: 48 / 84, y: 42 / 72))
            .rotationEffect(.degrees(lean), anchor: UnitPoint(x: 47 / 84, y: 68 / 72))
            if toss && gt > 0.3 {   // a soft toy star: rounded points, spinning off to the front
                let q = CGFloat(min((gt - 0.3) / 0.6, 1))
                ninjaToyStar()
                .rotationEffect(.degrees(Double(q) * 540))
                .opacity(Double(1 - max(0, q - 0.8) * 5))
                .position(x: 71 + 7 * q, y: 42 - 6 * sin(q * .pi))
            }
            if smoke {   // the poof
                ForEach(0..<6) { i in
                    let a = Double(i) / 6 * 2 * .pi + 0.4
                    Circle().fill(Color(white: 0.82)).frame(width: 12 + 8 * puff, height: 12 + 8 * puff)
                        .position(x: 48 + CGFloat(cos(a)) * 12 * CGFloat(puff + 0.3), y: 44 + CGFloat(sin(a)) * 11 * CGFloat(puff + 0.3))
                        .opacity(puff * 0.95)
                }
            }
        }
    }
}
