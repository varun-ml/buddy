#!/bin/bash
# Install Buddy: build it, start it at login, and hook it into Claude Code and Codex.
# Usage: ./install.sh [cat|pug|bear|random]   random: cat, pug and bear in turn, one per day. Safe to run again (after a git pull, or to switch pet).
#        ./install.sh --uninstall [--purge]   remove it; --purge also deletes your settings, goals and tasks in ~/.config/buddy
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL=com.buddy-pet.buddy
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
OLD_PLISTS=("$HOME"/Library/LaunchAgents/com.claude-mods.buddy.plist "$HOME"/Library/LaunchAgents/com.*.bit.plist)   # earlier names

# Add or remove Buddy's hook (beat.py) in each agent's settings. Other hooks are left alone.
hooks() { python3 "$DIR/beat.py" --hooks "$1"; }   # $1 = add | remove; each agent's settings file is listed in beat.py

stop_old() {
  for p in "$PLIST" "${OLD_PLISTS[@]}"; do
    [ -f "$p" ] || continue
    launchctl bootout "gui/$(id -u)" "$p" 2>/dev/null || true
    [ "$p" = "$PLIST" ] || rm -f "$p"
  done
}

if [ "${1:-}" = "--uninstall" ]; then
  stop_old
  rm -f "$PLIST" "$HOME/.local/bin/buddy"
  hooks remove
  rm -rf "$HOME/.claude/pet"   # session state and the message inbox
  if [ "${2:-}" = "--purge" ]; then rm -rf "$HOME/.config/buddy" "$HOME/.config/buddy.json"; echo "Settings, goals and tasks deleted."
  else echo "Kept your settings, goals and tasks in ~/.config/buddy (run with --purge to delete them)."; fi
  echo "Buddy is uninstalled. You can delete this folder: $DIR"
  exit 0
fi

PET="${1:-}"
command -v swiftc >/dev/null || { echo "Buddy needs Apple's command line tools. Run: xcode-select --install   then run this again."; exit 1; }
command -v gh >/dev/null || [ -x /opt/homebrew/bin/gh ] || echo "Optional: install and log in to GitHub's gh (brew install gh; gh auth login) to see your PRs."

# 1. pet choice: ~/.config/buddy.json
mkdir -p "$HOME/.config"
if [ -n "$PET" ] || [ ! -f "$HOME/.config/buddy.json" ]; then
  if [ -f "$HOME/.config/buddy.json" ]; then   # keep the other settings, change only the pet
    python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['pet']=sys.argv[2]; json.dump(d, open(p,'w'), indent=2)" "$HOME/.config/buddy.json" "$PET"
  else
    echo "{\"pet\": \"${PET:-cat}\"}" > "$HOME/.config/buddy.json"
  fi
fi
echo "pet: $(cat "$HOME/.config/buddy.json")"

# 2. build (from source, on your Mac: nothing is downloaded)
echo "building… (about a minute the first time)"
swiftc -swift-version 5 -O -suppress-warnings "$DIR"/Sources/*.swift -o "$DIR/Buddy"
chmod +x "$DIR/beat.py" "$DIR/buddy-cli"

# 2b. optional dance clip: ~/.config/buddy/dance.mp4 → transparent frames in ~/.config/buddy/dance (pug only, macOS 14+)
CLIP="$HOME/.config/buddy/dance.mp4"
if [ -f "$CLIP" ] && command -v ffmpeg >/dev/null; then
  T=$(mktemp -d)
  ffmpeg -v error -i "$CLIP" -vf fps=15 "$T/f%03d.png"
  swiftc -O -suppress-warnings "$DIR/lift.swift" -o "$T/lift"
  rm -rf "$HOME/.config/buddy/dance"
  "$T/lift" "$T" "$HOME/.config/buddy/dance" "${BUDDY_DANCE_TRIM:-24}"
  rm -rf "$T"
elif [ -f "$CLIP" ]; then echo "Note: brew install ffmpeg to use the dance clip."; fi

# 3. hooks into Claude Code and Codex
hooks add

# 4. start at login
stop_old
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DIR/Buddy</string></array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>/tmp/buddy.err.log</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"

# 5. the `buddy` command: `buddy` starts it again; `buddy say "…"` lets any agent talk to you through it
mkdir -p "$HOME/.local/bin" && ln -sf "$DIR/buddy-cli" "$HOME/.local/bin/buddy"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do   # an old alias would shadow the command
  [ -f "$rc" ] && sed -i '' '/alias buddy=.*com.claude-mods.buddy/d' "$rc"
done
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Add ~/.local/bin to your PATH so agents can run: buddy say \"…\"";; esac

echo ""
echo "Buddy is running (bottom right of your screen) and starts at login."
[ -d "$HOME/.codex" ] && echo "Using Codex? Open Codex → Settings (⌘,) → Hooks → Trust all, so Codex sessions show up."
echo "Closed it? Type: buddy. Remove it: ./install.sh --uninstall"
