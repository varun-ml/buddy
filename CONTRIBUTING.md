# Contributing to Buddy

Thanks for helping! Buddy is small on purpose: a handful of Swift files, one Python hook, one install script. No dependencies.

## How it fits together

| File | What it does |
|---|---|
| `Sources/Model.swift` | What Buddy knows (sessions, PRs, stats, limits) and what it says (`say`) |
| `Sources/Pet.swift` | The pet: coats, drawing and tricks for cat, pug and bear |
| `Sources/Theme.swift` | Theme colours, the card frame, and parts every theme shares (quote carousel, rings) |
| `Sources/Burrow.swift`, `Glass.swift`, `Ink.swift` | One card per theme |
| `Sources/Window.swift` | The floating window, bubbles, and walking along the screen |
| `Sources/Life.swift` | The Personal tab: profile, goals, to-dos and their nudges |
| `Sources/Codex.swift`, `Disk.swift`, `Inbox.swift` | Codex sessions, disk and worktree watch, `buddy say` messages |
| `Sources/Basics.swift` | Shared types, settings, and jumping to a session's window |
| `Sources/main.swift` | Start-up and the test flags |
| `beat.py` | The hook Claude Code and Codex run on each event. It writes one small file per session to `~/.claude/pet/sessions/` |
| `buddy-cli` | The `buddy` command: `buddy` starts it, `buddy say "…"` drops a message in `~/.claude/pet/inbox/` |
| `install.sh` | Builds, adds the hooks, starts Buddy at login; `--uninstall` undoes it |
| `wisdom.json` | Quotes and questions Buddy shows |

## Make a change

```bash
swiftc -swift-version 5 -O Sources/*.swift -o Buddy && ./Buddy --selftest   # quick check
./Buddy --snapshot /tmp/after                                            # every theme and tab as PNGs, from a made-up profile
./install.sh                                                            # rebuild and restart your own Buddy
./Buddy --card --theme burrow --personal                                # open the card on start, for screenshots
```

## Good first contributions

- **A new pet.** Siddharth's bear is the model: a coat list, a head drawing and a few tricks, all in `Sources/Pet.swift` (search for `isBear`).
- **A new theme.** Each theme is one card view (`BurrowCard`, `GlassCard`, `InkCard`) plus a few colours.
- **Quotes** in `wisdom.json`.

## Rules of the road

- Everything stays on the user's Mac. No telemetry, no new network calls without a setting that turns them on.
- No dependencies.
- Before a PR: build, run `--selftest`, and attach `--snapshot` images (before and after) for anything visual.
