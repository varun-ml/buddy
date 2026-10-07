import AppKit
import SwiftUI

// MARK: festivals. Buddy dresses up on its own from a week before the festival days to three days after,
// unless you've picked a costume (right-click → Costume). Pujo and Diwali are costumes like the hero (Costume.swift).
// Respect: no deities or rituals drawn on the pet; culture only: the dhak, dhunuchi smoke, diyas, rangoli.

/// The festival days themselves, from a panjika. Add each year's dates; with no entry, Buddy simply doesn't dress up.
let festivals: [(costume: String, from: String, to: String)] = [
    ("durga", "2026-10-17", "2026-10-21"),    // Shashthi to Bijoya Dashami
    ("diwali", "2026-11-06", "2026-11-11"),   // Dhanteras to Bhai Dooj
]
/// Once-a-day greetings on the big days.
let festivalGreetings: [String: String] = [
    "2026-10-17": "Shubho Shashthi! Pujo shuru, fatafati kota din aashche 🥁",
    "2026-10-19": "Ashtami! Anjali sere ekta bhalo khawa-dawa hok 🌸",
    "2026-10-21": "Bijoya Dashami. Asche bochor abar hobe 🥁",
    "2026-10-22": "Shubho Bijoya! Mishti kheyecho? 🍬",
    "2026-11-08": "Happy Diwali! Shubh Deepavali 🪔",
]

func shiftDay(_ day: String, _ n: Int) -> String {
    isoDay.date(from: day).flatMap { Calendar.current.date(byAdding: .day, value: n, to: $0) }.map { isoDay.string(from: $0) } ?? day
}
let festivalWindows = festivals.map { (costume: $0.costume, from: shiftDay($0.from, -7), to: shiftDay($0.to, 3)) }
var festivalCache = (at: Date.distantPast, name: String?.none)
/// The festival costume for that day, if any. Asked many times a frame, so today's answer is kept for a minute.
func festival(on d: Date? = nil) -> String? {
    if d == nil, Date().timeIntervalSince(festivalCache.at) < 60 { return festivalCache.name }
    let day = isoDay.string(from: d ?? Date())
    let name = festivalWindows.first { day >= $0.from && day <= $0.to }?.costume
    if d == nil { festivalCache = (Date(), name) }
    return name
}

let pujoCream = hex(0xf7f1e3), pujoRed = hex(0xc1121f), zari = hex(0xd4a017), kashStem = hex(0x6b7f3a)
let kurta = hex(0x9e1f63), kurtaGold = hex(0xe0b33a), marigold = [hex(0xf28c28), hex(0xffc23c)], diyaClay = hex(0xb5562b), flame = hex(0xffb627)
var evening: Bool { Calendar.current.component(.hour, from: frozenNow ?? Date()) >= 18 }

/// What each costume does when a session finishes, a PR merges, or one breaks.
enum Cue { case done, merge, red }
func costumeMove(_ cue: Cue) -> Gesture? {
    switch (wearing, cue) {
    case ("hero", .red): return .flyOff
    case ("hero", _): return .heroLanding
    case ("durga", .done): return .dhak
    case ("durga", .merge): return .dhunuchi
    case ("durga", .red): return .quietDhak
    case ("diwali", .done): return .diyas
    case ("diwali", .merge): return .phuljhari
    case ("diwali", .red): return .anaar
    default: return nil
    }
}
/// Extra idle tricks a costume brings.
var costumeTricks: [Gesture] {
    switch wearing {
    case "hero": return [.capeSwirl, .capeSwirl, .grapple]   // grapple: about 1 trick in 14
    case "durga": return [.dhak] + (Calendar.current.component(.hour, from: Date()) < 10 ? [.shiuli] : [])
    case "diwali": return [.rangoli] + (evening ? [.kandil] : [])
    default: return []
    }
}

/// The costume's way of saying things: a random line for that moment, or Buddy's usual one. {repo}, {n}, {pr}, {t}, {time} are filled in.
let costumeLines: [String: [String: [String]]] = [
    "durga": [
        "done": ["{repo} done. Fatafati! Ektu dekho? 👀", "{repo} sorted, ekdom fatafati ✨", "{repo} done, neater than a Saptami-morning pandal 🥁"],
        "waiting": ["{repo} is waiting like the 9 pm queue at Bagbazar. Ektu asho?", "{repo} needs you. Taratari, pandal bondho hoye jabe! 🥁"],
        "merged": ["Merged! Dhak bajao 🥁 That's {n} today.", "{n} merged today. Jomjomat! 🥁"],
        "red": ["{pr} broke. The dhak has gone quiet 😔 Hover me to see why.", "{pr} broke. Kono byapar na, let's fix it. Hover me 🥁"],
        "break": ["{t} without a break. Pandal-hop to the kitchen? Ektu jiriye nao ☕", "{t} straight. Ek bhaar cha, then back 🫖"],
        "stop": ["Past {time}. The pandals are lit. Cholo, ghure asho ✨"],
    ],
    "diwali": [
        "done": ["{repo} done! Ek aur diya jala 🪔", "{repo} done. Ghar roshan, kaam khatam ✨"],
        "waiting": ["Someone's at the door with mithai. It's {repo}. Aao na? 🪔", "{repo} needs you. Jaldi aao, mithai thandi ho rahi hai 🍬"],
        "merged": ["Merged! Phuljhari time ✨ {n} today.", "{n} merged. Patakha performance 🎇"],
        "red": ["{pr} fizzled like a damp anaar 🧨 Chalo, dekhte hain. Hover me.", "{pr} broke. Phuss. Hover me to see why."],
        "break": ["{t} without a break. Go find the kaju katli before it's gone 🍬"],
        "stop": ["Past {time}. Diye jal gaye, laptop ko bhi aaram do 🪔"],
    ],
]
func line(_ key: String, _ fallback: String, _ vars: [String: String] = [:]) -> String {
    guard let pick = wearing.flatMap({ costumeLines[$0]?[key]?.randomElement() }) else { return fallback }
    return vars.reduce(pick) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
}

struct Trapezoid: Shape {   // the dhunuchi's clay cup, the anaar's cone
    var top: CGFloat
    func path(in r: CGRect) -> Path {
        Path { p in
            let inset = (r.width - r.width * top) / 2
            p.move(to: CGPoint(x: r.minX + inset, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        }
    }
}

func diya(_ x: CGFloat, _ y: CGFloat, lit: Bool, s: Double) -> some View {
    ZStack {
        Ellipse().fill(diyaClay).frame(width: 11, height: 5).position(x: x, y: y)
        if lit {
            Ellipse().fill(flame).frame(width: 4, height: 7).scaleEffect(1 + 0.06 * sin(s * 10), anchor: .bottom).position(x: x, y: y - 5)
            Ellipse().fill(Color(red: 1, green: 0.95, blue: 0.72)).frame(width: 1.8, height: 3.5).position(x: x, y: y - 4.4)
        }
    }
}

extension Cat {
    var outfitFill: Color? { wearing == "durga" ? pujoCream : wearing == "diwali" ? kurta : nil }

    /// Over the body: Pujo's red-bordered drape, or Diwali's kurta trim.
    @ViewBuilder func outfitTrim(asleep: Bool) -> some View {
        let hem: CGFloat = asleep ? 63 : 62
        if wearing == "durga" {
            Capsule().fill(pujoRed).frame(width: 34, height: 3).position(x: 40, y: hem)
            Capsule().fill(zari).frame(width: 32, height: 0.8).position(x: 40, y: hem - 2.4)
            Capsule().fill(pujoRed).frame(width: 30, height: 3).rotationEffect(.degrees(-35)).position(x: 43, y: asleep ? 54 : 50)
        } else if wearing == "diwali" {
            Capsule().fill(kurtaGold).frame(width: 36, height: 2).position(x: 40, y: hem)
            Capsule().fill(kurtaGold).frame(width: 1.6, height: 14).position(x: 52, y: asleep ? 55 : 52)
            ForEach(0..<3) { i in Circle().fill(kurtaGold).frame(width: 2, height: 2).position(x: 54, y: (asleep ? 50 : 47) + CGFloat(i) * 4.5) }
        }
    }

    /// Over the head: a kash flower behind the ear for Pujo, a marigold garland for Diwali.
    @ViewBuilder func festiveHead() -> some View {
        if wearing == "durga" {
            ForEach(0..<3) { i in
                let dx = CGFloat(i) * 3
                Capsule().fill(kashStem).frame(width: 1, height: 14).rotationEffect(.degrees(20 + Double(i) * 8)).position(x: 72 + dx, y: 13)
                Capsule().fill(Color.white).frame(width: 3, height: 7).rotationEffect(.degrees(20 + Double(i) * 8)).position(x: 75 + dx, y: 6)
            }
        } else if wearing == "diwali" {
            ForEach(0..<7) { i in
                let t = Double(i) / 6, x = 46 + 28 * t, y = 46 + 6 * sin(t * .pi)
                Circle().fill(marigold[i % 2]).frame(width: 6.4, height: 6.4).position(x: x, y: y)
            }
        }
    }

    /// What the festive moves hold or put down, drawn with the pet. `gt` = seconds since the move began.
    @ViewBuilder func festiveProps(s: Double, gt: Double) -> some View {
        switch m.gesture {
        case .dhak, .quietDhak:
            ZStack {   // a barrel drum slung on the side, a kash plume on top; the paw beats it
                RoundedRectangle(cornerRadius: 4).fill(hex(0xa0522d)).frame(width: 15, height: 12)
                Ellipse().fill(pujoCream).frame(width: 4, height: 12).offset(x: -7)
                Ellipse().fill(pujoCream).frame(width: 4, height: 12).offset(x: 7)
                Capsule().fill(Color.white).frame(width: 4, height: 8).offset(x: 2, y: -10)
            }.position(x: 74, y: 54)
            Ellipse().fill(b.fur).frame(width: 7, height: 6)
                .position(x: 72, y: 45 + (m.gesture == .dhak ? -abs(sin(gt * 14)) * 4 : 3))
        case .dhunuchi:
            Trapezoid(top: 1.5).fill(hex(0x8b4a2b)).frame(width: 9, height: 6).position(x: 80, y: 52)
            ForEach(0..<3) { i in   // smoke curls rise in front of the face and fade
                let p = (gt * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Circle().fill(Color.gray.opacity(0.3 * (1 - p))).frame(width: 3 + 4 * p, height: 3 + 4 * p)
                    .position(x: 81 + sin(p * 6 + Double(i)) * 2, y: 47 - 22 * p)
            }
        case .diyas:
            ForEach(0..<3) { i in diya(18 + CGFloat(i) * 20, 70, lit: gt > 0.4 + Double(i) * 0.5, s: s).opacity(gt > 2.6 ? max(0, 1 - (gt - 2.6) / 0.4) : 1) }
        case .phuljhari:
            Capsule().fill(ink).frame(width: 1.2, height: 13).rotationEffect(.degrees(40)).position(x: 78, y: 45)
            ForEach(0..<6) { i in
                Capsule().fill(kurtaGold).frame(width: 1, height: 5).offset(y: -4)
                    .rotationEffect(.degrees(Double(i) * 60 + gt * 720)).position(x: 82, y: 40)
            }
        case .anaar:
            Trapezoid(top: 0.3).fill(hex(0xc0392b)).frame(width: 8, height: 9).position(x: 72, y: 66)
            if gt > 0.5 && gt < 1.4 {
                Circle().fill(Color.gray.opacity(0.5 * (1.4 - gt))).frame(width: 6 + 12 * (gt - 0.5), height: 6 + 12 * (gt - 0.5)).position(x: 72, y: 58 - 8 * (gt - 0.5))
            }
        case .rangoli:
            ForEach(0..<4) { i in   // rings draw themselves from the inside out
                let p = min(1, max(0, gt * 1.2 - Double(i) * 0.3))
                Ellipse().trim(from: 0, to: p).stroke([hex(0xe94e77), hex(0xf6c343), hex(0x3daa6b), hex(0x2e86de)][i], lineWidth: 1.6)
                    .frame(width: 8 + CGFloat(i) * 7, height: 3 + CGFloat(i) * 2).position(x: 40, y: 69)
            }.opacity(gt > 4 ? max(0, 1 - (gt - 4) / 0.5) : 1)
        case .kandil:
            ZStack {   // a paper star lantern on a string, swinging
                Capsule().fill(Color.gray).frame(width: 0.8, height: 10).offset(y: -12)
                Image(systemName: "star.fill").font(.system(size: 13)).foregroundColor(hex(0xf4a261))
                Capsule().fill(pujoRed).frame(width: 1.2, height: 6).offset(y: 9)
            }.rotationEffect(.degrees(sin(gt * 3) * 6), anchor: .top).position(x: 18, y: min(14, -12 + gt * 40))
        default: EmptyView()
        }
        if wearing == "diwali" && evening && m.gesture != .diyas { diya(74, 60, lit: true, s: s) }   // carries a diya after dark
    }
}

/// A pandal-hopper's walk: a little hop every 3 s.
func pandalHop(_ s: Double) -> CGFloat {
    let p = s.truncatingRemainder(dividingBy: 3)
    return p < 0.35 ? -6 * CGFloat(sin(p / 0.35 * .pi)) : 0
}
