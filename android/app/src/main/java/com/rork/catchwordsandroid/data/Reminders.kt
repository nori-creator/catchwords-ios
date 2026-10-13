package com.rork.catchwordsandroid.data

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.rork.catchwordsandroid.MainActivity
import com.rork.catchwordsandroid.R
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import java.util.Calendar
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/**
 * 「復習の通知」 (off / ai = おまかせ / custom times) — port of iOS ReminderService. Each planned reminder is a one-time
 * WorkManager job; custom times plan the next day again when they fire; おまかせ is re-planned whenever the app opens.
 */
object Reminders {
    private const val CHANNEL = "review"
    private const val PREFIX = "review-"
    const val DEFAULT_TIME = "09:00"
    private const val QUIET_START = 22 * 60
    private const val QUIET_END = 8 * 60
    private const val MIN_BATCH = 5
    private const val MERGE_WINDOW_MS = 90 * 60 * 1000L

    enum class Reason { CUSTOM, SRS, HABIT }

    var mode: String
        get() = AppGraph.prefs.getString("reminder.mode", "off") ?: "off"
        set(v) = AppGraph.prefs.edit().putString("reminder.mode", v).apply()

    var times: List<String>
        get() = parseTimes(AppGraph.prefs.getString("reminder.times", DEFAULT_TIME) ?: DEFAULT_TIME)
        set(v) = AppGraph.prefs.edit().putString("reminder.times", v.joinToString(",")).apply()

    fun parseTimes(raw: String): List<String> {
        val list = raw.split(",").map { it.trim() }.filter(::isValidTime)
        return if (list.isEmpty()) listOf(DEFAULT_TIME) else list.toSet().sorted().take(3)
    }

    fun isValidTime(s: String): Boolean {
        val p = s.split(":").mapNotNull { it.toIntOrNull() }
        return s.length == 5 && p.size == 2 && p[0] in 0..23 && p[1] in 0..59
    }

    fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** Remembers when the app was opened (at most every 30 min, 14 days) — for the habit reminder. */
    fun recordAppOpen(now: Long = System.currentTimeMillis()) {
        val list = opens().toMutableList()
        if (list.isNotEmpty() && now - list.last() < 30 * 60 * 1000L) return
        val kept = list.filter { now - it < 14 * 86_400_000L } + now
        AppGraph.prefs.edit().putString("app.opens", kept.joinToString(",")).apply()
    }

    private fun opens(): List<Long> = (AppGraph.prefs.getString("app.opens", "") ?: "").split(",").mapNotNull { it.toLongOrNull() }

    private fun outsideQuietHours(ms: Long): Long {
        val c = Calendar.getInstance().apply { timeInMillis = ms }
        val m = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
        if (m in QUIET_END until QUIET_START) return ms
        if (m >= QUIET_START) c.add(Calendar.DAY_OF_YEAR, 1)
        c.set(Calendar.HOUR_OF_DAY, QUIET_END / 60); c.set(Calendar.MINUTE, 0); c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }

    private fun nextOccurrence(hhmm: String, now: Long): Long {
        val p = hhmm.split(":").mapNotNull { it.toIntOrNull() }
        val c = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, p.getOrElse(0) { 9 }); set(Calendar.MINUTE, p.getOrElse(1) { 0 }); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        if (c.timeInMillis <= now) c.add(Calendar.DAY_OF_YEAR, 1)
        return c.timeInMillis
    }

    private fun srsBestTime(due: List<Long>, now: Long): Long? {
        val soon = due.filter { it <= now + 86_400_000L }.sorted()
        if (soon.isEmpty()) return null
        val pick = soon[minOf(MIN_BATCH, soon.size) - 1]
        return outsideQuietHours(maxOf(pick, now + 30 * 60 * 1000L))
    }

    private fun habitTime(now: Long): Long? {
        val y = Calendar.getInstance().apply { timeInMillis = now; add(Calendar.DAY_OF_YEAR, -1) }
        val first = opens().filter {
            val c = Calendar.getInstance().apply { timeInMillis = it }
            c.get(Calendar.YEAR) == y.get(Calendar.YEAR) && c.get(Calendar.DAY_OF_YEAR) == y.get(Calendar.DAY_OF_YEAR)
        }.minOrNull() ?: return null
        val c = Calendar.getInstance().apply { timeInMillis = first }
        return outsideQuietHours(nextOccurrence("%02d:%02d".format(c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE)), now))
    }

    fun plan(mode: String, times: List<String>, due: List<Long>, now: Long = System.currentTimeMillis()): List<Pair<Long, Reason>> {
        val out = mutableListOf<Pair<Long, Reason>>()
        when (mode) {
            "custom" -> times.forEach { out += nextOccurrence(it, now) to Reason.CUSTOM }
            "ai" -> {
                val srs = srsBestTime(due, now)
                srs?.let { out += it to Reason.SRS }
                habitTime(now)?.let { h -> if (srs == null || abs(h - srs) >= MERGE_WINDOW_MS) out += h to Reason.HABIT }
            }
        }
        return out.filter { it.first > now }.sortedBy { it.first }
    }

    /** Replaces every pending review reminder with the plan for the current setting. */
    fun apply(context: Context, due: List<Long> = emptyList()) {
        val wm = WorkManager.getInstance(context)
        for (i in 0 until 4) wm.cancelUniqueWork("$PREFIX$i")
        val m = mode
        if (m != "custom" && m != "ai") return
        plan(m, times, due).forEachIndexed { i, (at, reason) ->
            val req = OneTimeWorkRequestBuilder<ReminderWorker>()
                .setInitialDelay((at - System.currentTimeMillis()).coerceAtLeast(0), TimeUnit.MILLISECONDS)
                .setInputData(workDataOf("reason" to reason.name))
                .build()
            wm.enqueueUniqueWork("$PREFIX$i", ExistingWorkPolicy.REPLACE, req)
        }
    }

    /** Re-plans with the current setting and the cards coming due (app opened, reviews graded). */
    fun refresh(context: Context) {
        val due = AppGraph.dex.state.value.reviews.values.mapNotNull { it.dueAtMs }
        apply(context, due)
    }

    suspend fun saveToAccount() {
        val data = buildJsonObject {
            put("notification_preferences", buildJsonObject {
                put("mode", mode)
                put("times", JsonArray(times.map { JsonPrimitive(it) }))
                put("ai", buildJsonObject { put("srs", true); put("habit", true) })
            })
        }
        runCatching { AppGraph.client.updateUserMetadata(data) }
    }

    /** Takes the setting made on the web (or at onboarding) when this device has none yet. */
    suspend fun loadFromAccount() {
        if (AppGraph.prefs.contains("reminder.mode")) return
        val prefs = runCatching { AppGraph.client.userMetadata()?.obj("notification_preferences") }.getOrNull() ?: return
        val m = prefs.str("mode")?.takeIf { it in listOf("off", "custom", "ai") } ?: return
        mode = m
        times = (prefs["times"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }?.filter(::isValidTime)?.ifEmpty { null } ?: listOf(DEFAULT_TIME)
    }

    fun notify(context: Context, reason: Reason) {
        if (!canNotify(context)) return
        val nm = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, tr("復習の通知", "Review reminders", "複習提醒"), NotificationManager.IMPORTANCE_DEFAULT))
        }
        val body = when (reason) {
            Reason.SRS -> tr("思い出しどきの単語がたまっています。今なら記憶に残りやすい時間です", "Words are ready to recall. Now is a good time to make them stick.", "有些單字到了該回想的時候，現在複習最容易記住")
            Reason.HABIT -> tr("いつもの時間です。1枚だけでも思い出してみよう", "It's your usual time. Try recalling just one card.", "老時間到了，就算只回想一張也好")
            Reason.CUSTOM -> tr("今日の復習が待っています。1枚だけでも思い出してみよう", "Today's review is waiting. Try recalling just one card.", "今天的複習在等你，就算只回想一張也好")
        }
        val open = PendingIntent.getActivity(
            context, 1,
            Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(android.net.Uri.parse("catchwords://review"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_catchwords)
            .setContentTitle("CatchWords")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(reason.ordinal + 100, n) }
    }
}

/** Posts one review reminder; a custom time plans tomorrow's again. */
class ReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val reason = runCatching { Reminders.Reason.valueOf(inputData.getString("reason") ?: "CUSTOM") }.getOrDefault(Reminders.Reason.CUSTOM)
        Reminders.notify(applicationContext, reason)
        if (reason == Reminders.Reason.CUSTOM) Reminders.apply(applicationContext)
        return Result.success()
    }
}
