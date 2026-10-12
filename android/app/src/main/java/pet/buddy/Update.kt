package pet.buddy

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import kotlin.concurrent.thread

/**
 * The app updates itself from the Mac: /card says when the Mac's APK was built; if that's newer than this install,
 * the card shows "Update available". Install = download from the Mac, hand it to Android's installer, one confirm tap.
 */
object Update {
    const val ACTION = "pet.buddy.INSTALLED"

    fun available(a: Activity, macApk: Long): Boolean {
        val installed = a.packageManager.getPackageInfo(a.packageName, 0).lastUpdateTime / 1000
        return macApk > installed + 60
    }

    fun install(a: Activity, prefs: Prefs) {
        if (!a.packageManager.canRequestPackageInstalls()) {   // once: let Buddy install its own updates
            Toast.makeText(a, "Allow Buddy to install updates, then tap Update again", Toast.LENGTH_LONG).show()
            a.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${a.packageName}")))
            return
        }
        Toast.makeText(a, "Downloading the update from your Mac…", Toast.LENGTH_SHORT).show()
        thread {
            try {
                val apk = prefs.get("/buddy.apk")
                val pi = a.packageManager.packageInstaller
                val id = pi.createSession(PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL))
                pi.openSession(id).use { s ->
                    s.openWrite("buddy.apk", 0, apk.size.toLong()).use { it.write(apk); s.fsync(it) }
                    val done = PendingIntent.getActivity(a, 7, Intent(a, MainActivity::class.java).setAction(ACTION),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
                    s.commit(done.intentSender)
                }
            } catch (e: Exception) {
                a.runOnUiThread { Toast.makeText(a, "Update failed: ${e.message}", Toast.LENGTH_LONG).show() }
            }
        }
    }

    /** Android answers the commit here: usually "ask the user", so show its confirm screen. */
    fun result(a: Activity, i: Intent) {
        if (i.action != ACTION) return
        when (i.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION ->
                @Suppress("DEPRECATION") (i.getParcelableExtra<Intent>(Intent.EXTRA_INTENT))?.let { a.startActivity(it) }
            PackageInstaller.STATUS_SUCCESS -> Toast.makeText(a, "Buddy is up to date", Toast.LENGTH_SHORT).show()
            else -> Toast.makeText(a, "Update didn't install: ${i.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)}", Toast.LENGTH_LONG).show()
        }
    }
}
