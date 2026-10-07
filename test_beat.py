#!/usr/bin/env python3
"""Feeds beat.py the hook payloads each agent sends and checks the session file Buddy will read. Run: python3 test_beat.py"""
import json, os, subprocess, tempfile

T = tempfile.mkdtemp()
os.environ['BUDDY_SESSIONS'] = os.path.join(T, 'sessions')
HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(T, 'myrepo'); os.makedirs(WORK)

def hook(**d):
    subprocess.run(['python3', os.path.join(HERE, 'beat.py')], input=json.dumps(d), text=True, check=True)
    assert not os.path.exists('/tmp/beat.err') or os.path.getsize('/tmp/beat.err') == err0, open('/tmp/beat.err').read()[-500:]

def session(sid):
    p = os.path.join(os.environ['BUDDY_SESSIONS'], sid + '.json')
    return json.load(open(p)) if os.path.exists(p) else None

err0 = os.path.getsize('/tmp/beat.err') if os.path.exists('/tmp/beat.err') else 0

# Claude Code
hook(session_id='c1', hook_event_name='UserPromptSubmit', cwd=WORK, prompt='fix the login test')
s = session('c1'); assert s['state'] == 'working' and s['prompt'] == 'fix the login test' and s['repo'] == 'myrepo' and 'source' not in s, s
hook(session_id='c1', hook_event_name='PreToolUse', cwd=WORK, tool_name='Bash', tool_input={'command': 'npm test'})
assert session('c1')['activity'] == 'Bash npm test'
hook(session_id='c1', hook_event_name='Notification', cwd=WORK, message='Claude needs your permission to use Bash')
assert session('c1')['state'] == 'waiting'
hook(session_id='c1', hook_event_name='Notification', cwd=WORK, message='Claude is waiting for your input')
assert session('c1')['state'] == 'waiting'   # the idle ping changes nothing
hook(session_id='c1', hook_event_name='Stop', cwd=WORK, last_assistant_message='## Summary\n1. **All tests pass** now.\n```\nok\n```')
s = session('c1'); assert s['state'] == 'finished' and s['said'] == 'All tests pass now.', s
hook(session_id='c1', hook_event_name='SessionEnd', cwd=WORK)
assert session('c1') is None

# Codex: its transcript lives under ~/.codex; desktop or CLI comes from the first line
cx = os.path.join(T, '.codex', 'sessions'); os.makedirs(cx)
tp = os.path.join(cx, 'rollout.jsonl')
open(tp, 'w').write(json.dumps({'type': 'session_meta', 'payload': {'originator': 'Codex Desktop'}}) + '\n'
                    + json.dumps({'type': 'response_item', 'payload': {'type': 'message', 'role': 'assistant', 'content': [{'type': 'output_text', 'text': 'Draft is ready.'}]}}) + '\n')
hook(session_id='x1', hook_event_name='UserPromptSubmit', cwd=WORK, transcript_path=tp, prompt='files…\n## My request: shorter emails')
s = session('codex-x1'); assert s['source'] == 'codex-desktop' and s['prompt'] == 'shorter emails', s
hook(session_id='x1', hook_event_name='PermissionRequest', cwd=WORK, transcript_path=tp, tool_name='shell', tool_input={'command': 'rm -rf build'})
s = session('codex-x1'); assert s['state'] == 'waiting' and s['activity'] == 'Codex wants to run: shell rm -rf build', s
hook(session_id='x1', hook_event_name='Stop', cwd=WORK, transcript_path=tp)
assert session('codex-x1')['said'] == 'Draft is ready.'
hook(session_id='x1', hook_event_name='SessionEnd', cwd=WORK, transcript_path=tp)
assert session('codex-x1') is not None   # Codex ends a session when a thread unloads; Buddy keeps it
# Codex's own background jobs are not yours
hook(session_id='x2', hook_event_name='UserPromptSubmit', transcript_path=tp, prompt='hi')
hook(session_id='x3', hook_event_name='UserPromptSubmit', cwd=WORK, transcript_path=tp, prompt='You are an expert reviewer')
assert session('codex-x2') is None and session('codex-x3') is None
# Buddy's own Claude call (gift ideas)
hook(session_id='b1', hook_event_name='UserPromptSubmit', cwd=os.path.expanduser('~/.config/buddy'), prompt='ideas')
assert session('b1') is None

# install.sh: add twice, then remove; other hooks are left alone
H = os.path.join(T, 'home'); os.makedirs(os.path.join(H, '.claude')); os.makedirs(os.path.join(H, '.codex'))
mine = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'say done'}]}]}}
json.dump(mine, open(os.path.join(H, '.claude', 'settings.json'), 'w'))
def install(mode):
    subprocess.run(['python3', os.path.join(HERE, 'beat.py'), '--hooks', mode], env={**os.environ, 'HOME': H}, check=True, capture_output=True)
    return [json.load(open(os.path.join(H, f))) for f in ('.claude/settings.json', '.codex/hooks.json')]
def beats(d): return sum(h['command'].endswith('beat.py') for gs in d.get('hooks', {}).values() for g in gs for h in g['hooks'])
install('add'); claude, codex = install('add')
assert beats(claude) == 5 and beats(codex) == 6, (beats(claude), beats(codex))
claude, codex = install('remove')
assert claude == mine and beats(codex) == 0, claude
print('hook test ok')
