package com.myvault.myvault

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Document reminders. The app hands over the schedule whenever the vault
 * changes: for each reminder only its day, the expiry day and a short text
 * ("Passport expires in 1 month."), never numbers or names. A job runs about
 * twice a day, also after a restart, and posts what's due: the latest one per
 * document, once. It works while MyVault is closed or locked.
 */
class ReminderJob : JobService() {
    companion object {
        private const val JOB_ID = 4711
        private const val CHANNEL = "documents"
        private const val PREFS = "reminders"

        /** One file per vault ("reminders.json" for the original one), so each
         *  vault's reminders stay when another vault is opened. */
        private fun fileOf(c: Context, vault: String) =
            File(c.filesDir, if (vault == "default") "reminders.json" else "reminders-$vault.json")

        fun save(c: Context, vault: String, json: String) {
            if (!Regex("^(default|[0-9a-f]{32})$").matches(vault)) return
            val f = fileOf(c, vault)
            val tmp = File(c.filesDir, "${f.name}.part")
            tmp.writeText(json)
            tmp.renameTo(f)
            schedule(c)
            check(c)
        }

        fun schedule(c: Context) {
            val js = c.getSystemService(JobScheduler::class.java)
            if (js.getPendingJob(JOB_ID) != null) return
            js.schedule(JobInfo.Builder(JOB_ID, ComponentName(c, ReminderJob::class.java))
                .setPeriodic(12 * 60 * 60 * 1000L)
                .setPersisted(true)                // survives a restart (RECEIVE_BOOT_COMPLETED)
                .build())
        }

        /** Post one notification; false if Android doesn't allow MyVault to. */
        fun notifyNow(c: Context, tag: String, text: String): Boolean {
            val nm = c.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(NotificationChannel(CHANNEL, c.getString(R.string.reminders_channel), NotificationManager.IMPORTANCE_DEFAULT))
            }
            val open = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), PendingIntent.FLAG_IMMUTABLE)
            val n = (if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(c, CHANNEL)
                else @Suppress("DEPRECATION") android.app.Notification.Builder(c))
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("MyVault")
                .setContentText(text)
                .setContentIntent(open)
                .setAutoCancel(true)
                .setVisibility(android.app.Notification.VISIBILITY_PRIVATE)
                .build()
            return try {
                nm.notify(tag.hashCode(), n)
                true
            } catch (e: SecurityException) {
                false
            }
        }

        fun check(c: Context) {
            // every vault's reminders, while they're all locked
            val plan = JSONArray()
            c.filesDir.listFiles { f -> f.name.matches(Regex("""^reminders(-[0-9a-f]{32})?\.json$""")) }?.forEach { f ->
                try {
                    val a = JSONArray(f.readText())
                    for (i in 0 until a.length()) plan.put(a.get(i))
                } catch (_: Exception) {}
            }
            if (plan.length() == 0) return
            val prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val shown = prefs.getStringSet("shown", emptySet())!!.toMutableSet()
            val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
            val best = HashMap<String, org.json.JSONObject>()
            val done = HashMap<String, Int>()     // per document: the latest reminder already shown
            val keys = HashSet<String>()
            for (i in 0 until plan.length()) {
                val r = plan.getJSONObject(i)
                keys.add(r.getString("key"))
                if (r.getString("on") > today || today > r.getString("expires")) continue
                val entry = r.getString("entry")
                if (r.getString("key") in shown) {
                    done[entry] = minOf(done[entry] ?: 99999, r.getInt("days"))
                    continue
                }
                val prev = best[entry]
                if (prev == null || r.getInt("days") < prev.getInt("days")) best[entry] = r
            }
            // an earlier reminder never comes after a later one has been shown
            best.entries.removeAll { (entry, r) -> r.getInt("days") >= (done[entry] ?: 99999) }
            for (r in best.values) {
                if (!notifyNow(c, r.getString("entry"), r.getString("text"))) return   // not allowed (yet): next time
                shown.add(r.getString("key"))
            }
            prefs.edit().putStringSet("shown", shown.intersect(keys)).apply()
        }
    }

    override fun onStartJob(params: JobParameters?): Boolean {
        check(this)
        return false
    }

    override fun onStopJob(params: JobParameters?) = true
}
