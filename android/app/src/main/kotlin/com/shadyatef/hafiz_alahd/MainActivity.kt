package com.shadyatef.hafiz_alahd

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.shadyatef.hafiz_alahd/alarm_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scheduleExactAlarm") {
                val triggerTime = call.argument<Long>("triggerTime") ?: 0L
                val args = call.arguments as Map<String, Any>

                if (triggerTime > 0) {
                    scheduleNativeAlarm(triggerTime, args)
                    result.success(true)
                } else {
                    result.error("INVALID_TIME", "Trigger time cannot be zero", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun scheduleNativeAlarm(triggerTimeMillis: Long, args: Map<String, Any>) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, PrayerUpdateReceiver::class.java).apply {
            val notifId = args["notification_id"] as? Int ?: 888
            putExtra("notification_id", notifId)
            putExtra("notification_title", args["notification_title"] as? String)
            putExtra("notification_body", args["notification_body"] as? String)
            putExtra("next_prayer_name", args["next_prayer_name"] as? String)
            putExtra("next_prayer_time", args["next_prayer_time"] as? String)
            
            // Handle Number conversion properly for longs
            val nextPrayerMillis = when (val ms = args["next_prayer_millis"]) {
                is Long -> ms
                is Int -> ms.toLong()
                else -> 0L
            }
            putExtra("next_prayer_millis", nextPrayerMillis)
            
            putExtra("fajr_time", args["fajr_time"] as? String)
            putExtra("dhuhr_time", args["dhuhr_time"] as? String)
            putExtra("asr_time", args["asr_time"] as? String)
            putExtra("maghrib_time", args["maghrib_time"] as? String)
            putExtra("isha_time", args["isha_time"] as? String)
        }

        val pendingIntent = PendingIntent.getBroadcast(
            this,
            9999, // Unique request code to replace old intents
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // setExactAndAllowWhileIdle executes the broadcast exactly, ignoring Doze mode
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
            }
        } catch (e: SecurityException) {
            // لو أندرويد 14+ واليوزر رفض تصريح المنبه الدقيق، نستخدم المنبه العادي كاحتياطي عشان ميكراشش
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
            println("SecurityException: Exact alarm permission denied. Falling back to inexact alarm.")
        }
    }
}

