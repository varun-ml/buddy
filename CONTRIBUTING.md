# Contributing to Buddy

Thanks for helping! Buddy is small on purpose: one Swift file, one Python hook, one install script.

## How it fits together

| File | What it does |
|---|---|
| `Buddy.swift` | The app: the pet, bubbles, the card and its three themes |
| `beat.py` | The hook Claude Code and Codex run on each event. It writes one small file per session to `~/.claude/pet/sessions/` |
| `buddy-cli` | The `buddy` command: `buddy` starts it, `buddy say "…"` drops a message in `~/.claude/pet/inbox/` |
| `install.sh` | Builds, adds the hooks, starts Buddy at login; `--uninstall` undoes it |
| `wisdom.json` | Quotes and questions Buddy shows |

## Make a change

```bash
swiftc -swift-version 5 -O Buddy.swift -o Buddy && ./Buddy --selftest   # quick check
./install.sh                                                            # rebuild and restart your own Buddy
./Buddy --card --theme burrow --personal                                # open the card on start, for screenshots
```

## Good first contributions

- **A new pet.** Siddharth's bear is the model: a coat list, a head drawing and a few tricks, all in `Buddy.swift` (search for `isBear`).
- **A new theme.** Each theme is one card view (`BurrowCard`, `GlassCard`, `InkCard`) plus a few colours.
- **Quotes** in `wisdom.json`.

## Rules of the road

- Everything stays on the user's Mac. No telemetry, no new network calls without a setting that turns them on.
- Keep it one file per part. No dependencies.
- Before a PR: build, run `--selftest`, and attach a screenshot of anything visual.
