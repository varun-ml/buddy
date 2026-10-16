# Pet actions: Sit, Nap, Den

Status: draft for review. 16 Oct 2026.

## The problem

Buddy is good company until it isn't: it walks across the screen during a demo, a bubble pops up mid-call, and the only way to make it vanish is **Close Buddy**, which quits it and silences your sessions with it. The settings that exist overlap and speak in software words:

| Today | What it does | Problem |
|---|---|---|
| Nap 1h | no walking, needs-you held | still shows "done" bubbles and dances; lost on restart |
| 🌿 Relax mode | slower, calmer day until midnight | a tone, not a pause |
| 📌 Stay in place | stops walking | a pin, not a pet; tricks still play |
| Close Buddy | quits the app | the only "hide", and it ends alerts too |

## The idea

Three pet actions on one ladder. Each one is a pet doing something a pet does, and each step quiets more than the one before.

```
                 how much of Buddy is on screen
                 roams ──────── stays put ──────── gone
attention  full  [ default ]    [ Sit ]
           quiet                [ Nap ]            [ Den ]
                                                   (your phone still tells you)
```

Two switches stay separate because they aren't pauses: **Lazy day** (today's Relax mode, renamed: a calmer tone until midnight) and **🔒 Privacy** (what bubbles say). **Close Buddy** keeps its plain name: quitting an app isn't a pet action.

## The actions

Menu rule: the pet verb first, the plain meaning in grey after it, so a new user still understands.

| Menu | Durations | Stops | Keeps | Ends | Says |
|---|---|---|---|---|---|
| **Sit** · stay in one spot | until you say "Walkies" (remembered across restarts) | walking, zoomies, climbing onto windows, random tricks | bubbles, sounds, reactions to events, dragging | right-click → Walkies | "Sitting. I'll stay right here." / "Walkies! 🐾" |
| **Nap** · quiet for a while | 30 min · **1 h** · until I wake it | motion (breathing only), chatter, quotes, sounds, every bubble including "done" | the card on hover; needs-you as a silent "!" on the sleeping pet | the timer, a click, or "Wake up" | "Nap time. Poke me if you need me 💤" / "I'm up. While I slept: 2 done, 1 wants you." |
| **Den** · off the screen | 30 min · **1 h** · 2 h, never open-ended | everything on the Mac: Buddy leaves the screen | sessions are still tracked; the phone still speaks; nothing is lost | the timer, or `buddy back` | "Off to my {den} for an hour. Your phone has me." / "Back! While I was away: 3 done, 1 waiting." |

Why each rule:

- **Sit stops tricks too.** People who ask for "stay" mean "stop moving", and a spinning cat is moving.
- **Nap holds "done" bubbles.** Today a nap still shows good news and dances (`Model.swift:316`), which breaks the promise during focus or a call. The "done" events still go to the inbox, and the wake-up line summarises them.
- **Den is never open-ended.** A forgotten Den is the same as uninstalling Buddy: you'd stop hearing that a session needs you. Two hours at most, then it comes back.
- **Nap and Den survive a restart.** `snoozedUntil` isn't saved today (`Model.swift:40`), so a crash in the middle of a demo would bring Buddy back on screen.

## Every buddy does it its own way

The three verbs are the same for every buddy; how it looks and where it goes differ. A Den needs no scenery: the buddy leaves the screen its own way and the line names the place.

| Buddy | Sit | Nap | Den: how it leaves → where the line says it is | Meal |
|---|---|---|---|---|
| Cat | sits, tail wrapped | loaf, tail curled | walks off the edge → "my box" | 🐟 |
| Pug | sits | asleep | trots off → "my kennel" | 🦴 |
| Bear | sits | asleep | lumbers off → "my cave" | 🍯 |
| Hero | lands, arms crossed | asleep | flies off the top → "on patrol" | 🥪 |
| Ninja | crouches | asleep | climbs the rope out → "the dojo" | 🍙 |
| Wizard | plants the staff | asleep | poof → "my tower" | 🧪 |
| Astronaut | stands | visor up, asleep | jetpacks off → "back to the ship" | 🥫 |
| Robot | stands still | screen dims | rolls off → "my charging dock" | 🔋 |
| Stitch | sits | ears droop | surfs off → "out to sea" | 🍕 |
| Chemist | stands | asleep | walks off → "the lab" | ⚗️ |

New art: none for Sit, Nap and Den. Every buddy already has an asleep look, and the exits reuse moves that exist (flyOff, rope climb, teleport poof, surf). Meals use an emoji prop above the buddy, the way 🍯 and 🐟 already work.

## Meals

A meal is a Nap that ends when you come back, plus a little company. It is not a menu item.

1. Inside a lunch window (12:30–14:30) or a dinner window (19:30–21:30), the existing break nudge can say: "Lunch? I'll eat too 🍜".
2. Tap it: the buddy eats its meal (the prop above), then naps. Every Nap rule applies.
3. It ends when you're back at the keyboard, with the wake-up summary.
4. Noise limits: one offer per window per day; never while the microphone is in use (`micInUse()` exists); after two ignored offers in a row, it stops offering that meal.

## Calls and screen-shares

macOS gives apps no public "the screen is being shared" signal. Guessing from app and window names would sometimes hide Buddy for an hour by mistake, and needs-you is the one thing Buddy exists to show. So:

- **v1:** while the microphone is in use, Buddy goes quiet by itself: no sounds, no chatter. Needs-you still shows. When the mic turns off, it's back to normal.
- **Later, maybe:** when the mic turns on, one bubble offers "Sharing your screen? I'll go to my den." and does it only if you tap.

## The phone

The phone keeps its own Mute and quiet hours; Mac actions don't silence it. That's what makes Den safe: when Buddy is off the Mac screen, the phone still speaks. Sit, Nap and Den don't change what the phone receives.

## The menu after this

1. Sit · stay in one spot (or "Walkies" while sitting)
2. Nap ▸ 30 min · 1 hour · Until I wake it (or "Wake up")
3. Den ▸ 30 min · 1 hour · 2 hours
4. 🌿 Lazy day (until midnight)
5. 🔒 Privacy
6. Breathe for 2 minutes (in a lazy day, as now)
7. — 🎲 Shuffle buddy · Look ▸ · Personal ▸ · 📱 Pair phone… —
8. Close Buddy

`"stayPut": true` in `buddy.json` keeps working and means Sit.

## Done means

| Check | Pass |
|---|---|
| Den for an hour during a real screen-share | nothing of Buddy on screen and no sound; the return line counts every event |
| Restart Buddy during Nap or Den | it is still napping or away |
| A session finishes during Nap | no bubble, no dance; it's in the inbox and in the wake-up line |
| A session needs you during Nap | a silent "!" on the pet; the full bubble when it wakes |
| Each of the 10 buddies | does Sit, Nap and Den its own way, with its own den line |
| Right-click menu | no two items do the same thing |
| Two weeks of use | Close Buddy is never used to hide it |

## Not in v1

Lunch and dinner menu items · calendar or Focus-mode triggers · hiding automatically on screen-share · durations beyond the presets · drawn dens, kennels or caves · making Mac actions mute the phone.

## Open decisions

1. **Nap holds good news.** Today a nap lets "done" bubbles through with a dance. This PRD holds them. Keep that?
2. **Quiet on calls by itself** (mic in use) in v1, or opt-in?
3. **Den up to 2 hours.** Long enough for a long demo?
4. **Meals** in v1 (emoji props only), or after Sit, Nap and Den have settled?
