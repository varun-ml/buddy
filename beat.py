#!/usr/bin/env python3
"""Claude Code and Codex hook: record each session's state for Buddy, the desktop pet.

Writes ~/.claude/pet/sessions/<session_id>.json. Never fails the hook: any error exits 0 silently.
"""
import json, os, re, subprocess, sys, time

DIR = os.path.expanduser('~/.claude/pet/sessions')

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

def last_reply(d, transcript):
    """The agent's own last words this turn, first real line, for the "done" bubble. Claude and Codex logs differ."""
    text = d.get('last_assistant_message') or ''
    if not text:
        try:
            with open(transcript, 'rb') as f:
                f.seek(0, 2); f.seek(max(0, f.tell() - 300_000))
                lines = f.read().decode('utf-8', 'ignore').splitlines()
            for l in reversed(lines):
                try:
                    e = json.loads(l)
                except Exception:
                    continue
                p = e.get('payload') or {}
                if e.get('type') == 'assistant':                                   # Claude Code
                    parts = [b.get('text', '') for b in e.get('message', {}).get('content', []) if b.get('type') == 'text']
                elif p.get('type') == 'message' and p.get('role') == 'assistant':  # Codex
                    parts = [b.get('text', '') for b in p.get('content', []) if b.get('type') in ('output_text', 'text')]
                elif p.get('type') == 'agent_message' and isinstance(p.get('message'), str):
                    parts = [p['message']]
                else:
                    continue
                text = '\n'.join(x for x in parts if x.strip())
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
    os.makedirs(DIR, exist_ok=True)
    tp = d.get('transcript_path') or ''
    codex = '/.codex/' in tp
    if codex:
        sid = 'codex-' + sid   # Buddy opens codex://threads/<id> for these
    cwd0 = d.get('cwd') or ''
    if cwd0.startswith(os.path.expanduser('~/.codex')) and '/.codex/worktrees/' not in cwd0:
        return   # Codex's own jobs (memory consolidation) run in ~/.codex; its worktrees for your threads do not
    if cwd0.startswith(os.path.expanduser('~/.config/buddy')):
        return   # Buddy's own Claude call (gift ideas), not a session of yours
    if codex and not d.get('cwd'):
        return   # Codex's own background threads (ambient suggestions) have no folder; not yours
    asked = (d.get('prompt') or '').strip()
    if '## My request' in asked:   # Codex desktop puts attached files first
        asked = asked.split('## My request', 1)[1].lstrip(': \n')
    if codex and (asked.startswith('You are an expert') or cwd0.rstrip('/') == ''):
        return   # same (ambient suggestions, safety review), when they do carry a prompt or run in /
    path = os.path.join(DIR, sid + '.json')
    if ev == 'SessionEnd':
        if codex:   # Codex ends sessions when a thread unloads, not when you're done with it; Buddy forgets them after 12 h
            return
        if os.path.exists(path):
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
    if codex and 'source' not in s:
        try:
            first = open(tp).readline()
            s['source'] = 'codex-desktop' if 'Desktop' in json.loads(first)['payload'].get('originator', '') else 'codex-cli'
        except Exception:
            s['source'] = 'codex-cli'

    if ev == 'UserPromptSubmit':
        typed = asked
        s.update(state='working', activity='thinking', turnStart=time.time())
        if typed and not typed.startswith('<'):   # skip injected <task-notification> etc.
            s['prompt'] = typed.replace('\n', ' ')[:90]
        try:
            s['branch'] = subprocess.run(['git', '-C', cwd, 'branch', '--show-current'],
                                         capture_output=True, text=True, timeout=2).stdout.strip()
        except Exception:
            pass
    elif ev in ('PreToolUse', 'PostToolUse'):
        s.update(state='working', activity=short(d.get('tool_name', ''), d.get('tool_input') or {}))
    elif ev == 'PermissionRequest':            # Codex asks before running something
        what = short(d.get('tool_name', ''), d.get('tool_input') or {})
        if auto_reviewed(tp):                  # Codex's own reviewer decides; you're never asked
            s.update(state='working', activity='Auto-review: ' + what)
        else:
            s.update(state='waiting', activity='Codex wants to run: ' + what)
    elif ev == 'Stop':
        s.update(state='finished', activity='', said=last_reply(d, tp))
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

import traceback
try:
    main()
except Exception:
    open('/tmp/beat.err','a').write(traceback.format_exc())
