import AppKit
import SwiftUI

// MARK: the cat: seven coats, a long tail, pointed ears

let catPet = PetKind(
    name: "cat", emoji: "🐱", hello: "😼", coats: catBreeds,
    tricks: [.stretch, .yawn, .spin, .wash, .loaf, .sneeze, .zoomies, .knock, .hop],
    tail: { b, wag, asleep in AnyView(TailShape(curl: asleep ? 1 : 0)
        .stroke(b.points ?? b.fur, style: StrokeStyle(lineWidth: 7, lineCap: .round))
        .rotationEffect(.degrees(wag), anchor: UnitPoint(x: 20 / 84, y: 50 / 72))) },
    head: { c, s, blink, asleep, look in AnyView(c.catHead(blink: blink, asleep: asleep, look: look)) },
    kittenEars: { b in AnyView(ZStack {
        Tri(a: CGPoint(x: 6, y: 12), b: CGPoint(x: 7, y: 2), c: CGPoint(x: 13, y: 8)).fill(b.points ?? b.fur)
        Tri(a: CGPoint(x: 17, y: 8), b: CGPoint(x: 23, y: 2), c: CGPoint(x: 24, y: 12)).fill(b.points ?? b.fur)
    }) },
    kittenFace: { _ in AnyView(EmptyView()) },
    sceneEars: { c, fur, _ in
        var ears = Path()
        ears.move(to: CGPoint(x: 3, y: -25)); ears.addLine(to: CGPoint(x: 4, y: -32)); ears.addLine(to: CGPoint(x: 9, y: -28)); ears.closeSubpath()
        ears.move(to: CGPoint(x: 15, y: -25)); ears.addLine(to: CGPoint(x: 14, y: -32)); ears.addLine(to: CGPoint(x: 9, y: -28)); ears.closeSubpath()
        c.fill(ears, with: .color(fur))
    })

let catBreeds: [Breed] = [
    Breed(name: "Ginger tabby", fur: rgb(227, 140, 92), dark: rgb(184, 102, 64), belly: rgb(250, 226, 205), stripes: true),
    Breed(name: "Tuxedo", fur: rgb(38, 38, 44), dark: rgb(20, 20, 24), belly: .white, eye: rgb(170, 220, 90)),
    Breed(name: "Snowball", fur: rgb(246, 244, 240), dark: rgb(214, 210, 204), belly: .white, eye: rgb(70, 140, 220)),
    Breed(name: "Russian Blue", fur: rgb(132, 146, 166), dark: rgb(100, 112, 130), belly: rgb(170, 182, 200), eye: rgb(120, 200, 110)),
    Breed(name: "Siamese", fur: rgb(240, 226, 204), dark: rgb(205, 190, 168), belly: rgb(252, 245, 232), eye: rgb(60, 130, 220), points: rgb(92, 64, 50)),
    Breed(name: "Calico", fur: rgb(250, 247, 240), dark: rgb(220, 214, 204), belly: .white, patch: [rgb(222, 130, 60), rgb(48, 40, 38)]),
    Breed(name: "Midnight", fur: rgb(22, 22, 28), dark: rgb(10, 10, 14), belly: rgb(40, 40, 48), eye: rgb(250, 205, 60)),
]

extension Cat {
    @ViewBuilder func catHead(blink: Bool, asleep: Bool, look: CGSize) -> some View {
        ZStack {
            Tri(a: CGPoint(x: 45, y: 24), b: CGPoint(x: 47, y: 6), c: CGPoint(x: 58, y: 18)).fill(b.fur)
            Tri(a: CGPoint(x: 62, y: 17), b: CGPoint(x: 73, y: 5), c: CGPoint(x: 74, y: 24)).fill(b.fur)
            Tri(a: CGPoint(x: 48, y: 20), b: CGPoint(x: 49, y: 11), c: CGPoint(x: 55, y: 17)).fill(Color.pink.opacity(0.7))
            Tri(a: CGPoint(x: 65, y: 16), b: CGPoint(x: 71, y: 10), c: CGPoint(x: 71, y: 20)).fill(Color.pink.opacity(0.7))
            Circle().fill(b.fur).frame(width: 38, height: 36).position(x: 60, y: 32)
            if let pt = b.points {
                Ellipse().fill(pt.opacity(0.85)).frame(width: 22, height: 18).position(x: 60, y: 38)
                Tri(a: CGPoint(x: 46, y: 22), b: CGPoint(x: 47, y: 7), c: CGPoint(x: 56, y: 17)).fill(pt)
                Tri(a: CGPoint(x: 64, y: 17), b: CGPoint(x: 73, y: 6), c: CGPoint(x: 73, y: 22)).fill(pt)
            }
            if b.patch.count == 2 { Circle().fill(b.patch[0]).frame(width: 16).position(x: 69, y: 24).clipShape(Circle().size(width: 84, height: 72)) }
            if b.name == "Tuxedo" { Ellipse().fill(Color.white).frame(width: 16, height: 12).position(x: 60, y: 42) }
            Capsule().fill(b.dark).frame(width: 3, height: 8).position(x: 60, y: 18)
            if m.hovering && mood != .upset {
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 47, y: 38)
                Circle().fill(Color.pink.opacity(0.5)).frame(width: 7).position(x: 73, y: 38)
            }
            eyes(blink: blink, asleep: asleep, look: look)
            Tri(a: CGPoint(x: 58, y: 37), b: CGPoint(x: 62, y: 37), c: CGPoint(x: 60, y: 40)).fill(Color.pink)
            mouth
            Path { p in
                for (y, dy) in [(39.0, -2.0), (42.0, 1.0)] {
                    p.move(to: CGPoint(x: 48, y: y)); p.addLine(to: CGPoint(x: 38, y: y + dy))
                    p.move(to: CGPoint(x: 72, y: y)); p.addLine(to: CGPoint(x: 82, y: y + dy))
                }
            }.stroke(faceInk.opacity(0.35), lineWidth: 0.8)
        }
    }
}
