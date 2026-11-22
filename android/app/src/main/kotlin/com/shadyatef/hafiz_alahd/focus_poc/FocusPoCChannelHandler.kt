package com.shadyatef.hafiz_alahd.focus_poc

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class FocusPoCChannelHandler(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val TAG = "FocusPoCChannel"
    private val METHOD_CHANNEL = "com.shadyatef.hafiz_alahd/focus_poc"
    private val EVENT_CHANNEL = "com.shadyatef.hafiz_alahd/focus_poc_events"

    private val usageStatsPoller = UsageStatsPoller(context)
    private val overlayShieldManager = OverlayShieldManager(context)
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        var pendingWardIntent: String? = null
        private var eventSink: EventChannel.EventSink? = null
        private val staticHandler = Handler(Looper.getMainLooper())

        fun notifyEvent(eventType: String, data: Map<String, Any>) {
            staticHandler.post {
                try {
                    val payload = mutableMapOf<String, Any>(
                        "type" to eventType,
                        "timestamp" to System.currentTimeMillis()
                    )
                    payload.putAll(data)
                    eventSink?.success(payload)
                } catch (e: Exception) {
                    Log.w("FocusPoCChannel", "Error sending event $eventType to sink: ${e.message}")
                }
            }
        }
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
        Log.i(TAG, "Focus PoC Channels successfully registered")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkPermissions" -> {
                val hasUsage = usageStatsPoller.hasUsageAccessPermission()
                val hasOverlay = overlayShieldManager.hasOverlayPermission()
                val canExactAlarm = canScheduleExactAlarms()

                result.success(mapOf(
                    "hasUsageAccess" to hasUsage,
                    "hasOverlayPermission" to hasOverlay,
                    "canScheduleExactAlarms" to canExactAlarm
                ))
            }

            "openUsageAccessSettings" -> {
                try {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to open usage settings: ${e.message}", e)
                    result.error("INTENT_ERROR", e.message, null)
                }
            }

            "openOverlaySettings" -> {
                try {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:${context.packageName}")
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    } else {
                        Intent(Settings.ACTION_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    }
                    context.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to open overlay settings: ${e.message}", e)
                    result.error("INTENT_ERROR", e.message, null)
                }
            }

            "openExactAlarmSettings" -> {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val intent = Intent(
                            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:${context.packageName}")
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to open alarm settings: ${e.message}", e)
                    result.error("INTENT_ERROR", e.message, null)
                }
            }

            "startMonitoring" -> {
                val wardTitle = call.argument<String>("wardTitle") ?: "أذكار الصباح"
                val sessionId = call.argument<String>("sessionId")
                val serviceIntent = Intent(context, FocusPoCService::class.java).apply {
                    action = FocusPoCService.ACTION_START
                    putExtra(FocusPoCService.EXTRA_WARD_TITLE, wardTitle)
                    if (sessionId != null) {
                        putExtra(FocusPoCService.EXTRA_SESSION_ID, sessionId)
                    }
                }
                ContextCompat.startForegroundService(context, serviceIntent)
                result.success(true)
            }

            "stopMonitoring" -> {
                val serviceIntent = Intent(context, FocusPoCService::class.java).apply {
                    action = FocusPoCService.ACTION_STOP
                }
                context.startService(serviceIntent)
                result.success(true)
            }

            "isServiceRunning" -> {
                result.success(FocusPoCService.isRunning)
            }

            "getPendingWardIntent" -> {
                val target = pendingWardIntent
                pendingWardIntent = null
                result.success(target)
            }

            "getEnforcementStatus" -> {
                result.success(FocusPoCService.getDetailedStatus())
            }

            "getCurrentForegroundApp" -> {
                val currentPkg = usageStatsPoller.getForegroundPackage()
                val isExempt = usageStatsPoller.isPackageExempted(currentPkg)
                result.success(mapOf(
                    "packageName" to currentPkg,
                    "isExempted" to isExempt
                ))
            }

            "scheduleAlarm" -> {
                val scheduleId = call.argument<String>("scheduleId") ?: ""
                val triggerAtMillis = call.argument<Long>("triggerAtMillis")
                    ?: (call.argument<Number>("triggerAtMillis")?.toLong() ?: 0L)
                val wardTitle = call.argument<String>("wardTitle") ?: "ورد التركيز"
                val wardType = call.argument<String>("wardType") ?: "morningAdhkar"

                if (scheduleId.isEmpty() || triggerAtMillis <= 0L) {
                    result.error("INVALID_ARGS", "Missing scheduleId or triggerAtMillis", null)
                } else {
                    val scheduled = FocusAlarmScheduler.scheduleExactAlarm(
                        context,
                        scheduleId,
                        triggerAtMillis,
                        wardTitle,
                        wardType
                    )
                    result.success(scheduled)
                }
            }

            "cancelAlarm" -> {
                val scheduleId = call.argument<String>("scheduleId") ?: ""
                if (scheduleId.isEmpty()) {
                    result.error("INVALID_ARGS", "Missing scheduleId", null)
                } else {
                    val cancelled = FocusAlarmScheduler.cancelAlarm(context, scheduleId)
                    result.success(cancelled)
                }
            }

            "getInstalledApps" -> {
                Thread {
                    try {
                        val apps = AppInfoCollector.getInstalledLaunchableApps(context)
                        mainHandler.post {
                            result.success(apps)
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("QUERY_ERROR", e.message, null)
                        }
                    }
                }.start()
            }

            "setExemptions" -> {
                val exemptPackages = call.argument<List<String>>("exemptPackages") ?: emptyList()
                ExemptionRegistry.setExemptPackages(context, exemptPackages)
                result.success(true)
            }

            "getSystemCriticalPackages" -> {
                val criticals = ExemptionRegistry.getSystemCriticalPackages(context)
                result.success(criticals)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        Log.i(TAG, "Event channel listener attached")
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        Log.i(TAG, "Event channel listener cancelled")
    }

    private fun canScheduleExactAlarms(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            alarmManager?.canScheduleExactAlarms() ?: false
        } else {
            true
        }
    }
}
