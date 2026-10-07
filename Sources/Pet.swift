import AppKit
import SwiftUI

// MARK: the cat

extension Mood {
    var color: Color {
        switch self {
        case .asleep: return Color(red: 0.55, green: 0.58, blue: 0.66)
        case .calm: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .busy: return Color(red: 0.36, green: 0.62, blue: 0.98)
        case .waiting: return Color(red: 0.96, green: 0.72, blue: 0.27)
        case .upset: return Color(red: 0.94, green: 0.33, blue: 0.33)
        case .happy: return Color(red: 0.36, green: 0.82, blue: 0.55)
        }
    }
    var word: String {
        switch self {
        case .asleep: return "napping"
        case .calm: return "chilling"
        case .busy: return "watching your sessions"
        case .waiting: return "waiting on you"
        case .upset: return "worried"
        case .happy: return "happy"
        }
    }
}

let fur = Color(red: 0.89, green: 0.55, blue: 0.36)
let claudeColor = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)   // Anthropic clay
let codexColor = Color(red: 16 / 255, green: 163 / 255, blue: 127 / 255)    // OpenAI green

let furDark = Color(red: 0.72, green: 0.40, blue: 0.25)
let ink = Color(red: 0.16, green: 0.11, blue: 0.10)

struct Breed {
    var name: String
    var fur: Color, dark: Color, belly: Color
    var eye: Color = ink
    var points: Color? = nil      // siamese: darker ears, mask, tail, paws
    var patch: [Color] = []       // calico patches
    var stripes = false
    var mask: Color? = nil        // pug: black face
}
func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
let pugCoats: [Breed] = [
    Breed(name: "Fawn pug", fur: rgb(226, 190, 140), dark: rgb(70, 56, 48), belly: rgb(240, 214, 176), mask: rgb(40, 32, 30)),
    Breed(name: "Black pug", fur: rgb(40, 38, 40), dark: rgb(18, 18, 20), belly: rgb(58, 56, 58), eye: rgb(120, 80, 50), mask: rgb(14, 14, 16)),
    Breed(name: "Apricot pug", fur: rgb(222, 162, 100), dark: rgb(80, 54, 40), belly: rgb(240, 200, 150), mask: rgb(44, 32, 28)),
    Breed(name: "Silver pug", fur: rgb(200, 196, 188), dark: rgb(70, 68, 66), belly: rgb(226, 222, 214), mask: rgb(36, 34, 34)),
]
let catBreeds: [Breed] = [
    Breed(name: "Ginger tabby", fur: rgb(227, 140, 92), dark: rgb(184, 102, 64), belly: rgb(250, 226, 205), stripes: true),
    Breed(name: "Tuxedo", fur: rgb(38, 38, 44), dark: rgb(20, 20, 24), belly: .white, eye: rgb(170, 220, 90)),
    Breed(name: "Snowball", fur: rgb(246, 244, 240), dark: rgb(214, 210, 204), belly: .white, eye: rgb(70, 140, 220)),
    Breed(name: "Russian Blue", fur: rgb(132, 146, 166), dark: rgb(100, 112, 130), belly: rgb(170, 182, 200), eye: rgb(120, 200, 110)),
    Breed(name: "Siamese", fur: rgb(240, 226, 204), dark: rgb(205, 190, 168), belly: rgb(252, 245, 232), eye: rgb(60, 130, 220), points: rgb(92, 64, 50)),
    Breed(name: "Calico", fur: rgb(250, 247, 240), dark: rgb(220, 214, 204), belly: .white, patch: [rgb(222, 130, 60), rgb(48, 40, 38)]),
    Breed(name: "Midnight", fur: rgb(22, 22, 28), dark: rgb(10, 10, 14), belly: rgb(40, 40, 48), eye: rgb(250, 205, 60)),
]

/// Bears reuse `points` for panda black (ears, legs, eye patches).
let bearCoats: [Breed] = [
    Breed(name: "Grizzly", fur: rgb(140, 98, 66), dark: rgb(96, 64, 42), belly: rgb(196, 160, 120)),
    Breed(name: "Black bear", fur: rgb(36, 32, 32), dark: rgb(18, 16, 16), belly: rgb(170, 130, 96), eye: rgb(150, 100, 60)),
    Breed(name: "Polar bear", fur: rgb(246, 244, 236), dark: rgb(214, 210, 198), belly: rgb(255, 253, 246)),
    Breed(name: "Panda", fur: rgb(248, 248, 244), dark: rgb(214, 214, 210), belly: .white, points: rgb(28, 28, 30)),
]

// after all three arrays: top-level globals initialise in file order
var breeds: [Breed] { isBear ? bearCoats : isPug ? pugCoats : catBreeds }

enum Gesture: CaseIterable { case none, stretch, yawn, spin, wash, loaf, sneeze, zoomies, knock, hop, shimmy, roar, honey, fish, scratch }

struct Particle: Identifiable { let id = UUID(); let glyph: String; let dx: CGFloat; var fall = false }

struct FloatUp: View {
    let p: Particle
    @State private var gone = false
    var body: some View {
        Text(p.glyph).font(.system(size: p.glyph.count > 2 ? 11 : 14, weight: .heavy, design: .rounded)).foregroundColor(.white).shadow(radius: 1)
            .rotationEffect(.degrees(p.fall && gone ? 160 : 0))
            .offset(x: p.dx + (p.fall && gone ? 18 : 0), y: p.fall ? (gone ? 60 : 30) : (gone ? -60 : -10))
            .opacity(gone ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.3)) { gone = true } }
    }
}

struct Tri: Shape {
    var a: CGPoint, b: CGPoint, c: CGPoint
    func path(in r: CGRect) -> Path { Path { $0.move(to: a); $0.addLine(to: b); $0.addLine(to: c); $0.closeSubpath() } }
}

struct TailShape: Shape {
    var curl: CGFloat
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 20, y: 50))
            p.addQuadCurve(to: CGPoint(x: 6 - curl * 4, y: 22 + curl * 18), control: CGPoint(x: 0, y: 50))
        }
    }
}

/// Bit, drawn facing right in an 84×72 box. The view flips it to face left.
struct Cat: View {
    @ObservedObject var m: Model
    @State private var wobble: CGFloat = 0
    @State private var jump: CGFloat = 0
    @State private var particles: [Particle] = []

    var b: Breed { m.breed }
    var dark: Bool { b.name == "Tuxedo" || b.name == "Midnight" || b.name == "Black pug" || b.name == "Black bear" }
    var faceInk: Color { dark ? Color.white : ink }
    var mood: Mood { m.squatting ? .asleep : (m.hovering && m.mood == .asleep && !m.snoozed ? .calm : m.mood) }

    var body: some View {
        TimelineView(.animation(minimumInterval: m.walking || m.zoomies || m.gesture != .none || m.hovering ? 1.0 / 30 : 1.0)) { t in   // 1 fps when idle: 7.6% → 3% CPU, measured
            let s = t.date.timeIntervalSinceReferenceDate
            let asleep = mood == .asleep
            let breathe = 1 + (asleep ? 0.05 : 0.025) * sin(s * (asleep ? 1.4 : 2.4))
            let step = m.walking ? sin(s * 12) : 0
            let wagSpeed: Double = m.hovering ? 9 : mood == .busy ? 4 : mood == .upset ? 14 : 2
            let wag = asleep ? 0 : sin(s * wagSpeed) * (m.hovering ? 16 : 9)
            let blink = !asleep && Int(s * 10) % 37 == 0
            let g = m.gesture, gt = Date().timeIntervalSince(m.gestureAt)
            let k = g == .stretch ? sin(min(gt / 2.4, 1) * .pi) : 0
            let loaf = g == .loaf
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if isBear {
                        Circle().fill(b.points ?? b.dark).frame(width: 9, height: 9).position(x: 13, y: 46 + wag * 0.08)   // stub tail
                    } else if isPug {
                        Circle().trim(from: 0, to: 0.8).stroke(b.fur, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .frame(width: 11, height: 11).rotationEffect(.degrees(wag * 2)).position(x: 13, y: 40)
                    } else {
                        TailShape(curl: asleep ? 1 : 0)
                            .stroke(b.points ?? b.fur, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(wag), anchor: UnitPoint(x: 20 / 84, y: 50 / 72))
                    }
                    ForEach(0..<4) { i in
                        let y = asleep ? 64 : 63 + (i % 2 == 0 ? step : -step) * 2
                        Capsule().fill(drip ? ink : (b.points ?? (i % 2 == 0 ? b.dark : b.fur))).frame(width: isBear ? 10 : 7, height: asleep || loaf ? 4 : 12)
                            .position(x: [22, 32, 46, 56][i], y: y)
                        if drip && !asleep && !loaf {   // sneakers
                            Capsule().fill(Color.white).frame(width: 9, height: 4.5).overlay(Capsule().fill(ink).frame(width: 4, height: 1.1))
                                .position(x: [23, 33, 47, 57][i], y: y + 4.5)
                        }
                    }
                    Ellipse().fill(drip ? ink : b.fur).frame(width: isBear ? 60 : 54, height: asleep ? (isBear ? 30 : 26) : (isBear ? 35 : 30))
                        .scaleEffect(y: breathe, anchor: .bottom)
                        .position(x: 38, y: asleep ? 54 : 50)
                    if drip {
                        // tracksuit: two white stripes down the side, white waistband, white hood round the neck
                        ForEach(0..<2) { i in Capsule().fill(Color.white).frame(width: 30, height: 1.6).rotationEffect(.degrees(-8)).position(x: 34, y: (asleep ? 47 : 43) + CGFloat(i) * 4) }
                        Capsule().fill(Color.white).frame(width: 34, height: 3).position(x: 40, y: asleep ? 63 : 62)
                        ForEach([55.0, 63.0], id: \.self) { x in Capsule().fill(Color.white).frame(width: 1.6, height: 8).position(x: x, y: asleep ? 60 : 54) }   // hoodie strings
                    } else {
                        markings(asleep: asleep)
                        Ellipse().fill(b.belly.opacity(0.85)).frame(width: 26, height: 10).position(x: 46, y: asleep ? 60 : 58)
                    }
                    ZStack {
                        head(s: s, blink: blink, asleep: asleep)
                        poseLayer
                    }
                    .rotationEffect(.degrees(m.pose == .thinking ? -9 : 0), anchor: UnitPoint(x: 0.7, y: 0.6))
                    .offset(y: asleep ? 10 : 0)
                }
                .frame(width: 84, height: 72)
                .shadow(color: .black.opacity(0.45), radius: 0.8)   // outline, so white cats show on white pages
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                .scaleEffect(x: 1 + 0.24 * k, y: 1 - 0.16 * k, anchor: .bottom)
                .offset(y: loaf ? 4 : 0)
                .rotationEffect(.degrees(g == .spin && gt < 1 ? gt * 360 : 0))
                .offset(y: g == .sneeze && gt > 0.7 && gt < 0.9 ? -8 : 0)
                .offset(x: g == .shimmy ? sin(gt * 16) * 3 : 0, y: g == .shimmy ? -abs(sin(gt * 8)) * 3 : 0)
                .rotationEffect(.degrees(g == .shimmy ? sin(gt * 8) * 6 : 0), anchor: .bottom)
                .rotationEffect(.degrees(g == .roar ? -16 * sin(min(gt / 1.8, 1) * .pi) : 0), anchor: UnitPoint(x: 0.3, y: 1))
                .offset(x: g == .scratch ? sin(gt * 6) * 2.5 : 0, y: g == .scratch ? -abs(sin(gt * 6)) * 2 : 0)
                .rotationEffect(.degrees(g == .scratch ? sin(gt * 6) * 4 : 0), anchor: .bottom)
                .scaleEffect(x: m.facingLeft ? -1 : 1, y: 1)
                accessory(s: s).frame(width: 84, height: 20).offset(y: -22)
                if m.badge > 0 && !m.snoozed {
                    Text("\(m.badge)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16).background(Circle().fill(Color.red))
                        .offset(x: 2, y: -2)
                }
                ForEach(particles) { FloatUp(p: $0).frame(width: 84) }
            }
            .offset(x: wobble, y: jump + (m.walking ? -abs(step) * 1.5 : 0))
        }
        .frame(width: 84, height: 72)
        .onChange(of: m.shake) { _ in
            withAnimation(.easeInOut(duration: 0.06).repeatCount(7, autoreverses: true)) { wobble = 5 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { wobble = 0 }
        }
        .onChange(of: m.celebrate) { _ in
            burst(["✨", "🎉", "✨", "⭐️"])
            withAnimation(.spring(response: 0.25, dampingFraction: 0.35)) { jump = -22 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { jump = 0 } }
        }
        .onChange(of: m.hearts) { _ in burst(["💖", "💗", "💖"]) }
        .onChange(of: m.gesture) { g in
            switch g {
            case .sneeze: DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { burst(["achoo!"]) }
            case .knock: burst(["🥛"], fall: true)
            case .zoomies: burst(["💨", "💨"])
            case .spin: burst(["🌀"])
            case .yawn: burst(["yawn"])
            case .wash: burst(["lick lick"])
            case .loaf: burst(["🍞"])
            case .shimmy: burst(["🎵", "🎶"])
            case .roar: burst(["ROAR!"]); shakeSoon()
            case .honey: burst(["🍯", "yum"])
            case .fish: DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { burst(["🐟", "💦"]) }
            case .scratch: burst(["scritch"])
            default: break
            }
        }
    }

    @ViewBuilder func markings(asleep: Bool) -> some View {
        let y: CGFloat = asleep ? 54 : 50
        if b.stripes {
            ForEach(0..<3) { i in Capsule().fill(b.dark).frame(width: 4, height: 13).rotationEffect(.degrees(-12)).position(x: 26 + CGFloat(i) * 9, y: y - 6) }
        }
        if b.patch.count == 2 {
            Ellipse().fill(b.patch[0]).frame(width: 20, height: 14).position(x: 28, y: y - 4)
            Ellipse().fill(b.patch[1]).frame(width: 14, height: 11).position(x: 44, y: y - 8)
        }
    }

    @ViewBuilder func head(s: Double, blink: Bool, asleep: Bool) -> some View {
        let look = lookVector()
        if isBear { bearHead(s: s, blink: blink, asleep: asleep, look: look) } else if isPug { pugHead(blink: blink, asleep: asleep, look: look) } else {
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
                    .frame(width: 10, height: 8).position(x: 61, y: 44 + sin(t.date.timeIntervalSinceReferenceDate * 14) * 2)
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

    @ViewBuilder func eyes(blink: Bool, asleep: Bool, look: CGSize) -> some View {
        if asleep || (m.hovering && mood == .calm) || m.gesture == .yawn || m.gesture == .wash {
            ForEach([53.0, 67.0], id: \.self) { x in
                Circle().trim(from: asleep ? 0.05 : 0.55, to: asleep ? 0.45 : 0.95)
                    .stroke(faceInk.opacity(0.8), lineWidth: 1.8).frame(width: 8, height: 8).position(x: x, y: 31)
            }
        } else if mood == .happy {
            ForEach([53.0, 67.0], id: \.self) { x in
                Circle().trim(from: 0.55, to: 0.95).stroke(faceInk.opacity(0.85), lineWidth: 2.2).frame(width: 9, height: 9).position(x: x, y: 33)
            }
        } else {
            let big = mood == .waiting || mood == .upset
            ForEach([53.0, 67.0], id: \.self) { x in
                ZStack {
                    Ellipse().fill(b.eye == ink ? ink : b.eye).overlay(Ellipse().fill(ink).frame(width: 3)).frame(width: big ? 9 : 7.5, height: blink ? 1.5 : (big ? 11 : 9))
                    if !blink { Circle().fill(Color.white).frame(width: 3).offset(x: 1.2, y: -2) }
                }
                .position(x: x, y: 31).offset(look)
            }
        }
    }

    @ViewBuilder func accessory(s: Double) -> some View {
        let bob = sin(s * 5) * 2
        switch mood {
        case .upset:
            Text("!").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Mood.upset.color)).offset(x: m.facingLeft ? -18 : 18, y: bob)
        case .waiting:
            Text("?").font(.system(size: 13, weight: .black, design: .rounded)).foregroundColor(ink)
                .frame(width: 18, height: 18).background(Circle().fill(Mood.waiting.color)).offset(x: m.facingLeft ? -18 : 18, y: bob)
        case .busy:
            HStack(spacing: 3) {
                ForEach(0..<3) { i in Circle().fill(Mood.busy.color).frame(width: 5).opacity(Int(s * 3) % 3 == i ? 1 : 0.35) }
            }
            .padding(.horizontal, 6).padding(.vertical, 4).background(Capsule().fill(Color.white.opacity(0.9)))
            .offset(x: m.facingLeft ? -16 : 16)
        case .asleep:
            Text("z z").font(.system(size: 10 + CGFloat(Int(s) % 3), weight: .heavy)).foregroundColor(.white.opacity(0.9))
                .shadow(radius: 1).offset(x: m.facingLeft ? -22 : 22, y: -CGFloat(Int(s) % 3) * 2)
        default: EmptyView()
        }
    }

    /// The roar lands a beat after the bear rears up.
    func shakeSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.05).repeatCount(9, autoreverses: true)) { wobble = 3 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { wobble = 0 }
        }
    }

    func burst(_ glyphs: [String], fall: Bool = false) {
        let new = glyphs.enumerated().map { Particle(glyph: $1, dx: CGFloat($0 - glyphs.count / 2) * 14 + (fall ? 26 : 0), fall: fall) }
        particles += new
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { particles.removeAll { p in new.contains { $0.id == p.id } } }
    }

    /// Eyes follow the mouse anywhere on screen.
    func lookVector() -> CGSize {
        let mouse = NSEvent.mouseLocation
        let c = blobCenter()
        let dx = (mouse.x - c.x) * (m.facingLeft ? -1 : 1), dy = mouse.y - c.y
        let d = max(1, sqrt(dx * dx + dy * dy))
        let k = min(1, d / 200) * 2.5
        return CGSize(width: dx / d * k, height: -dy / d * k)
    }
}
