import Foundation

/// The pure parts of Google Tasks: PKCE, the sign-in URL and callback, token replies, due dates and time zones, task parsing.
/// Made-up data only. No network, no Keychain.
func googleSelftest() {
    // PKCE S256: the example in RFC 7636, appendix B
    precondition(pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")

    // the sign-in URL carries what Google's installed-app flow needs
    let u = URLComponents(url: googleAuthURL(clientId: "cid.apps.googleusercontent.com", redirect: "http://127.0.0.1:5123", challenge: "ch", state: "st"), resolvingAgainstBaseURL: false)!
    let q = Dictionary(uniqueKeysWithValues: (u.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    precondition(u.scheme == "https" && u.host == "accounts.google.com" && u.path == "/o/oauth2/v2/auth")
    precondition(q["client_id"] == "cid.apps.googleusercontent.com" && q["redirect_uri"] == "http://127.0.0.1:5123" && q["response_type"] == "code")
    precondition(q["scope"] == "https://www.googleapis.com/auth/tasks" && q["code_challenge"] == "ch" && q["code_challenge_method"] == "S256" && q["state"] == "st")
    precondition(q["prompt"] == "consent")   // so a second sign-in (after a sign-out whose revoke failed) still gets a refresh token

    // the browser comes back to the loopback listener: a code only with our state; a refusal says why
    precondition(callbackResult("GET /?state=st&code=4/0Ab-x_y&scope=https://www.googleapis.com/auth/tasks HTTP/1.1", state: "st") == .code("4/0Ab-x_y"))
    precondition(callbackResult("GET /?state=evil&code=4/0Ab HTTP/1.1", state: "st") == .bad)   // CSRF: someone else's code
    precondition(callbackResult("GET /?error=access_denied&state=st HTTP/1.1", state: "st") == .denied("access_denied"))
    precondition(callbackResult("GET /favicon.ico HTTP/1.1", state: "st") == .bad)

    // token replies: a fresh one, a refresh (no new refresh token), revoked access, and anything else
    precondition(parseTokenReply(Data(#"{"access_token":"ya29.a","expires_in":3599,"refresh_token":"1//r","scope":"x","token_type":"Bearer"}"#.utf8), status: 200) == .ok(access: "ya29.a", expiresIn: 3599, refresh: "1//r"))
    precondition(parseTokenReply(Data(#"{"access_token":"ya29.b","expires_in":3599,"token_type":"Bearer"}"#.utf8), status: 200) == .ok(access: "ya29.b", expiresIn: 3599, refresh: nil))
    precondition(parseTokenReply(Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8), status: 400) == .revoked)
    precondition(parseTokenReply(Data(#"{"error":"invalid_client"}"#.utf8), status: 401) == .failed("invalid_client"))
    precondition(parseTokenReply(Data("<html>".utf8), status: 502) == .failed("HTTP 502"))

    // due dates are a day, stored as midnight UTC: the day must not move with your time zone (in Los Angeles a plain
    // conversion makes 18 Oct 00:00 UTC the 17th; in Kolkata or Auckland it stays the 18th either way)
    let tz = NSTimeZone.default
    for z in ["America/Los_Angeles", "Asia/Kolkata", "Pacific/Auckland", "UTC"] {
        NSTimeZone.default = TimeZone(identifier: z)!
        precondition(googleDay("2026-10-18T00:00:00.000Z") == "2026-10-18", z)
    }
    NSTimeZone.default = tz
    precondition(googleDay("2026-10-18T00:00:00Z") == "2026-10-18" && googleDay("soon") == nil && googleDay("2026-13-45T00:00:00.000Z") == nil)
    // ask Google for a day either side (it doesn't say whether dueMax counts), then keep exactly today
    precondition(dueWindow(today: "2026-10-18") == ("2026-10-17T00:00:00.000Z", "2026-10-19T00:00:00.000Z"))
    precondition(dueWindow(today: "2026-11-01") == ("2026-10-31T00:00:00.000Z", "2026-11-02T00:00:00.000Z"))

    // a page of tasks.list: open, done, no due date, hidden, deleted, no title, and the next page
    let page = Data(#"""
    {"kind":"tasks#tasks","nextPageToken":"p2","items":[
     {"id":"a","title":"Call the bank","status":"needsAction","due":"2026-10-18T00:00:00.000Z"},
     {"id":"b","title":"Done already","status":"completed","due":"2026-10-18T00:00:00.000Z","completed":"2026-10-18T08:00:00.000Z"},
     {"id":"c","title":"Someday","status":"needsAction"},
     {"id":"d","title":"Cleared","status":"completed","due":"2026-10-18T00:00:00.000Z","hidden":true},
     {"id":"e","title":"Gone","status":"needsAction","due":"2026-10-18T00:00:00.000Z","deleted":true},
     {"id":"f","title":"  ","status":"needsAction","due":"2026-10-18T00:00:00.000Z"},
     {"id":"g","title":"Yesterday's","status":"needsAction","due":"2026-10-17T00:00:00.000Z"},
     {"id":"h","title":"Tomorrow's","status":"needsAction","due":"2026-10-19T00:00:00.000Z"},
     {"id":"i","title":"Pay rent","status":"needsAction","due":"2026-10-18T00:00:00.000Z","parent":"a"}]}
    """#.utf8)
    let p = parseGoogleTasks(page, list: "L1")
    precondition(p.next == "p2" && p.tasks.count == 9 && p.tasks[0] == GTask(id: "a", list: "L1", title: "Call the bank", status: "needsAction", due: "2026-10-18T00:00:00.000Z"))
    precondition(p.tasks[3].hidden && p.tasks[4].deleted && p.tasks[2].due == nil)
    precondition(parseGoogleTasks(Data(#"{"kind":"tasks#tasks"}"#.utf8), list: "L1").tasks.isEmpty && parseGoogleTasks(Data("x".utf8), list: "L").next == nil)

    // today only: open, titled, due today
    let today = googleToday(p.tasks, today: "2026-10-18", snoozed: [:])
    precondition(today.map(\.text) == ["Call the bank", "Pay rent"] && today[0].gid == "a" && today[0].glist == "L1" && today[0].line.isEmpty)
    precondition(today[0].id == "g:a" && today[0].due.map(isoDay.string) == "2026-10-18")   // shows as "today" in your own time zone
    precondition(googleToday(p.tasks, today: "2026-10-19", snoozed: [:]).map(\.text) == ["Tomorrow's"])

    // "☾ tomorrow" hides a task in Buddy until the next day, then keeps it on the list until you tick it, though its due day has passed
    let s1 = googleSnooze([:], id: "a", due: "2026-10-18", today: "2026-10-18")
    precondition(s1 == ["a": GSnooze(until: "2026-10-19", due: "2026-10-18")])
    precondition(googleToday(p.tasks, today: "2026-10-18", snoozed: s1).map(\.text) == ["Pay rent"])                  // put off: gone today
    precondition(googleToday(p.tasks, today: "2026-10-19", snoozed: s1).map(\.text) == ["Call the bank", "Tomorrow's"])   // back the next day
    precondition(googleToday(p.tasks, today: "2026-10-25", snoozed: s1).map(\.text) == ["Call the bank"])              // and stays until done
    let s2 = googleSnooze(s1, id: "a", due: "2026-10-18", today: "2026-10-19")                                     // put off again
    precondition(s2["a"] == GSnooze(until: "2026-10-20", due: "2026-10-18") && googleToday(p.tasks, today: "2026-10-19", snoozed: s2).map(\.text) == ["Tomorrow's"])
    // the query reaches back to the oldest put-off task, so Google still sends it
    precondition(dueWindow(today: "2026-10-25", snoozed: s1) == ("2026-09-24T00:00:00.000Z", "2026-10-26T00:00:00.000Z"))   // 30 days back, a day of margin
    precondition(dueWindow(today: "2026-10-18", snoozed: s1).min == "2026-09-17T00:00:00.000Z")
    // a put-off task that Google no longer sends as open (done or deleted elsewhere) is forgotten
    precondition(googlePrune(s1, open: ["b", "c"]).isEmpty && googlePrune(s1, open: ["a"]) == s1)
    // a put-off task that is done in Google does not come back
    var doneA = p.tasks; doneA[0].status = "completed"
    precondition(googleToday(doneA, today: "2026-10-19", snoozed: s1).map(\.text) == ["Tomorrow's"])

    // the log: only plain error codes go in; anything else (a task id in a path, text from a browser) becomes "other"
    precondition(logSafe("invalid_client") == "invalid_client" && logSafe("HTTP 403") == "HTTP 403")
    precondition(logSafe("<script>") == "other" && logSafe("/lists/abc/tasks") == "other" && logSafe(String(repeating: "a", count: 60)) == "other")
    // the log file is yours: made 0600 in a 0700 folder; a symlink in its place is refused
    let ld = NSTemporaryDirectory() + "buddy-log-test-\(getpid())", lp = ld + "/sub/google.log"
    try? FileManager.default.removeItem(atPath: ld)
    precondition(openPrivateLog(lp) != nil)
    precondition((try? FileManager.default.attributesOfItem(atPath: lp)[.posixPermissions] as? Int) == 0o600)
    precondition((try? FileManager.default.attributesOfItem(atPath: ld + "/sub")[.posixPermissions] as? Int) == 0o700)
    try? FileManager.default.removeItem(atPath: lp)
    try? FileManager.default.createSymbolicLink(atPath: lp, withDestinationPath: ld + "/target")
    precondition(openPrivateLog(lp) == nil && !FileManager.default.fileExists(atPath: ld + "/target"))
    try? FileManager.default.removeItem(atPath: lp); mkfifo(lp, 0o600)
    precondition(openPrivateLog(lp) == nil)   // a FIFO is refused, and does not hang
    try? FileManager.default.removeItem(atPath: ld + "/sub"); try? FileManager.default.createDirectory(atPath: ld + "/real", withIntermediateDirectories: true)
    try? FileManager.default.createSymbolicLink(atPath: ld + "/sub", withDestinationPath: ld + "/real")
    precondition(openPrivateLog(lp) == nil && !FileManager.default.fileExists(atPath: ld + "/real/google.log"))   // a symlinked folder is refused
    try? FileManager.default.removeItem(atPath: ld)

    // the browser's request can come in pieces: wait for the whole first line, but not for ever
    precondition(readRequestLine(Data("GET /?sta".utf8)) == .more)
    precondition(readRequestLine(Data("GET /?state=st&code=c HTTP/1.1\r\nHost: x".utf8)) == .line("GET /?state=st&code=c HTTP/1.1"))
    precondition(readRequestLine(Data(repeating: 65, count: 8193)) == .tooBig)

    // each sign-in gets a number; forget, a new sign-in or the timeout makes the old number stale, and a stale one saves nothing
    let at = SignInAttempts()
    let first = at.begin(); precondition(at.current(first))
    let second = at.begin(); precondition(!at.current(first) && at.current(second))
    at.end(ifCurrent: first); precondition(at.current(second))   // an old attempt's timeout leaves the new one alone
    at.end(); precondition(!at.current(second))                  // forget ends whatever is running
    // a sign-in that got to saving: the timeout or a new sign-in can't stop it halfway; forget can
    let third = at.begin(); precondition(at.claim(third) && !at.current(third))   // claimed: the timeout's check now sees it ended
    _ = at.begin(); precondition(at.release(third))                               // a new sign-in meanwhile: the save still counts
    let fourth = at.begin(); precondition(at.claim(fourth)); at.end(all: true); precondition(!at.release(fourth))   // forget while saving
    let fifth = at.begin(); at.end(); precondition(!at.claim(fifth))             // ended before saving: nothing is saved
    let rd = googleRedate(["m": GSnooze(until: "2026-10-19", due: "2026-10-18")], tasks: [GTask(id: "m", list: "L", title: "x", status: "needsAction", due: "2026-10-10T00:00:00.000Z", hidden: false, deleted: false)])
    precondition(rd["m"]?.due == "2026-10-10" && dueWindow(today: "2026-11-11", snoozed: rd).min == "2026-10-09T00:00:00.000Z")   // moved earlier: still reached weeks later
    precondition(callbackError("access_denied") == "access_denied" && callbackError("Private task 123") == "other" && callbackError("") == "other")
    let okReply = TokenReply.ok(access: "ya29.a", expiresIn: 3599, refresh: "1//r")
    precondition(signInStep(okReply, current: false) == .stale && signInStep(nil, current: false) == .stale)
    precondition(signInStep(okReply, current: true) == .save(access: "ya29.a", expiresIn: 3599, refresh: "1//r"))
    if case .fail(_, _, let forget) = signInStep(.failed("invalid_client"), current: true) { precondition(forget) } else { preconditionFailure() }
    if case .fail(_, _, let forget) = signInStep(nil, current: true) { precondition(!forget) } else { preconditionFailure() }
    if case .fail = signInStep(.ok(access: "a", expiresIn: 1, refresh: nil), current: true) {} else { preconditionFailure() }

    // the PKCE verifier: 32 random bytes, 43 characters, new each time
    let v1 = randomVerifier(), v2 = randomVerifier()
    precondition(v1?.count == 43 && v2?.count == 43 && v1 != v2)

    callbackServerSelftest()

    precondition(parseGoogleTasks(Data(#"{"items":[{"id":"L1","title":"My Tasks"},{"id":"L2","title":"Work"}]}"#.utf8), list: "").tasks.map(\.id) == ["L1", "L2"])   // tasklists.list has the same shape

    // a failed fetch waits 10 minutes like a good one (it retried every 30 s, all day); a new day fetches at once
    let t9 = Date(timeIntervalSince1970: 1_800_000_000)
    precondition(!googleDue(now: t9, last: t9.addingTimeInterval(-60), lastDay: "2026-10-18", today: "2026-10-18"))
    precondition(googleDue(now: t9, last: t9.addingTimeInterval(-600), lastDay: "2026-10-18", today: "2026-10-18"))
    precondition(googleDue(now: t9, last: t9.addingTimeInterval(-60), lastDay: "2026-10-17", today: "2026-10-18"))

    // the morning bubble: nothing when there is nothing; three names at most
    precondition(googleMorningText([]) == nil)
    precondition(googleMorningText(Array(today.prefix(1))) == "1 Google task today: Call the bank")
    let four = (1...4).map { Todo(text: "T\($0)", gid: "\($0)") }
    precondition(googleMorningText(four) == "4 Google tasks today:\n• T1\n• T2\n• T3\n+ 1 more")
}

/// The real loopback listener, on 127.0.0.1, with a test client: a request in two pieces, a silent connection, too many connections, cancel.
func callbackServerSelftest() {
    func connect(_ port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var tv = timeval(tv_sec: 3, tv_usec: 0); setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_port = port.bigEndian; a.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        precondition(r == 0, "connect to the callback listener")
        return fd
    }
    func put(_ fd: Int32, _ s: String) { _ = s.withCString { send(fd, $0, strlen($0), 0) } }
    /// Everything until the server closes (or 3 s): the reply text, and how long it took.
    func reply(_ fd: Int32) -> (String, TimeInterval) {
        let t0 = Date(); var out = Data(), buf = [UInt8](repeating: 0, count: 4096)
        while true { let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; out.append(contentsOf: buf[0..<n]) }
        close(fd); return (String(decoding: out, as: UTF8.self), Date().timeIntervalSince(t0))
    }
    func serve(deadline: TimeInterval, maxOpen: Int, _ got: @escaping (Callback, @escaping (Int, String) -> Void) -> Void) -> (CallbackServer, UInt16) {
        let s = CallbackServer(state: "st", deadline: deadline, maxOpen: maxOpen, onResult: got), ready = DispatchSemaphore(value: 0)
        var port: UInt16 = 0
        s.start(onReady: { port = $0; ready.signal() }, onFail: { ready.signal() })
        precondition(ready.wait(timeout: .now() + 3) == .success && port != 0, "callback listener ready")
        return (s, port)
    }

    // the request line arrives in two pieces: still one sign-in, and the browser gets the page
    var result: Callback?
    let (s1, p1) = serve(deadline: 5, maxOpen: 4) { r, respond in result = r; respond(200, "done") }
    let c1 = connect(p1); put(c1, "GET /?sta"); usleep(150_000); put(c1, "te=st&code=abc HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    let (text1, _) = reply(c1)
    precondition(result == .code("abc") && text1.hasPrefix("HTTP/1.1 200") && text1.hasSuffix("done</p>"), "split request: \(text1.prefix(40))")
    s1.cancel()
    // forty junk connections, one after another, don't use up the sign-in: the real one still gets through
    var late: Callback?
    let (s5, p5) = serve(deadline: 5, maxOpen: 4) { r, respond in late = r; respond(200, "done") }
    for _ in 0..<40 { let j = connect(p5); put(j, "GET /favicon.ico HTTP/1.1\r\n\r\n"); _ = reply(j) }
    let c5 = connect(p5); put(c5, "GET /?state=st&code=xyz HTTP/1.1\r\n\r\n"); _ = reply(c5)
    precondition(late == .code("xyz"), "the sign-in still works after many connections")
    s5.cancel()

    // a connection that says nothing is closed after its deadline; a fifth at once while four are open; cancel closes the rest
    let (s2, p2) = serve(deadline: 0.4, maxOpen: 4) { _, _ in preconditionFailure("nothing valid was sent") }
    let quiet = connect(p2)
    let (_, waited) = reply(quiet)
    precondition(waited > 0.2 && waited < 2, "a silent connection waits about its deadline, not for ever (\(waited) s)")
    s2.cancel()
    let (s3, p3) = serve(deadline: 30, maxOpen: 4) { _, _ in preconditionFailure("nothing valid was sent") }
    let held = (0..<4).map { _ in connect(p3) }; usleep(200_000)
    let (_, extra) = reply(connect(p3))
    precondition(extra < 1, "over the cap: closed at once (\(extra) s)")
    s3.cancel()
    for fd in held { let (_, t) = reply(fd); precondition(t < 1, "cancel closes the open connections (\(t) s)") }
    // too long a request line: closed, no sign-in
    let (s4, p4) = serve(deadline: 5, maxOpen: 4) { _, _ in preconditionFailure("an oversized request is not a sign-in") }
    let big = connect(p4); put(big, "GET /?" + String(repeating: "a", count: 9000))
    let (text4, t4) = reply(big)
    precondition(t4 < 2 && !text4.contains(" 200 "), "oversized request refused")
    s4.cancel()
}

/// Made-up Google tasks for --snapshot. Never real data.
func googleSamples() -> [Todo] {
    let today = Calendar.current.startOfDay(for: Date())
    return [Todo(text: "Renew the car insurance", due: today, gid: "s1", glist: "L"), Todo(text: "Send the slides to Priya", due: today, gid: "s2", glist: "L")]
}
