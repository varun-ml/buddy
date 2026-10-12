# PRD: Buddy on the phone (v0)

**Status:** draft · **Platform:** Android (Pixel), sideloaded APK · **Transport:** Tailscale only

## 1. Problem

You run several Claude Code and Codex sessions at once. When you leave the desk, the laptop keeps working, but you can't see Buddy. A session that has finished, or that is waiting for your OK, can sit idle for an hour.

Buddy on the phone brings the Mac Buddy's events to you:

- It reads each event aloud, with a different sound for each kind, so you know what happened without looking.
- A tap on the bubble opens the same status card as on the Mac, so you can choose what to start next in Claude Remote Control.

It serves one person: the owner of the Mac. Data goes only between that Mac and that phone.

## 2. Jobs, ranked

| # | When I… | I want to… | So that… |
|---|---|---|---|
| 1 | am driving with Maps open | hear "needs you" the moment a session waits for my OK | it doesn't sit idle until I'm home |
| 2 | am away from the desk | hear "done" plus the agent's one-line result | I know whether to start the next task |
| 3 | glance at the phone | tap the bubble and see what's running, waiting or done | I pick the next session in Remote Control |
| 4 | was out of signal | catch up on what I missed, in order | nothing is lost |
| 5 | am on a call or in a meeting | mute Buddy in one gesture | it doesn't talk over people |
| 6 | don't want the bubble on screen | hide it without losing alerts | the screen stays clear |

## 3. v0 requirements

### Status card

The card is a read-only copy of the Mac card's Work tab, in the Mac's current theme.

| Card item | Mac source |
|---|---|
| Headline | `Model.headline` |
| Wants your OK | `waiting` → repo, activity, ts, source |
| Quiet or stuck | `stuck` → repo, how long it has been quiet, activity |
| Running | `working` → repo, activity, age |
| Your turn (done in the last hour) | `yourTurn` → repo, said or prompt, ts |
| Inbox | `notices` (today, newest first, at most 100); unread = newer than the phone's last-seen time |

Tapping a row does nothing. Only sessions and the inbox are shown: no GitHub (PRs, leaderboard), usage limits or daily stats. The Personal tab is never sent to the phone.

### Speech and notifications

**What is spoken.** Only events: needs-you, done, failed, and `buddy say`. Quotes, nudges and anything from GitHub are never spoken.

**Sound before speech.** Each event plays its own sound, under 600 ms, and then the phone's TTS reads the `spoken` line.

| Event | Sound |
|---|---|
| needs-you, and urgent `say` | rising two-tone chime |
| done | pop |
| failed | low thud |
| plain `say` | soft tick |

**Length.** `spoken` is at most 140 characters, about 8 seconds of speech. The Mac enforces this limit.

**Queue**

- needs-you jumps to the front of the queue.
- One utterance plays at a time. Nothing interrupts it.
- When two or more "done" events are waiting, they are read as one line: "3 done: a, b, c".
- An event older than 15 minutes is not spoken. Its notification and inbox entry stay.

**Repeats**

- A needs-you that is still unresolved is spoken one more time, 10 minutes later.
- The same line within 60 seconds is spoken once.

**Audio**

- Buddy takes transient, ducking audio focus, so Maps lowers its voice while Buddy speaks.
- Speech plays on the active output: car Bluetooth or the phone speaker.

**Notifications**

- Each event also posts an Android notification in a channel for its kind.
- A needs-you notification clears itself when the Mac resolves it.

**Mute**

- Long-press the bubble, then choose "Mute 1 h" or "Mute until tomorrow".
- Quiet hours default to 22:00–07:00.
- While Buddy is muted, notifications still post, silently.

**Lock screen.** If privacy mode is on on the Mac, the lock screen shows the `privateText()` wording instead of the event text.

### Overlay

The overlay is a floating bubble, like a chat head, that shows the current buddy in its current mood.

**Motion.** It shakes on needs-you and hops on done. Otherwise it stays still.

**Placement.** You can drag the bubble anywhere. When you let go, it snaps to the nearest edge and remembers that position.

**Hiding.** Drag the bubble to the ✕ at the bottom to hide it until the app is opened again. Hiding the bubble does not stop speech.

**Gestures**

- Tap opens the status card.
- Long-press opens a menu: Mute, Hide bubble, Quit.

**Badge.** The bubble shows a number: waiting sessions + stuck sessions.

### Connection

- The phone reaches the Mac only by its Tailscale name. There is no public address.
- The phone keeps one long-lived stream open.
- When the stream drops, the phone reconnects after 1 s, then 2 s, then 5 s, up to 60 s. It also retries at once when the network changes.

**Offline.** The bubble greys out and the card shows "Mac unreachable since HH:MM". Buddy does not say anything about being offline.

**Catch-up.** After reconnecting, the phone asks for the inbox items it missed.

- It speaks at most the 3 newest, with needs-you first.
- The rest go into the inbox without being spoken.

### Settings

This is the complete list:

- the Mac's Tailscale name and the pairing token, set by scanning a QR code
- speech on/off
- quiet hours
- speech rate
- overlay on/off

### Budget

- Battery: under 3% a day while the stream is idle and the screen is off.
- Data: under 5 MB a day.
- No polling while the screen is off. The card is fetched only when you open it.

## 4. Out of scope for v0

| Item | When |
|---|---|
| Voice reply to sessions, approving from the phone (use Remote Control instead) | v1 |
| Driving-safety rules | v1 |
| Actions: continue a session, ignore a session | v1 |
| GitHub: PRs, CI, leaderboard, usage limits, daily stats | Not planned (sessions only) |
| Personal tab, goals, to-dos, people | Never on the phone |
| Ambient chatter, tricks, costumes | v2 at most |
| Several Macs, iOS, Play Store, Wear OS | v2 |
| Push or relay through any cloud service | Never |

## 5. Mac-side contract

### Where `spoken` comes from

The intelligence stays in the hooks, not in Buddy.

- When a turn ends, the Claude Code Stop hook rewrites the agent's last reply into one spoken sentence. It uses a small model, and the sentence has no code, paths or URLs. The Codex notify hook does the same.
- If the model call fails, the hook falls back to the `said` line that beat.py already extracts.
- Text from `buddy say` is passed through as it is.
- Buddy only relays the line and never writes one.

### Event

```
{id (monotonic), at, kind, session_id, repo, source, spoken, text, sticky_key?, resolved?}
```

Kinds: needs-you, done, failed, say. When a sticky key clears, the Mac sends a resolve event.

### Endpoints

| Endpoint | Purpose |
|---|---|
| event stream (SSE) | pushes events to the phone |
| `GET inbox?after=<id>` | returns the events the phone missed |
| `GET card` | returns the fields in Section 3 (sessions and inbox only) |
| `GET avatar` | returns the current buddy as rendered PNG frames, so its look has one source |

### Persistence

Today's `notices` must be stored on disk with stable ids. Today they live only in memory and are lost when Buddy restarts.

### Auth and exposure

- The server listens on the Tailscale interface only.
- Each paired device gets its own bearer token, stored in `~/.config/buddy/`.
- The server is off by default. `"phone": true` turns it on.
- The repo contains no host names, tokens or personal data.

## 6. Acceptance checks

1. With the screen locked and Maps navigating, a done event is spoken within 3 s of the hook firing. Maps lowers its volume for it and then comes back.
2. In a blind test, you can tell the needs-you, done and failed sounds apart, 3 out of 3.
3. Three sessions finish within 5 s of each other. The phone speaks one line, "3 done: …", and the inbox has 3 entries.
4. You approve a request on the Mac. The phone notification clears within 5 s, and the 10-minute repeat does not fire.
5. The phone is offline for 20 minutes while 6 events happen. On reconnect, it speaks no more than 3 of them, the inbox has all 6, and none is duplicated.
6. While Buddy is muted, a needs-you event makes no sound and posts a silent notification.
7. The Mac port refuses connections from outside the tailnet. Inside the tailnet, a request without a token gets 401.
8. After 24 h idle on battery with the stream connected, Android battery stats show the app at or under 3%.

## 7. Open questions

1. **Decided: no GitHub on the phone.** "failed" means a session that went quiet for too long, or an agent that reported a failure. Red PRs are not included.
2. **Should "same look" use PNG frames from the Mac, or a redraw on the phone?** The pets are drawn in Swift. The recommendation is that the Mac renders the frames.
