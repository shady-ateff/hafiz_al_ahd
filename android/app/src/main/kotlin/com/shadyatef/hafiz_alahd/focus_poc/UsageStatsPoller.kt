package com.shadyatef.hafiz_alahd.focus_poc

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.telecom.TelecomManager
import android.util.Log

class UsageStatsPoller(private val context: Context) {
    private val TAG = "UsageStatsPoller"
    private var lastKnownForegroundPackage: String? = null

    init {
        ExemptionRegistry.init(context)
    }

    /**
     * Checks if the app has PACKAGE_USAGE_STATS permission granted via AppOps.
     */
    fun hasUsageAccessPermission(): Boolean {
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.e(TAG, "Error checking usage stats permission: ${e.message}", e)
            false
        }
    }

    /**
     * Retrieves the current foreground package name using UsageStatsManager.
     * Uses UsageEvents first for high accuracy, falling back to queryUsageStats.
     */
    fun getForegroundPackage(): String? {
        if (!hasUsageAccessPermission()) {
            Log.w(TAG, "Cannot query foreground package: Usage stats permission not granted")
            return null
        }

        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
        if (usm == null) {
            Log.e(TAG, "UsageStatsManager is null")
            return null
        }

        val endTime = System.currentTimeMillis()
        val startTime = endTime - 30000 // Last 30 seconds

        var detectedPackage: String? = null

        // 1. Try UsageEvents (Most accurate for recent transitions)
        try {
            val usageEvents = usm.queryEvents(startTime, endTime)
            val event = UsageEvents.Event()
            var lastEventTime = 0L

            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                val isResumed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    event.eventType == UsageEvents.Event.ACTIVITY_RESUMED
                } else {
                    event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
                }

                if (isResumed && event.timeStamp > lastEventTime) {
                    detectedPackage = event.packageName
                    lastEventTime = event.timeStamp
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "queryEvents failed: ${e.message}. Falling back to queryUsageStats")
        }

        // 2. Fallback to queryUsageStats if no event in the last window
        if (detectedPackage.isNullOrEmpty()) {
            try {
                val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, endTime - 60000, endTime)
                if (!stats.isNullOrEmpty()) {
                    val mostRecent = stats.maxByOrNull { it.lastTimeUsed }
                    detectedPackage = mostRecent?.packageName
                }
            } catch (e: Exception) {
                Log.e(TAG, "queryUsageStats fallback failed: ${e.message}", e)
            }
        }

        // 3. Fallback to lastKnownForegroundPackage if system returns empty while sitting on same app
        if (detectedPackage.isNullOrEmpty()) {
            detectedPackage = lastKnownForegroundPackage
        } else {
            lastKnownForegroundPackage = detectedPackage
        }

        return detectedPackage
    }

    /**
     * Determines whether a given package is exempt from being shielded.
     * Always exempt:
     * - Hafiz Al-Ahd itself
     * - The default phone / dialer app
     * - System home launcher
     * - System in-call UI
     */
    fun isPackageExempted(packageName: String?): Boolean {
        // If package is unknown or empty, do NOT assume safe if last known was restricted
        if (packageName.isNullOrEmpty()) {
            val last = lastKnownForegroundPackage
            return if (!last.isNullOrEmpty() && last != context.packageName) {
                isPackageExempted(last)
            } else {
                true
            }
        }

        return ExemptionRegistry.isPackageExempt(context, packageName)
    }

    private fun getDefaultDialerPackage(): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                telecomManager?.defaultDialerPackage
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun getDefaultLauncherPackage(): String? {
        return try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
            }
            val resolveInfo = context.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
            resolveInfo?.activityInfo?.packageName
        } catch (e: Exception) {
            null
        }
    }
}
