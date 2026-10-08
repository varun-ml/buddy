import AppKit
import SwiftUI

// MARK: Stitch: a little blue alien with huge ears, big black eyes and a wide grin. Waddles on short legs, ears bouncing.
// Merges get a hula on the ukulele with a lei on, red PRs flip it into alien mode (extra arms, antennae, back spines, teeth),
// and now and then it surfs a wave or flaps its ears wide.
// Coat colours: fur = fur, dark = nose, belly = muzzle and tummy, eye = eyes, points = inside the ears, mask = patches round the eyes.

let stitchBuddy = PetKind(
    name: "stitch", emoji: "👽", hello: "🌺", coats: stitchCoats,
    tricks: [.shimmy, .hop, .hop, .stretch, .spin, .sneeze],
    onRed: .sneeze, onMerge: .shimmy, biped: true,
    bursts: [.shimmy: ["Aloha!", "🌺", "🎶"], .sneeze: ["Meega nala!", "👾"], .hop: ["🌊", "🏄"], .stretch: ["Ohana 💙"], .spin: ["wheee!"]],
    sceneEars: { _, _, _ in })

let stitchCoats: [Breed] = [
    Breed(name: "Blue alien", fur: hex(0x4f86d9), dark: hex(0x1e3f7a), belly: hex(0xa8d1f5), eye: hex(0x0d0f1a), points: hex(0xc77db5), mask: hex(0x2f5fae)),
    Breed(name: "Pink alien", fur: hex(0xf08cbd), dark: hex(0x8c2f63), belly: hex(0xfbd3e6), eye: hex(0x0d0f1a), points: hex(0x9b5fd0), mask: hex(0xd0609a)),
    Breed(name: "Purple alien", fur: hex(0x8f6fd8), dark: hex(0x3b2a78), belly: hex(0xcdbff5), eye: hex(0x0d0f1a), points: hex(0xf28cb6), mask: hex(0x6a4fb8)),
    Breed(name: "Green alien", fur: hex(0x5fbf7a), dark: hex(0x235c35), belly: hex(0xc6ecd0), eye: hex(0x0d0f1a), points: hex(0xf2a65a), mask: hex(0x3e9658)),
    Breed(name: "Night alien", fur: hex(0x2c3e8f), dark: hex(0x0f1640), belly: hex(0x7f9ae0), eye: hex(0x0d0f1a), points: hex(0xb565a7), mask: hex(0x1c2a66)),
]

/// A point `len` along a direction `deg` degrees from straight up (+ = forward), from `root`.
private func along(_ root: CGPoint, _ deg: Double, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
    let r = deg * .pi / 180, c = CGFloat(cos(r)), s = CGFloat(sin(r))
    return CGPoint(x: root.x + x * c - y * s, y: root.y + x * s + y * c)
}

extension Cat {
    /// A big leaf-shaped ear from `root`, pointing `deg` degrees from straight up (+ = forward), with a dark notch near the tip.
    func stitchEar(_ root: CGPoint, _ deg: Double, len: CGFloat, _ b: Breed) -> some View {
        func leaf(_ l: CGFloat, _ w: CGFloat, _ dy: CGFloat) -> Path {
            Path { c in
                c.move(to: along(root, deg, -w * 0.4, dy))
                c.addQuadCurve(to: along(root, deg, 0, dy - l), control: along(root, deg, -w, dy - l * 0.45))
                c.addQuadCurve(to: along(root, deg, w * 0.4, dy), control: along(root, deg, w, dy - l * 0.55))
                c.closeSubpath()
            }
        }
        return ZStack {
            leaf(len, 12, 2).fill(b.fur)
            leaf(len, 12, 2).stroke(Color.black.opacity(0.15), lineWidth: 0.8)
            leaf(len * 0.7, 7, -1).fill(b.points ?? b.dark)
            Path { c in c.move(to: along(root, deg, -3.5, 2 - len * 0.8)); c.addLine(to: along(root, deg, -1, 2 - len * 0.72)) }
                .stroke(b.dark, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

    /// A stubby arm hanging from `sh`, swung `deg` degrees (+ = forward).
    func stitchArm(_ sh: CGPoint, _ deg: Double, len: CGFloat = 11, _ b: Breed) -> some View {
        Capsule().fill(b.fur).overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 0.7))
            .frame(width: 6, height: len)
            .rotationEffect(.degrees(-deg), anchor: .top)
            .position(x: sh.x, y: sh.y + len / 2)
    }

    func stitchAvatar(_ p: AvatarPose) -> some View {
        let b = p.b, g = p.g, gt = p.gt
        let st = p.step
        let hula = g == .shimmy && gt < 2.4
        let alien = g == .sneeze && gt > 0.15 && gt < 2.3             // extra arms, antennae and spines out
        let surf = g == .hop && gt < 2.4
        let flap = g == .stretch ? sin(min(gt / 2.4, 1) * .pi) : 0      // ears spread wide
        let happy = hula || surf || flap > 0.2
        let bob: CGFloat = -abs(CGFloat(st)) * 2
        let wave = sin(p.s * 3)
        // ears: back one sweeps back, front one forward; droop asleep, flap on a stretch, bounce on a walk, flatten in alien mode
        let twitch = !p.asleep && Int(p.s / 2.5) % 5 == 0 ? sin(p.s * 30) * 6 : 0
        let earB = p.asleep ? -112 : alien ? -88 : -80 - 20 * flap - st * 8 + (hula ? sin(gt * 12) * 10 : 0)
        let earF = p.asleep ? 108 : alien ? 82 : 60 + 20 * flap + st * 8 + twitch + (hula ? -sin(gt * 12) * 10 : 0)
        // arms (+ = forward)
        var armB = -st * 28 - 8, armF = st * 28 + 12
        if hula { armB = 125; armF = 35 + sin(gt * 26) * 18 }         // back hand on the neck, front hand strumming
        else if surf { armB = -75 + wave * 8; armF = 80 - wave * 8 }   // out for balance
        else if alien { armB = -40 + sin(gt * 18) * 20; armF = 60 + sin(gt * 18 + 1) * 20 }
        else if flap > 0 { armB = -50 * flap; armF = 70 * flap }
        let leg = surf ? 0 : st * 24
        let jitter: CGFloat = alien ? CGFloat(sin(gt * 60)) * 0.7 : 0

        return ZStack {
            if surf {   // the wave under the board, scrolling back
                let off = CGFloat((p.s * 30).truncatingRemainder(dividingBy: 14))
                Capsule().fill(hex(0x4cc9f0)).frame(width: 84, height: 7).position(x: 42, y: 71)
                ForEach(0..<7, id: \.self) { i in
                    Circle().fill(Color.white.opacity(0.9)).frame(width: 3, height: 3).position(x: CGFloat(i) * 14 - off + 4, y: 68.5)
                }
                ForEach(0..<3, id: \.self) { i in   // spray off the tail
                    Circle().fill(hex(0x90e0ef)).frame(width: 2.4, height: 2.4)
                        .position(x: 26 - CGFloat(i) * 4, y: 62 - CGFloat(i) * 2 + CGFloat(sin(p.s * 9 + Double(i))) * 1.5)
                }
            }
            ZStack {
                stitchEar(CGPoint(x: 41, y: 22), earB, len: 26, b)
                stitchEar(CGPoint(x: 59, y: 18), earF, len: 23, b)
                // back spines and the extra pair of arms, alien mode only
                if alien {
                    ForEach(0..<3, id: \.self) { i in
                        let y = 42 + CGFloat(i) * 6
                        Tri(a: CGPoint(x: 39, y: y - 2), b: CGPoint(x: 31 - CGFloat(i), y: y + 1), c: CGPoint(x: 39, y: y + 3)).fill(b.dark)
                    }
                    stitchArm(CGPoint(x: 44, y: 53), -60 + sin(gt * 20) * 25, len: 10, b)
                }
                stitchArm(CGPoint(x: 43, y: 45), armB, b)
                // back leg and foot
                Capsule().fill(b.fur).frame(width: 7, height: 10).rotationEffect(.degrees(-leg), anchor: .top).position(x: 45, y: 61)
                Ellipse().fill(b.dark.opacity(0.85)).frame(width: 9, height: 4.5)
                    .rotationEffect(.degrees(-leg), anchor: UnitPoint(x: 0.5, y: -1.6)).position(x: 46, y: 66)
                // body and tummy
                Ellipse().fill(b.fur).frame(width: 25, height: 21).scaleEffect(y: 1 + 0.02 * sin(p.s * 2.4), anchor: .bottom).position(x: 50, y: 51)
                Ellipse().fill(b.belly).frame(width: 14, height: 13).position(x: 54, y: 53)
                if hula {   // a lei round the neck
                    ForEach(0..<7, id: \.self) { i in
                        let x = 43 + CGFloat(i) * 3.3
                        Circle().fill([hex(0xff6fae), hex(0xffd84d), Color.white][i % 3]).frame(width: 4, height: 4)
                            .position(x: x, y: 42 + 2.5 * CGFloat(sin(Double(i) / 6 * .pi)))
                    }
                }
                // front leg and foot
                Capsule().fill(b.fur).frame(width: 7, height: 10).rotationEffect(.degrees(leg), anchor: .top).position(x: 55, y: 61)
                Ellipse().fill(b.dark.opacity(0.85)).frame(width: 9, height: 4.5)
                    .rotationEffect(.degrees(leg), anchor: UnitPoint(x: 0.5, y: -1.6)).position(x: 56, y: 66)
                if surf {   // the board, under both feet
                    Capsule().fill(hex(0xffb703)).frame(width: 40, height: 5).overlay(Capsule().fill(hex(0xe85d04)).frame(width: 36, height: 1.4))
                        .rotationEffect(.degrees(-5 + wave * 3)).position(x: 50, y: 69)
                }
                // head: big round head, lighter muzzle, tuft, eye patches, eyes, nose, mouth
                ZStack {
                    if alien {   // antennae
                        ForEach([(CGFloat(49), CGFloat(40)), (CGFloat(56), CGFloat(64))], id: \.0) { root, tip in
                            Path { c in c.move(to: CGPoint(x: root, y: 17)); c.addQuadCurve(to: CGPoint(x: tip, y: 4), control: CGPoint(x: (root + tip) / 2, y: 6)) }
                                .stroke(b.dark, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                            Circle().fill(b.dark).frame(width: 3.4, height: 3.4).position(x: tip, y: 4)
                        }
                    }
                    Ellipse().fill(b.fur).frame(width: 42, height: 28).position(x: 53, y: 29)
                    Ellipse().stroke(Color.black.opacity(0.15), lineWidth: 0.8).frame(width: 42, height: 28).position(x: 53, y: 29)
                    ForEach(0..<3, id: \.self) { i in
                        let x = 45 + CGFloat(i) * 3.5
                        Tri(a: CGPoint(x: x - 2, y: 17), b: CGPoint(x: x - 1 + CGFloat(i) * 0.5, y: 11 - CGFloat(i % 2) * 2), c: CGPoint(x: x + 2, y: 17)).fill(b.fur)
                    }
                    Ellipse().fill(b.belly).frame(width: 22, height: 12).position(x: 61, y: 36)
                    Ellipse().fill(b.mask ?? b.dark).frame(width: 12, height: 14).position(x: 55, y: 26)
                    Ellipse().fill(b.mask ?? b.dark).frame(width: 14, height: 15).position(x: 66.5, y: 25)
                    stitchFace(p, alien: alien, happy: happy)
                    Ellipse().fill(b.dark).frame(width: 13, height: 8.5).position(x: 72, y: 31.5)
                    Ellipse().fill(Color.white.opacity(0.35)).frame(width: 4.5, height: 2).position(x: 70, y: 29.5)
                }
                .rotationEffect(.degrees(p.asleep ? 8 : 0), anchor: UnitPoint(x: 52 / 84, y: 40 / 72))
                if hula {   // the ukulele across the tummy
                    ZStack {
                        Capsule().fill(hex(0x7a4a22)).frame(width: 2.6, height: 17).rotationEffect(.degrees(55)).position(x: 63, y: 46)
                        RoundedRectangle(cornerRadius: 1).fill(hex(0x5a3416)).frame(width: 4, height: 3).position(x: 70, y: 41)
                        Ellipse().fill(hex(0xc8894a)).frame(width: 12, height: 9.5).position(x: 54, y: 53)
                        Circle().fill(hex(0x3d2210)).frame(width: 3.2, height: 3.2).position(x: 55, y: 52.5)
                    }
                }
                if alien { stitchArm(CGPoint(x: 58, y: 53), 70 + sin(gt * 20 + 2) * 25, len: 10, b) }
                stitchArm(CGPoint(x: 58, y: 45), armF, b)
            }
            .rotationEffect(.degrees(st * 5 + (surf ? wave * 4 : 0)), anchor: .bottom)   // waddle; rock on the wave
            .offset(x: jitter, y: bob + (surf ? -3 : 0))
        }
        .frame(width: 84, height: 72)
    }

    /// Big black eyes with a shine; happy arcs, narrowed alien eyes, or closed lines. Below them a smile, or an open grin with teeth.
    @ViewBuilder func stitchFace(_ p: AvatarPose, alien: Bool, happy: Bool) -> some View {
        let e = p.b.eye
        let eyes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(55.5, 26, 7.5, 10), (66.5, 25, 9, 11.5)]   // x, y, w, h: the far eye smaller
        if p.asleep || p.blink {
            ForEach(eyes.indices, id: \.self) { i in
                let (x, y, w, _) = eyes[i]
                Path { c in c.move(to: CGPoint(x: x - w / 2, y: y)); c.addQuadCurve(to: CGPoint(x: x + w / 2, y: y), control: CGPoint(x: x, y: y + 2.5)) }
                    .stroke(e, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        } else if happy && !alien {
            ForEach(eyes.indices, id: \.self) { i in
                let (x, y, w, _) = eyes[i]
                Path { c in c.move(to: CGPoint(x: x - w / 2, y: y + 1.5)); c.addQuadCurve(to: CGPoint(x: x + w / 2, y: y + 1.5), control: CGPoint(x: x, y: y - 3.5)) }
                    .stroke(e, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        } else {
            ForEach(eyes.indices, id: \.self) { i in
                let (x, y, w, h) = eyes[i]
                Ellipse().fill(e).frame(width: w, height: alien ? h * 0.6 : h).position(x: x, y: alien ? y + h * 0.15 : y)
                Circle().fill(Color.white).frame(width: w * 0.35, height: w * 0.35).position(x: x + w * 0.15, y: y - h * (alien ? 0.05 : 0.2))
            }
            if alien {   // angry brows
                Path { c in c.move(to: CGPoint(x: 51, y: 20)); c.addLine(to: CGPoint(x: 59, y: 23)); c.move(to: CGPoint(x: 62, y: 21.5)); c.addLine(to: CGPoint(x: 71, y: 19)) }
                    .stroke(p.b.dark, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
        if alien || happy {
            Path { c in
                c.move(to: CGPoint(x: 54, y: 36.5)); c.addLine(to: CGPoint(x: 72, y: 35.5))
                c.addQuadCurve(to: CGPoint(x: 54, y: 36.5), control: CGPoint(x: 63, y: alien ? 47 : 44))
            }.fill(hex(0x5a1a2a))
            Capsule().fill(Color.white).frame(width: 15, height: 2.4).position(x: 63, y: 37)   // top teeth
            Ellipse().fill(hex(0xff7a9a)).frame(width: 7, height: 3).position(x: 63, y: alien ? 42.5 : 40.5)
        } else {
            Path { c in c.move(to: CGPoint(x: 55, y: 37)); c.addQuadCurve(to: CGPoint(x: 71, y: 36), control: CGPoint(x: 63, y: 41)) }
                .stroke(e, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
    }
}
