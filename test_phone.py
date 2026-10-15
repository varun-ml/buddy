#!/usr/bin/env python3
"""Buddy on the phone, end to end: hooks fire → phone.py → what the phone app receives. Run: python3 test_phone.py"""
import json, os, socket, subprocess, sys, tempfile, threading, time, urllib.request

T = tempfile.mkdtemp()
HERE = os.path.dirname(os.path.abspath(__file__))
with socket.socket() as s:
    s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]
stub = os.path.join(T, 'model'); open(stub, 'w').write('#!/bin/sh\ncat > /dev/null\nprintf "Fixed the login test, and all tests pass.\\n- Did: fixed the login test\\n- Result: all tests pass\\n"\n'); os.chmod(stub, 0o755)
env = {**os.environ, 'HOME': os.path.join(T, 'home'), 'BUDDY_SESSIONS': os.path.join(T, 'sessions'), 'BUDDY_PHONE': os.path.join(T, 'phone'),
       'BUDDY_PHONE_TOKEN': os.path.join(T, 'token'), 'BUDDY_PHONE_HOST': '127.0.0.1',
       'BUDDY_PHONE_PORT': str(port), 'BUDDY_SPEAK_CMD': stub}
os.makedirs(env['HOME'] + '/.config/buddy')
env['BUDDY_DONE'] = env['HOME'] + '/.claude/pet/done'   # where `buddy done` writes
WORK = os.path.join(T, 'myrepo'); os.makedirs(WORK)
srv = subprocess.Popen([sys.executable, os.path.join(HERE, 'phone.py')], env=env, stdout=subprocess.PIPE, text=True)
assert 'phone server on' in srv.stdout.readline()
tok = open(env['BUDDY_PHONE_TOKEN']).read().strip()
URL = f'http://127.0.0.1:{port}'

def get(path, auth=True):
    req = urllib.request.Request(URL + path, headers={'Authorization': f'Bearer {tok}'} if auth else {})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, None

def hook(**d):
    subprocess.run([sys.executable, os.path.join(HERE, 'beat.py')], input=json.dumps(d), text=True, check=True, env=env)

got = []
def listen():   # the phone: one server-sent-events stream
    req = urllib.request.Request(URL + '/events?after=0', headers={'Authorization': f'Bearer {tok}'})
    with urllib.request.urlopen(req) as r:
        for line in r:
            if line.startswith(b'data: '):
                got.append(json.loads(line[6:]))

def wait_for(kind, n=1, secs=20):
    end = time.time() + secs
    while time.time() < end:
        if sum(e['kind'] == kind for e in got) >= n:
            return [e for e in got if e['kind'] == kind][n - 1]
        time.sleep(0.2)
    raise AssertionError(f'no {kind} event; got {got}')

try:
    sys.path.insert(0, HERE); from phone import speakable
    assert speakable('Option A is pushed: PR #625 (e3215623f), see https://x.y/z and src/app.py at 19:53:01.') == 'Option A is pushed: PR #625 see and at'
    assert get('/card', auth=False)[0] == 401
    threading.Thread(target=listen, daemon=True).start()
    time.sleep(1.5)
    assert os.path.exists(os.path.join(env['BUDDY_PHONE'], 'listening'))   # beat.py only spends a model call when a phone listens

    hook(session_id='c1', hook_event_name='UserPromptSubmit', cwd=WORK, prompt='fix the login test')
    hook(session_id='c1', hook_event_name='Notification', cwd=WORK, message='Claude needs your permission to use Bash')
    e = wait_for('needs-you')
    assert e['spoken'] == 'myrepo needs your OK.' and e['sticky'] == 's:c1' and e['repo'] == 'myrepo', e
    assert get('/card')[1]['waiting'][0]['repo'] == 'myrepo'

    hook(session_id='c1', hook_event_name='Stop', cwd=WORK, last_assistant_message='## Summary\n```\nok\n```\nAll tests pass now.')
    assert wait_for('resolve')['sticky'] == 's:c1'
    e = wait_for('done')
    assert e['spoken'] == 'myrepo is done. Fixed the login test, and all tests pass.', e   # the model's line, not the first line
    assert e['details'] == ['Did: fixed the login test', 'Result: all tests pass'], e   # what you'd otherwise read the chat for
    c = get('/card')[1]
    assert c['headline'] == 'All clear' and c['yourTurn'][0]['repo'] == 'myrepo' and c['badge'] == 0, c

    subprocess.run([os.path.join(HERE, 'buddy-cli'), 'say', 'Lesson 3 is ready', '--sticky', 'l3'], cwd=WORK, env=env, check=True, capture_output=True)
    e = wait_for('say')
    assert e['spoken'] == 'myrepo: Lesson 3 is ready' and e['sticky'] == 'say:l3' and e['session'] == 'c1', e
    subprocess.run([os.path.join(HERE, 'buddy-cli'), 'done', 'l3'], env=env, check=True, capture_output=True)
    assert wait_for('resolve', 2)['sticky'] == 'say:l3'

    # car mode: the details are read aloud too, as sentences, without paths or hashes; off again, the short line
    from phone import car_text
    assert car_text('Fixed login', ['Did: fixed login/signup flow', 'Result: e3215623f', 'Needs you: defaced README check']) == \
        'Fixed login. Did: fixed flow. Needs you: defaced README check.'
    assert len(car_text('x', ['Did: ' + 'a' * 150, 'Result: ' + 'b' * 150, 'Next: ' + 'c' * 100])) <= 350 and 'Next' not in car_text('x', ['Did: ' + 'a' * 150, 'Result: ' + 'b' * 150, 'Next: ' + 'c' * 100])
    subprocess.run([os.path.join(HERE, 'buddy-cli'), 'car', 'on'], cwd=WORK, env=env, check=True, capture_output=True)
    assert 'Car mode on' in wait_for('say', 2)['spoken']
    hook(session_id='c1', hook_event_name='UserPromptSubmit', cwd=WORK, prompt='again')
    time.sleep(1.5)   # let phone.py see it working, or finished → finished is no change
    hook(session_id='c1', hook_event_name='Stop', cwd=WORK, last_assistant_message='ok')
    e = wait_for('done', 2)
    assert e['spoken'] == 'myrepo is done. Fixed the login test, and all tests pass. Did: fixed the login test. Result: all tests pass.', e
    subprocess.run([os.path.join(HERE, 'buddy-cli'), 'car', 'off'], env=env, check=True, capture_output=True)
    assert not os.path.exists(os.path.join(env['BUDDY_PHONE'], 'car'))
    # the app's Car button: on announces once (it repeats on every reconnect), off announces, the card says which
    n = sum(e['kind'] == 'say' for e in got)
    assert get('/car?on=1')[1] == {'car': True} and get('/car?on=1')[1] == {'car': True} and get('/card')[1]['car'] is True
    assert 'Car mode on' in wait_for('say', n + 1)['spoken']
    assert get('/car?on=0')[1] == {'car': False} and get('/card')[1]['car'] is False
    assert 'Car mode off' in wait_for('say', n + 2)['spoken']
    time.sleep(0.5); assert sum(e['kind'] == 'say' for e in got) == n + 2, got[-3:]

    # an offline phone catches up from the inbox, in order, nothing twice
    inbox = get('/inbox?after=0')[1]
    assert [x['kind'] for x in inbox] == [x['kind'] for x in got] and len({x['id'] for x in inbox}) == len(inbox), (inbox, got)
    assert get(f'/inbox?after={inbox[-2]["id"]}')[1] == inbox[-1:]
finally:
    srv.kill()
# a failing CLI (expired login) prints its error on stdout: that must never become the spoken line
bad = os.path.join(T, 'bad'); open(bad, 'w').write('#!/bin/sh\ncat > /dev/null\necho "Failed to authenticate: OAuth session expired"\nexit 1\n'); os.chmod(bad, 0o755)
sf = os.path.join(T, 'speak-check.json'); json.dump({'state': 'done'}, open(sf, 'w'))
subprocess.run([sys.executable, os.path.join(HERE, 'beat.py'), '--speak', sf], input='reply', text=True, env={**env, 'BUDDY_SPEAK_CMD': bad}, check=True)
assert 'spoken' not in json.load(open(sf)), json.load(open(sf))
# ...and you are told once (not per session) that summaries are off, and the bubble clears when they work again
says = lambda: [l for l in open(os.path.join(env['BUDDY_PHONE'], 'say.jsonl')) if 'summaries are off' in l]
subprocess.run([sys.executable, os.path.join(HERE, 'beat.py'), '--speak', sf], input='reply', text=True, env={**env, 'BUDDY_SPEAK_CMD': bad}, check=True)
assert len(says()) == 1 and 'log in again' in says()[0] and '/' not in json.loads(says()[0])['text'], says()
assert not os.path.exists(os.path.join(env['BUDDY_DONE'], 'claude-login'))
subprocess.run([sys.executable, os.path.join(HERE, 'beat.py'), '--speak', sf], input='reply', text=True, env=env, check=True)
assert os.path.exists(os.path.join(env['BUDDY_DONE'], 'claude-login')) and json.load(open(sf))['spoken'], json.load(open(sf))
# a saved setup token reaches the summary call (and nothing else is needed); the stub reports whether it got it
tokstub = os.path.join(T, 'tokstub'); open(tokstub, 'w').write('#!/bin/sh\ncat > /dev/null\necho "token is $CLAUDE_CODE_OAUTH_TOKEN."\n'); os.chmod(tokstub, 0o755)
open(env['HOME'] + '/.config/buddy/claude-token', 'w').write('tok-123\n')
tf = os.path.join(T, 'tok.json'); json.dump({'state': 'done'}, open(tf, 'w'))
subprocess.run([sys.executable, os.path.join(HERE, 'beat.py'), '--speak', tf], input='reply', text=True, env={**env, 'BUDDY_SPEAK_CMD': tokstub}, check=True)
assert json.load(open(tf))['spoken'] == 'token is tok-123.', json.load(open(tf))
os.remove(env['HOME'] + '/.config/buddy/claude-token')
print('phone test ok')
