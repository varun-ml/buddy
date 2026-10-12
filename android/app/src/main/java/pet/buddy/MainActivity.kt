package pet.buddy

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.concurrent.thread

/** The card: the same Work tab as the Mac (sessions and inbox only), plus start/stop, mute and the bubble switch. */
class MainActivity : Activity() {
    private lateinit var prefs: Prefs
    private lateinit var list: LinearLayout
    private val main = Handler(Looper.getMainLooper())
    private var inbox = JSONArray()
    private val tick = object : Runnable { override fun run() { load(); main.postDelayed(this, 5000) } }

    override fun onCreate(b: Bundle?) {
        super.onCreate(b)
        prefs = Prefs(this)
        list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(16), dp(24), dp(16), dp(24)) }
        setContentView(ScrollView(this).apply { addView(list) })
        pair(intent)
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
    }

    override fun onResume() {
        super.onResume()
        BuddyService.instance?.onChange = { main.post { render() } }
        main.post(tick)
    }

    override fun onPause() {
        super.onPause()
        BuddyService.instance?.onChange = null
        main.removeCallbacks(tick)
    }

    private fun start() {
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        if (!Settings.canDrawOverlays(this))
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        startForegroundService(Intent(this, BuddyService::class.java))
        main.postDelayed({ BuddyService.instance?.onChange = { main.post { render() } }; render() }, 500)
    }

    private fun load() = thread {
        if (!prefs.paired) { main.post { render() }; return@thread }
        try {
            val all = JSONArray(String(prefs.get("/inbox?after=0")))
            main.post { inbox = all; render() }
            BuddyService.instance?.refresh()
        } catch (_: Exception) { main.post { render() } }
    }

    private fun render() {
        list.removeAllViews()
        val svc = BuddyService.instance
        val card = svc?.card
        text(card?.optString("headline") ?: if (prefs.paired) "Connecting…" else "Not paired", 24f, bold = true)
        text(when {
            !prefs.paired -> "On your Mac: set \"phone\": true in ~/.config/buddy.json, run ./install.sh, then buddy pair and scan the code with the camera."
            svc == null -> "Buddy is off."
            !svc.online -> "Mac unreachable. Is Tailscale on, on both?"
            prefs.muted -> "Quiet until ${hm(prefs.mutedUntil / 1000.0)}"
            prefs.quiet() -> "Quiet hours (${prefs.quietFrom}:00–${prefs.quietTo}:00)"
            else -> "Listening"
        }, 13f, dim = true)

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(0, dp(12), 0, dp(4)) }
        fun btn(label: String, f: () -> Unit) = row.addView(Button(this).apply { text = label; isAllCaps = false; setOnClickListener { f(); render() } })
        if (svc == null) btn("Start") { start() } else btn("Stop") { stopService(Intent(this, BuddyService::class.java)) }
        btn(if (prefs.muted) "Unmute" else "Mute 1 h") { svc?.toggleMute() ?: run { prefs.mutedUntil = if (prefs.muted) 0 else System.currentTimeMillis() + 3600_000 } }
        btn(if (prefs.bubble) "Hide bubble" else "Show bubble") { svc?.showBubble(!prefs.bubble) ?: run { prefs.bubble = !prefs.bubble } }
        list.addView(row)
        if (svc != null) list.addView(Button(this).apply {
            text = "Voice: ${prefs.voice.ifEmpty { "default" }}"; isAllCaps = false
            setOnClickListener { pickVoice(svc) }
        })
        if (!getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)) {
            list.addView(Button(this).apply {
                text = "Let Buddy stay connected in the background"; isAllCaps = false
                setOnClickListener { startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))) }
            })
        }

        if (card != null) {
            section("Wants your OK", card.optJSONArray("waiting")) { "${it.optString("repo")}  ·  ${it.optString("activity")}" }
            section("Quiet", card.optJSONArray("stuck")) { "${it.optString("repo")}  ·  quiet ${ago(it.optDouble("ts"))}" }
            section("Running", card.optJSONArray("working")) { "${it.optString("repo")}  ·  ${it.optString("activity")}" }
            section("Your turn", card.optJSONArray("yourTurn")) { "${it.optString("repo")}  ·  ${it.optString("spoken").ifEmpty { it.optString("said") }}" }
        }
        val events = (0 until inbox.length()).map { inbox.getJSONObject(it) }.filter { it.optString("kind") != "resolve" }.reversed()
        if (events.isNotEmpty()) {
            text("Inbox · ${events.size} today", 15f, bold = true, top = 20)
            for (e in events.take(60)) text("${hm(e.optDouble("at"))}  ${e.optString("text").substringBefore("\n")}", 14f)
        }
    }

    /** Every English voice on the phone, best first; tapping one plays a sample and keeps it. */
    private fun pickVoice(svc: BuddyService) {
        val vs = svc.voices()
        if (vs.isEmpty()) { Toast.makeText(this, "No voices yet: Settings → System → Languages → Text-to-speech → Speech Services by Google", Toast.LENGTH_LONG).show(); return }
        val names = vs.map { v -> "${v.locale.displayCountry} · ${v.name.substringAfter("-x-").substringBefore("-")}" + (if (v.isNetworkConnectionRequired) " · natural (online)" else " · offline") }
        android.app.AlertDialog.Builder(this).setTitle("Buddy's voice")
            .setSingleChoiceItems(names.toTypedArray(), vs.indexOfFirst { it.name == prefs.voice }) { _, i -> svc.preview(vs[i].name) }
            .setPositiveButton("Done") { _, _ -> render() }.show()
    }

    private fun section(title: String, a: JSONArray?, line: (JSONObject) -> String) {
        if (a == null || a.length() == 0) return
        text(title, 15f, bold = true, top = 20)
        for (i in 0 until a.length()) text(line(a.getJSONObject(i)), 14f)
    }

    private fun text(s: String, size: Float, bold: Boolean = false, dim: Boolean = false, top: Int = 4) = list.addView(TextView(this).apply {
        text = s; textSize = size; setPadding(0, dp(top), 0, dp(2))
        if (bold) typeface = Typeface.DEFAULT_BOLD
        if (dim) setTextColor(0xff777777.toInt())
    })

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun hm(t: Double) = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date((t * 1000).toLong()))
    private fun ago(t: Double): String {
        val s = (System.currentTimeMillis() / 1000.0 - t).toInt()
        return if (s < 3600) "${s / 60}m" else "${s / 3600}h${(s % 3600) / 60}"
    }
}
