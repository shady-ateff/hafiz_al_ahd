package com.shadyatef.hafiz_alahd.focus_poc

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat

class FocusAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "FocusAlarmReceiver"
        const val ACTION_FIRE_ALARM = "com.shadyatef.hafiz_alahd.focus_poc.ACTION_FIRE_ALARM"
        const val EXTRA_SCHEDULE_ID = "extra_schedule_id"
        const val EXTRA_WARD_TITLE = "extra_ward_title"
        const val EXTRA_WARD_TYPE = "extra_ward_type"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val scheduleId = intent?.getStringExtra(EXTRA_SCHEDULE_ID) ?: "default_schedule"
        val wardTitle = intent?.getStringExtra(EXTRA_WARD_TITLE) ?: "أذكار الصباح"
        val wardType = intent?.getStringExtra(EXTRA_WARD_TYPE) ?: "morningAdhkar"

        Log.i(TAG, "Alarm triggered for schedule: $scheduleId ($wardTitle, $wardType)")

        // Acquire a temporary WakeLock (max 10 seconds) to ensure foreground service starts
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = powerManager?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "hafiz_al_ahd:FocusAlarmWakeLock"
        )
        wakeLock?.acquire(10000L)

        try {
            val sessionId = "sched_${scheduleId}_${System.currentTimeMillis()}"
            val serviceIntent = Intent(context, FocusPoCService::class.java).apply {
                action = FocusPoCService.ACTION_START
                putExtra(FocusPoCService.EXTRA_WARD_TITLE, wardTitle)
                putExtra(FocusPoCService.EXTRA_SESSION_ID, sessionId)
            }

            ContextCompat.startForegroundService(context, serviceIntent)
            Log.i(TAG, "Started FocusPoCService from exact alarm for session $sessionId")

            // Notify Flutter isolate if running
            FocusPoCChannelHandler.notifyEvent(
                "onScheduleFired",
                mapOf(
                    "scheduleId" to scheduleId,
                    "sessionId" to sessionId,
                    "wardTitle" to wardTitle,
                    "wardType" to wardType
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start service from alarm receiver: ${e.message}", e)
        } finally {
            if (wakeLock?.isHeld == true) {
                try {
                    wakeLock.release()
                } catch (e: Exception) {
                    Log.w(TAG, "WakeLock release warning: ${e.message}")
                }
            }
        }
    }
}
