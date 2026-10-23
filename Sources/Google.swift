import AppKit
import CryptoKit
import Network
import SwiftUI

// MARK: Google Tasks (opt-in: right-click → Personal → Connect Google Tasks…). Shows your Google tasks due today in the to-do list.
// Off until you sign in: no Google call happens before that. You bring your own OAuth client (README → Google Tasks), so nothing
// secret is in this repo. Sign-in is Google's installed-app flow: PKCE, a one-time listener on 127.0.0.1, your browser.
// The client and the refresh token live in your login Keychain ("Buddy Google Tasks"); the access token only in memory.
// Sign out revokes the token at Google and deletes the Keychain item.

let googleScope = "https://www.googleapis.com/auth/tasks"   // read, and tick done
let googleKeychain = "Buddy Google Tasks"

/// One task from tasks.list. `due` is Google's RFC 3339 text: a day, stored as midnight UTC.
struct GTask: Equatable { var id, list, title, status: String; var due: String?; var hidden = false, deleted = false }
enum TokenReply: Equatable { case ok(access: String, expiresIn: Int, refresh: String?); case revoked; case failed(String) }
enum Callback: Equatable { case code(String); case denied(String); case bad }

// MARK: pure parts (checked by googleSelftest)

func base64url(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
func pkceChallenge(_ verifier: String) -> String { base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }

func googleAuthURL(clientId: String, redirect: String, challenge: String, state: String) -> URL {
    var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    c.queryItems = [.init(name: "client_id", value: clientId), .init(name: "redirect_uri", value: redirect), .init(name: "response_type", value: "code"),
                    .init(name: "scope", value: googleScope), .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
                    .init(name: "state", value: state), .init(name: "prompt", value: "consent")]
    return c.url!
}

/// The first line of the browser's request to the loopback listener → the code, Google's refusal, or not ours.
func callbackResult(_ requestLine: String, state: String) -> Callback {
    let parts = requestLine.split(separator: " ")
    guard parts.count >= 2, parts[0] == "GET", let c = URLComponents(string: "http://127.0.0.1" + parts[1]) else { return .bad }
    let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    guard q["state"] == state else { return .bad }
    if let e = q["error"] { return .denied(e) }
    return q["code"].map(Callback.code) ?? .bad
}

func parseTokenReply(_ data: Data, status: Int) -> TokenReply {
    let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if status == 200, let a = o?["access_token"] as? String { return .ok(access: a, expiresIn: o?["expires_in"] as? Int ?? 3600, refresh: o?["refresh_token"] as? String) }
    if let e = o?["error"] as? String { return e == "invalid_grant" ? .revoked : .failed(e) }   // invalid_grant: expired or revoked; sign in again
    return .failed("HTTP \(status)")
}

/// "2026-10-18T00:00:00.000Z" → "2026-10-18". Read in UTC: it is a day, not a moment, so your time zone must not move it.
func googleDay(_ due: String) -> String? {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
    let day = String(due.prefix(10))
    return f.date(from: day).map(f.string) == day ? day : nil
}

/// dueMin / dueMax for tasks.list: a day either side of today, and back to the day before the oldest task you put off, so Google
/// still sends it. (Google doesn't say whether dueMin counts, so a day of margin either way.)
func dueWindow(today: String, snoozed: [String: GSnooze] = [:]) -> (min: String, max: String) {
    // with put-off tasks, also 30 days back: one whose due day you moved earlier in Google must still come back, or it's pruned
    // as done. ponytail: moved more than 30 days back, it's still lost; a per-task lookup would close that
    let from = ([today] + snoozed.values.map(\.due) + (snoozed.isEmpty ? [] : [shiftDay(today, -30)])).min().map { shiftDay($0, -1) }!
    return (from + "T00:00:00.000Z", shiftDay(today, 1) + "T00:00:00.000Z")
}

/// One page of tasks.list or tasklists.list → items and the next page token.
func parseGoogleTasks(_ data: Data, list: String) -> (tasks: [GTask], next: String?) {
    guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ([], nil) }
    let items = (o["items"] as? [[String: Any]] ?? []).compactMap { t -> GTask? in
        guard let id = t["id"] as? String else { return nil }
        return GTask(id: id, list: list, title: t["title"] as? String ?? "", status: t["status"] as? String ?? "", due: t["due"] as? String,
                     hidden: t["hidden"] as? Bool ?? false, deleted: t["deleted"] as? Bool ?? false)
    }
    return (items, o["nextPageToken"] as? String)
}

/// A task you put off with "☾ tomorrow": hidden in Buddy until `until`, then on the list every day until you tick it.
/// `due` is its Google due day, so the query can still reach it. Kept in Buddy only; Google is not changed.
struct GSnooze: Codable, Equatable { var until, due: String }

/// Put off `id` until the day after `today`. A task put off again keeps its first due day.
func googleSnooze(_ s: [String: GSnooze], id: String, due: String, today: String) -> [String: GSnooze] {
    var out = s; out[id] = GSnooze(until: shiftDay(today, 1), due: s[id]?.due ?? due); return out
}
/// Put-off tasks whose due day you moved earlier in Google: keep the earlier day, so the query keeps reaching them. Selftested.
func googleRedate(_ s: [String: GSnooze], tasks: [GTask]) -> [String: GSnooze] {
    var out = s
    for t in tasks { if let old = s[t.id], let d = t.due.flatMap(googleDay), d < old.due { out[t.id]?.due = d } }
    return out
}
/// Forget put-off tasks that Google no longer sends as open: done or deleted, there or here.
func googlePrune(_ s: [String: GSnooze], open: Set<String>) -> [String: GSnooze] { s.filter { open.contains($0.key) } }

/// Open tasks due on `today` (your local yyyy-MM-dd), and tasks you put off that are back. Not the ones still put off.
func googleToday(_ tasks: [GTask], today: String, snoozed: [String: GSnooze]) -> [Todo] {
    tasks.filter { t in
        guard t.status == "needsAction", !t.hidden, !t.deleted, !t.title.trimmingCharacters(in: .whitespaces).isEmpty, let d = t.due.flatMap(googleDay) else { return false }
        if let s = snoozed[t.id] { return s.until <= today && d <= today }
        return d == today
    }.map { Todo(text: $0.title.trimmingCharacters(in: .whitespaces), due: isoDay.date(from: today), gid: $0.id, glist: $0.list) }
}

func googleMorningText(_ todos: [Todo]) -> String? {
    guard let first = todos.first else { return nil }
    if todos.count == 1 { return "1 Google task today: \(first.text)" }
    return "\(todos.count) Google tasks today:\n" + todos.prefix(3).map { "• \($0.text)" }.joined(separator: "\n") + (todos.count > 3 ? "\n+ \(todos.count - 3) more" : "")
}

/// The small mark on a Google row, in the theme's quiet colour.
func googleMark(_ c: Color) -> some View { Image(systemName: "g.circle.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(c).help("From Google Tasks") }

// MARK: Keychain, through /usr/bin/security so a rebuilt Buddy reads it without a password prompt.
// The value goes in on stdin (security -i), never on a command line where `ps` could see it.

struct GoogleCreds: Codable { var clientId, clientSecret: String; var refresh: String }

func loadGoogleCreds() -> GoogleCreds? {
    guard let out = run("/usr/bin/security", ["find-generic-password", "-s", googleKeychain, "-a", "buddy", "-w"]),
          let b64 = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), let d = Data(base64Encoded: b64) else { return nil }
    return try? JSONDecoder().decode(GoogleCreds.self, from: d)
}
@discardableResult
func saveGoogleCreds(_ c: GoogleCreds) -> Bool {
    guard let d = try? JSONEncoder().encode(c) else { return false }
    let p = Process(), inp = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security"); p.arguments = ["-i"]
    p.standardInput = inp; p.standardOutput = Pipe(); p.standardError = Pipe()
    guard (try? p.run()) != nil else { return false }
    inp.fileHandleForWriting.write("add-generic-password -U -s \"\(googleKeychain)\" -a buddy -l \"\(googleKeychain)\" -w \"\(d.base64EncodedString())\"\n".data(using: .utf8)!)
    inp.fileHandleForWriting.closeFile(); p.waitUntilExit()
    return loadGoogleCreds()?.refresh == c.refresh
}
func deleteGoogleCreds() { run("/usr/bin/security", ["delete-generic-password", "-s", googleKeychain, "-a", "buddy"]) }

let googleLogPath = NSHomeDirectory() + "/Library/Logs/Buddy/google.log"

/// A log file only you can read, or nil. Its folder is made 0700. Refuses a symlink, anything but a plain file, a file with
/// other links, or one you don't own, so another program can't pre-create it to read it or point it at another file.
func openPrivateLog(_ path: String) -> FileHandle? {
    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var ds = stat()
    guard lstat(dir, &ds) == 0, ds.st_mode & S_IFMT == S_IFDIR, ds.st_uid == getuid() else { return nil }   // not a symlink, and yours
    if ds.st_mode & 0o077 != 0 { chmod(dir, 0o700) }
    let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)   // O_NONBLOCK: a FIFO there can't hang Buddy
    guard fd >= 0 else { return nil }
    var st = stat()
    guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid(), st.st_nlink == 1 else { close(fd); return nil }
    if st.st_mode & 0o077 != 0 { fchmod(fd, 0o600) }
    return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
}

/// An error code from Google or the browser, fit for the log: short letters, digits, "_" and spaces, else "other".
func logSafe(_ s: String) -> String { s.range(of: "^[A-Za-z0-9_ ]{1,40}$", options: .regularExpression) != nil ? s : "other" }

/// The `error` a browser redirect carries, for the log: only the codes OAuth defines (RFC 6749 §4.1.2.1), else "other".
/// Anyone can open the callback URL, so its text is never written as is.
func callbackError(_ s: String) -> String {
    ["access_denied", "invalid_request", "unauthorized_client", "unsupported_response_type", "invalid_scope", "server_error",
     "temporarily_unavailable", "admin_policy_enforced", "org_internal", "disallowed_useragent"].contains(s) ? s : "other"
}

/// What Buddy did with Google, for when something goes wrong: fixed events and error codes only, never a token, a task or an id.
func glog(_ s: String) {
    openPrivateLog(googleLogPath)?.write("\(ISO8601DateFormatter().string(from: Date())) \(s)\n".data(using: .utf8)!)
}

/// 32 random bytes as a PKCE verifier, or nil if the system has no randomness to give.
func randomVerifier() -> String? {
    var raw = Data(count: 32)
    guard raw.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }) == errSecSuccess else { return nil }
    return base64url(raw)
}

/// The browser's request, as far as it has come: the first line once it is complete, or too long to be ours.
enum LineRead: Equatable { case more, line(String), tooBig }
func readRequestLine(_ buf: Data, limit: Int = 8192) -> LineRead {
    if let r = buf.range(of: Data("\r\n".utf8)) { return r.lowerBound - buf.startIndex <= limit ? .line(String(decoding: buf[buf.startIndex..<r.lowerBound], as: UTF8.self)) : .tooBig }
    return buf.count > limit ? .tooBig : .more
}

/// Each sign-in gets a number. Forget, a new sign-in or the timeout ends it; an ended sign-in must not save or sign you in.
/// Read from any thread.
final class SignInAttempts {
    private let lock = NSLock(); private var n = 0, live = 0, saving = 0
    func begin() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; live = n; return n }
    func current(_ id: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return id == live }
    /// End the running sign-in; with an id, only if that one is still running. A sign-in already saving is left to finish:
    /// it got past every check, so a new sign-in or the timeout no longer stops it (forget does, with `all`).
    func end(ifCurrent id: Int? = nil, all: Bool = false) { lock.lock(); defer { lock.unlock() }; if id == nil || id == live { live = 0 }; if all { saving = 0 } }
    /// Take the sign-in from running to saving, in one step, so nothing can end it between the check and the Keychain write.
    func claim(_ id: Int) -> Bool { lock.lock(); defer { lock.unlock() }; guard id == live else { return false }; live = 0; saving = id; return true }
    /// After the save: true if no forget came in meanwhile, so it's fine to show Buddy as signed in.
    func release(_ id: Int) -> Bool { lock.lock(); defer { lock.unlock() }; let ok = saving == id; if ok { saving = 0 }; return ok }
}

/// A token Buddy won't keep (the sign-in ended, or the save failed): give it back to Google. True if Google took it back;
/// if not, Buddy can't sign out of it later, and the caller tells you where to remove it (`stillConnected`).
func revokeUnkept(_ refresh: String, _ why: String) -> Bool {
    let code = Google.shared.post("https://oauth2.googleapis.com/revoke", ["token": refresh]).1
    glog("sign in: revoke \(why): HTTP \(code)")
    return code == 200
}
let stillConnected = "Google may still list Buddy as connected. Remove it at myaccount.google.com/permissions."
/// Revoking failed: remember to tell you, and say it at the first moment you can read it (privacy off), from googleTick.
/// Kept in UserDefaults, so a restart, a call or screen-sharing can't lose it.
func noteStillConnected() { UserDefaults.standard.set(true, forKey: "bit.gStillConnected") }

/// What to do with Google's answer to the sign-in code. nil = no network.
enum SignInStep: Equatable { case stale; case save(access: String, expiresIn: Int, refresh: String); case fail(log: String, text: String, forgetClient: Bool) }
func signInStep(_ r: TokenReply?, current: Bool) -> SignInStep {
    guard current else { return .stale }
    switch r {
    case nil: return .fail(log: "token exchange: no network", text: "I couldn't reach Google. Check your connection, then try again.", forgetClient: false)
    case let .ok(a, exp, refresh?)?: return .save(access: a, expiresIn: exp, refresh: refresh)
    case .ok(_, _, nil)?: return .fail(log: "token exchange: ok, but no refresh token", text: "Google signed you in but gave no lasting token. Try again.", forgetClient: false)
    case .revoked?: return .fail(log: "token exchange: invalid_grant", text: "Google didn't accept the sign-in code. Try again.", forgetClient: false)
    case .failed(let e)?:   // a bad client: ask for it again next time
        return .fail(log: "token exchange: \(logSafe(e))", text: "Google didn't accept the sign-in (\(logSafe(e))). Check the client ID and secret, then try again.",
                     forgetClient: e == "invalid_client" || e == "unauthorized_client")
    }
}

/// The one-time sign-in listener on 127.0.0.1 (any free port). Reads each request's first line in as many pieces as it comes,
/// with a deadline per connection and a cap on open connections. cancel() closes the listener and every connection still waiting.
/// The first valid answer (a code or a refusal) goes to onResult once; it replies to the browser through `respond`, from any queue.
final class CallbackServer {
    private let q = DispatchQueue(label: "buddy.google.listen")
    private let state: String, deadline: TimeInterval, maxOpen: Int
    private let onResult: (Callback, @escaping (Int, String) -> Void) -> Void
    private var listener: NWListener?, open: [ObjectIdentifier: NWConnection] = [:], answering: Set<ObjectIdentifier> = [], handled = false, done = false   // q only

    init(state: String, deadline: TimeInterval = 5, maxOpen: Int = 4, onResult: @escaping (Callback, @escaping (Int, String) -> Void) -> Void) {
        self.state = state; self.deadline = deadline; self.maxOpen = maxOpen; self.onResult = onResult
    }

    func start(onReady: @escaping (UInt16) -> Void, onFail: @escaping () -> Void) {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)   // loopback only: nothing else on the network can reach it
        guard let l = try? NWListener(using: params) else { glog("sign in: no listener"); onFail(); return }
        l.stateUpdateHandler = { [weak self] s in
            switch s {
            case .ready: if let p = l.port?.rawValue { onReady(p) }
            case .failed: glog("sign in: listener failed"); self?.stop(force: true); onFail()
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        q.sync { listener = l }
        l.start(queue: q)
    }

    /// `force` (forget, a new sign-in): also close a connection still being answered. Otherwise its page is sent first.
    func cancel(force: Bool = false) { q.async { self.stop(force: force) } }

    private func stop(force: Bool) {   // q
        done = true; listener?.cancel(); listener = nil
        for (k, c) in open where force || !answering.contains(k) { c.cancel() }   // one being answered closes after its page is sent
    }

    private func accept(_ c: NWConnection) {   // q
        guard !done, open.count < maxOpen else { c.cancel(); return }
        let k = ObjectIdentifier(c); open[k] = c
        c.stateUpdateHandler = { [weak self] s in
            switch s { case .cancelled: self?.open[k] = nil; self?.answering.remove(k); case .failed: c.cancel(); default: break }
        }
        c.start(queue: q)
        q.asyncAfter(deadline: .now() + deadline) { [weak self] in if let self, self.open[k] != nil, !self.answering.contains(k) { c.cancel() } }
        q.asyncAfter(deadline: .now() + 60) { c.cancel() }   // even one being answered; holds c, so it fires after the server is gone too
        read(c, Data())
    }

    private func read(_ c: NWConnection, _ buf: Data) {   // q
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] d, _, eof, err in
            guard let self, self.open[ObjectIdentifier(c)] != nil else { return }
            let b = buf + (d ?? Data())
            switch readRequestLine(b) {
            case .more: if eof || err != nil { c.cancel() } else { self.read(c, b) }
            case .tooBig: CallbackServer.respond(c, 431, "Request too large.")
            case .line(let line):
                let r = self.handled ? .bad : callbackResult(line, state: self.state)
                guard r != .bad else { CallbackServer.respond(c, 404, "Not found."); return }   // the favicon, a stray request, or a repeat
                self.handled = true; self.answering.insert(ObjectIdentifier(c))
                self.onResult(r) { code, msg in CallbackServer.respond(c, code, msg) }
            }
        }
    }

    static func respond(_ c: NWConnection, _ code: Int, _ msg: String) {
        let body = "<!doctype html><meta charset=utf-8><title>Buddy</title><body style=\"font:16px -apple-system;margin:4em;text-align:center\"><p>\(msg)</p>"
        let reason = code == 200 ? "OK" : code == 431 ? "Request Header Fields Too Large" : "Not Found"
        c.send(content: "HTTP/1.1 \(code) \(reason)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".data(using: .utf8),
               completion: .contentProcessed { _ in c.cancel() })
    }
}

/// Time to ask Google again? Every 10 minutes, whether the last try worked or not, and at once on a new day.
func googleDue(now: Date, last: Date, lastDay: String, today: String) -> Bool { now.timeIntervalSince(last) >= 600 || lastDay != today }

// MARK: the connection

enum GErr: Error, Equatable { case offline, revoked, failed(String) }

/// Google state. `gq` does every network and Keychain call; the rest is main-thread only unless marked.
final class Google {
    static let shared = Google()
    let gq = DispatchQueue(label: "buddy.google")   // one call at a time: no two refreshes race
    var checked = false, signedIn = false   // signedIn is read from the Keychain once, on gq, at the first dayCare
    var hasClient = false                   // your OAuth client is in the Keychain (stays after access ends, until sign out)
    var epoch = 0                           // +1 on sign-in, sign-out and lost access: answers from before are dropped
    var raw: [GTask] = []                   // the last fetch, before today's filter
    var doneAt: [String: Date] = [:]        // ticked in Buddy: hidden until a fetch that started after Google said OK
    var lastFetch = Date.distantPast, fetchedDay = "", busy = false
    var freshDay = ""   // the day of the last fetch that succeeded: the morning bubble waits for today's list
    var access: String?, accessUntil = Date.distantPast   // gq only
    var server: CallbackServer?             // the sign-in listener, while a sign-in runs
    let attempts = SignInAttempts()

    /// POST a form, wait for the reply. nil data = no network.
    func post(_ url: String, _ form: [String: String]) -> (Data?, Int) {
        var r = URLRequest(url: URL(string: url)!, timeoutInterval: 15); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        r.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        return send(r)
    }
    func send(_ r: URLRequest) -> (Data?, Int) {
        var out: (Data?, Int) = (nil, 0)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: r) { d, resp, _ in out = (d, (resp as? HTTPURLResponse)?.statusCode ?? 0); done.signal() }.resume()
        done.wait(); return out
    }

    /// A live access token, refreshed a minute before it runs out. On gq.
    func token() -> Result<String, GErr> {
        if let a = access, Date() < accessUntil { return .success(a) }
        guard let c = loadGoogleCreds(), !c.refresh.isEmpty else { return .failure(.revoked) }
        let (d, code) = post("https://oauth2.googleapis.com/token", ["client_id": c.clientId, "client_secret": c.clientSecret, "refresh_token": c.refresh, "grant_type": "refresh_token"])
        guard let d else { glog("refresh: no network"); return .failure(.offline) }
        switch parseTokenReply(d, status: code) {
        case let .ok(a, exp, _): access = a; accessUntil = Date().addingTimeInterval(Double(exp) - 60); glog("refresh: ok"); return .success(a)
        case .revoked: glog("refresh: invalid_grant (revoked or expired)"); return .failure(.revoked)
        case .failed(let e): glog("refresh: \(logSafe(e))"); return .failure(.failed(logSafe(e)))
        }
    }

    /// One Tasks API call with the token; a 401 gets one fresh token and one retry. On gq.
    /// `what` names the call in the log ("lists", "tasks", "tick"): the URL has list and task ids, so it stays out.
    func api(_ method: String, _ url: URL, what: String, json: [String: Any]? = nil) -> Result<Data, GErr> {
        for attempt in 0..<2 {
            let t: String
            switch token() { case .success(let s): t = s; case .failure(let e): return .failure(e) }
            var r = URLRequest(url: url, timeoutInterval: 15); r.httpMethod = method
            r.setValue("Bearer " + t, forHTTPHeaderField: "Authorization")
            if let json { r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.httpBody = try? JSONSerialization.data(withJSONObject: json) }
            let (d, code) = send(r)
            guard let d else { glog("\(what): no network"); return .failure(.offline) }
            if code == 401 && attempt == 0 { access = nil; continue }
            guard (200..<300).contains(code) else { glog("\(what): HTTP \(code)"); return .failure(.failed("HTTP \(code)")) }
            return .success(d)
        }
        return .failure(.failed("HTTP 401"))
    }

    /// Every list's open tasks due within a day of today, or since the oldest task you put off. On gq.
    func fetch(today: String, snoozed: [String: GSnooze]) -> Result<[GTask], GErr> {
        let base = "https://tasks.googleapis.com/tasks/v1"
        var lists: [String] = [], page: String? = nil
        repeat {
            var c = URLComponents(string: base + "/users/@me/lists")!
            c.queryItems = [.init(name: "maxResults", value: "100")] + (page.map { [.init(name: "pageToken", value: $0)] } ?? [])
            switch api("GET", c.url!, what: "lists") {
            case .success(let d): let p = parseGoogleTasks(d, list: ""); lists += p.tasks.map(\.id); page = p.next
            case .failure(let e): return .failure(e)
            }
        } while page != nil
        let w = dueWindow(today: today, snoozed: snoozed)
        var all: [GTask] = []
        for l in lists {
            page = nil
            repeat {
                var c = URLComponents(string: base + "/lists/\(pathPart(l))/tasks")!
                c.queryItems = [.init(name: "dueMin", value: w.min), .init(name: "dueMax", value: w.max), .init(name: "showCompleted", value: "false"), .init(name: "showAssigned", value: "true"),
                                .init(name: "maxResults", value: "100")] + (page.map { [.init(name: "pageToken", value: $0)] } ?? [])
                switch api("GET", c.url!, what: "tasks") {
                case .success(let d): let p = parseGoogleTasks(d, list: l); all += p.tasks; page = p.next
                case .failure(let e): return .failure(e)
                }
            } while page != nil
        }
        glog("fetch: \(lists.count) lists, \(all.count) tasks in the window")
        return .success(all)
    }
}
func pathPart(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? s }

extension Model {
    var googleSignedIn: Bool { Google.shared.signedIn }
    var googleHasClient: Bool { Google.shared.hasClient }

    /// "☾ tomorrow" on Google rows (see GSnooze). Kept in Buddy only; Google is not changed.
    private var googleSnoozed: [String: GSnooze] {
        get { UserDefaults.standard.data(forKey: "bit.gsnooze").flatMap { try? JSONDecoder().decode([String: GSnooze].self, from: $0) } ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "bit.gsnooze") }
    }
    func showGoogle() {
        let g = Google.shared
        let t = googleToday(g.raw.filter { g.doneAt[$0.id] == nil }, today: isoDay.string(from: Date()), snoozed: googleSnoozed)
        if t != google { google = t }
    }

    /// From dayCare (every 30 s while you're at the Mac). First time: read the Keychain off the main thread. Then fetch every 10 minutes.
    func googleTick(_ now: Date) {
        if !privacy, UserDefaults.standard.bool(forKey: "bit.gStillConnected") {   // a token Buddy couldn't revoke: tell you, once you can read it
            UserDefaults.standard.removeObject(forKey: "bit.gStillConnected")
            say(stillConnected, .waiting, seconds: 30)   // an event: shown even on a call, and kept in the inbox
        }
        let g = Google.shared, today = isoDay.string(from: now)
        if !g.checked {
            g.checked = true
            let epoch = g.epoch
            g.gq.async { let c = loadGoogleCreds(), on = !(c?.refresh ?? "").isEmpty; DispatchQueue.main.async { guard g.epoch == epoch else { return }; g.hasClient = c != nil; if on { g.signedIn = true; self.fetchGoogle() } } }
            return
        }
        guard g.signedIn, !g.busy, googleDue(now: now, last: g.lastFetch, lastDay: g.fetchedDay, today: today) else { return }
        fetchGoogle()
    }

    func fetchGoogle() {
        let g = Google.shared, today = isoDay.string(from: Date()), epoch = g.epoch, started = Date(), snoozed = googleSnoozed
        g.busy = true; g.lastFetch = started; g.fetchedDay = today
        g.gq.async {
            let r = g.fetch(today: today, snoozed: snoozed)
            DispatchQueue.main.async {
                g.busy = false
                guard g.epoch == epoch else { return }   // signed out (or in again) meanwhile
                switch r {
                case .success(let t):
                    g.raw = t; g.freshDay = today
                    let redated = googleRedate(self.googleSnoozed, tasks: t)
                    if redated != self.googleSnoozed { self.googleSnoozed = redated }
                    // put-off tasks this fetch asked for but Google no longer has open: forget them (ones put off since, keep)
                    let gone = Set(snoozed.keys).subtracting(googlePrune(snoozed, open: Set(t.filter { $0.status == "needsAction" && !$0.deleted }.map(\.id))).keys)
                    if !gone.isEmpty { self.googleSnoozed = self.googleSnoozed.filter { !gone.contains($0.key) } }
                    g.doneAt = g.doneAt.filter { $0.value >= started }   // this fetch saw those ticks: Google has them
                    self.showGoogle()
                case .failure(.revoked): self.googleLost()
                case .failure(.offline): self.showGoogle()   // keep the last list; try again in 10 minutes, quietly
                case .failure(.failed(let e)):
                    self.showGoogle()
                    if Day.once("gtasks-error") {
                        let hint = e == "HTTP 403" ? " Is the Google Tasks API enabled in your Cloud project?" : e == "invalid_client" ? " Your OAuth client was deleted or its secret changed: sign out of Google Tasks, then connect again." : ""
                        self.say("Google Tasks isn't working (\(e)).\(hint) Details: ~/Library/Logs/Buddy/google.log", .calm, seconds: 20, kind: .ambient)
                    }
                }
            }
        }
    }

    /// The refresh token stopped working (you revoked Buddy, or it expired). Forget it, keep your client, say so once.
    func googleLost() {
        let g = Google.shared
        guard g.signedIn else { return }
        g.signedIn = false; g.epoch += 1; g.raw = []; g.doneAt = [:]; google = []
        g.gq.async { g.access = nil; if var c = loadGoogleCreds() { c.refresh = ""; saveGoogleCreds(c) } }
        say("Google Tasks stopped working: access ended or expired. Right-click → Personal → Connect Google Tasks… to sign in again.", .calm, seconds: 30, kind: .ambient)
    }

    func tickGoogle(_ t: Todo) {
        guard let id = t.gid, let list = t.glist else { return }
        let g = Google.shared, epoch = g.epoch
        g.doneAt[id] = .distantFuture; showGoogle(); celebrate += 1   // gone at once; back if Google says no
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(pathPart(list))/tasks/\(pathPart(id))")!
        g.gq.async {
            let r = g.api("PATCH", url, what: "tick", json: ["status": "completed"])
            DispatchQueue.main.async {
                guard g.epoch == epoch else { return }
                switch r {
                case .success: glog("tick: ok"); g.doneAt[id] = Date()
                case .failure(.revoked): self.googleLost()
                case .failure: g.doneAt[id] = nil; self.showGoogle(); self.say("I couldn't mark \"\(t.text)\" done in Google. It's back on the list.", .calm, seconds: 10, kind: .ambient)
                }
            }
        }
    }

    func snoozeGoogle(_ t: Todo) {
        guard let id = t.gid else { return }
        let today = isoDay.string(from: Date()), due = Google.shared.raw.first { $0.id == id }?.due.flatMap(googleDay) ?? today
        googleSnoozed = googleSnooze(googleSnoozed, id: id, due: due, today: today); showGoogle()
    }

    /// Once a day, 10:00–12:00, if Google has tasks for today. Privacy mode keeps it for later rather than spending it.
    func googleNudge(_ now: Date) -> Bool {
        let h = Calendar.current.component(.hour, from: now)
        // today's list, not yesterday's left over from a Mac that slept: wait until a fetch has succeeded today
        guard !privacy, (10..<12).contains(h), Google.shared.freshDay == isoDay.string(from: now), let text = googleMorningText(google), Day.once("gtasks") else { return false }
        say(text, .calm, seconds: 30, kind: .ambient) { self.bubble = nil; self.tab = "personal"; self.showCard = true; self.onExpandChange?() }
        return true
    }

    /// Revoke at Google, delete the Keychain item (client and token). Also works after access was lost, to forget the client.
    /// Ends a sign-in still running, so finishing it in the browser afterwards saves nothing.
    func signOutGoogle() {
        let g = Google.shared
        g.attempts.end(all: true); g.server?.cancel(force: true); g.server = nil
        g.signedIn = false; g.hasClient = false; g.epoch += 1; g.raw = []; g.doneAt = [:]; google = []
        g.gq.async {
            g.access = nil
            var revoked = true
            if let c = loadGoogleCreds(), !c.refresh.isEmpty {   // revoking the refresh token ends Buddy's access at Google too
                let code = g.post("https://oauth2.googleapis.com/revoke", ["token": c.refresh]).1
                glog("revoke: HTTP \(code)"); revoked = code == 200
            }
            deleteGoogleCreds()
            let gone = loadGoogleCreds() == nil
            glog("sign out: keychain item \(gone ? "deleted" : "NOT deleted")")
            DispatchQueue.main.async {
                var text = gone ? "Signed out of Google Tasks. I deleted the token from your Keychain." : "Signed out, but I couldn't delete the Keychain item \"\(googleKeychain)\". Delete it in Keychain Access."
                if !revoked { noteStillConnected() }   // said on its own, when you can read it
                self.say(text, .calm, seconds: 20, kind: .ambient)
            }
        }
    }

    /// Ask for your OAuth client (once), then sign in in your browser. The Keychain is read on gq: a locked one must not freeze Buddy.
    func connectGoogle() {
        let g = Google.shared, epoch = g.epoch   // forget (sign out) bumps epoch: a Connect still reading the Keychain then stops
        g.gq.async { let saved = loadGoogleCreds(); DispatchQueue.main.async { guard g.epoch == epoch else { glog("connect: dropped after forget"); return }; self.connectGoogle(saved) } }
    }
    private func connectGoogle(_ saved: GoogleCreds?) {
        var c = saved ?? GoogleCreds(clientId: "", clientSecret: "", refresh: "")
        if c.clientId.isEmpty || c.clientSecret.isEmpty {
            guard let id = try? ask("Connect Google Tasks\n\nBuddy uses your own Google OAuth client, type \"Desktop app\". README → Google Tasks has the 5-minute setup.\n\nPaste the client ID:", "1234-abc.apps.googleusercontent.com"),
                  !id.isEmpty else { return }
            guard id.hasSuffix(".apps.googleusercontent.com") else { say("That doesn't look like a client ID. It ends in .apps.googleusercontent.com.", .calm, seconds: 10, kind: .ambient); return }
            guard let secret = try? ask("Now paste that client's secret.\nIt stays in your Keychain.", "GOCSPX-…"), !secret.isEmpty else { return }
            c = GoogleCreds(clientId: id, clientSecret: secret, refresh: "")
        }
        signInGoogle(c)
    }

    /// The installed-app flow: listen on 127.0.0.1, open Google's page, take the code, swap it for tokens.
    /// A new sign-in, forget, or the 5-minute timeout ends this one: it then saves nothing and says nothing.
    func signInGoogle(_ c: GoogleCreds) {
        let g = Google.shared
        g.attempts.end(); g.server?.cancel(force: true); g.server = nil
        guard let verifier = randomVerifier() else { glog("sign in: no random bytes"); say("I couldn't start the sign-in. Try again?", .calm, seconds: 10, kind: .ambient); return }
        let me = g.attempts.begin(), state = UUID().uuidString
        var redirect = ""   // set when the listener is ready, before any request can arrive
        weak var mine: CallbackServer?   // this sign-in's listener: a newer sign-in may own g.server by the time this one saves
        /// End this sign-in (if it is still the one running) and say how it went.
        func finish(_ text: String) {
            DispatchQueue.main.async {
                guard g.attempts.current(me) else { return }
                g.attempts.end(); g.server?.cancel(); g.server = nil
                self.say(text, .calm, seconds: 12, kind: .ambient)
            }
        }
        let server = CallbackServer(state: state) { result, respond in
            switch result {
            case .bad: break   // the server answers those itself
            case .denied(let e): glog("sign in: denied (\(callbackError(e)))"); respond(200, "Sign-in cancelled. You can close this tab."); finish("Google sign-in cancelled.")
            case .code(let code):
                glog("sign in: got a code")
                g.gq.async {
                    let stale = { glog("sign in: ended in Buddy, code dropped"); respond(200, "This sign-in was cancelled in Buddy. You can close this tab.") }
                    guard g.attempts.current(me) else { stale(); return }
                    let (d, status) = g.post("https://oauth2.googleapis.com/token", ["client_id": c.clientId, "client_secret": c.clientSecret, "code": code,
                                                                                     "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": redirect])
                    let reply = d.map { parseTokenReply($0, status: status) }
                    switch signInStep(reply, current: g.attempts.current(me)) {
                    case .stale:   // ended while Google answered: give back what it gave, so no grant is left that Buddy can't sign out of
                        if case .ok(_, _, let r?)? = reply, !revokeUnkept(r, "after end") { noteStillConnected() }
                        stale()
                    case let .fail(log, text, forgetClient):
                        glog("sign in: " + log)
                        if forgetClient { deleteGoogleCreds(); DispatchQueue.main.async { g.hasClient = false } }
                        respond(200, "Buddy couldn't finish the sign-in. See Buddy's bubble."); finish(text)
                    case let .save(access, exp, refresh):
                        // claim: from here the timeout or a new sign-in can't strand a half-done save; forget still wins, because
                        // it queues its Keychain delete on gq after this save and clears the claim (release then says no)
                        guard g.attempts.claim(me) else { if !revokeUnkept(refresh, "after end") { noteStillConnected() }; stale(); return }
                        var saved = c; saved.refresh = refresh
                        guard saveGoogleCreds(saved) else {
                            _ = g.attempts.release(me); glog("sign in: keychain save failed")
                            // Buddy can't sign out of a token it couldn't keep: give it back to Google now
                            if !revokeUnkept(refresh, "after failed save") { noteStillConnected() }
                            respond(200, "Buddy couldn't finish the sign-in. See Buddy's bubble.")
                            DispatchQueue.main.async { mine?.cancel(); if g.server === mine { g.server = nil }; self.say("I couldn't save the token to your Keychain.", .calm, seconds: 15, kind: .ambient) }
                            return
                        }
                        g.access = access; g.accessUntil = Date().addingTimeInterval(Double(exp) - 60)
                        glog("sign in: ok")
                        respond(200, "🐾 Buddy is connected to Google Tasks. You can close this tab.")
                        DispatchQueue.main.async {
                            guard g.attempts.release(me) else { return }   // forgotten while saving: the queued sign-out deletes what was saved and clears access
                            mine?.cancel(); if g.server === mine { g.server = nil }
                            g.signedIn = true; g.hasClient = true; g.checked = true; g.epoch += 1; self.fetchGoogle()
                            self.say("Connected to Google Tasks ✓ Today's tasks show in your to-do list.", .calm, seconds: 12, kind: .ambient)
                        }
                    }
                }
            }
        }
        g.server = server; mine = server
        server.start(onReady: { port in
            redirect = "http://127.0.0.1:\(port)"
            glog("sign in: listening")
            DispatchQueue.main.async {
                guard g.attempts.current(me) else { return }
                NSWorkspace.shared.open(googleAuthURL(clientId: c.clientId, redirect: redirect, challenge: pkceChallenge(verifier), state: state))
                self.say("Finish signing in to Google in your browser 🌐", .calm, seconds: 20, kind: .ambient)
            }
        }, onFail: { finish("The sign-in stopped. Try again?") })
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { if g.attempts.current(me) { glog("sign in: timed out"); finish("The Google sign-in timed out. Try again when you're ready.") } }
    }
}
