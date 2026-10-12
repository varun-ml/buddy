package pet.buddy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import kotlin.concurrent.thread

/**
 * Keeps one stream open to the Mac (phone.py), and for each event: a sound for its kind, then the phone reads the line aloud,
 * plus an Android notification. Runs as a foreground service, so it keeps working with the screen off or Maps open.
 */
class BuddyService : Service() {
    companion object {
        var instance: BuddyService? = null
        val SPOKEN = setOf("needs-you", "done", "failed", "say")
        const val MAX_AGE_S = 15 * 60          // older than this: notification and inbox only, never spoken
        const val REPEAT_MS = 10 * 60 * 1000L  // a needs-you still open is said once more, 10 minutes later
    }

    lateinit var prefs: Prefs
    private val main = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<JSONObject>()   // main thread only
    private val open = mutableSetOf<String>()       // sticky keys not resolved yet
    private val lastSaid = mutableMapOf<String, Long>()
    private var speaking = false
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var overlay: Overlay? = null
    @Volatile private var running = true
    @Volatile private var conn: HttpURLConnection? = null
    var online = false; private set
    var card: JSONObject? = null; private set
    var onChange: (() -> Unit)? = null   // the open screen refreshes itself

    private val audio by lazy { getSystemService(AudioManager::class.java) }
    private val nm by lazy { getSystemService(NotificationManager::class.java) }
    private val speech = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(speech).build()

    override fun onBind(i: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        prefs = Prefs(this)
        for ((id, name, imp) in listOf(Triple("needs-you", "Needs you", NotificationManager.IMPORTANCE_HIGH),
                Triple("done", "Done", NotificationManager.IMPORTANCE_DEFAULT), Triple("failed", "Failed or stuck", NotificationManager.IMPORTANCE_DEFAULT),
                Triple("say", "Messages", NotificationManager.IMPORTANCE_DEFAULT), Triple("running", "Buddy is listening", NotificationManager.IMPORTANCE_MIN))) {
            nm.createNotificationChannel(NotificationChannel(id, name, imp).apply { setSound(null, null) })   // Buddy plays its own sound
        }
        startForeground(1, Notification.Builder(this, "running").setSmallIcon(R.drawable.icon).setContentTitle("Buddy is listening")
            .setContentIntent(openApp()).build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        tts = TextToSpeech(this) { ok ->
            ttsReady = ok == TextToSpeech.SUCCESS
            tts?.setAudioAttributes(speech)
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) {}
                override fun onDone(id: String?) { main.post { finished() } }
                @Deprecated("old API") override fun onError(id: String?) { main.post { finished() } }
            })
        }
        showBubble(prefs.bubble)
        thread(name = "stream") { stream() }
    }

    override fun onStartCommand(i: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        running = false
        conn?.disconnect()
        tts?.shutdown()
        overlay?.hide()
        instance = null
        super.onDestroy()
    }

    fun showBubble(on: Boolean) {
        prefs.bubble = on
        if (on && overlay == null && Settings.canDrawOverlays(this)) overlay = Overlay(this).also { it.show(); it.update(card, online) }
        if (!on) { overlay?.hide(); overlay = null }
    }

    fun toggleMute() {
        prefs.mutedUntil = if (prefs.muted) 0 else System.currentTimeMillis() + 3600_000
        if (prefs.muted) { queue.clear(); tts?.stop() }
        changed()
    }

    private fun openApp() = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)

    private fun changed() { overlay?.update(card, online); onChange?.invoke() }

    // ---- the stream: reconnects by itself (1 s, 2 s, 5 s … 60 s), and catches up from the last event it saw

    private fun stream() {
        var wait = 1000L
        while (running) {
            if (prefs.paired) try {
                val c = prefs.open("/events?after=${prefs.lastId}", readTimeoutMs = 60_000).also { conn = it }
                val backlog = mutableListOf<JSONObject>()
                var live = false
                var data = ""
                c.inputStream.bufferedReader().use { r ->
                    main.post { online = true; changed() }
                    wait = 1000
                    refresh()
                    while (running) {
                        val line = r.readLine() ?: break
                        when {
                            line.startsWith("data: ") -> data = line.substring(6)
                            line == ": live" -> { live = true; val b = backlog.toList(); backlog.clear(); main.post { catchUp(b) } }
                            line.isEmpty() && data.isNotEmpty() -> {
                                val e = JSONObject(data); data = ""
                                prefs.lastId = e.getLong("id")
                                if (live) main.post { handle(e, speak = true) } else backlog += e
                            }
                        }
                    }
                }
            } catch (_: Exception) {}
            main.post { online = false; changed() }
            if (!running) break
            Thread.sleep(wait)
            wait = minOf(if (wait < 2000) wait * 2 else wait + 3000, 60_000)
        }
    }

    /** Back after a gap: everything goes to notifications and the inbox, but only the 3 newest are spoken, needs-you first. */
    private fun catchUp(events: List<JSONObject>) {
        val say = events.filter { it.optString("kind") in SPOKEN }
            .sortedWith(compareBy<JSONObject> { it.optString("kind") != "needs-you" }.thenByDescending { it.getLong("id") }).take(3)
            .map { it.getLong("id") }.toSet()
        for (e in events) handle(e, speak = e.getLong("id") in say)
    }

    fun refresh() = thread {
        try {
            val c = JSONObject(String(prefs.get("/card")))
            for (mood in listOf("calm", "busy", "waiting", "asleep")) {   // the Mac draws the buddy; fetch it once per connect
                val f = File(filesDir, "$mood.png")
                if (!f.exists() || System.currentTimeMillis() - f.lastModified() > 3600_000) f.writeBytes(prefs.get("/avatar/$mood.png"))
            }
            main.post { card = c; changed() }
        } catch (_: Exception) {}
    }

    // ---- one event

    private fun handle(e: JSONObject, speak: Boolean) {
        val kind = e.optString("kind")
        val sticky = e.optString("sticky")
        if (kind == "resolve") {
            open.remove(sticky)
            nm.cancel(sticky.hashCode())
            queue.removeAll { it.optString("sticky") == sticky }
            refresh()
            return
        }
        if (sticky.isNotEmpty()) open += sticky
        notify(e)
        refresh()
        overlay?.react(kind)
        val fresh = System.currentTimeMillis() / 1000.0 - e.optDouble("at") < MAX_AGE_S
        if (speak && fresh && kind in SPOKEN) enqueue(e)
        if (kind == "needs-you" && sticky.isNotEmpty() && !e.optBoolean("repeat"))
            main.postDelayed({ if (sticky in open) enqueue(JSONObject(e.toString()).put("repeat", true)) }, REPEAT_MS)
    }

    private fun notify(e: JSONObject) {
        val kind = e.optString("kind").let { if (it in SPOKEN) it else "say" }
        val lines = e.optString("text").split("\n")
        val title = lines.first()
        val n = Notification.Builder(this, kind).setSmallIcon(R.drawable.icon).setContentTitle(title)
            .setContentText(lines.drop(1).joinToString(" ")).setContentIntent(openApp()).setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(Notification.Builder(this, kind).setSmallIcon(R.drawable.icon)
                .setContentTitle(if (kind == "needs-you") "A session needs your OK" else "Buddy").build())
            .build()
        nm.notify(e.optString("sticky").ifEmpty { e.getLong("id").toString() }.hashCode(), n)
    }

    // ---- speaking: one line at a time, needs-you first; several "done" waiting together become one line

    private fun enqueue(e: JSONObject) {
        if (!prefs.speech || prefs.quiet()) return
        val line = e.optString("spoken")
        if (System.currentTimeMillis() - (lastSaid[line] ?: 0) < 60_000) return   // the same line twice within a minute: once
        if (e.optString("kind") == "needs-you") queue.addFirst(e) else queue.addLast(e)
        next()
    }

    private fun next() {
        if (speaking || queue.isEmpty() || !ttsReady) return
        if (prefs.quiet()) { queue.clear(); return }
        val e = queue.removeFirst()
        val kind = e.optString("kind")
        var line = e.optString("spoken")
        if (kind == "done") {
            val more = queue.filter { it.optString("kind") == "done" }
            if (more.isNotEmpty()) {
                queue.removeAll { it.optString("kind") == "done" }
                line = "${more.size + 1} done: " + (listOf(e) + more).joinToString(", ") { it.optString("repo") }
            }
        }
        lastSaid[e.optString("spoken")] = System.currentTimeMillis()
        speaking = true
        audio.requestAudioFocus(focus)   // Maps and music duck while Buddy talks
        tone(kind)
        main.postDelayed({
            tts?.setSpeechRate(prefs.rate)
            tts?.speak(line, TextToSpeech.QUEUE_FLUSH, null, e.optString("id"))
        }, 650)
    }

    private fun finished() {
        audio.abandonAudioFocusRequest(focus)
        speaking = false
        next()
    }

    /** The kind, before the words: rising two-tone = needs you, single beep = done, low buzz = failed, soft prompt = a message. */
    private fun tone(kind: String) {
        val t = when (kind) {
            "needs-you" -> ToneGenerator.TONE_PROP_ACK
            "done" -> ToneGenerator.TONE_PROP_BEEP
            "failed" -> ToneGenerator.TONE_SUP_ERROR
            else -> ToneGenerator.TONE_PROP_PROMPT
        }
        try {
            val g = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
            g.startTone(t, 500)
            main.postDelayed({ g.release() }, 700)
        } catch (_: Exception) {}
    }
}
