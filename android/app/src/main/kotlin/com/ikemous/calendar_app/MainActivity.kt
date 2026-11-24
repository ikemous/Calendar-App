package com.ikemous.calendar_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Lock screen countdowns: the app pushes fresh data after every
        // change (see CountdownWidgets).
        MethodChannel(messenger, "calendar_app/widgets")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        CountdownWidgets.save(
                            applicationContext,
                            call.argument<String>("data") ?: "{}",
                            call.argument<Boolean>("lockScreen") ?: false,
                            call.argument<Boolean>("showNext") ?: true,
                            call.argument<String>("image"),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Sync with the phone's own calendars (see DeviceCalendar).
        MethodChannel(messenger, "calendar_app/device_calendar")
            .setMethodCallHandler(::onDeviceCalendarCall)
    }

    private fun onDeviceCalendarCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(DeviceCalendar.hasPermission(this))
            "requestPermission" -> {
                if (DeviceCalendar.hasPermission(this)) {
                    result.success(true)
                } else {
                    // Answered in onRequestPermissionsResult.
                    permissionResult?.success(false)
                    permissionResult = result
                    requestPermissions(DeviceCalendar.permissions, CALENDAR_PERMISSION)
                }
            }
            else -> {
                // Calendar reads and writes can be slow: keep them off the
                // UI thread.
                val context = applicationContext
                thread {
                    try {
                        val id = call.argument<Number>("id")?.toLong()
                        val calendarId = call.argument<String>("calendarId")?.toLongOrNull()
                        val values = call.argument<Map<String, Any?>>("values")
                        val answer: Any? = when (call.method) {
                            "calendars" -> DeviceCalendar.calendars(context)
                            "events" -> DeviceCalendar.events(context, calendarId!!)
                            "event" -> DeviceCalendar.event(context, id!!)
                            "insert" -> DeviceCalendar.insert(context, calendarId!!, values!!)
                            "update" -> DeviceCalendar.update(context, id!!, values!!)
                            "delete" -> DeviceCalendar.delete(context, id!!).let { null }
                            else -> NOT_IMPLEMENTED
                        }
                        runOnUiThread {
                            if (answer === NOT_IMPLEMENTED) result.notImplemented()
                            else result.success(answer)
                        }
                    } catch (e: SecurityException) {
                        runOnUiThread { result.error("permission", "Calendar access denied", null) }
                    } catch (e: Exception) {
                        // Only the error type: event contents are private.
                        runOnUiThread { result.error("failed", e.javaClass.simpleName, null) }
                    }
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != CALENDAR_PERMISSION) return
        permissionResult?.success(DeviceCalendar.hasPermission(this))
        permissionResult = null
    }

    private companion object {
        const val CALENDAR_PERMISSION = 4201
        val NOT_IMPLEMENTED = Any()
    }
}
