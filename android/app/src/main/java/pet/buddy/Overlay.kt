package pet.buddy

import android.animation.ObjectAnimator
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONObject
import java.io.File
import kotlin.math.abs

/**
 * The floating Buddy over other apps, and its speech bubble.
 * Drag: it snaps to the nearest edge. Tap: the card. Long-press: Mute 1 h · Hide · Quit.
 * Bubble: which session, what kind, the line; tap it to hear and read the details.
 */
class Overlay(private val s: BuddyService) {
    private val wm = s.getSystemService(WindowManager::class.java)
    private val size = s.dp(64)
    private val img = ImageView(s).apply {
        background = shape(C.platter, s.dp(32).toFloat()); clipToOutline = true; elevation = s.dp(6).toFloat()
        setPadding(s.dp(5), s.dp(5), s.dp(5), s.dp(5))
    }
    private val badge = TextView(s).apply {
        setTextColor(C.platter); textSize = 12f; gravity = Gravity.CENTER; typeface = android.graphics.Typeface.DEFAULT_BOLD
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(C.red); setStroke(s.dp(2), C.platter) }
        elevation = s.dp(8).toFloat()
    }
    private val root = FrameLayout(s).apply {
        val pad = s.dp(6)
        setPadding(pad, pad, pad, pad)   // room for the shadow and the badge
        addView(img, FrameLayout.LayoutParams(size - 2 * pad, size - 2 * pad))
        addView(badge, FrameLayout.LayoutParams(s.dp(22), s.dp(22), Gravity.TOP or Gravity.END).apply { topMargin = -pad; marginEnd = -pad })
        clipChildren = false; clipToPadding = false
    }
    private val lp = params(size, size).apply { x = s.prefs.bx; y = s.prefs.by }
    private var mood = ""

    private fun params(w: Int, h: Int) = WindowManager.LayoutParams(w, h, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT).apply { gravity = Gravity.TOP or Gravity.START }

    private val onLeft get() = lp.x + size / 2 < s.resources.displayMetrics.widthPixels / 2

    init {
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0; var moved = false
        val longPress = Runnable { moved = true; menu() }
        root.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { downX = e.rawX; downY = e.rawY; startX = lp.x; startY = lp.y; moved = false; v.postDelayed(longPress, 550) }
                MotionEvent.ACTION_MOVE -> if (moved || abs(e.rawX - downX) + abs(e.rawY - downY) > s.dp(12)) {
                    if (!moved) { moved = true; v.removeCallbacks(longPress); hideNote(); hideMenu() }
                    lp.x = startX + (e.rawX - downX).toInt(); lp.y = startY + (e.rawY - downY).toInt()
                    wm.updateViewLayout(root, lp)
                }
                MotionEvent.ACTION_UP -> {
                    v.removeCallbacks(longPress)
                    if (!moved) { hideMenu(); openCard() }
                    else if (menuView == null) {   // snap to the nearer side, and remember
                        val w = s.resources.displayMetrics.widthPixels
                        lp.x = if (onLeft) 0 else w - size
                        lp.y = lp.y.coerceIn(s.dp(40), s.resources.displayMetrics.heightPixels - size - s.dp(120))
                        wm.updateViewLayout(root, lp)
                        s.prefs.bx = lp.x; s.prefs.by = lp.y
                    }
                }
            }
            true
        }
    }

    fun show() = wm.addView(root, lp)

    /** Out of the way while Buddy's own screen is open: it would only cover the card. */
    fun away(yes: Boolean) { root.visibility = if (yes) View.GONE else View.VISIBLE; if (yes) { hideNote(); hideMenu() } }
    fun hide() { hideNote(); hideMenu(); try { wm.removeView(root) } catch (_: Exception) {} }

    private fun openCard() = s.startActivity(Intent(s, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))

    /** Put a view beside Buddy, toward the middle of the screen, inside the screen. */
    private fun beside(v: View, maxW: Int): WindowManager.LayoutParams {
        v.measure(View.MeasureSpec.makeMeasureSpec(maxW, View.MeasureSpec.AT_MOST), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        val h = s.resources.displayMetrics.heightPixels
        return params(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT).apply {
            x = if (onLeft) lp.x + size + s.dp(4) else maxOf(0, lp.x - v.measuredWidth - s.dp(4))
            // lower part of the screen: bottom-align with Buddy, so the bubble grows upward
            y = (if (lp.y > h * 0.6) lp.y + size - v.measuredHeight else lp.y).coerceIn(s.dp(32), maxOf(s.dp(32), h - v.measuredHeight - s.dp(160)))
        }
    }

    // ---- the speech bubble

    private var note: View? = null
    private var noteEvent: JSONObject? = null
    private val hideNoteR = Runnable { hideNote() }

    private fun hideNote() {
        root.removeCallbacks(hideNoteR)
        note?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        note = null; noteEvent = null
    }

    fun say(e: JSONObject) {
        if (root.visibility != View.VISIBLE) return   // the app is open: the event is on the card already
        // a "done" never pushes a visible needs-you away; it's in the inbox and was spoken
        if (noteEvent?.str("kind") == "needs-you" && e.str("kind") != "needs-you") return
        showNote(e, expanded = false)
    }

    private fun showNote(e: JSONObject, expanded: Boolean) {
        hideNote()
        val kind = e.str("kind")
        val label = when (kind) { "needs-you" -> "needs your OK"; "done" -> "done"; "failed" -> "stuck?"; else -> "says" }
        val color = C.kind(kind)
        val repo = e.str("repo").ifEmpty { "Buddy" }
        // needs-you: what it wants to run (the header already says it needs you); otherwise the line that was read aloud
        val line = if (kind == "needs-you" && e.str("text").contains("\n")) e.str("text").substringAfter("\n").substringAfter("wants to run: ")
            else e.str("spoken").removePrefix("$repo is done.").removePrefix("$repo:").trim()
        val details = e.optJSONArray("details")
        val maxW = minOf(s.dp(280), s.resources.displayMetrics.widthPixels - s.dp(100))
        val v = LinearLayout(s).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(s.dp(12), s.dp(10), s.dp(12), s.dp(10))
            background = shape(C.platter, s.dp(16).toFloat(), s.dp(2), color); elevation = s.dp(6).toFloat()
            addView(s.label("$repo · $label", 13f, color, medium = true))
            if (line.isNotEmpty()) addView(s.label(line, 15f, C.ink, lines = if (expanded) 6 else 3).apply { setPadding(0, s.dp(4), 0, 0) })
            if (expanded && details != null) for (i in 0 until details.length())
                addView(s.label("• " + details.optString(i), 14f, C.ink, lines = 3).apply { setPadding(0, s.dp(5), 0, 0) })
            if (!expanded && details != null && details.length() > 0)
                addView(s.label("Tap for details", 12f, C.sub).apply { setPadding(0, s.dp(6), 0, 0) })
            setOnClickListener {
                if (!expanded && details != null && details.length() > 0) {   // first tap: hear and read the details
                    showNote(e, expanded = true)
                    s.speakNow((0 until details.length()).joinToString(". ") { details.optString(it) })
                } else { hideNote(); openCard() }
            }
        }
        // swipe sideways to dismiss
        var x0 = 0f
        v.setOnTouchListener { view, ev ->
            when (ev.action) {
                MotionEvent.ACTION_DOWN -> { x0 = ev.rawX; false }
                MotionEvent.ACTION_UP -> if (abs(ev.rawX - x0) > s.dp(60)) { hideNote(); true } else { view.performClick(); true }
                else -> true
            }
        }
        try { wm.addView(v, beside(v, maxW)) } catch (_: Exception) { return }
        note = v; noteEvent = e
        root.postDelayed(hideNoteR, when {
            expanded -> 30_000L
            kind == "needs-you" -> 60_000L   // or until the Mac says it's handled
            kind == "failed" -> 20_000L
            else -> 10_000L
        })
    }

    /** A needs-you bubble goes as soon as the Mac says it's handled. */
    fun resolved(sticky: String) { if (sticky.isNotEmpty() && sticky == noteEvent?.str("sticky")) hideNote() }

    // ---- long-press menu: three pills beside Buddy

    private var menuView: View? = null
    private fun hideMenu() { menuView?.let { try { wm.removeView(it) } catch (_: Exception) {} }; menuView = null }

    private fun menu() {
        hideNote(); hideMenu()
        fun pill(text: String, color: Int, f: () -> Unit) = s.label(text, 15f, color, medium = true).apply {
            gravity = Gravity.CENTER; setPadding(s.dp(16), 0, s.dp(16), 0); minHeight = s.dp(44)
            background = shape(C.platter, s.dp(22).toFloat()); elevation = s.dp(6).toFloat()
            setOnClickListener { hideMenu(); f() }
        }
        val v = LinearLayout(s).apply {
            orientation = LinearLayout.VERTICAL; setPadding(s.dp(4), s.dp(4), s.dp(4), s.dp(4)); clipToPadding = false
            val m = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply { bottomMargin = s.dp(8) }
            addView(pill(if (s.prefs.muted) "Unmute" else "Mute 1 h", C.ink) { s.toggleMute() }, m)
            addView(pill("Hide", C.ink) { s.showBubble(false) }, m)
            addView(pill("Quit", C.red) { s.stopSelf() }, m)
        }
        try { wm.addView(v, beside(v, s.dp(200))) } catch (_: Exception) { return }
        menuView = v
        root.postDelayed({ hideMenu() }, 8000)
    }

    /** The buddy in its current mood (drawn by the Mac), the badge (waiting + stuck), and grey while the Mac is out of reach. */
    fun update(card: JSONObject?, online: Boolean) {
        val m = if (s.prefs.muted) "asleep" else card?.str("mood") ?: "calm"
        if (m != mood) File(s.filesDir, "$m.png").takeIf { it.exists() }?.let { img.setImageBitmap(BitmapFactory.decodeFile(it.path)); mood = m }
        if (mood.isEmpty()) img.setImageResource(R.drawable.icon)
        val n = card?.optInt("badge") ?: 0
        badge.text = if (n > 9) "9+" else "$n"; badge.visibility = if (n > 0) View.VISIBLE else View.GONE
        root.alpha = if (online) 1f else 0.4f
    }

    /** A shake when something needs you, a hop when something is done. */
    fun react(kind: String) {
        when (kind) {
            "needs-you", "failed" -> ObjectAnimator.ofFloat(img, "rotation", 0f, -12f, 12f, -8f, 8f, 0f).setDuration(600).start()
            "done" -> ObjectAnimator.ofFloat(img, "translationY", 0f, -s.dp(14).toFloat(), 0f).setDuration(500).start()
        }
    }
}
