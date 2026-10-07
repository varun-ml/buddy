#!/usr/bin/env python3
"""Coding-agent hook (Claude Code, Codex): record each session's state for Buddy, the desktop pet.

Writes ~/.claude/pet/sessions/<session_id>.json. Never fails the hook: any error exits 0 silently.
"""
import json, os, re, subprocess, sys, time

DIR = os.environ.get('BUDDY_SESSIONS') or os.path.expanduser('~/.claude/pet/sessions')   # tests point this elsewhere

def short(tool, inp):
    arg = inp.get('command') or inp.get('file_path') or inp.get('pattern') or inp.get('description') or inp.get('url') or ''
    if arg == inp.get('file_path'):
        arg = os.path.basename(arg)
    return f'{tool} {arg}'.replace('\n', ' ')[:70]

def auto_reviewed(transcript):
    """True when this Codex thread's approvals go to Codex's auto-reviewer, not to you (latest turn_context wins)."""
    try:
        with open(transcript, 'rb') as f:
            head = f.read(400_000).decode('utf-8', 'ignore')
            f.seek(0, 2); f.seek(max(0, f.tell() - 400_000))
            tail = f.read().decode('utf-8', 'ignore')
        # the setting is logged per turn; a sub-agent's log may state it only once, at the top
        for text in (tail, head):
            i = text.rfind('"approvals_reviewer":"')
            if i >= 0:
                return text[i + 22:].startswith('auto_review')
        return False
    except Exception:
        return False

def last_reply(agent, d, transcript):
    """The agent's own last words this turn, first real line, for the "done" bubble."""
    text = d.get('last_assistant_message') or ''
    if not text:
        try:
            with open(transcript, 'rb') as f:
                f.seek(0, 2); f.seek(max(0, f.tell() - 300_000))
                lines = f.read().decode('utf-8', 'ignore').splitlines()
            for l in reversed(lines):
                try:
                    text = '\n'.join(x for x in agent.said(json.loads(l)) if x.strip())
                except Exception:
                    continue
                if text:
                    break
        except Exception:
            return ''
    lines = [l.strip() for l in text.splitlines()]
    # prose first: skip headings, code fences and JSON (Codex's auto-review replies are JSON)
    for line in [l for l in lines if not l.startswith(('#', '```', '{', '|'))] + [l for l in lines if l.startswith('#')]:
        line = re.sub(r'^(\d+[.)]|[>*\-•#]+)\s*', '', line).replace('**', '').replace('`', '').strip()
        if len(line) > 3:
            return line[:140]
    return ''

# ---- Agents. Each one says how to recognise its hook payload and how to read it.
# To add one (Cursor, Gemini CLI, …): subclass Claude, override what differs, and put it in AGENTS before Claude.
# Then add its entry in Sources/Agents.swift (name, colour, how to open a session) and a case to test_beat.py.

class Claude:
    name = 'claude'           # becomes the session's "source"; the Swift side looks it up in Sources/Agents.swift
    label = 'Claude'
    prefix = ''               # added to session ids, so two agents' ids never clash
    settings = '~/.claude/settings.json'   # where install.sh adds the hook
    hooks = ['UserPromptSubmit', 'PreToolUse', 'Notification', 'Stop', 'SessionEnd']
    keep_on_end = False       # True when SessionEnd doesn't mean you're done with the session

    def match(self, d):
        return True

    def ignore(self, d, asked):
        """The agent's own background jobs, which aren't your sessions."""
        return False

    def source(self, d, s):
        return None           # None = Claude Code, for sessions recorded before agents had names

    def asking(self, d, what):
        """(state, activity) for a permission request."""
        return 'waiting', f'{self.label} wants to run: ' + what

    def said(self, e):
        """Text parts of one transcript line, if it is the agent speaking."""
        if e.get('type') == 'assistant':
            return [b.get('text', '') for b in e.get('message', {}).get('content', []) if b.get('type') == 'text']
        return []


class Codex(Claude):
    name = 'codex'
    label = 'Codex'
    prefix = 'codex-'         # Buddy opens codex://threads/<id> for these
    settings = '~/.codex/hooks.json'
    hooks = ['UserPromptSubmit', 'PreToolUse', 'PermissionRequest', 'PostToolUse', 'Stop', 'SessionEnd']
    keep_on_end = True        # Codex ends sessions when a thread unloads; Buddy forgets them after 12 h

    def match(self, d):
        return '/.codex/' in (d.get('transcript_path') or '')

    def ignore(self, d, asked):
        cwd = d.get('cwd') or ''
        return (not cwd                                    # ambient suggestions have no folder
                or cwd.rstrip('/') == ''                   # safety review runs in /
                or asked.startswith('You are an expert')   # ambient suggestions that carry a prompt
                or cwd.startswith(os.path.expanduser('~/.codex')) and '/.codex/worktrees/' not in cwd)   # memory consolidation

    def source(self, d, s):
        try:
            first = open(d.get('transcript_path') or '').readline()
            return 'codex-desktop' if 'Desktop' in json.loads(first)['payload'].get('originator', '') else 'codex-cli'
        except Exception:
            return 'codex-cli'

    def asking(self, d, what):
        if auto_reviewed(d.get('transcript_path') or ''):   # Codex's own reviewer decides; you're never asked
            return 'working', 'Auto-review: ' + what
        return super().asking(d, what)

    def said(self, e):
        p = e.get('payload') or {}
        if p.get('type') == 'message' and p.get('role') == 'assistant':
            return [b.get('text', '') for b in p.get('content', []) if b.get('type') in ('output_text', 'text')]
        if p.get('type') == 'agent_message' and isinstance(p.get('message'), str):
            return [p['message']]
        return []


AGENTS = [Codex(), Claude()]   # first match wins; Claude matches everything, so it goes last

def where_it_runs():
    """The terminal tab (tty) and app a session lives in, found by walking up from the agent process."""
    out, pid = {}, os.getppid()
    for _ in range(15):
        try:
            ppid, tty, comm = subprocess.run(['ps', '-o', 'ppid=,tty=,comm=', '-p', str(pid)],
                                             capture_output=True, text=True, timeout=2).stdout.split(None, 2)
        except ValueError:
            break
        if tty != '??' and 'tty' not in out:
            out['tty'] = '/dev/' + tty
        if '.app/' in comm:
            out['termApp'] = comm.split('.app/')[0].rsplit('/', 1)[-1]
            break
        pid = int(ppid)
        if pid <= 1:
            break
    if os.environ.get('HERDR_PANE_ID'):
        out['herdrPane'] = os.environ['HERDR_PANE_ID']   # inside herdr: the pane, not the app's tab
    return out

def main():
    d = json.load(sys.stdin)
    sid, ev = d.get('session_id'), d.get('hook_event_name')
    if not sid or not ev:
        return
    agent = next(a for a in AGENTS if a.match(d))
    os.makedirs(DIR, exist_ok=True)
    tp = d.get('transcript_path') or ''
    sid = agent.prefix + sid
    if (d.get('cwd') or '').startswith(os.path.expanduser('~/.config/buddy')):
        return   # Buddy's own Claude call (gift ideas), not a session of yours
    asked = (d.get('prompt') or '').strip()
    if '## My request' in asked:   # Codex desktop puts attached files first
        asked = asked.split('## My request', 1)[1].lstrip(': \n')
    if agent.ignore(d, asked):
        return
    path = os.path.join(DIR, sid + '.json')
    if ev == 'SessionEnd':
        if not agent.keep_on_end and os.path.exists(path):
            os.remove(path)
        return
    try:
        s = json.load(open(path))
    except Exception:
        s = {}
    cwd = d.get('cwd') or s.get('cwd', '')
    s.update(id=sid, cwd=cwd, repo=os.path.basename(cwd.rstrip('/')), ts=time.time())
    if 'termApp' not in s and 'herdrPane' not in s:
        s.update(where_it_runs())   # once per session; a few ps calls
    if 'source' not in s:
        src = agent.source(d, s)
        if src:
            s['source'] = src

    if ev == 'UserPromptSubmit':
        s.update(state='working', activity='thinking', turnStart=time.time())
        if asked and not asked.startswith('<'):   # skip injected <task-notification> etc.
            s['prompt'] = asked.replace('\n', ' ')[:90]
        try:
            s['branch'] = subprocess.run(['git', '-C', cwd, 'branch', '--show-current'],
                                         capture_output=True, text=True, timeout=2).stdout.strip()
        except Exception:
            pass
    elif ev in ('PreToolUse', 'PostToolUse'):
        s.update(state='working', activity=short(d.get('tool_name', ''), d.get('tool_input') or {}))
    elif ev == 'PermissionRequest':
        state, activity = agent.asking(d, short(d.get('tool_name', ''), d.get('tool_input') or {}))
        s.update(state=state, activity=activity)
    elif ev == 'Stop':
        s.update(state='finished', activity='', said=last_reply(agent, d, tp))
    elif ev == 'Notification':
        msg = d.get('message') or ''
        # ponytail: only permission asks count as "waiting"; the idle "waiting for input" ping is just noise
        if 'permission' in msg.lower():
            s.update(state='waiting', activity=msg[:90])
        else:
            return
    else:
        return
    tmp = f'{path}.{os.getpid()}.tmp'   # parallel tool calls fire hooks at once; one tmp each
    with open(tmp, 'w') as f:
        json.dump(s, f)
    os.replace(tmp, path)


def install_hooks(mode, beat):
    """install.sh: add or remove beat.py in each agent's hook settings. Other hooks are left alone."""
    import shutil
    for agent in reversed(AGENTS):   # Claude first, as before
        path = os.path.expanduser(agent.settings)
        if agent.prefix and not os.path.isdir(os.path.dirname(path)):
            continue   # that agent isn't installed
        d = {}
        if os.path.exists(path):
            try:
                d = json.load(open(path))
            except ValueError as e:
                print(f'skipped {path}: it is not valid JSON ({e}). Fix it and run this again.')
                continue
            if not os.path.exists(path + '.bak-buddy'):   # keep the original from before Buddy, not a copy of a copy
                shutil.copy(path, path + '.bak-buddy')
        elif mode == 'remove':
            continue
        hooks = d.setdefault('hooks', {})
        for ev in agent.hooks:
            groups = hooks.setdefault(ev, [])
            for g in groups:   # drop any copy of beat.py (any path)
                g['hooks'] = [h for h in g.get('hooks', []) if not h.get('command', '').endswith('beat.py')]
            groups[:] = [g for g in groups if g['hooks']]
            if mode == 'add':
                groups.append({'hooks': [{'type': 'command', 'command': f'python3 {beat}', 'timeout': 5}]})
            if not groups:
                del hooks[ev]
        os.makedirs(os.path.dirname(path), exist_ok=True)
        json.dump(d, open(path, 'w'), indent=2)
        print(('hooks added: ' if mode == 'add' else 'hooks removed: ') + path)

import traceback
if sys.argv[1:2] == ['--hooks']:   # install.sh: beat.py --hooks add|remove
    install_hooks(sys.argv[2], os.path.abspath(__file__))
    sys.exit()
try:
    main()
except Exception:
    open('/tmp/beat.err','a').write(traceback.format_exc())
