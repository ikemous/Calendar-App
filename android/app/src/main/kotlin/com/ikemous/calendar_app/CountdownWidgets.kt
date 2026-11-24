package com.ikemous.calendar_app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * The two lock screen countdowns: the featured repeating event and the next
 * event.
 *
 * The lock screen card is one silent, persistent notification, which is the
 * only thing every Android phone shows on the lock screen. It shows a single
 * event (the featured one, or failing that the next one) with a live
 * countdown. The same data also feeds two app widgets for phones that allow
 * widgets on the lock screen.
 *
 * The Flutter side stores, per countdown, the list of entries that take
 * over from one another. This code picks the current entry, counts the days
 * and wakes itself at the next change (an entry ending, or midnight), so
 * everything stays right while the app is closed.
 */
object CountdownWidgets {
    /** Kept out of the Flutter notification plugin's "cancel all". */
    const val NOTIFICATION_ID = 7001

    private const val PREFS = "countdown_widgets"
    private const val KEY_DATA = "data"
    private const val KEY_LOCK_SCREEN = "lockScreen"
    private const val KEY_SHOW_NEXT = "showNext"
    private const val KEY_IMAGE = "image"
    private const val IMAGE_PX = 144
    private const val CHANNEL = "lock_screen"
    private const val FEATURED = "featured"
    private const val NEXT = "next"
    private const val HOUR_MS = 3_600_000L
    private const val DAY_MS = 24 * HOUR_MS

    private class Entry(val title: String, val startMs: Long, val untilMs: Long)

    fun save(
        context: Context,
        json: String,
        lockScreen: Boolean,
        showNext: Boolean,
        imagePath: String?,
    ) {
        prefs(context).edit()
            .putString(KEY_DATA, json)
            .putBoolean(KEY_LOCK_SCREEN, lockScreen)
            .putBoolean(KEY_SHOW_NEXT, showNext)
            .putString(KEY_IMAGE, imagePath)
            .apply()
        refresh(context)
    }

    /** Redraws the notification and the widgets, and books the next redraw. */
    fun refresh(context: Context) {
        val now = System.currentTimeMillis()
        val featured = current(context, FEATURED, now)
        val next = current(context, NEXT, now)

        val manager = AppWidgetManager.getInstance(context)
        renderWidgets(context, manager, FeaturedWidgetProvider::class.java, FEATURED, featured)
        renderWidgets(context, manager, NextEventWidgetProvider::class.java, NEXT, next)
        val changes = renderNotification(context, featured, next, now)
        scheduleRefresh(
            context, changes + listOfNotNull(featured?.untilMs, next?.untilMs))
    }

    fun renderWidget(context: Context, manager: AppWidgetManager, ids: IntArray, slot: String) {
        val entry = current(context, slot, System.currentTimeMillis())
        val views = RemoteViews(context.packageName, R.layout.widget_countdown)
        views.setTextViewText(
            R.id.widget_title,
            entry?.title ?: context.getString(
                if (slot == FEATURED) R.string.widget_featured_empty
                else R.string.widget_next_empty))
        views.setTextViewText(
            R.id.widget_days, entry?.let { daysLabel(context, it.startMs) } ?: "")
        openApp(context)?.let { views.setOnClickPendingIntent(R.id.widget_root, it) }
        manager.updateAppWidget(ids, views)
    }

    private fun renderWidgets(
        context: Context,
        manager: AppWidgetManager,
        provider: Class<*>,
        slot: String,
        entry: Entry?,
    ) {
        val ids = manager.getAppWidgetIds(ComponentName(context, provider))
        if (ids.isNotEmpty()) renderWidget(context, manager, ids, slot)
    }

    /**
     * Draws the lock screen card for one event and returns the moments at
     * which it has to be drawn again.
     */
    private fun renderNotification(
        context: Context,
        featured: Entry?,
        next: Entry?,
        now: Long,
    ): List<Long> {
        val manager = context.getSystemService(NotificationManager::class.java)
        val prefs = prefs(context)
        // One event only: the featured one, or failing that the next event.
        val entry = featured ?: if (prefs.getBoolean(KEY_SHOW_NEXT, true)) next else null
        if (!prefs.getBoolean(KEY_LOCK_SCREEN, false) || entry == null) {
            manager.cancel(NOTIFICATION_ID)
            return emptyList()
        }

        val views = RemoteViews(context.packageName, R.layout.notification_countdown)
        views.setTextViewText(R.id.countdown_title, entry.title)
        // The user's picture belongs to the featured event. Without one,
        // there is no image at all.
        val picture = if (entry === featured) loadPicture(prefs.getString(KEY_IMAGE, null)) else null
        views.setViewVisibility(
            R.id.countdown_image, if (picture == null) View.GONE else View.VISIBLE)
        if (picture != null) views.setImageViewBitmap(R.id.countdown_image, picture)
        val changes = mutableListOf(entry.untilMs)
        val remaining = entry.startMs - now
        if (remaining > 0) {
            // "100d 20:20:59": whole days as text, the rest as a system
            // timer that ticks by itself. It is reset each time a whole day
            // has run down.
            val days = remaining / DAY_MS
            val rest = remaining % DAY_MS
            views.setViewVisibility(R.id.countdown_timer, View.VISIBLE)
            views.setViewVisibility(R.id.countdown_now, View.GONE)
            views.setChronometer(
                R.id.countdown_timer,
                SystemClock.elapsedRealtime() + rest,
                if (days > 0) context.getString(R.string.countdown_days_format, days)
                else null,
                true,
            )
            views.setChronometerCountDown(R.id.countdown_timer, true)
            changes += now + rest
        } else {
            // Started: a whole-day event reads "Today", a timed one "Now".
            views.setViewVisibility(R.id.countdown_timer, View.GONE)
            views.setViewVisibility(R.id.countdown_now, View.VISIBLE)
            views.setTextViewText(
                R.id.countdown_now,
                context.getString(
                    if (entry.untilMs - entry.startMs >= DAY_MS - HOUR_MS)
                        R.string.widget_today
                    else R.string.countdown_now))
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Default importance keeps it out of the "silent" group, which
            // many phones hide on the lock screen. It makes no sound.
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    context.getString(R.string.lock_screen_channel),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                })
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        builder
            // Invisible: the card shows no icon of its own. Reminders keep
            // theirs (they are posted by the notification plugin).
            .setSmallIcon(R.drawable.ic_blank_small)
            // Plain text for places that cannot show the custom layout.
            .setContentTitle("${entry.title}  ${daysLabel(context, entry.startMs)}")
            // Android (12+) always gives a notification an expanded form and
            // an expand arrow; neither can be turned off. The expanded form
            // shows the same countdown, so expanding never loses it.
            .setCustomContentView(views)
            .setCustomBigContentView(views)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_EVENT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        // No tap action: the card is a display, and tapping one on the lock
        // screen would swap it for the unlock prompt.
        manager.notify(NOTIFICATION_ID, builder.build())
        return changes
    }

    /**
     * Wakes [CountdownRefreshReceiver] at the earliest of [changes] and
     * midnight (when the widgets' day counts roll over).
     */
    private fun scheduleRefresh(context: Context, changes: List<Long>) {
        val midnight = LocalDate.now().plusDays(1)
            .atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val at = (changes + midnight).min() + 1000
        val alarms = context.getSystemService(AlarmManager::class.java)
        val intent = PendingIntent.getBroadcast(
            context, 1, Intent(context, CountdownRefreshReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            alarms.canScheduleExactAlarms()
        try {
            if (exact) alarms.setExactAndAllowWhileIdle(AlarmManager.RTC, at, intent)
            else alarms.setAndAllowWhileIdle(AlarmManager.RTC, at, intent)
        } catch (e: SecurityException) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC, at, intent)
        }
    }

    /** The picture at [path] as a small rounded square, or null. */
    private fun loadPicture(path: String?): Bitmap? {
        if (path == null) return null
        return try {
            val source = BitmapFactory.decodeFile(path) ?: return null
            val side = minOf(source.width, source.height)
            val output = Bitmap.createBitmap(IMAGE_PX, IMAGE_PX, Bitmap.Config.ARGB_8888)
            val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            // Centre-crop to a square, scaled to the output size.
            val scale = IMAGE_PX.toFloat() / side
            shader.setLocalMatrix(Matrix().apply {
                setTranslate(-(source.width - side) / 2f, -(source.height - side) / 2f)
                postScale(scale, scale)
            })
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = shader }
            val radius = IMAGE_PX * 0.22f
            Canvas(output).drawRoundRect(
                RectF(0f, 0f, IMAGE_PX.toFloat(), IMAGE_PX.toFloat()), radius, radius, paint)
            output
        } catch (e: Exception) {
            null
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun openApp(context: Context): PendingIntent? =
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(
                context, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

    /** The first entry of [slot] that is not over yet. */
    private fun current(context: Context, slot: String, now: Long): Entry? {
        val json = prefs(context).getString(KEY_DATA, null) ?: return null
        return try {
            val entries = JSONObject(json).optJSONArray(slot) ?: return null
            for (i in 0 until entries.length()) {
                val entry = entries.getJSONObject(i)
                val until = entry.getLong("untilMs")
                if (until > now) {
                    return Entry(entry.getString("title"), entry.getLong("startMs"), until)
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    private fun daysLabel(context: Context, startMs: Long): String {
        val day = Instant.ofEpochMilli(startMs)
            .atZone(ZoneId.systemDefault()).toLocalDate()
        val days = ChronoUnit.DAYS.between(LocalDate.now(), day).toInt()
        return if (days <= 0) context.getString(R.string.widget_today)
        else context.resources.getQuantityString(R.plurals.widget_days, days, days)
    }
}

/**
 * Redraws the countdowns when an entry ends, at midnight, after a restart or
 * app update, and when the clock or time zone changes.
 */
class CountdownRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) =
        CountdownWidgets.refresh(context)
}

abstract class CountdownWidgetProvider(private val slot: String) :
    AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) = CountdownWidgets.renderWidget(context, appWidgetManager, appWidgetIds, slot)
}

class FeaturedWidgetProvider : CountdownWidgetProvider("featured")

class NextEventWidgetProvider : CountdownWidgetProvider("next")
