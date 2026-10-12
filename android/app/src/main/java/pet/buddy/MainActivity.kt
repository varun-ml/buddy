package pet.buddy

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.app.TimePickerDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.thread

/**
 * The card, on the phone: what needs you, what's stuck, what's running, what finished and what it said, and today's inbox.
 * Largest type only for what needs action. Settings and help are bottom sheets.
 */
class MainActivity : Activity() {
    private lateinit var prefs: Prefs
    private lateinit var col: LinearLayout
    private lateinit var bar: LinearLayout
    private val main = Handler(Looper.getMainLooper())
    private var inbox = JSONArray()
    private var lastCard: JSONObject? = null
    private var lastCardAt = 0.0
    private val open = mutableSetOf<String>()   // expanded rows (their details showing)
    private var allInbox = false
    private val tick = object : Runnable { override fun run() { load(); main.postDelayed(this, 5000) } }
    private val svc get() = BuddyService.instance

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        prefs = Prefs(this)
        window.statusBarColor = C.ground
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(12), dp(16), dp(12), dp(96)) }
        bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setBackgroundColor(C.platter); elevation = dp(8).toFloat() }
        setContentView(FrameLayout(this).apply {
            setBackgroundColor(C.ground)
            addView(ScrollView(this@MainActivity).apply { addView(col) })
            addView(bar, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(64), Gravity.BOTTOM))
            // Android 15 draws behind the status and navigation bars: keep content out from under them
            setOnApplyWindowInsetsListener { v, insets ->
                val sb = insets.getInsets(android.view.WindowInsets.Type.systemBars())
                v.setPadding(0, sb.top, 0, 0)
                bar.layoutParams = (bar.layoutParams as FrameLayout.LayoutParams).apply { height = dp(64) + sb.bottom }
                bar.setPadding(0, 0, 0, sb.bottom)
                insets
            }
        })
        pair(intent)
        if (prefs.paired && svc == null) start()
    }

    override fun onNewIntent(i: Intent) { super.onNewIntent(i); pair(i) }

    /** buddy://pair?url=…&token=… (the QR code from `buddy pair` on the Mac) */
    private fun pair(i: Intent?) {
        val u = i?.data ?: return
        if (u.scheme != "buddy" || u.host != "pair") return
        prefs.url = u.getQueryParameter("url") ?: return
        prefs.token = u.getQueryParameter("token") ?: return
        prefs.lastId = 0
        Toast.makeText(this, "Paired with your Mac", Toast.LENGTH_SHORT).show()
        start()
        if (!prefs.helpSeen) main.postDelayed({ help() }, 800)
    }

    override fun onResume() {
        super.onResume()
        svc?.onChange = { main.post { render() } }
        main.post(tick)
    }

    override fun onPause() {
        super.onPause()
        svc?.onChange = null
        main.removeCallbacks(tick)
    }

    private fun start() {
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        if (!Settings.canDrawOverlays(this))
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        startForegroundService(Intent(this, BuddyService::class.java))
        main.postDelayed({ svc?.onChange = { main.post { render() } }; render() }, 500)
    }

    private fun load() = thread {
        if (!prefs.paired) { main.post { render() }; return@thread }
        try {
            val all = JSONArray(String(prefs.get("/inbox?after=0")))
            main.post { inbox = all; render() }
            svc?.refresh()
        } catch (_: Exception) { main.post { render() } }
    }

    // ---- screen

    private fun render() {
        col.removeAllViews()
        renderBar()
        if (!prefs.paired) { unpaired(); return }
        val s = svc
        val card = s?.card
        val online = s?.online == true
        if (card != null && online) { lastCard = card; lastCardAt = System.currentTimeMillis() / 1000.0 }
        val shown = card ?: lastCard
        header(shown, online)
        when {
            s == null -> banner("Buddy is off", "Start", C.chip) { start() }
            !online -> banner("Mac unreachable" + (if (lastCardAt > 0) " · as of ${hm(lastCardAt)}" else ""), "Retry", C.redBg) { s.refresh(); load() }
            prefs.muted -> banner("Muted until ${hm(prefs.mutedUntil / 1000.0)}", "Unmute", C.chip) { mute() }
            prefs.quiet() -> banner("Quiet hours until ${prefs.quietTo}:00 · notifications only", null, C.chip) {}
        }
        if (shown == null) { col.addView(label("Connecting…", 15f, C.sub).apply { setPadding(dp(4), dp(16), 0, 0) }); return }
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; alpha = if (online) 1f else 0.5f }
        col.addView(body)
        val waiting = rows(shown, "waiting"); val stuck = rows(shown, "stuck"); val working = rows(shown, "working"); val done = rows(shown, "yourTurn")
        if (waiting.isNotEmpty()) { section(body, "Wants your OK", null); waiting.forEach { body.addView(waitingRow(it, online)) } }
        if (stuck.isNotEmpty()) { section(body, "Stuck", null); stuck.forEach { body.addView(stuckRow(it, online)) } }
        if (working.isNotEmpty()) { section(body, "Running", "${working.size}"); body.addView(platter(working.map { runningRow(it, online) })) }
        if (done.isNotEmpty()) { section(body, "Done", "${done.size}"); body.addView(platter(done.map { doneRow(it, online) })) }
        if (waiting.isEmpty() && stuck.isEmpty() && working.isEmpty() && done.isEmpty()) body.addView(allClear())
        inboxSection(body)
    }

    private fun mute() {
        svc?.toggleMute() ?: run { prefs.mutedUntil = if (prefs.muted) 0 else System.currentTimeMillis() + 3600_000 }
        render()
    }

    private fun rows(card: JSONObject, key: String): List<JSONObject> {
        val a = card.optJSONArray(key) ?: return emptyList()
        return (0 until a.length()).map { a.getJSONObject(it) }
    }

    private fun header(card: JSONObject?, online: Boolean) {
        val waiting = card?.optJSONArray("waiting")?.length() ?: 0
        val running = card?.optJSONArray("working")?.length() ?: 0
        val mood = if (prefs.muted) "asleep" else card?.str("mood") ?: "calm"
        val row = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(dp(4), dp(8), dp(4), dp(12)) }
        row.addView(avatar(mood, 48), LinearLayout.LayoutParams(dp(48), dp(48)).apply { marginEnd = dp(12) })
        val t = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val head = when {
            card == null -> "Buddy"
            waiting == 1 -> "1 needs your OK"
            waiting > 1 -> "$waiting need your OK"
            else -> card.str("headline")
        }
        t.addView(label(head, 24f, if (waiting > 0) C.orange else C.ink, medium = true, lines = 2))
        val host = Uri.parse(prefs.url).host ?: "Mac"
        val state = when {
            svc == null -> "Off"
            !online -> "Unreachable"
            prefs.muted -> "Muted"
            else -> "Live"
        }
        val line = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL; setPadding(0, dp(4), 0, 0) }
        line.addView(View(this).apply { background = shape(if (state == "Live") C.running else if (state == "Unreachable") C.red else C.sub, dp(4).toFloat()) },
            LinearLayout.LayoutParams(dp(8), dp(8)).apply { marginEnd = dp(6) })
        line.addView(label("$state · $host" + if (running > 0) " · $running running" else "", 14f, C.sub))
        t.addView(line)
        row.addView(t, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(label("?", 18f, C.sub, medium = true).apply {
            gravity = Gravity.CENTER; background = shape(0, dp(16).toFloat(), dp(2), C.hairline)
            setOnClickListener { help() }
        }, LinearLayout.LayoutParams(dp(32), dp(32)).apply { marginStart = dp(8) })
        col.addView(row)
    }

    private fun avatar(mood: String, size: Int) = ImageView(this).apply {
        val f = File(filesDir, "$mood.png")
        if (f.exists()) setImageBitmap(BitmapFactory.decodeFile(f.path)) else setImageResource(R.drawable.icon)
        background = shape(C.platter, dp(size / 2).toFloat()); clipToOutline = true
        setPadding(dp(4), dp(4), dp(4), dp(4))
    }

    private fun banner(text: String, action: String?, bg: Int, f: () -> Unit) {
        val row = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; background = shape(bg, dp(14).toFloat()); setPadding(dp(14), dp(10), dp(14), dp(10))
        }
        row.addView(label(text, 14f, C.ink, lines = 2), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (action != null) row.addView(label(action, 14f, C.accent, medium = true).apply {
            setPadding(dp(12), dp(6), 0, dp(6)); setOnClickListener { f() }
        })
        col.addView(row, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(8) })
    }

    private fun section(into: LinearLayout, title: String, count: String?) {
        val row = LinearLayout(this).apply { setPadding(dp(8), dp(16), dp(8), dp(6)) }
        row.addView(label(title.uppercase(), 13f, C.sub, medium = true).apply { letterSpacing = 0.04f },
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        if (count != null) row.addView(label(count, 13f, C.sub, medium = true))
        into.addView(row)
    }

    private fun platter(rows: List<View>) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL; background = shape(C.platter, dp(16).toFloat()); clipToOutline = true
        rows.forEachIndexed { i, r ->
            if (i > 0) addView(View(this@MainActivity).apply { setBackgroundColor(C.hairline) },
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1).apply { marginStart = dp(56) })
            addView(r)
        }
    }

    /** icon · (title, line, details…) · right column */
    private fun row(icon: View?, iconSize: Int, title: View, sub: View?, right: List<View>, pad: Int = 10, extra: List<View> = emptyList()) =
        LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(56); setPadding(dp(14), dp(pad), dp(14), dp(pad))
            if (icon != null) addView(icon, LinearLayout.LayoutParams(dp(iconSize), dp(iconSize)).apply { marginEnd = dp(12); gravity = Gravity.TOP; topMargin = dp(2) })
            addView(LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                addView(title)
                if (sub != null) addView(sub.apply { setPadding(0, dp(4), 0, 0) })
                extra.forEach { addView(it) }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            if (right.isNotEmpty()) addView(LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL; gravity = Gravity.END
                right.forEach { addView(it) }
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { marginStart = dp(8) })
        }

    private fun isCodex(s: JSONObject) = s.str("source").startsWith("codex")

    private fun waitingRow(s: JSONObject, online: Boolean): View {
        val r = row(agentIcon(s.str("source"), 40), 40, label(s.str("repo"), 18f, C.ink, medium = true),
            label(s.str("activity"), 14f, C.orange, mono = true),
            listOf(label(if (isCodex(s)) "At Mac" else "Answer ›", 14f, if (isCodex(s)) C.sub else C.orange, medium = true),
                label(if (online) ago(s.optDouble("ts")) else "–", 14f, C.sub).apply { setPadding(0, dp(4), 0, 0) }), pad = 14)
        r.minimumHeight = dp(76); r.background = shape(C.orangeBg, dp(16).toFloat())
        r.setOnClickListener { answer(s) }
        return r.withMargin()
    }

    private fun stuckRow(s: JSONObject, online: Boolean): View {
        val r = row(agentIcon(s.str("source"), 32), 32,
            label("${s.str("repo")} · quiet ${if (online) ago(s.optDouble("ts")) else "–"}", 16f, C.red, medium = true),
            label(s.str("activity"), 13f, C.sub, mono = true), emptyList())
        r.background = shape(C.redBg, dp(16).toFloat())
        r.setOnClickListener { answer(s) }
        return r.withMargin()
    }

    private fun runningRow(s: JSONObject, online: Boolean): View {
        val title = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
        title.addView(label(s.str("repo"), 16f, C.ink, medium = true))
        title.addView(View(this).apply { background = shape(C.running, dp(4).toFloat()) },
            LinearLayout.LayoutParams(dp(7), dp(7)).apply { marginStart = dp(6) })
        val since = s.optDouble("turnStart").takeIf { !it.isNaN() && it > 0 } ?: s.optDouble("ts")
        return row(agentIcon(s.str("source"), 32), 32, title, label(s.str("activity"), 13f, C.sub, mono = true),
            listOf(label(if (online) ago(since) else "–", 14f, C.sub)))
    }

    private fun doneRow(s: JSONObject, online: Boolean): View {
        val id = "s:" + s.str("id")
        val said = s.str("spoken").ifEmpty { s.str("said").ifEmpty { s.str("prompt") } }
        val r = row(agentIcon(s.str("source"), 32), 32, label(s.str("repo"), 16f, C.ink, medium = true),
            label(said, 15f, C.ink, lines = if (id in open) 6 else 2),
            listOf(label(if (online) "done ${ago(s.optDouble("ts"))}" else "done", 14f, C.done, medium = true)),
            extra = if (id in open) detailViews(s.optJSONArray("details")) else emptyList())
        r.setOnClickListener { if (!open.add(id)) open.remove(id); render() }
        return r
    }

    private fun detailViews(d: JSONArray?): List<View> =
        if (d == null) emptyList() else (0 until d.length()).map { i ->
            label("• " + d.optString(i), 14f, C.ink, lines = 3).apply { setPadding(0, dp(6), 0, 0) }
        }

    private fun allClear() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL
        background = shape(C.platter, dp(16).toFloat()); setPadding(dp(16), dp(24), dp(16), dp(24))
        addView(avatar("calm", 72), LinearLayout.LayoutParams(dp(72), dp(72)))
        addView(label("Nothing needs you", 18f, C.ink, medium = true).apply { setPadding(0, dp(12), 0, 0) })
        addView(label("Buddy will speak up when a session finishes or waits for you.", 14f, C.sub, lines = 3).apply {
            gravity = Gravity.CENTER; setPadding(0, dp(6), 0, 0)
        })
    }.withMargin(top = 8)

    private fun inboxSection(into: LinearLayout) {
        val events = (0 until inbox.length()).map { inbox.getJSONObject(it) }.filter { it.str("kind") != "resolve" }.reversed()
        if (events.isEmpty()) return
        section(into, "Today", "${events.size}")
        val shown = if (allInbox) events else events.take(5)
        val rows = shown.map { e -> inboxRow(e) }.toMutableList<View>()
        if (events.size > shown.size) rows += label("Show ${events.size - shown.size} earlier", 14f, C.accent, medium = true).apply {
            setPadding(dp(14), dp(14), dp(14), dp(14)); setOnClickListener { allInbox = true; render() }
        }
        into.addView(platter(rows))
    }

    private fun inboxRow(e: JSONObject): View {
        val id = "e:" + e.optLong("id")
        val kind = e.str("kind")
        val left = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL
            addView(label(hm(e.optDouble("at")), 13f, C.sub))
            addView(View(this@MainActivity).apply { background = shape(C.kind(kind), dp(4).toFloat()) },
                LinearLayout.LayoutParams(dp(8), dp(8)).apply { topMargin = dp(6) })
        }
        val repo = e.str("repo")
        val spoken = e.str("spoken").removePrefix("$repo is done.").removePrefix("$repo:").trim()   // the title already says it
        val r = row(left, 40, label(e.str("text").substringBefore("\n"), 15f, C.ink, medium = true),
            if (spoken.isNotEmpty()) label(spoken, 14f, C.sub, lines = if (id in open) 6 else 2) else null, emptyList(),
            extra = if (id in open) detailViews(e.optJSONArray("details")) else emptyList())
        r.setOnClickListener { if (!open.add(id)) open.remove(id); render() }
        return r
    }

    private fun View.withMargin(top: Int = 0) = apply {
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            .apply { bottomMargin = dp(8); topMargin = dp(top) }
    }

    /** The phone can't approve: open the Claude app (Remote Control) to answer. Codex sessions are answered at the Mac. */
    private fun answer(s: JSONObject) {
        if (isCodex(s)) { Toast.makeText(this, "Codex sessions: answer this at the Mac", Toast.LENGTH_SHORT).show(); return }
        openClaude()
    }

    private fun openClaude() {
        val i = packageManager.getLaunchIntentForPackage("com.anthropic.claude")
        if (i == null) Toast.makeText(this, "Install the Claude app to answer from your phone", Toast.LENGTH_SHORT).show() else startActivity(i)
    }

    private fun renderBar() {
        bar.removeAllViews()
        fun item(glyph: String, text: String, color: Int, f: () -> Unit) = bar.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            addView(label(glyph, 20f, color).apply { gravity = Gravity.CENTER })
            addView(label(text, 12f, color, medium = true).apply { gravity = Gravity.CENTER; setPadding(0, dp(3), 0, 0) })
            setOnClickListener { f() }
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f))
        item(if (prefs.muted) "🔔" else "🔕", if (prefs.muted) "Unmute" else "Mute 1 h", C.ink) { mute() }
        item("✳", "Open Claude", C.orange) { openClaude() }
        item("⚙", "Settings", C.ink) { settings() }
    }

    private fun unpaired() {
        col.addView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_HORIZONTAL; setPadding(dp(16), dp(48), dp(16), dp(16))
            addView(avatar("calm", 96), LinearLayout.LayoutParams(dp(96), dp(96)))
            addView(label("Pair Buddy with your Mac", 24f, C.ink, medium = true).apply { setPadding(0, dp(20), 0, dp(16)) })
            for ((n, t) in listOf("1" to "Turn on Tailscale on the Mac and this phone (same account).",
                    "2" to "On the Mac: \"phone\": true in ~/.config/buddy.json, then ./install.sh",
                    "3" to "Run buddy pair and scan the second code with the camera.")) {
                addView(LinearLayout(this@MainActivity).apply {
                    setPadding(0, dp(8), 0, dp(8))
                    addView(label(n, 15f, C.platter, medium = true).apply { gravity = Gravity.CENTER; background = shape(C.accent, dp(12).toFloat()) },
                        LinearLayout.LayoutParams(dp(24), dp(24)).apply { marginEnd = dp(12) })
                    addView(label(t, 15f, C.ink, lines = 3), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                })
            }
            addView(label("Open camera", 16f, C.platter, medium = true).apply {
                gravity = Gravity.CENTER; background = shape(C.accent, dp(14).toFloat())
                setOnClickListener { try { startActivity(Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)) } catch (_: Exception) {} }
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)).apply { topMargin = dp(24) })
        })
    }

    // ---- sheets

    private fun sheet(build: LinearLayout.() -> Unit): Dialog {
        val d = Dialog(this)
        val body = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(10), dp(16), dp(24))
            background = GradientDrawable().apply { setColor(C.ground); cornerRadii = FloatArray(8) { if (it < 4) dp(24).toFloat() else 0f } }
            addView(View(this@MainActivity).apply { background = shape(C.hairline, dp(3).toFloat()) },
                LinearLayout.LayoutParams(dp(36), dp(5)).apply { gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = dp(12) })
            build()
        }
        d.setContentView(ScrollView(this).apply { addView(body) })
        d.window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            setGravity(Gravity.BOTTOM)
            setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
        }
        d.show()
        return d
    }

    private fun LinearLayout.group(rows: List<View>) = addView(platter(rows), LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { bottomMargin = dp(12) })

    private fun settingRow(title: String, value: String? = null, color: Int = C.ink, control: View? = null, f: (() -> Unit)? = null) =
        LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(52); setPadding(dp(16), dp(8), dp(16), dp(8))
            addView(label(title, 16f, color), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            if (value != null) addView(label(value, 15f, C.sub).apply { maxWidth = dp(180) })
            if (control != null) addView(control)
            if (f != null) setOnClickListener { f() }
        }

    private fun settings() {
        lateinit var d: Dialog
        d = sheet {
            addView(label("Settings", 20f, C.ink, medium = true).apply { setPadding(dp(4), 0, 0, dp(12)) })
            val rate = label("Speech rate · ${"%.1f".format(prefs.rate)}×", 16f)
            group(listOf(
                settingRow("Read aloud", control = Switch(context).apply { isChecked = prefs.speech; setOnCheckedChangeListener { _, v -> prefs.speech = v } }),
                LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(10), dp(16), dp(10))
                    addView(rate)
                    addView(SeekBar(context).apply {
                        max = 8; progress = ((prefs.rate - 0.8f) * 10).toInt().coerceIn(0, 8)
                        setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                            override fun onProgressChanged(b: SeekBar, p: Int, u: Boolean) { prefs.rate = 0.8f + p / 10f; rate.text = "Speech rate · ${"%.1f".format(prefs.rate)}×" }
                            override fun onStartTrackingTouch(b: SeekBar) {}
                            override fun onStopTrackingTouch(b: SeekBar) { svc?.preview(prefs.voice) }
                        })
                    })
                },
                settingRow("Voice", voiceName(prefs.voice)) { pickVoice { d.dismiss(); settings() } },
            ))
            group(listOf(
                settingRow("Quiet hours", "${prefs.quietFrom}:00 – ${prefs.quietTo}:00") {
                    TimePickerDialog(context, { _, h, _ ->
                        prefs.quietFrom = h
                        TimePickerDialog(context, { _, h2, _ -> prefs.quietTo = h2; d.dismiss(); settings() }, prefs.quietTo, 0, true).apply { setTitle("Quiet until") }.show()
                    }, prefs.quietFrom, 0, true).apply { setTitle("Quiet from") }.show()
                },
                settingRow(if (prefs.muted) "Unmute" else "Mute for 1 hour", color = C.accent) { d.dismiss(); mute() },
                settingRow("Floating buddy", control = Switch(context).apply {
                    isChecked = prefs.bubble; setOnCheckedChangeListener { _, v -> svc?.showBubble(v) ?: run { prefs.bubble = v } }
                }),
            ))
            val rows = mutableListOf<View>(settingRow("Paired with", Uri.parse(prefs.url).host ?: "–"),
                settingRow("Re-pair", color = C.accent) {
                    AlertDialog.Builder(context).setMessage("On the Mac, run buddy pair and scan the second code with this phone's camera.").setPositiveButton("OK", null).show()
                })
            if (!getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName))
                rows += settingRow("Stay connected in the background", color = C.accent) {
                    startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                }
            group(rows)
            group(listOf(
                settingRow("How Buddy works", color = C.accent) { d.dismiss(); help() },
                settingRow("Stop Buddy", color = C.red) { stopService(Intent(context, BuddyService::class.java)); d.dismiss(); main.postDelayed({ render() }, 300) },
            ))
        }
    }

    private fun voiceName(name: String) = if (name.isEmpty()) "Automatic"
        else name.substringAfter("-x-").substringBefore("-").uppercase() + " · " + name.substringBefore("-x-").uppercase()

    /** Every English voice on the phone, best first; tapping one plays a sample and keeps it. */
    private fun pickVoice(after: () -> Unit) {
        val s = svc ?: run { Toast.makeText(this, "Start Buddy first", Toast.LENGTH_SHORT).show(); return }
        val vs = s.voices()
        if (vs.isEmpty()) { Toast.makeText(this, "Install voices: Settings → System → Languages → Text-to-speech → Speech Services by Google", Toast.LENGTH_LONG).show(); return }
        val names = vs.map { v -> "${v.locale.displayCountry} · ${v.name.substringAfter("-x-").substringBefore("-")}" + (if (v.isNetworkConnectionRequired) " · natural, online" else " · offline") }
        AlertDialog.Builder(this).setTitle("Buddy's voice")
            .setSingleChoiceItems(names.toTypedArray(), vs.indexOfFirst { it.name == prefs.voice }) { _, i -> s.preview(vs[i].name) }
            .setPositiveButton("Done") { _, _ -> after() }.show()
    }

    private fun help() {
        lateinit var d: Dialog
        d = sheet {
            addView(label("How Buddy works", 20f, C.ink, medium = true).apply { setPadding(dp(4), 0, 0, dp(12)) })
            fun line(lead: String, text: String, kind: String? = null) = LinearLayout(context).apply {
                gravity = Gravity.CENTER_VERTICAL; minimumHeight = dp(48); setPadding(dp(16), dp(8), dp(12), dp(8))
                addView(label(lead, 15f, if (kind != null) C.kind(kind) else C.ink, medium = true), LinearLayout.LayoutParams(dp(96), ViewGroup.LayoutParams.WRAP_CONTENT))
                addView(label(text, 15f, C.ink, lines = 3), LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
                if (kind != null) addView(label("▶", 16f, C.accent).apply {
                    gravity = Gravity.CENTER; setOnClickListener { svc?.tone(kind) }
                }, LinearLayout.LayoutParams(dp(40), dp(40)))
            }
            group(listOf(
                line("The buddy", "Floats over your apps and mirrors your Mac's sessions."),
                line("Tap", "Opens this card."),
                line("Long-press", "Mute for 1 h, hide, or quit."),
                line("Drag", "Move it; it snaps to the nearest edge."),
            ))
            group(listOf(
                line("Needs you", "Rising two-tone. A session waits for your OK.", "needs-you"),
                line("Done", "Single beep, then what it did.", "done"),
                line("Stuck", "Low buzz. Quiet for 15 minutes.", "failed"),
                line("Message", "Soft prompt. An agent ran buddy say.", "say"),
            ))
            group(listOf(
                line("Answer", "In the Claude app (Remote Control). Codex: at the Mac."),
                line("More", "Tap the speech bubble to hear the details. Tap a row to read them."),
                line("Quiet", "Mute 1 h, or quiet hours in Settings. Notifications stay."),
                line("Offline", "Grey buddy. Back online, it reads the 3 newest; all are in Today."),
                line("Re-pair", "Run buddy pair on the Mac, scan the second code."),
            ))
            addView(label("Got it", 16f, C.platter, medium = true).apply {
                gravity = Gravity.CENTER; background = shape(C.accent, dp(14).toFloat())
                setOnClickListener { prefs.helpSeen = true; d.dismiss() }
            }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(52)))
        }
        d.setOnDismissListener { prefs.helpSeen = true }
    }
}
