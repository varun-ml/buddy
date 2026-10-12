package pet.buddy

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Buddy's Glass look from the Mac card, made opaque for a phone (see docs/phone-prd.md and the design mock). */
object C {
    const val ground = 0xFFF6F6FA.toInt()
    const val platter = 0xFFFFFFFF.toInt()
    const val ink = 0xFF1D1D1F.toInt()
    const val sub = 0xFF8A8A8E.toInt()
    const val hairline = 0xFFE5E5EA.toInt()
    const val chip = 0xFFE9E9EE.toInt()
    const val accent = 0xFF007AFF.toInt()
    const val running = 0xFF34C759.toInt()
    const val done = 0xFF248A3D.toInt()
    const val orange = 0xFFE8590C.toInt()
    const val orangeBg = 0xFFFFEED6.toInt()
    const val red = 0xFFE5484D.toInt()
    const val redBg = 0xFFFDE7E8.toInt()

    fun kind(kind: String) = when (kind) {
        "needs-you" -> orange
        "done" -> done
        "failed" -> red
        else -> accent
    }
}

fun Context.dp(v: Number) = (v.toFloat() * resources.displayMetrics.density).toInt()

fun shape(color: Int, radius: Float, strokeWidth: Int = 0, strokeColor: Int = 0) = GradientDrawable().apply {
    setColor(color); cornerRadius = radius
    if (strokeWidth > 0) setStroke(strokeWidth, strokeColor)
}

fun Context.label(text: CharSequence, sp: Float, color: Int = C.ink, medium: Boolean = false, mono: Boolean = false, lines: Int = 1) =
    TextView(this).apply {
        this.text = text; textSize = sp; setTextColor(color)
        typeface = when {
            mono -> Typeface.MONOSPACE
            medium -> Typeface.create("sans-serif-medium", Typeface.NORMAL)
            else -> Typeface.DEFAULT
        }
        maxLines = lines; ellipsize = TextUtils.TruncateAt.END
        includeFontPadding = false
        setLineSpacing(0f, 1.15f)
    }

/** The agent's mark: Claude Code ✳ in clay, Codex >_ in green, as on the Mac card. */
fun Context.agentIcon(source: String?, sizeDp: Int): TextView {
    val codex = source?.startsWith("codex") == true
    return TextView(this).apply {
        text = if (codex) ">_" else "✳"
        gravity = Gravity.CENTER; setTextColor(0xFFFFFFFF.toInt())
        textSize = sizeDp * 0.36f; typeface = if (codex) Typeface.MONOSPACE else Typeface.DEFAULT_BOLD
        background = GradientDrawable(GradientDrawable.Orientation.TL_BR,
            if (codex) intArrayOf(0xFF1FC79C.toInt(), 0xFF0E8F6F.toInt()) else intArrayOf(0xFFE8906F.toInt(), 0xFFC9643F.toInt()))
            .apply { cornerRadius = dp(if (sizeDp >= 40) 11 else 9).toFloat() }
    }
}

fun hm(t: Double): String = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date((t * 1000).toLong()))

fun ago(t: Double): String {
    val s = (System.currentTimeMillis() / 1000.0 - t).toInt().coerceAtLeast(0)
    return when {
        s < 60 -> "now"
        s < 3600 -> "${s / 60}m"
        else -> "${s / 3600}h${(s % 3600) / 60}"
    }
}

/** optString, but a JSON null is "" (not the word "null"). */
fun org.json.JSONObject.str(key: String): String = if (isNull(key)) "" else optString(key)
