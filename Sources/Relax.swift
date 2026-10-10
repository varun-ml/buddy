import AppKit
import AVFoundation
import SwiftUI

// MARK: relax mode: right-click → 🌿 Relax mode, until midnight. Slower walk with drifting leaves, calm lines instead of work chatter,
// a soft chime and a "time for a break" every 2 hours, and a 2-minute breathing break with sound Buddy makes itself (no audio files).
// Things that need you (a session waiting for your OK, a red PR) still get through.

let relaxLines: [[String]] = [
    ["Almost everything will work again if you unplug it for a few minutes, including you.", "Anne Lamott"],
    ["Rest is not idleness.", "John Lubbock"],
    ["Nature does not hurry, yet everything is accomplished.", "Lao Tzu"],
    ["Breathe. Let go. And remind yourself that this very moment is the only one you know you have for sure.", "Oprah Winfrey"],
    ["Within you there is a stillness and a sanctuary to which you can retreat at any time.", "Hermann Hesse"],
    ["Your calm mind is the ultimate weapon against your challenges.", "Bryant McGill"],
    ["Sometimes the most productive thing you can do is relax.", "Mark Black"],
    ["Slow down and everything you are chasing will come around and catch you.", "John De Paola"],
    ["The time to relax is when you don't have time for it.", "Sydney J. Harris"],
    ["Tension is who you think you should be. Relaxation is who you are.", "Chinese proverb"],
]

let breakSeconds: Double = 120

/// One breath every 10 s: 4 s in, 6 s out. 0…1 is how full the lungs are.
func breath(_ t: Double) -> (fill: Double, inhaling: Bool) {
    let c = t.truncatingRemainder(dividingBy: 10)
    return c < 4 ? (sin(c / 4 * .pi / 2), true) : (cos((c - 4) / 6 * .pi / 2), false)
}

/// Soft brown noise that swells with the breath, and a two-note chime. Generated live, so nothing ships but code.
// ponytail: the render block reads these vars without a lock; a torn Double is one odd sample, not worth a lock.
final class Calm {
    static let shared = Calm()
    private var engine: AVAudioEngine?
    private var t = 0.0, brown = 0.0, noiseUntil = 0.0, chimeAt = -10.0

    func chime() { start(); chimeAt = t }
    func ambience(_ seconds: Double) { start(); noiseUntil = t + seconds }
    func stop() { noiseUntil = t; DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if self.t >= self.noiseUntil, self.t - self.chimeAt > 4 { self.engine?.stop(); self.engine = nil } } }

    private func render(_ frames: Int, _ abl: UnsafeMutablePointer<AudioBufferList>, _ dt: Double) -> OSStatus {
        let bufs = UnsafeMutableAudioBufferListPointer(abl)
        for f in 0..<frames {
            t += dt
            var v: Double = 0
            // noise: fades in and out over 3 s, louder on the in-breath
            let fade: Double = t > noiseUntil ? 0 : min(1, (noiseUntil - t) / 3)
            if fade > 0 {
                brown = (brown + 0.02 * Double.random(in: -1...1)) / 1.02
                let swell: Double = 0.35 + 0.65 * breath(t).fill
                v += brown * 1.5 * fade * swell
            }
            // chime: 528 Hz, then 792 Hz, each ringing out over ~3 s
            let c: Double = t - chimeAt
            if c >= 0 && c < 4 {
                v += 0.12 * sin(2 * .pi * 528 * c) * exp(-c * 1.4)
                let d: Double = c - 0.35
                if d > 0 { v += 0.09 * sin(2 * .pi * 792 * d) * exp(-d * 1.4) }
            }
            for buf in bufs { buf.mData?.assumingMemoryBound(to: Float.self)[f] = Float(v) }
        }
        return noErr
    }

    private func start() {
        guard engine == nil else { return }
        let e = AVAudioEngine()
        let fmt = e.outputNode.inputFormat(forBus: 0)
        let rate = fmt.sampleRate, dt = 1 / rate
        let src = AVAudioSourceNode { [unowned self] _, _, frames, abl -> OSStatus in self.render(Int(frames), abl, dt) }
        e.attach(src)
        e.connect(src, to: e.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: rate, channels: fmt.channelCount))
        do { try e.start(); engine = e } catch { engine = nil }
    }
}

extension Model {
    var relaxing: Bool { (relaxUntil ?? .distantPast) > Date() }
    var breathing: Bool { (breakUntil ?? .distantPast) > Date() }

    func toggleRelax() {
        if relaxing { relaxUntil = nil; endBreak(quiet: true) }
        else {
            relaxUntil = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)   // until midnight
            lastBreakNudge = Date()   // the first nudge comes 2 hours from now
            say("Relax mode on 🌿 I'll ring a soft bell every 2 hours.", .calm, seconds: 6, kind: .ambient)
        }
        UserDefaults.standard.set(relaxUntil, forKey: "bit.relax")
    }

    /// Two minutes of breathing: Buddy naps with a ring that grows and shrinks, over soft noise. Ends itself.
    func startBreak() {
        breakUntil = Date().addingTimeInterval(breakSeconds)
        snoozedUntil = breakUntil
        bubble = nil
        Calm.shared.chime(); Calm.shared.ambience(breakSeconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + breakSeconds) { [weak self] in
            guard let self, let b = self.breakUntil, b <= Date().addingTimeInterval(1) else { return }
            self.endBreak(quiet: false)
        }
        onExpandChange?()
    }

    func endBreak(quiet: Bool) {
        guard breakUntil != nil else { return }
        breakUntil = nil; snoozedUntil = nil; workingSince = nil
        Calm.shared.stop()
        if !quiet { say("Welcome back 🌿", .happy, seconds: 5, kind: .ambient) }
        onExpandChange?()
    }

    /// Every 2 hours in relax mode: a chime and an offer to breathe. True if it spoke.
    func relaxNudge(_ now: Date) -> Bool {
        guard relaxing, !breathing, now.timeIntervalSince(lastBreakNudge) >= 2 * 3600 else { return false }
        lastBreakNudge = now
        Calm.shared.chime()
        say("Time for a break 🌿\nTap me to breathe for 2 minutes.", .calm, seconds: 30, kind: .ambient) { [weak self] in self?.startBreak() }
        return true
    }

    /// Relax mode's chatter: a calm line, nothing about work.
    func relaxQuote() {
        let q = relaxLines.filter { $0[0] != lastAmbient }.randomElement()!
        lastAmbient = q[0]
        say("“\(q[0])”", .calm, seconds: 14, kind: .quote, byline: "— \(q[1])", pose: .none)
    }
}

extension Cat {
    /// The breathing ring behind Buddy during a break, and what to do now.
    @ViewBuilder func breathingGuide(s: Double) -> some View {
        if m.breathing {
            let b = breath(s)
            ZStack {
                Circle().fill(hex(0x8fd3b6).opacity(0.18)).frame(width: 40 + 44 * b.fill, height: 40 + 44 * b.fill)
                Circle().stroke(hex(0x5fb894).opacity(0.7), lineWidth: 1.5).frame(width: 40 + 44 * b.fill, height: 40 + 44 * b.fill)
            }
            .position(x: 42, y: 44)
            Text(b.inhaling ? "breathe in" : "breathe out").font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(hex(0x2f7d62)).padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.85))).position(x: 52, y: -16)   // above the nap's z-z
        }
    }
}
