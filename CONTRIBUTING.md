# Contributing to Buddy

Thanks for helping! Buddy is small on purpose: a handful of Swift files, one Python hook, one install script. No dependencies.

## How it fits together

| File | What it does |
|---|---|
| `Sources/Model.swift` | What Buddy knows (sessions, PRs, stats, limits) and what it says (`say`) |
| `Sources/Pet.swift` | What every pet shares: the body, eyes, poses, and the list of pets |
| `Sources/PetCat.swift`, `PetPug.swift`, `PetBear.swift` | One pet each: coats, tricks, head, tail and ears |
| `Sources/Agents.swift` | One entry per coding agent: colours, badge, how to open its session |
| `Sources/Theme.swift` | Theme colours, the card frame, and parts every theme shares (quote carousel, rings) |
| `Sources/Burrow.swift`, `Glass.swift`, `Ink.swift` | One card per theme |
| `Sources/Window.swift` | The floating window, bubbles, and walking along the screen |
| `Sources/Life.swift` | The Personal tab: profile, goals, to-dos and their nudges |
| `Sources/Codex.swift`, `Disk.swift`, `Inbox.swift` | Codex sessions, disk and worktree watch, `buddy say` messages |
| `Sources/Basics.swift` | Shared types, settings, and jumping to a session's window |
| `Sources/main.swift` | Start-up and the test flags |
| `beat.py` | The hook each agent runs on each event, one class per agent. It writes one small file per session to `~/.claude/pet/sessions/` |
| `test_beat.py` | Feeds `beat.py` each agent's hook payloads and checks the result |
| `buddy-cli` | The `buddy` command: `buddy` starts it, `buddy say "…"` drops a message in `~/.claude/pet/inbox/` |
| `install.sh` | Builds, adds the hooks, starts Buddy at login; `--uninstall` undoes it |
| `wisdom.json` | Quotes and questions Buddy shows |

## Make a change

```bash
swiftc -swift-version 5 -O Sources/*.swift -o Buddy && ./Buddy --selftest   # quick check
python3 test_beat.py                                                     # the hook
./Buddy --snapshot /tmp/after                                            # every theme, tab, pet and coat as PNGs, from a made-up profile
./install.sh                                                            # rebuild and restart your own Buddy
./Buddy --card --theme burrow --personal                                # open the card on start, for screenshots
```

## Good first contributions

### Add a coding agent (Cursor, Gemini CLI, Aider, …)

1. **`beat.py`**: subclass `Claude` (copy `Codex`), override what differs: how to recognise its hook payload (`match`), its settings file and hook events, its background jobs to ignore, and how its transcript records replies (`said`). Put it in `AGENTS` before `Claude`.
2. **`Sources/Agents.swift`**: add an entry with the same `name`: label, colour, badge, and how to open one of its sessions.
3. **`test_beat.py`**: add the payloads it sends, and check the session file.

### Add a pet

Copy `Sources/PetBear.swift` (Siddharth's bear) to `PetYours.swift`: coats, tricks, and how its head, tail and ears draw. Add it to `pets` in `Pet.swift`. `./Buddy --snapshot` draws every coat, so you can see it without installing.

### Add a buddy that isn't an animal

Copy `Sources/BuddyHero.swift`: a `PetKind` with `biped: true`, five coats, and one drawing function that gets an `AvatarPose` (time, walk step, the trick under way). Add it to `pets` in `Pet.swift` and a case to `avatarBody` in `Sources/Avatars.swift`. `./Buddy --snapshot` draws all its coats and moves. Original characters only.

### Add a costume

Costumes are drawn over any pet (`Sources/Costume.swift`): the caped hero is the model. A costume adds its drawing, can change the walk, and brings its own moves (new `Gesture` cases). `./Buddy --costume hero --trick grapple` tries one live. Original characters only: no trademarked heroes.

**Festival costumes** (`Sources/Festive.swift`) switch on by date: add next year's dates to `festivals` from a panjika. Celebrate the culture, never draw deities or rituals on the pet, and have someone who celebrates the festival check the lines.

### Also welcome

- **A theme.** Each theme is one card view (`BurrowCard`, `GlassCard`, `InkCard`); the data they show is shaped once in `Theme.swift`.
- **Quotes** in `wisdom.json`.

## Rules of the road

- Everything stays on the user's Mac. No telemetry, no new network calls without a setting that turns them on.
- No dependencies.
- CI builds every PR, runs the self-test and the hook test, and attaches card and pet images from before and after your change, with a table of which views changed. Check that table matches what you meant to change.
