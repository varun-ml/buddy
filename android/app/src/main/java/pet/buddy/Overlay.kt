package pet.buddy

import android.animation.ObjectAnimator
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject
import java.io.File
import kotlin.math.abs

/** The floating Buddy over other apps. Drag it (it snaps to the nearest edge), tap: the card, long-press: mute for an hour. */
class Overlay(private val s: BuddyService) {
    private val wm = s.getSystemService(WindowManager::class.java)
    private val dp = s.resources.displayMetrics.density
    private val size = (72 * dp).toInt()
    private val img = ImageView(s)
    private val badge = TextView(s).apply {
        setTextColor(0xffffffff.toInt()); textSize = 11f; gravity = Gravity.CENTER
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(0xffe5484d.toInt()) }
    }
    private val root = FrameLayout(s).apply {
        addView(img, FrameLayout.LayoutParams(size, size))
        addView(badge, FrameLayout.LayoutParams((20 * dp).toInt(), (20 * dp).toInt(), Gravity.TOP or Gravity.END))
    }
    private val lp = WindowManager.LayoutParams(size, size, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT).apply {
        gravity = Gravity.TOP or Gravity.START; x = s.prefs.bx; y = s.prefs.by
    }
    private var mood = ""

    init {
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0; var moved = false
        val longPress = Runnable {
            moved = true
            s.toggleMute()
            Toast.makeText(s, if (s.prefs.muted) "Buddy is quiet for an hour" else "Buddy can talk again", Toast.LENGTH_SHORT).show()
        }
        root.setOnTouchListener { v, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { downX = e.rawX; downY = e.rawY; startX = lp.x; startY = lp.y; moved = false; v.postDelayed(longPress, 600) }
                MotionEvent.ACTION_MOVE -> if (moved || abs(e.rawX - downX) + abs(e.rawY - downY) > 12 * dp) {
                    if (!moved) { moved = true; v.removeCallbacks(longPress); hideNote.run() }
                    lp.x = startX + (e.rawX - downX).toInt(); lp.y = startY + (e.rawY - downY).toInt()
                    wm.updateViewLayout(root, lp)
                }
                MotionEvent.ACTION_UP -> {
                    v.removeCallbacks(longPress)
                    if (!moved) s.startActivity(Intent(s, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    else {   // snap to the nearer side, and remember
                        val w = s.resources.displayMetrics.widthPixels
                        lp.x = if (lp.x + size / 2 < w / 2) 0 else w - size
                        wm.updateViewLayout(root, lp)
                        s.prefs.bx = lp.x; s.prefs.by = lp.y
                    }
                }
            }
            true
        }
    }

    fun show() = wm.addView(root, lp)
    fun hide() { hideNote.run(); try { wm.removeView(root) } catch (_: Exception) {} }

    // ---- the speech bubble beside Buddy, like on the Mac: which session, what kind, and the line

    private var note: View? = null
    private var noteSticky = ""
    private val hideNote = Runnable {
        note?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        note = null; noteSticky = ""
    }

    fun say(e: JSONObject) {
        hideNote.run(); root.removeCallbacks(hideNote)
        val kind = e.optString("kind")
        val (label, color) = when (kind) {
            "needs-you" -> "needs your OK" to 0xffe8590c
            "done" -> "done" to 0xff248a3d
            "failed" -> "stuck?" to 0xffe5484d
            else -> "says" to 0xff3b6fd8
        }
        val repo = e.optString("repo").ifEmpty { "Buddy" }
        val body = e.optString("spoken").removePrefix("$repo is done.").removePrefix("$repo:").trim()
        val head = "$repo · $label"
        val text = SpannableStringBuilder(if (body.isEmpty()) head else "$head\n$body").apply {
            setSpan(StyleSpan(Typeface.BOLD), 0, head.length, 0)
            setSpan(ForegroundColorSpan(color.toInt()), 0, head.length, 0)
        }
        val v = TextView(s).apply {
            this.text = text; textSize = 14f; setTextColor(0xff1f1f1f.toInt()); maxWidth = (260 * dp).toInt()
            setPadding((12 * dp).toInt(), (10 * dp).toInt(), (12 * dp).toInt(), (10 * dp).toInt())
            background = GradientDrawable().apply { cornerRadius = 16 * dp; setColor(0xfffffdf7.toInt()); setStroke((2 * dp).toInt(), color.toInt()) }
            elevation = 6 * dp
            setOnClickListener { hideNote.run(); s.startActivity(Intent(s, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
        v.measure(View.MeasureSpec.makeMeasureSpec((260 * dp).toInt(), View.MeasureSpec.AT_MOST), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
        val left = lp.x + size / 2 < s.resources.displayMetrics.widthPixels / 2   // Buddy on the left edge: the bubble opens to its right
        val nlp = WindowManager.LayoutParams(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (left) lp.x + size + (4 * dp).toInt() else maxOf(0, lp.x - v.measuredWidth - (4 * dp).toInt())
            y = lp.y
        }
        try { wm.addView(v, nlp) } catch (_: Exception) { return }
        note = v; noteSticky = e.optString("sticky")
        root.postDelayed(hideNote, if (kind == "needs-you") 30_000L else 15_000L)
    }

    /** A needs-you bubble goes as soon as the Mac says it's handled. */
    fun resolved(sticky: String) { if (sticky.isNotEmpty() && sticky == noteSticky) { root.removeCallbacks(hideNote); hideNote.run() } }

    /** The buddy in its current mood (drawn by the Mac), the badge (waiting + stuck), and grey while the Mac is out of reach. */
    fun update(card: JSONObject?, online: Boolean) {
        val m = if (s.prefs.muted) "asleep" else card?.optString("mood") ?: "calm"
        if (m != mood) File(s.filesDir, "$m.png").takeIf { it.exists() }?.let { img.setImageBitmap(BitmapFactory.decodeFile(it.path)); mood = m }
        if (mood.isEmpty()) img.setImageResource(R.drawable.icon)
        val n = card?.optInt("badge") ?: 0
        badge.text = "$n"; badge.visibility = if (n > 0) android.view.View.VISIBLE else android.view.View.GONE
        root.alpha = if (online) 1f else 0.4f
    }

    /** A shake when something needs you, a hop when something is done. */
    fun react(kind: String) {
        when (kind) {
            "needs-you", "failed" -> ObjectAnimator.ofFloat(img, "rotation", 0f, -12f, 12f, -8f, 8f, 0f).setDuration(600).start()
            "done" -> ObjectAnimator.ofFloat(img, "translationY", 0f, -18 * dp, 0f).setDuration(500).start()
        }
    }
}
