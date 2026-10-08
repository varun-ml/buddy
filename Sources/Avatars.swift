import AppKit
import SwiftUI

// MARK: avatars: buddies that aren't animals (a caped hero, …). They stand on two legs and are drawn whole by their own file.
// To add one: copy BuddyHero.swift, add it to `pets` (Pet.swift) and a case to `avatarBody` below.
// Their `Breed` colours mean: fur = main suit, dark = cape or second colour, belly = skin, eye = eyes,
// points = trim (belt, emblem), mask = mask or visor. Costumes (Costume.swift) don't apply to avatars; they're dressed already.

/// What an avatar needs to draw one frame, in the same 84×72 box as the pets, facing right (the view flips it to face left).
/// The floor is y = 68. Head roughly at (52, 24) so poses (glasses, crown) line up.
struct AvatarPose {
    let b: Breed
    let s: Double           // seconds, for breathing, flutter, flicker
    let step: Double        // -1…1 while walking, 0 standing
    let asleep: Bool
    let blink: Bool
    let g: Gesture          // the trick under way, .none if none
    let gt: Double          // seconds into it
    var flying: Bool { g == .flyOff || g == .grapple }
}

extension Cat {
    @ViewBuilder func avatarBody(_ p: AvatarPose) -> some View {
        switch petKind.name {
        case "hero": heroAvatar(p)
        case "ninja": ninjaAvatar(p)
        case "wizard": wizardAvatar(p)
        case "astronaut": astronautAvatar(p)
        case "robot": robotAvatar(p)
        case "stitch": stitchAvatar(p)
        default: heroAvatar(p)
        }
    }
}

/// The small avatars that wait for you (one per waiting session), and the one in Burrow's scene: generic, from the coat colours.
func avatarKitten(_ b: Breed) -> some View {
    ZStack {
        Capsule().fill(b.dark).frame(width: 18, height: 16).position(x: 12, y: 31)
        RoundedRectangle(cornerRadius: 5).fill(b.fur).frame(width: 14, height: 14).position(x: 15, y: 32)
        Circle().fill(b.belly).frame(width: 17, height: 17).position(x: 15, y: 17)
        if let mk = b.mask { Capsule().fill(mk).frame(width: 15, height: 5).position(x: 15, y: 16) }
    }
}
