import AppKit
import SwiftUI

// MARK: the pug: folded ears, a black mask, a curly tail, and (unless "outfit": "none") a tracksuit and shades. It dances.

let pugPet = PetKind(
    name: "pug", emoji: "🐶", hello: "🐶", coats: pugCoats,
    tricks: [.stretch, .yawn, .spin, .wash, .loaf, .sneeze, .zoomies, .knock, .hop],
    outfit: true, dances: true,
    sceneEars: { c, _, dark in
        c.fill(Path(ellipseIn: CGRect(x: 0, y: -28, width: 5, height: 8)), with: .color(dark))
        c.fill(Path(ellipseIn: CGRect(x: 13, y: -28, width: 5, height: 8)), with: .color(dark))
    })

let pugCoats: [Breed] = [
    Breed(name: "Fawn pug", fur: rgb(226, 190, 140), dark: rgb(70, 56, 48), belly: rgb(240, 214, 176), mask: rgb(40, 32, 30)),
    Breed(name: "Black pug", fur: rgb(40, 38, 40), dark: rgb(18, 18, 20), belly: rgb(58, 56, 58), eye: rgb(120, 80, 50), mask: rgb(14, 14, 16)),
    Breed(name: "Apricot pug", fur: rgb(222, 162, 100), dark: rgb(80, 54, 40), belly: rgb(240, 200, 150), mask: rgb(44, 32, 28)),
    Breed(name: "Silver pug", fur: rgb(200, 196, 188), dark: rgb(70, 68, 66), belly: rgb(226, 222, 214), mask: rgb(36, 34, 34)),
]

@ViewBuilder func pugKittenFace(_ b: Breed) -> some View {
    if let mk = b.mask {
        Tri(a: CGPoint(x: 4, y: 11), b: CGPoint(x: 10, y: 9), c: CGPoint(x: 6, y: 18)).fill(mk)
        Tri(a: CGPoint(x: 20, y: 9), b: CGPoint(x: 26, y: 11), c: CGPoint(x: 24, y: 18)).fill(mk)
        Ellipse().fill(mk).frame(width: 11, height: 8).position(x: 15, y: 21)
    }
}

extension Cat {
    func pugTail(wag: Double) -> some View {
        Circle().trim(from: 0, to: 0.8).stroke(b.fur, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: 11, height: 11).rotationEffect(.degrees(wag * 2)).position(x: 13, y: 40)
    }

    /// A pug: round head, folded black ears, black mask, forehead wrinkles, flat nose.
    @ViewBuilder func pugHead(blink: Bool, asleep: Bool, look: CGSize) -> some View {
        let mask = b.mask ?? ink
        ZStack {
            Ellipse().fill(b.fur).frame(width: 42, height: 36).position(x: 60, y: 32)
            Tri(a: CGPoint(x: 41, y: 18), b: CGPoint(x: 51, y: 14), c: CGPoint(x: 43, y: 29)).fill(mask)
            Tri(a: CGPoint(x: 69, y: 14), b: CGPoint(x: 79, y: 18), c: CGPoint(x: 77, y: 29)).fill(mask)
            ForEach(0..<2) { i in
                Path { p in p.move(to: CGPoint(x: 54, y: 21 + CGFloat(i) * 3)); p.addQuadCurve(to: CGPoint(x: 66, y: 21 + CGFloat(i) * 3), control: CGPoint(x: 60, y: 18 + CGFloat(i) * 3)) }
                    .stroke(mask.opacity(0.55), lineWidth: 1.1)
            }
            Ellipse().fill(mask).frame(width: 24, height: 17).position(x: 60, y: 40)
            if m.hovering && mood != .upset {
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 46, y: 37)
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 74, y: 37)
            }
            if drip && !asleep {
                ForEach([52.5, 67.5], id: \.self) { x in
                    RoundedRectangle(cornerRadius: 3.5).fill(Color.black).frame(width: 13, height: 9).position(x: x, y: 31)
                    Capsule().fill(Color.white.opacity(0.55)).frame(width: 4, height: 1.3).rotationEffect(.degrees(-25)).position(x: x - 2.5, y: 29)
                }
                Capsule().fill(Color.black).frame(width: 5, height: 1.8).position(x: 60, y: 29.5)
            } else {
                eyes(blink: blink, asleep: asleep, look: look)
            }
            Ellipse().fill(Color.black).frame(width: 9, height: 5).position(x: 60, y: 37)
            if mood == .happy || m.hovering {
                Capsule().fill(Color(red: 0.95, green: 0.45, blue: 0.55)).frame(width: 5, height: 7).position(x: 61, y: 46)   // tongue out
            }
            mouth
        }
    }
}
