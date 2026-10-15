#!/usr/bin/env python3
"""Buddy on the phone: streams your sessions' events to the Buddy Android app, over Tailscale only.

  python3 phone.py           serve on this Mac's Tailscale address (port 8732)
  python3 phone.py --pair    show the QR code the app scans (address + token)

It reads the same session files Buddy does (~/.claude/pet/sessions, written by beat.py) and turns changes into events:
  needs-you  a session waits for your OK        done    a session finished (with the line beat.py wrote to read aloud)
  failed     a session went quiet for 15 min    say     `buddy say` (needs-you when --urgent)
  resolve    a needs-you is no longer needed (the phone clears its notification)
Today's events are kept in ~/.claude/pet/phone/events-<day>.jsonl, so a phone that was offline catches up.
Endpoints (all need the token): GET /events?after=ID (server-sent events), /inbox?after=ID, /card, /avatar/<name>.png
"""
import hmac, json, os, plistlib, re, secrets, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

H = os.path.expanduser('~')
SESS = os.environ.get('BUDDY_SESSIONS') or H + '/.claude/pet/sessions'
PHONE = os.environ.get('BUDDY_PHONE') or H + '/.claude/pet/phone'
DONE = os.environ.get('BUDDY_DONE') or H + '/.claude/pet/done'
TOKEN = os.environ.get('BUDDY_PHONE_TOKEN') or H + '/.config/buddy/phone-token'
PORT = int(os.environ.get('BUDDY_PHONE_PORT') or 8732)
APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'android/app/build/outputs/apk/debug/app-debug.apk')
STALE, FORGET, SPEAK_WAIT = 15 * 60, 12 * 3600, 15   # the same "quiet" and "forget" as Buddy (Basics.swift); wait for the spoken line


def token():
    if not os.path.exists(TOKEN):
        os.makedirs(os.path.dirname(TOKEN), exist_ok=True)
        with open(os.open(TOKEN, os.O_WRONLY | os.O_CREAT, 0o600), 'w') as f:
            f.write(secrets.token_urlsafe(24))
    return open(TOKEN).read().strip()


def tailscale_ip():
    for exe in ('tailscale', '/Applications/Tailscale.app/Contents/MacOS/Tailscale'):
        try:
            ip = subprocess.run([exe, 'ip', '-4'], capture_output=True, text=True, timeout=5).stdout.split()
            if ip:
                return ip[0]
        except Exception:
            pass
    return None


def ignored():
    """Sessions you ignored in Buddy (✕ or right-click): the phone ignores them too."""
    try:
        d = plistlib.loads(subprocess.run(['defaults', 'export', 'Buddy', '-'], capture_output=True, timeout=5).stdout)
        return set(d.get('bit.ignored', {}))
    except Exception:
        return set()


def speakable(text):
    """What's safe to read aloud: no URLs, paths, hashes or long numbers (a voice reading 'e3215623f' is noise)."""
    words = []
    for w in (text or '').split():
        bare = w.strip('.,;:()[]`"\'')
        if '://' in bare or '/' in bare or re.fullmatch(r'#?(?=[a-f]*\d)[0-9a-f]{7,}', bare) or re.fullmatch(r'[#\d,._:-]{5,}', bare):
            continue
        words.append(w)
    return re.sub(r'\s+([.,;:])', r'\1', ' '.join(words)).strip()


CAR_HOURS, CAR_MAX = 12, 350   # car mode switches itself off; a needs-you waits for the line being read, so keep it short


def car_on():
    """`buddy car on` made the flag file in the last 12 hours: read each finished session's details aloud too."""
    try:
        return time.time() - os.stat(os.path.join(PHONE, 'car')).st_mtime < CAR_HOURS * 3600
    except OSError:
        return False


def car_text(line, details):
    """The summary and its details as sentences you can follow by ear: "Fixed login. Did: …. Result: …." """
    parts = []
    for p in [line or '', *details]:
        t = speakable(p)
        if re.fullmatch(r'\w+( you)?:?', t):   # a label whose content was all paths or hashes says nothing
            continue
        t = t.rstrip('.;: ')
        if t:
            parts.append(t + '.')
    while len(' '.join(parts)) > CAR_MAX and len(parts) > 1:   # "Next" goes first, then from the end
        parts.pop(next((i for i, x in enumerate(parts) if x.startswith('Next:')), len(parts) - 1))
    return ' '.join(parts)


def doing(activity):
    """'Claude wants to run: Bash npm test' → 'run Bash npm test'"""
    a = (activity or '').strip()
    return 'run ' + a.split('wants to run: ', 1)[1] if 'wants to run: ' in a else a


def start_page(host, tok):
    from urllib.parse import quote
    pair = f'buddy://pair?url={quote("http://" + host, safe="")}&token={tok}'
    btn = 'display:block;margin:14px 0;padding:18px;border-radius:14px;text-align:center;font:600 18px system-ui;text-decoration:none'
    return f'''<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Buddy</title>
<body style="margin:0;padding:28px 20px;background:#F6F6FA;color:#1D1D1F;font:16px/1.45 system-ui">
<h1 style="font:600 26px system-ui;margin:0 0 6px">Buddy on your phone</h1>
<p style="color:#8A8A8E;margin:0 0 18px">Two taps. Skip step 1 if the app is already installed.</p>
<a style="{btn};background:#fff;color:#007AFF;border:2px solid #007AFF" href="/buddy.apk?token={tok}">1 · Install the app</a>
<p style="color:#8A8A8E;font-size:14px;margin:0 4px">Open the download and tap Install. Allow installs from your browser if asked.</p>
<a style="{btn};background:#007AFF;color:#fff" href="{pair}">2 · Pair with this Mac</a>
<p style="color:#8A8A8E;font-size:14px;margin:0 4px">After this, the app updates itself from your Mac. No more codes.</p>'''


class Hub:
    """The event log, and what the sessions looked like last time, to spot changes."""

    def __init__(self):
        os.makedirs(PHONE, exist_ok=True)
        self.cv = threading.Condition()
        self.day = time.strftime('%Y-%m-%d')
        self.events = self._load()
        self.last_id = self.events[-1]['id'] if self.events else 0
        self.prev = None            # session id → state, last time we looked
        self.quiet = set()          # sessions already reported quiet (until they move again)
        self.pending = {}           # session id → when it finished, while we wait for its spoken line
        self.open_says = set()      # sticky `buddy say` keys not yet cleared with `buddy done`
        self.ign, self.ign_at = set(), 0
        self.say_pos = os.path.getsize(self._says()) if os.path.exists(self._says()) else 0   # only new ones
        self.sessions = []
        self.clients = 0

    def _file(self):
        return os.path.join(PHONE, f'events-{self.day}.jsonl')

    def _says(self):
        return os.path.join(PHONE, 'say.jsonl')

    def _load(self):
        try:
            return [json.loads(l) for l in open(self._file()) if l.strip()]
        except FileNotFoundError:
            return []

    def emit(self, kind, text, spoken, s=None, **extra):
        with self.cv:
            if time.strftime('%Y-%m-%d') != self.day:   # a new day: a new file and an empty inbox; keep 2 days on disk
                self.day, self.events = time.strftime('%Y-%m-%d'), []
                old = 'events-' + time.strftime('%Y-%m-%d', time.localtime(time.time() - 2 * 86400))
                for f in os.listdir(PHONE):
                    if f.startswith('events-') and f < old:
                        os.remove(os.path.join(PHONE, f))
            # ids are milliseconds and only grow, across days and restarts, so a phone's "after" is never ambiguous
            self.last_id = max(self.last_id + 1, int(time.time() * 1000))
            e = dict(id=self.last_id, at=time.time(), kind=kind, text=text, spoken=spoken,
                     session=(s or {}).get('id'), repo=(s or {}).get('repo'), source=(s or {}).get('source'), **extra)
            self.events.append(e)
            with open(self._file(), 'a') as f:
                f.write(json.dumps(e) + '\n')
            self.cv.notify_all()
        return e

    def load_sessions(self):
        if time.time() - self.ign_at > 30:
            self.ign, self.ign_at = ignored(), time.time()
        out = []
        for f in os.listdir(SESS) if os.path.isdir(SESS) else []:
            if not f.endswith('.json'):
                continue
            try:
                s = json.load(open(os.path.join(SESS, f)))
            except Exception:
                continue
            if s.get('id') in self.ign or time.time() - s.get('ts', 0) > FORGET:
                continue
            out.append(s)
        return out

    def tick(self):
        now = time.time()
        self.sessions = sessions = self.load_sessions()
        first = self.prev is None
        prev, self.prev = self.prev or {}, {s['id']: s.get('state') for s in sessions}
        for s in sessions:
            sid, st, was, repo = s['id'], s.get('state'), prev.get(s['id']), s.get('repo') or 'A session'
            if first:
                continue   # starting up: today's log already has what happened before
            if st == 'waiting' and was != 'waiting':
                self.emit('needs-you', f'{repo} wants your OK\n{s.get("activity") or ""}'.strip(),
                          f'{repo} needs your OK.', s, sticky='s:' + sid)   # the command shows on screen; read aloud it's noise
            if was == 'waiting' and st != 'waiting':
                self.emit('resolve', '', '', s, sticky='s:' + sid)
            if st == 'finished' and was != 'finished':
                self.pending[sid] = s.get('ts', now)
            if st == 'working' and now - s.get('ts', now) > STALE:
                if sid not in self.quiet:
                    self.quiet.add(sid)
                    self.emit('failed', f'{repo} has been quiet for 15 minutes\n{s.get("activity") or ""}'.strip(),
                              f'{repo} has gone quiet. It may be stuck.', s)
            else:
                self.quiet.discard(sid)
        # done: say it once the spoken line is in (beat.py writes it a few seconds after the turn ends), or after SPEAK_WAIT
        for sid, at in list(self.pending.items()):
            s = next((x for x in sessions if x['id'] == sid), None)
            if not s or s.get('state') != 'finished':
                del self.pending[sid]; continue
            fresh = s.get('spokenAt', 0) >= at - 1
            line = s.get('spoken') if fresh else None
            if line or now - at > SPEAK_WAIT:
                del self.pending[sid]
                repo = s.get('repo') or 'A session'
                # only the model's line is read aloud; the raw first line of a reply is for the screen
                self.emit('done', f'{repo} is done\n{s.get("said") or s.get("prompt") or ""}'.strip(), f'{repo} is done. {car_text(line, s.get("details", [])) if fresh and car_on() else speakable(line)}'.strip(),
                          s, details=s.get('details', []) if fresh else [])
        self.read_says(sessions)

    def read_says(self, sessions):
        """`buddy say` lines (buddy-cli appends them to say.jsonl while the phone server is on), and `buddy done` keys."""
        p = self._says()
        if os.path.exists(p) and os.path.getsize(p) > self.say_pos:
            with open(p) as f:
                f.seek(self.say_pos)
                lines = f.read()
                self.say_pos = f.tell()
            for l in lines.splitlines():
                try:
                    j = json.loads(l)
                except ValueError:
                    continue
                cwd = os.path.realpath(j.get('cwd') or '/')   # /tmp and /private/tmp are one folder
                s = next((x for x in sessions if x.get('cwd') and (cwd + '/').startswith(os.path.realpath(x['cwd']) + '/')), None)
                who = (s or {}).get('repo') or os.path.basename(cwd.rstrip('/')) or 'Buddy'
                key = j.get('sticky')
                self.emit('needs-you' if j.get('urgent') else 'say', f'{who}: {j["text"]}', f'{who}: {speakable(j["text"])}', s,
                          **({'sticky': 'say:' + key} if key else {}))
                if key:
                    self.open_says.add(key)
        for key in list(self.open_says):
            if os.path.exists(os.path.join(DONE, key)):
                self.open_says.discard(key)
                self.emit('resolve', '', '', None, sticky='say:' + key)

    def card(self):
        """The Mac card's Work tab, sessions only (no GitHub)."""
        now, ss = time.time(), self.sessions
        row = lambda s: {k: s.get(k) for k in ('id', 'repo', 'activity', 'prompt', 'said', 'spoken', 'details', 'ts', 'turnStart', 'source')}
        waiting = [s for s in ss if s.get('state') == 'waiting']
        stuck = [s for s in ss if s.get('state') == 'working' and now - s.get('ts', now) > STALE]
        working = [s for s in ss if s.get('state') == 'working' and s not in stuck]
        done = sorted([s for s in ss if s.get('state') == 'finished' and now - s.get('ts', 0) < 3600], key=lambda s: -s.get('ts', 0))
        if waiting:
            head = f'{waiting[0].get("repo") or "A session"} is waiting for your OK'
        elif stuck:
            head = f'{stuck[0].get("repo") or "A session"} has gone quiet'
        elif working:
            head = f'{working[0].get("repo")} is cooking' if len(working) == 1 else f'{len(working)} sessions cooking'
        else:
            head = 'All clear'
        mood = 'waiting' if waiting or stuck else 'busy' if working else 'calm'
        apk = APK if os.path.exists(APK) else None
        return dict(headline=head, mood=mood, badge=len(waiting) + len(stuck), at=now, car=car_on(), apk=int(os.path.getmtime(apk)) if apk else 0,
                    waiting=[row(s) for s in waiting],
                    stuck=[row(s) for s in stuck], working=[row(s) for s in working], yourTurn=[row(s) for s in done])

    def loop(self):
        while True:
            try:
                self.tick()
                if self.clients:   # beat.py writes spoken lines only while this file is fresh
                    open(os.path.join(PHONE, 'listening'), 'w').close()
            except Exception as e:
                print('tick:', e, file=sys.stderr)
            time.sleep(1)


hub = None


def set_car(on):
    """Car mode on (for 12 hours) or off, from the phone. Says so on the phone only when it changes."""
    flag, was = os.path.join(PHONE, 'car'), car_on()
    if on:
        open(flag, 'w').close()
    elif os.path.exists(flag):
        os.remove(flag)
    if on != was:
        line = 'Car mode on. I will read the details of each finished session.' if on else 'Car mode off. Short lines again.'
        hub.emit('say', 'Buddy: ' + line, line, None)
    return {'car': on}


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *a):
        pass

    def send(self, code, body, ctype='application/json'):
        b = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        got = (self.headers.get('Authorization') or '').removeprefix('Bearer ').strip() or (q.get('token') or [''])[0]
        if not hmac.compare_digest(got, token()):
            return self.send(401, {'error': 'pair the app first: python3 phone.py --pair'})
        after = int((q.get('after') or [self.headers.get('Last-Event-ID') or 0])[0] or 0)
        if u.path == '/card':
            return self.send(200, hub.card())
        if u.path == '/car':   # the app's Car button; it repeats it on every reconnect, so only a change is announced
            return self.send(200, set_car(q.get('on') == ['1']))
        if u.path == '/inbox':
            with hub.cv:
                return self.send(200, [e for e in hub.events if e['id'] > after])
        if u.path.startswith('/avatar/'):
            p = os.path.join(PHONE, 'avatar', os.path.basename(u.path))
            return self.send(200, open(p, 'rb').read(), 'image/png') if os.path.exists(p) else self.send(404, {'error': 'no avatar'})
        if u.path == '/buddy.apk':   # the app itself, built from android/ (see README)
            return self.send(200, open(APK, 'rb').read(), 'application/vnd.android.package-archive') if os.path.exists(APK) \
                else self.send(404, {'error': 'build it: cd android && ./gradlew assembleDebug'})
        if u.path == '/start':   # what the pairing QR code opens on the phone: install, then pair, two taps
            return self.send(200, start_page(self.headers.get('Host') or '', token()).encode(), 'text/html; charset=utf-8')
        if u.path == '/events':
            return self.stream(after)
        self.send(404, {'error': 'not found'})

    def stream(self, after):
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        hub.clients += 1
        open(os.path.join(PHONE, 'listening'), 'w').close()
        try:
            self.wfile.write(b'retry: 2000\n\n')
            sent_live = False
            while True:
                with hub.cv:
                    new = [e for e in hub.events if e['id'] > after]
                    if not new and sent_live:
                        hub.cv.wait(20)
                        new = [e for e in hub.events if e['id'] > after]
                for e in new:
                    self.wfile.write(f'id: {e["id"]}\ndata: {json.dumps(e)}\n\n'.encode())
                    after = e['id']
                if not sent_live:   # everything before this was catch-up: the app reads it quietly, except the newest few
                    self.wfile.write(b': live\n\n'); sent_live = True
                elif not new:
                    self.wfile.write(b': ping\n\n')   # keeps mobile networks from dropping a quiet connection
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            pass
        finally:
            hub.clients -= 1


def main():
    global hub
    # started from Buddy's menu or launchd, PATH is bare: find Homebrew's qrencode and Tailscale's CLI too
    os.environ['PATH'] = os.environ.get('PATH', '') + ':/opt/homebrew/bin:/usr/local/bin'
    host = os.environ.get('BUDDY_PHONE_HOST') or tailscale_ip()
    if not host:
        sys.exit('Tailscale is not running on this Mac. Open Tailscale, sign in, and run this again.')
    url = f'http://{host}:{PORT}'
    if sys.argv[1:2] == ['--pair']:   # `buddy pair`, or Buddy's menu → Pair phone…
        link = f'{url}/start?token={token()}'
        png = os.path.join(PHONE, 'pair.png')
        os.makedirs(PHONE, exist_ok=True)
        if subprocess.run(['which', 'qrencode'], capture_output=True).returncode != 0:
            sys.exit(f'brew install qrencode, then run this again. Or open this on the phone: {link}')
        subprocess.run(['qrencode', '-s', '12', '-m', '3', '-o', png, link])
        subprocess.run(['open', png])
        print('Scan the QR code with the phone camera: install the app and pair, two taps. (It holds your token: don\'t share it.)')
        return
    token()
    hub = Hub()
    threading.Thread(target=hub.loop, daemon=True).start()
    srv = ThreadingHTTPServer((host, PORT), Handler)
    srv.daemon_threads = True
    print(f'Buddy phone server on {url}', flush=True)
    srv.serve_forever()


if __name__ == '__main__':
    main()
