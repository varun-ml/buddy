package pet.buddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** After an update (the app replaces itself) or a phone restart, Android stops Buddy. Start it again, if it was paired. */
class Restart : BroadcastReceiver() {
    override fun onReceive(c: Context, i: Intent) {
        if (Prefs(c).paired) c.startForegroundService(Intent(c, BuddyService::class.java))
    }
}
