package com.ikemous.calendar_app

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Reminders

/**
 * Reads and writes the phone's own calendars (Android's Calendar Provider).
 *
 * A calendar that belongs to a Google account on the phone is kept in step
 * with Google by Android itself, so syncing with it reaches Google Calendar
 * without the app signing in to Google.
 *
 * Only raw rows cross to the Flutter side; all interpretation (dates,
 * repeat rules, change detection) happens there, where it is unit-tested.
 */
object DeviceCalendar {
    val permissions = arrayOf(
        Manifest.permission.READ_CALENDAR,
        Manifest.permission.WRITE_CALENDAR,
    )

    fun hasPermission(context: Context) = permissions.all {
        context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    /** Calendars the user can add events to. */
    fun calendars(context: Context): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            Calendars.CONTENT_URI,
            arrayOf(
                Calendars._ID,
                Calendars.CALENDAR_DISPLAY_NAME,
                Calendars.ACCOUNT_NAME,
                Calendars.ACCOUNT_TYPE,
                Calendars.CALENDAR_COLOR,
                Calendars.IS_PRIMARY,
            ),
            "${Calendars.CALENDAR_ACCESS_LEVEL} >= ?",
            arrayOf("${Calendars.CAL_ACCESS_CONTRIBUTOR}"),
            "${Calendars.IS_PRIMARY} DESC, ${Calendars.CALENDAR_DISPLAY_NAME}",
        )?.use { c ->
            while (c.moveToNext()) {
                result += mapOf(
                    "id" to c.getLong(0).toString(),
                    "name" to (c.getString(1) ?: ""),
                    "account" to (c.getString(2) ?: ""),
                    "accountType" to (c.getString(3) ?: ""),
                    "color" to c.getInt(4),
                    "primary" to (c.getInt(5) == 1),
                )
            }
        }
        return result
    }

    private val eventColumns = arrayOf(
        Events._ID,
        Events.TITLE,
        Events.DESCRIPTION,
        Events.EVENT_LOCATION,
        Events.DTSTART,
        Events.DTEND,
        Events.DURATION,
        Events.ALL_DAY,
        Events.RRULE,
        Events.EXDATE,
        Events.EVENT_TIMEZONE,
        Events.ORIGINAL_ID,
        Events.ORIGINAL_INSTANCE_TIME,
        Events.STATUS,
    )

    private fun Cursor.longOrNull(i: Int) = if (isNull(i)) null else getLong(i)

    private fun row(c: Cursor, reminders: List<Int>) = mapOf(
        "id" to c.getLong(0),
        "title" to c.getString(1),
        "description" to c.getString(2),
        "location" to c.getString(3),
        "dtstart" to c.longOrNull(4),
        "dtend" to c.longOrNull(5),
        "duration" to c.getString(6),
        "allDay" to (c.getInt(7) == 1),
        "rrule" to c.getString(8),
        "exdate" to c.getString(9),
        "timezone" to c.getString(10),
        "originalId" to c.getString(11)?.toLongOrNull(),
        "originalInstanceTime" to c.longOrNull(12),
        "cancelled" to (!c.isNull(13) && c.getInt(13) == Events.STATUS_CANCELED),
        "reminders" to reminders,
    )

    /** Reminder minutes by event id, for [eventId] or for every event. */
    private fun reminders(context: Context, eventId: Long?): Map<Long, List<Int>> {
        val result = mutableMapOf<Long, MutableList<Int>>()
        context.contentResolver.query(
            Reminders.CONTENT_URI,
            arrayOf(Reminders.EVENT_ID, Reminders.MINUTES),
            eventId?.let { "${Reminders.EVENT_ID} = ?" },
            eventId?.let { arrayOf("$it") },
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val minutes = c.getInt(1)
                if (minutes >= 0) result.getOrPut(c.getLong(0)) { mutableListOf() } += minutes
            }
        }
        return result
    }

    /** Every event of the calendar that has not been deleted. */
    fun events(context: Context, calendarId: Long): List<Map<String, Any?>> {
        val reminders = reminders(context, null)
        val result = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            Events.CONTENT_URI,
            eventColumns,
            "${Events.CALENDAR_ID} = ? AND ${Events.DELETED} = 0",
            arrayOf("$calendarId"),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                result += row(c, reminders[c.getLong(0)] ?: emptyList())
            }
        }
        return result
    }

    fun event(context: Context, id: Long): Map<String, Any?>? {
        context.contentResolver.query(
            ContentUris.withAppendedId(Events.CONTENT_URI, id),
            eventColumns,
            "${Events.DELETED} = 0",
            null,
            null,
        )?.use { c ->
            if (c.moveToFirst()) return row(c, reminders(context, id)[id] ?: emptyList())
        }
        return null
    }

    private fun values(v: Map<*, *>): ContentValues = ContentValues().apply {
        put(Events.TITLE, v["title"] as String? ?: "")
        put(Events.DESCRIPTION, v["description"] as String? ?: "")
        put(Events.EVENT_LOCATION, v["location"] as String? ?: "")
        // An event whose repeat rule the app cannot represent keeps its
        // timing exactly as it is.
        if (v["keepTiming"] == true) return@apply
        put(Events.DTSTART, (v["dtstart"] as Number).toLong())
        put(Events.ALL_DAY, if (v["allDay"] == true) 1 else 0)
        put(Events.EVENT_TIMEZONE, v["timezone"] as String? ?: "UTC")
        // Android wants an end for single events and a duration for
        // repeating ones, never both.
        val dtend = (v["dtend"] as Number?)?.toLong()
        if (dtend == null) putNull(Events.DTEND) else put(Events.DTEND, dtend)
        for ((column, key) in listOf(
            Events.DURATION to "duration",
            Events.RRULE to "rrule",
            Events.EXDATE to "exdate",
        )) {
            val text = v[key] as String?
            if (text == null) putNull(column) else put(column, text)
        }
    }

    private fun writeReminders(context: Context, id: Long, v: Map<*, *>) {
        val resolver = context.contentResolver
        resolver.delete(Reminders.CONTENT_URI, "${Reminders.EVENT_ID} = ?", arrayOf("$id"))
        for (minutes in v["reminders"] as List<*>? ?: emptyList<Any>()) {
            resolver.insert(Reminders.CONTENT_URI, ContentValues().apply {
                put(Reminders.EVENT_ID, id)
                put(Reminders.MINUTES, (minutes as Number).toInt())
                put(Reminders.METHOD, Reminders.METHOD_ALERT)
            })
        }
    }

    /** Returns the new event's id. */
    fun insert(context: Context, calendarId: Long, v: Map<*, *>): Long {
        val uri = context.contentResolver.insert(
            Events.CONTENT_URI,
            values(v).apply { put(Events.CALENDAR_ID, calendarId) },
        ) ?: throw IllegalStateException("The calendar refused the event")
        val id = ContentUris.parseId(uri)
        writeReminders(context, id, v)
        return id
    }

    /** Returns false if the event no longer exists. */
    fun update(context: Context, id: Long, v: Map<*, *>): Boolean {
        if (event(context, id) == null) return false
        val rows = context.contentResolver.update(
            ContentUris.withAppendedId(Events.CONTENT_URI, id), values(v), null, null)
        if (rows == 0) return false
        writeReminders(context, id, v)
        return true
    }

    fun delete(context: Context, id: Long) {
        context.contentResolver.delete(
            ContentUris.withAppendedId(Events.CONTENT_URI, id), null, null)
    }
}
