package com.shadyatef.hafiz_alahd.focus_poc

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class FocusBootReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "FocusBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        Log.i(TAG, "Received system broadcast action: $action")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                Log.i(TAG, "Restoring and rescheduling exact focus alarms after $action")
                FocusAlarmScheduler.rescheduleAllOnBoot(context)
            }
            else -> {
                Log.d(TAG, "Unhandled action: $action")
            }
        }
    }
}
