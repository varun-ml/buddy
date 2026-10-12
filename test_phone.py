#!/usr/bin/env python3
"""Buddy on the phone, end to end: hooks fire → phone.py → what the phone app receives. Run: python3 test_phone.py"""
import json, os, socket, subprocess, sys, tempfile, threading, time, urllib.request

T = tempfile.mkdtemp()
HERE = os.path.dirname(os.path.abspath(__file__))
with socket.socket() as s:
    s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]
stub = os.path.join(T, 'model'); open(stub, 'w').write('#!/bin/sh\necho "Fixed the login test, and all tests pass."\n'); os.chmod(stub, 0o755)
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
    c = get('/card')[1]
    assert c['headline'] == 'All clear' and c['yourTurn'][0]['repo'] == 'myrepo' and c['badge'] == 0, c

    subprocess.run([os.path.join(HERE, 'buddy-cli'), 'say', 'Lesson 3 is ready', '--sticky', 'l3'], cwd=WORK, env=env, check=True, capture_output=True)
    e = wait_for('say')
    assert e['spoken'] == 'myrepo: Lesson 3 is ready' and e['sticky'] == 'say:l3' and e['session'] == 'c1', e
    subprocess.run([os.path.join(HERE, 'buddy-cli'), 'done', 'l3'], env=env, check=True, capture_output=True)
    assert wait_for('resolve', 2)['sticky'] == 'say:l3'

    # an offline phone catches up from the inbox, in order, nothing twice
    inbox = get('/inbox?after=0')[1]
    assert [x['kind'] for x in inbox] == [x['kind'] for x in got] and len({x['id'] for x in inbox}) == len(inbox), (inbox, got)
    assert get(f'/inbox?after={inbox[-2]["id"]}')[1] == inbox[-1:]
finally:
    srv.kill()
print('phone test ok')
