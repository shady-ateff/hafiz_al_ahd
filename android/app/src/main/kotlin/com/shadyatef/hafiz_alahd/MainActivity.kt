package com.shadyatef.hafiz_alahd

import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.shadyatef.hafiz_alahd/alarm_channel"
    private val TAG = "HafizDisplay"

    private var lastAppliedModeId: Int = -1
    private var lastAppliedRefreshRate: Float = -1f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Ensure window is attached and ready before requesting display mode
        window.decorView.post {
            setOptimalDisplayMode()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            // Dismiss the keyguard without requiring password (like native alarm apps)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        setOptimalDisplayMode()
    }

    override fun onResume() {
        super.onResume()
        setOptimalDisplayMode()
    }

    /**
     * Enumerates supported display modes and requests the highest refresh rate (e.g. 90Hz, 120Hz)
     * compatible with the physical screen resolution. Avoids the maxRate initialization trap,
     * applies both preferredDisplayModeId and preferredRefreshRate, and logs detailed diagnostics.
     */
    private fun setOptimalDisplayMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            Log.i(TAG, "Display mode selection requires Android 6.0+ (API 23). Current SDK: ${Build.VERSION.SDK_INT}")
            return
        }

        try {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }

            if (display == null) {
                Log.w(TAG, "Display instance is null; cannot evaluate display modes")
                return
            }

            val currentMode = display.mode
            val currentW = currentMode.physicalWidth
            val currentH = currentMode.physicalHeight
            val currentRate = currentMode.refreshRate
            val modes = display.supportedModes

            Log.i(TAG, "Current Display Mode: ID=${currentMode.modeId}, Resolution=${currentW}x${currentH}, RefreshRate=${currentRate}Hz")
            Log.i(TAG, "Total Supported Modes: ${modes.size}")
            for (m in modes) {
                Log.i(TAG, "  -> Supported Mode: ID=${m.modeId}, Resolution=${m.physicalWidth}x${m.physicalHeight}, RefreshRate=${m.refreshRate}Hz")
            }

            // 1. Group modes matching current physical resolution (handling orientation dimension swaps)
            val resolutionMatchedModes = modes.filter { m ->
                (m.physicalWidth == currentW && m.physicalHeight == currentH) ||
                (m.physicalWidth == currentH && m.physicalHeight == currentW)
            }

            // 2. Fall back to all modes if strict resolution matching produced no candidates (e.g. system cutout insets)
            val candidateModes = if (resolutionMatchedModes.isNotEmpty()) {
                resolutionMatchedModes
            } else {
                Log.w(TAG, "No modes strictly matched resolution ${currentW}x${currentH}. Falling back to all supported modes.")
                modes.toList()
            }

            // 3. Select mode with maximum refresh rate (without biasing against currentRate)
            val bestMode = candidateModes.maxByOrNull { it.refreshRate }

            if (bestMode == null) {
                Log.w(TAG, "Could not determine candidate display mode.")
                return
            }

            Log.i(TAG, "Selected Optimal Mode: ID=${bestMode.modeId}, Resolution=${bestMode.physicalWidth}x${bestMode.physicalHeight}, RefreshRate=${bestMode.refreshRate}Hz")

            // 4. Deduplicate requests if already applied
            val targetRate = bestMode.refreshRate
            if (lastAppliedModeId == bestMode.modeId && lastAppliedRefreshRate == targetRate) {
                Log.d(TAG, "Mode ID ${bestMode.modeId} @ ${targetRate}Hz already applied; skipping duplicate request.")
                return
            }

            val params = window.attributes
            var changed = false

            // 5. Apply preferredDisplayModeId (API 23+)
            if (params.preferredDisplayModeId != bestMode.modeId) {
                params.preferredDisplayModeId = bestMode.modeId
                changed = true
            }

            // 6. Apply preferredRefreshRate (API 23+) alongside preferredDisplayModeId for modern SurfaceFlinger frame-rate voting
            if (params.preferredRefreshRate != targetRate) {
                params.preferredRefreshRate = targetRate
                changed = true
            }

            if (changed) {
                window.attributes = params
                lastAppliedModeId = bestMode.modeId
                lastAppliedRefreshRate = targetRate
                Log.i(TAG, "Successfully applied Window display preferences: preferredDisplayModeId=${bestMode.modeId}, preferredRefreshRate=${targetRate}Hz")
            } else {
                Log.i(TAG, "Window attributes already matched target mode ID ${bestMode.modeId} and rate ${targetRate}Hz.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error while applying display mode preferences: ${e.message}", e)
        }
    }

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
            } else if (call.method == "getDisplayRefreshRate") {
                val refreshRateInfo = getDisplayRefreshRateInfo()
                result.success(refreshRateInfo)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getDisplayRefreshRateInfo(): Map<String, Any> {
        val info = mutableMapOf<String, Any>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }
                if (display != null) {
                    val current = display.mode
                    info["currentModeId"] = current.modeId
                    info["activeRefreshRate"] = current.refreshRate.toDouble()
                    info["currentWidth"] = current.physicalWidth
                    info["currentHeight"] = current.physicalHeight
                    info["preferredDisplayModeId"] = window.attributes.preferredDisplayModeId
                    info["preferredRefreshRate"] = window.attributes.preferredRefreshRate.toDouble()

                    val modesList = display.supportedModes.map { m ->
                        mapOf(
                            "modeId" to m.modeId,
                            "width" to m.physicalWidth,
                            "height" to m.physicalHeight,
                            "refreshRate" to m.refreshRate.toDouble()
                        )
                    }
                    info["supportedModes"] = modesList
                }
            } catch (e: Exception) {
                info["error"] = e.message ?: "Unknown error"
                Log.e(TAG, "Error in getDisplayRefreshRateInfo: ${e.message}", e)
            }
        }
        return info
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
