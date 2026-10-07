import AppKit
import SwiftUI

// MARK: the robot: a friendly little robot (an original design), boxy head with a screen face, antenna light, a dial on its chest.
// Stiff little steps. Dances the robot on good news, short-circuits (sparks, "bzzt") at a red PR.
// Coat colours: fur = shell, dark = arms, legs and feet, belly = screen, eye = eyes on the screen, points = antenna light and dial,
// mask = screen bezel.

let robotBuddy = PetKind(
    name: "robot", emoji: "🤖", hello: "🤖", coats: robotShells,
    tricks: [.shimmy, .shimmy, .sneeze, .stretch, .spin, .hop],
    onRed: .sneeze, onMerge: .shimmy, biped: true,
    bursts: [.shimmy: ["beep boop!", "🎵"], .sneeze: ["bzzt", "⚡"], .stretch: ["vrrr"], .spin: ["whirr"]],
    sceneEars: { _, _, _ in })

let robotShells: [Breed] = [
    Breed(name: "Teal robot", fur: hex(0x2a9d8f), dark: hex(0x264653), belly: hex(0x12302d), eye: hex(0x7ff5e6), points: hex(0xf4a261), mask: hex(0x1b4a44)),
    Breed(name: "Orange robot", fur: hex(0xf28c28), dark: hex(0x4a4e57), belly: hex(0x1d1f2b), eye: hex(0x9cf27a), points: hex(0xe63946), mask: hex(0x8a4a10)),
    Breed(name: "Silver robot", fur: hex(0xb8c0cc), dark: hex(0x5b6472), belly: hex(0x1b2a41), eye: hex(0x6ec6ff), points: hex(0xff5d5d), mask: hex(0x6b7480)),
    Breed(name: "Mint robot", fur: hex(0x8fdcb9), dark: hex(0x3d6b5c), belly: hex(0xf3fff8), eye: hex(0x24433a), points: hex(0xff7aa2), mask: hex(0x4f8f76)),
    Breed(name: "Cherry robot", fur: hex(0xd23c50), dark: hex(0x3b2230), belly: hex(0x2a1a24), eye: hex(0xffd166), points: hex(0xffd166), mask: hex(0x7d1f2e)),
]

extension Cat {
    /// One bendy arm from `sh`: a 10 pt upper arm at angle `a1`, an 8 pt forearm at `a2` (degrees from straight down, + = forward),
    /// with `rod` points of shiny piston between them (the stretch).
    func robotArm(_ sh: CGPoint, _ a1: Double, _ a2: Double, rod: CGFloat, _ b: Breed) -> some View {
        let r1 = a1 * .pi / 180, r2 = a2 * .pi / 180
        let e = CGPoint(x: sh.x + 10 * CGFloat(sin(r1)), y: sh.y + 10 * CGFloat(cos(r1)))
        let pe = CGPoint(x: e.x + rod * CGFloat(sin(r1)), y: e.y + rod * CGFloat(cos(r1)))
        let h = CGPoint(x: pe.x + 8 * CGFloat(sin(r2)), y: pe.y + 8 * CGFloat(cos(r2)))
        return ZStack {
            if rod > 0.3 { Path { c in c.move(to: e); c.addLine(to: pe) }.stroke(hex(0xd9dee5), style: StrokeStyle(lineWidth: 2, lineCap: .round)) }
            Path { c in c.move(to: sh); c.addLine(to: e) }.stroke(b.dark, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            Path { c in c.move(to: pe); c.addLine(to: h) }.stroke(b.dark, style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
            Circle().fill(b.fur).frame(width: 3.6, height: 3.6).position(pe)   // elbow joint
            Circle().fill(b.dark).frame(width: 5.4, height: 5.4).position(h)   // hand
        }
    }

    func robotAvatar(_ p: AvatarPose) -> some View {
        let b = p.b, g = p.g, gt = p.gt
        let st = max(-1, min(1, p.step * 2.5))   // clipped: a stiff, mechanical step
        let dancing = g == .shimmy && gt < 2.4
        let phase = dancing ? Int(gt / 0.45) % 4 : 0   // each pose holds long enough to register
        let k = g == .stretch ? sin(min(gt / 2.4, 1) * .pi) : 0
        // the short circuit starts with the "bzzt" (bursts fire at gt = 0), then a dazed shake
        let sneezing = g == .sneeze && gt < 2.0, zapped = sneezing && gt > 0.05 && gt < 1.0, dazed = sneezing && gt >= 1.0 && gt < 1.5
        let spinning = g == .spin && gt < 1.6
        let spinCos = spinning ? cos(gt / 1.6 * 4 * .pi) : 1
        let neck = CGFloat(4 * k)   // the head rises on its neck piston in a stretch
        let dim = p.asleep
        let light = !dim && (zapped ? Int(gt * 20) % 2 == 0 : sin(p.s * 3) > -0.8)

        // arms: (upper angle, forearm angle) for back and front
        var back = (a1: -10.0, a2: -4.0), front = (a1: 12.0, a2: 30.0)
        if dancing {
            switch phase {
            case 0: front = (90, 180); back = (-90, 0)
            case 2: front = (90, 0); back = (-90, -180)
            default: front = (5, 90); back = (-5, 90)
            }
        } else if k > 0 { front = (12 + 118 * k, 12 + 118 * k); back = (-10 - 120 * k, -10 - 120 * k) }
        else if zapped { let j = Double(Int(gt * 14) % 2) * 30; front = (60 + j, 120 - j); back = (-60 - j, -120 + j) }
        else if p.step != 0 { front = (10 + 26 * max(0, -st), 28 + 26 * max(0, -st)); back = (-10 - 26 * max(0, st), -4 - 26 * max(0, st)) }   // swing out, never across the body
        else if p.asleep { front = (3, 6); back = (-3, -2) }

        // feet: which one lifts (walk, or in time with the dance)
        let liftF: CGFloat = dancing ? (phase % 2 == 1 ? 3 : 0) : CGFloat(max(0, st)) * 3
        let liftB: CGFloat = dancing ? (phase == 2 ? 3 : 0) : CGFloat(max(0, -st)) * 3
        let footY: CGFloat = 66
        let jitter: CGFloat = dazed ? CGFloat(sin(gt * 70)) * 0.8 : 0
        let headX: CGFloat = dancing ? (phase % 2 == 0 ? 1 : -1) : 0

        return ZStack {
            // back arm, back leg and foot
            robotArm(CGPoint(x: 39.5, y: 41), back.a1, back.a2, rod: CGFloat(9 * k), b)
            RoundedRectangle(cornerRadius: 1.5).fill(b.dark).frame(width: 4, height: footY - 57 - liftB).position(x: 42, y: 57 + (footY - 57 - liftB) / 2)
            RoundedRectangle(cornerRadius: 2).fill(b.dark).frame(width: 9, height: 4.5).position(x: 43 + liftB / 2, y: footY - liftB)
            // body: rounded shell, dial, two buttons
            RoundedRectangle(cornerRadius: 7).fill(b.fur).frame(width: 24, height: 21).position(x: 50, y: 47)
            RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.18), lineWidth: 1).frame(width: 24, height: 21).position(x: 50, y: 47)
            Circle().fill(b.points ?? kurtaGold).frame(width: 9, height: 9).overlay(Circle().stroke(b.dark, lineWidth: 1.2)).position(x: 51, y: 45)
            Capsule().fill(b.dark).frame(width: 1.4, height: 4)
                .rotationEffect(.degrees(zapped ? gt * 900 : dancing ? Double(phase) * 90 : sin(p.s * 2) * 40), anchor: .bottom)
                .position(x: 51, y: 43)
            ForEach([46.0, 51.0, 56.0], id: \.self) { x in
                Capsule().fill(b.dark.opacity(0.55)).frame(width: 3, height: 1.4).position(x: x, y: 53)
            }
            // front leg and foot
            RoundedRectangle(cornerRadius: 1.5).fill(b.dark).frame(width: 4, height: footY - 57 - liftF).position(x: 58, y: 57 + (footY - 57 - liftF) / 2)
            RoundedRectangle(cornerRadius: 2).fill(b.dark).frame(width: 9, height: 4.5).position(x: 59 + liftF / 2, y: footY - liftF)
            // neck (a piston that shows in a stretch)
            Rectangle().fill(neck > 0.3 ? hex(0xd9dee5) : b.dark).frame(width: 5, height: 4 + neck).position(x: 51, y: 36.5 - neck / 2)
            // head: antenna, shell, screen, face
            ZStack {
                Path { c in c.move(to: CGPoint(x: 50, y: 13)); c.addLine(to: CGPoint(x: 50, y: 6)) }.stroke(b.dark, lineWidth: 1.6)
                Circle().fill(light ? (b.points ?? kurtaGold) : b.dark.opacity(0.7)).frame(width: 5, height: 5).position(x: 50, y: 4.5)
                if light { Circle().fill(Color.white.opacity(0.7)).frame(width: 1.6, height: 1.6).position(x: 49.2, y: 3.8) }
                RoundedRectangle(cornerRadius: 5).fill(b.fur).frame(width: 28, height: 22).position(x: 52, y: 23)
                RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.18), lineWidth: 1).frame(width: 28, height: 22).position(x: 52, y: 23)
                if spinCos >= 0 {
                    Circle().fill(b.dark).frame(width: 4, height: 4).position(x: 39, y: 23)   // ear bolt
                    RoundedRectangle(cornerRadius: 3.5).fill(b.mask ?? b.dark).frame(width: 21, height: 16).position(x: 55, y: 23)
                    RoundedRectangle(cornerRadius: 2.5).fill(dim ? b.belly.opacity(0.35) : b.belly).frame(width: 18, height: 13).position(x: 55, y: 23)
                    robotFace(p, zapped: zapped, squint: dazed)
                } else {   // the back of the head: a vent
                    ForEach([18.0, 22.0, 26.0], id: \.self) { y in
                        Capsule().fill(b.dark.opacity(0.6)).frame(width: 14, height: 1.6).position(x: 52, y: y)
                    }
                }
            }
            .scaleEffect(x: spinCos, y: 1, anchor: UnitPoint(x: 52 / 84, y: 0.3))
            .rotationEffect(.degrees(p.asleep ? 7 : 0), anchor: UnitPoint(x: 51 / 84, y: 34 / 72))
            .offset(x: headX + jitter, y: -neck)
            // front arm, over the body
            robotArm(CGPoint(x: 60.5, y: 41), front.a1, front.a2, rod: CGFloat(9 * k), b)
            // sparks round the head when it short-circuits
            if zapped {
                let f = Int(gt * 12)
                ForEach(0..<4, id: \.self) { i in
                    let pts: [(CGFloat, CGFloat)] = [(34, 10), (70, 8), (73, 30), (32, 34), (66, 2), (36, 20)]
                    let (x, y) = pts[(i + f) % pts.count]
                    Path { c in
                        c.move(to: CGPoint(x: x - 3, y: y - 4)); c.addLine(to: CGPoint(x: x + 1, y: y - 1))
                        c.addLine(to: CGPoint(x: x - 1, y: y + 1)); c.addLine(to: CGPoint(x: x + 3, y: y + 4))
                    }.stroke(hex(0xffd84d), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: 84, height: 72)
        // Pet.swift turns every pet's whole body in a .spin and squashes it in a .stretch. Undo both here, in the same box
        // about the same anchors, so the robot spins only its head and stretches only on its pistons.
        .scaleEffect(x: 1 / (1 + 0.24 * k), y: 1 / (1 - 0.16 * k), anchor: .bottom)
        .rotationEffect(.degrees(g == .spin && gt < 1 ? -gt * 360 : 0))
    }

    /// Two glowing eyes and a little mouth on the screen; X eyes and static when zapped, flat lines asleep or blinking.
    @ViewBuilder func robotFace(_ p: AvatarPose, zapped: Bool, squint: Bool) -> some View {
        let e = p.b.eye
        if zapped {
            ForEach([50.5, 59.5], id: \.self) { x in
                Path { c in
                    c.move(to: CGPoint(x: x - 2, y: 19.5)); c.addLine(to: CGPoint(x: x + 2, y: 23.5))
                    c.move(to: CGPoint(x: x + 2, y: 19.5)); c.addLine(to: CGPoint(x: x - 2, y: 23.5))
                }.stroke(e, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(e.opacity(0.35)).frame(width: 7 + CGFloat((Int(p.gt * 15) + i * 3) % 7), height: 0.8)
                    .position(x: 55, y: 18 + CGFloat(i) * 5 + CGFloat(Int(p.gt * 15) % 3))
            }
        } else if p.asleep || p.blink || squint {
            ForEach([50.5, 59.5], id: \.self) { x in
                Capsule().fill(e.opacity(p.asleep ? 0.6 : 1)).frame(width: 4.5, height: 1.4).position(x: x, y: 22)
            }
        } else {
            ForEach([50.5, 59.5], id: \.self) { x in
                RoundedRectangle(cornerRadius: 1.2).fill(e).frame(width: 3.6, height: 5).position(x: x, y: 21.5)
            }
            Path { c in c.move(to: CGPoint(x: 52, y: 26.5)); c.addQuadCurve(to: CGPoint(x: 58, y: 26.5), control: CGPoint(x: 55, y: 29)) }
                .stroke(e, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }
}
