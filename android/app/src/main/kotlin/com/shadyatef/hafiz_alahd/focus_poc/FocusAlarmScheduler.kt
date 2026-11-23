package com.shadyatef.hafiz_alahd.focus_poc

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONObject

/**
 * Native alarm scheduler providing exact Doze-safe alarm registration
 * and local persistence for boot and timezone restoration.
 */
object FocusAlarmScheduler {
    private const val TAG = "FocusAlarmScheduler"
    private const val PREFS_NAME = "focus_native_schedules_prefs"

    fun scheduleExactAlarm(
        context: Context,
        scheduleId: String,
        triggerAtMillis: Long,
        wardTitle: String,
        wardType: String
    ): Boolean {
        return try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            if (alarmManager == null) {
                Log.e(TAG, "AlarmManager not available")
                return false
            }

            val intent = Intent(context, FocusAlarmReceiver::class.java).apply {
                action = FocusAlarmReceiver.ACTION_FIRE_ALARM
                putExtra(FocusAlarmReceiver.EXTRA_SCHEDULE_ID, scheduleId)
                putExtra(FocusAlarmReceiver.EXTRA_WARD_TITLE, wardTitle)
                putExtra(FocusAlarmReceiver.EXTRA_WARD_TYPE, wardType)
            }

            val requestCode = scheduleId.hashCode()
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            }

            // Persist locally for boot & time change restoration
            saveScheduleEntry(context, scheduleId, triggerAtMillis, wardTitle, wardType)
            Log.i(TAG, "Exact alarm scheduled for $scheduleId at $triggerAtMillis ($wardTitle)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule exact alarm: ${e.message}", e)
            false
        }
    }

    fun cancelAlarm(context: Context, scheduleId: String): Boolean {
        return try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            val intent = Intent(context, FocusAlarmReceiver::class.java).apply {
                action = FocusAlarmReceiver.ACTION_FIRE_ALARM
            }
            val requestCode = scheduleId.hashCode()
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )

            if (pendingIntent != null && alarmManager != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            }

            removeScheduleEntry(context, scheduleId)
            Log.i(TAG, "Alarm cancelled for schedule $scheduleId")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel alarm: ${e.message}", e)
            false
        }
    }

    fun rescheduleAllOnBoot(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val allEntries = prefs.all
        val now = System.currentTimeMillis()
        val gracePeriodMillis = 30 * 60 * 1000L // 30 minutes

        Log.i(TAG, "Rescheduling ${allEntries.size} focus schedules on boot/time change")

        for ((scheduleId, jsonStr) in allEntries) {
            if (jsonStr is String) {
                try {
                    val obj = JSONObject(jsonStr)
                    val triggerAtMillis = obj.getLong("triggerAtMillis")
                    val wardTitle = obj.getString("wardTitle")
                    val wardType = obj.getString("wardType")

                    if (triggerAtMillis > now) {
                        // Future alarm - restore directly
                        scheduleExactAlarm(context, scheduleId, triggerAtMillis, wardTitle, wardType)
                    } else {
                        val elapsed = now - triggerAtMillis
                        if (elapsed <= gracePeriodMillis) {
                            Log.w(TAG, "Schedule $scheduleId missed recently (${elapsed / 1000}s ago). Triggering immediately.")
                            val triggerIntent = Intent(context, FocusAlarmReceiver::class.java).apply {
                                action = FocusAlarmReceiver.ACTION_FIRE_ALARM
                                putExtra(FocusAlarmReceiver.EXTRA_SCHEDULE_ID, scheduleId)
                                putExtra(FocusAlarmReceiver.EXTRA_WARD_TITLE, wardTitle)
                                putExtra(FocusAlarmReceiver.EXTRA_WARD_TYPE, wardType)
                            }
                            context.sendBroadcast(triggerIntent)
                        } else {
                            // Missed past grace period: advance by 24h
                            val nextDayMillis = triggerAtMillis + (24 * 60 * 60 * 1000L)
                            Log.i(TAG, "Schedule $scheduleId expired ($elapsed ms). Advancing to next day at $nextDayMillis")
                            scheduleExactAlarm(context, scheduleId, nextDayMillis, wardTitle, wardType)
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to parse schedule entry for $scheduleId: ${e.message}", e)
                }
            }
        }
    }

    private fun saveScheduleEntry(
        context: Context,
        scheduleId: String,
        triggerAtMillis: Long,
        wardTitle: String,
        wardType: String
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val obj = JSONObject().apply {
            put("scheduleId", scheduleId)
            put("triggerAtMillis", triggerAtMillis)
            put("wardTitle", wardTitle)
            put("wardType", wardType)
        }
        prefs.edit().putString(scheduleId, obj.toString()).apply()
    }

    private fun removeScheduleEntry(context: Context, scheduleId: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().remove(scheduleId).apply()
    }
}
