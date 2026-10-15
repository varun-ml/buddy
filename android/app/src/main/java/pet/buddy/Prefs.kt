package pet.buddy

import android.content.Context
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar

/** Everything the app remembers: which Mac, the token, where the bubble sits, mute and quiet hours. */
class Prefs(c: Context) {
    private val p = c.getSharedPreferences("buddy", Context.MODE_PRIVATE)
    var url: String get() = p.getString("url", "")!!; set(v) = p.edit().putString("url", v).apply()
    var token: String get() = p.getString("token", "")!!; set(v) = p.edit().putString("token", v).apply()
    var lastId: Long get() = p.getLong("lastId", 0); set(v) = p.edit().putLong("lastId", v).apply()
    var mutedUntil: Long get() = p.getLong("mutedUntil", 0); set(v) = p.edit().putLong("mutedUntil", v).apply()
    var speech: Boolean get() = p.getBoolean("speech", true); set(v) = p.edit().putBoolean("speech", v).apply()
    var bubble: Boolean get() = p.getBoolean("bubble", true); set(v) = p.edit().putBoolean("bubble", v).apply()
    var quietFrom: Int get() = p.getInt("quietFrom", 22); set(v) = p.edit().putInt("quietFrom", v).apply()
    var quietTo: Int get() = p.getInt("quietTo", 7); set(v) = p.edit().putInt("quietTo", v).apply()
    var voice: String get() = p.getString("voice", "")!!; set(v) = p.edit().putString("voice", v).apply()
    var helpSeen: Boolean get() = p.getBoolean("helpSeen", false); set(v) = p.edit().putBoolean("helpSeen", v).apply()
    var rate: Float get() = p.getFloat("rate", 1.0f); set(v) = p.edit().putFloat("rate", v).apply()
    var bx: Int get() = p.getInt("bx", 0); set(v) = p.edit().putInt("bx", v).apply()
    var by: Int get() = p.getInt("by", 400); set(v) = p.edit().putInt("by", v).apply()
    var carUntil: Long get() = p.getLong("carUntil", 0); set(v) = p.edit().putLong("carUntil", v).apply()

    val paired get() = url.isNotEmpty() && token.isNotEmpty()
    val muted get() = System.currentTimeMillis() < mutedUntil
    /** Car mode: the Mac reads details aloud, and quiet hours don't apply. Off by itself after 12 hours, like on the Mac. */
    val car get() = System.currentTimeMillis() < carUntil

    /** Muted, or inside quiet hours (default 22:00–07:00) and not in car mode: nothing is spoken and nothing makes a sound. */
    fun quiet(): Boolean {
        if (muted) return true
        if (car) return false   // driving at night: you asked to hear it
        val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        return if (quietFrom > quietTo) h >= quietFrom || h < quietTo else h in quietFrom until quietTo
    }

    fun open(path: String, readTimeoutMs: Int = 10_000): HttpURLConnection =
        (URL(url.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
            setRequestProperty("Authorization", "Bearer $token")
            connectTimeout = 10_000
            readTimeout = readTimeoutMs
        }

    fun get(path: String): ByteArray = open(path).run {
        try { inputStream.readBytes() } finally { disconnect() }
    }
}
