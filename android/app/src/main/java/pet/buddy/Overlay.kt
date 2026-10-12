package pet.buddy

import android.animation.ObjectAnimator
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
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
                    if (!moved) { moved = true; v.removeCallbacks(longPress) }
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
    fun hide() = try { wm.removeView(root) } catch (_: Exception) {}

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
