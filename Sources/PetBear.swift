import AppKit
import SwiftUI

// MARK: the bear, by Siddharth Sahu: round ears, a stub tail, and its own tricks. It roars at red PRs and catches a salmon on good news.

let bearPet = PetKind(
    name: "bear", emoji: "🐻", hello: "🐻", coats: bearCoats,
    tricks: [.stretch, .yawn, .loaf, .sneeze, .zoomies, .hop, .roar, .roar, .honey, .fish, .scratch],
    onRed: .roar, onMerge: .fish, chunky: true,
    sceneEars: { c, fur, _ in
        c.fill(Path(ellipseIn: CGRect(x: 1, y: -31, width: 6, height: 6)), with: .color(fur))
        c.fill(Path(ellipseIn: CGRect(x: 11, y: -31, width: 6, height: 6)), with: .color(fur))
    })

/// Bears reuse `points` for panda black (ears, legs, eye patches).
let bearCoats: [Breed] = [
    Breed(name: "Grizzly", fur: rgb(140, 98, 66), dark: rgb(96, 64, 42), belly: rgb(196, 160, 120)),
    Breed(name: "Black bear", fur: rgb(36, 32, 32), dark: rgb(18, 16, 16), belly: rgb(170, 130, 96), eye: rgb(150, 100, 60)),
    Breed(name: "Polar bear", fur: rgb(246, 244, 236), dark: rgb(214, 210, 198), belly: rgb(255, 253, 246)),
    Breed(name: "Panda", fur: rgb(248, 248, 244), dark: rgb(214, 214, 210), belly: .white, points: rgb(28, 28, 30)),
]

func bearKittenEars(_ b: Breed) -> some View {
    ForEach([7.0, 23.0], id: \.self) { x in Circle().fill(b.points ?? b.fur).frame(width: 8, height: 8).position(x: x, y: 9) }
}
func bearKittenFace(_ b: Breed) -> some View { Ellipse().fill(b.belly).frame(width: 10, height: 7).position(x: 15, y: 21) }

extension Cat {
    func bearTail(wag: Double) -> some View {   // a stub
        Circle().fill(b.points ?? b.dark).frame(width: 9, height: 9).position(x: 13, y: 46 + wag * 0.08)
    }

    /// A bear: round ears, broad head, pale muzzle, big nose. Panda: black ears and eye patches.
    @ViewBuilder func bearHead(s: Double, blink: Bool, asleep: Bool, look: CGSize) -> some View {
        let ear = b.points ?? b.fur
        ZStack {
            ForEach([45.0, 75.0], id: \.self) { x in
                Circle().fill(ear).frame(width: 15, height: 15).position(x: x, y: 17)
                Circle().fill(b.points == nil ? b.dark : ear).frame(width: 7, height: 7).position(x: x, y: 18)
            }
            Ellipse().fill(b.fur).frame(width: 42, height: 37).position(x: 60, y: 32)
            if let pt = b.points {
                Ellipse().fill(pt).frame(width: 11, height: 13).rotationEffect(.degrees(-25)).position(x: 52, y: 31)
                Ellipse().fill(pt).frame(width: 11, height: 13).rotationEffect(.degrees(25)).position(x: 68, y: 31)
            }
            Ellipse().fill(b.belly).frame(width: 20, height: 14).position(x: 60, y: 41)
            if m.hovering && mood != .upset {
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 45, y: 38)
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 75, y: 38)
            }
            if b.points != nil && !asleep && !blink {
                // panda eyes sit inside the patches, so draw them light
                ForEach([53.0, 67.0], id: \.self) { x in Circle().fill(Color.white).frame(width: 4.5).overlay(Circle().fill(ink).frame(width: 2.5)).position(x: x, y: 31).offset(look) }
            } else {
                eyes(blink: blink, asleep: asleep, look: look)
            }
            Ellipse().fill(ink).frame(width: 9, height: 6).position(x: 60, y: 37)
            Capsule().fill(Color.white.opacity(0.5)).frame(width: 3, height: 1.2).position(x: 58, y: 35.6)
            if m.gesture == .roar {
                // jaws wide, two fangs
                Ellipse().fill(ink).overlay(Ellipse().fill(Color(red: 0.85, green: 0.35, blue: 0.4)).frame(width: 7, height: 4).offset(y: 3))
                    .frame(width: 12, height: 11).position(x: 60, y: 46)
                Tri(a: CGPoint(x: 55.5, y: 41.5), b: CGPoint(x: 58, y: 41.5), c: CGPoint(x: 56.8, y: 45)).fill(Color.white)
                Tri(a: CGPoint(x: 62, y: 41.5), b: CGPoint(x: 64.5, y: 41.5), c: CGPoint(x: 63.2, y: 45)).fill(Color.white)
            } else if m.gesture == .honey {
                Text("🍯").font(.system(size: 12)).position(x: 72, y: 50 + sin(s * 10) * 1.5)
                Capsule().fill(Color(red: 0.95, green: 0.45, blue: 0.55)).frame(width: 5, height: 5 + abs(sin(s * 10)) * 3).position(x: 61, y: 45)
            } else if m.gesture == .fish {
                // a paw swipes up through the river
                let gt = Date().timeIntervalSince(m.gestureAt)
                Ellipse().fill(b.points ?? b.dark).frame(width: 11, height: 9)
                    .position(x: 76, y: 58 - 22 * sin(min(gt / 0.9, 1) * .pi))
                moodMouth
            } else {
                mouth
            }
        }
    }

    /// Props for what Bit is saying: glasses for quotes, paw-on-chin for questions, trophy, flex, and a crown while #1.
    @ViewBuilder var poseLayer: some View {
        ZStack {
            if m.stats.rank == 1 && m.mood != .asleep {
                Text("👑").font(.system(size: 13, design: .rounded)).position(x: 60, y: 6)
            }
            switch m.pose {
            case .glasses where !drip:
                Group {
                    Circle().stroke(ink, lineWidth: 1.6).frame(width: 11, height: 11).position(x: 53, y: 31)
                    Circle().stroke(ink, lineWidth: 1.6).frame(width: 11, height: 11).position(x: 67, y: 31)
                    Path { p in p.move(to: CGPoint(x: 58.5, y: 30)); p.addLine(to: CGPoint(x: 61.5, y: 30)) }.stroke(ink, lineWidth: 1.4)
                }
            case .thinking:
                Ellipse().fill(b.dark).frame(width: 9, height: 7).position(x: 64, y: 50)
            case .trophy:
                Text("🏆").font(.system(size: 14, design: .rounded)).position(x: 80, y: 46)
            case .flex:
                Text("💪").font(.system(size: 14, design: .rounded)).position(x: 82, y: 40)
            case .none, .glasses:
                EmptyView()
            }
        }
    }

    @ViewBuilder var mouth: some View {
        if m.gesture == .yawn {
            Ellipse().fill(ink).overlay(Ellipse().fill(Color.pink).frame(width: 4, height: 3).offset(y: 2)).frame(width: 7, height: 9).position(x: 60, y: 45)
        } else if m.gesture == .wash {
            TimelineView(.animation) { t in
                Ellipse().fill(b.points ?? b.fur).overlay(Ellipse().stroke(b.dark, lineWidth: 1))
                    .frame(width: 10, height: 8).position(x: 61, y: 44 + sin((frozenTime ?? t.date.timeIntervalSinceReferenceDate) * 14) * 2)
            }
        } else {
            moodMouth
        }
    }

    @ViewBuilder var moodMouth: some View {
        switch mood {
        case .upset:
            Circle().trim(from: 0.55, to: 0.95).stroke(ink.opacity(0.7), lineWidth: 1.6).frame(width: 9, height: 9).position(x: 60, y: 46)
        case .happy:
            Circle().trim(from: 0.05, to: 0.45).fill(ink.opacity(0.8)).frame(width: 10, height: 10).position(x: 60, y: 39)
        case .waiting:
            Circle().stroke(ink.opacity(0.7), lineWidth: 1.4).frame(width: 4, height: 4).position(x: 60, y: 44)
        default:
            Path { p in
                p.move(to: CGPoint(x: 56, y: 41)); p.addQuadCurve(to: CGPoint(x: 60, y: 41), control: CGPoint(x: 58, y: 44))
                p.addQuadCurve(to: CGPoint(x: 64, y: 41), control: CGPoint(x: 62, y: 44))
            }.stroke(faceInk.opacity(0.7), lineWidth: 1.3)
        }
    }
}
