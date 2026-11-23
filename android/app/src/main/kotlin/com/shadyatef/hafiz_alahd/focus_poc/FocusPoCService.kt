package com.shadyatef.hafiz_alahd.focus_poc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class FocusPoCService : Service() {
    private val TAG = "FocusPoCService"
    private val NOTIFICATION_ID = 9991
    private val CHANNEL_ID = "focus_poc_service_channel"

    private var serviceJob: Job? = null
    private val serviceScope = CoroutineScope(Dispatchers.Default)

    private lateinit var usageStatsPoller: UsageStatsPoller
    private lateinit var overlayShieldManager: OverlayShieldManager
    private var wakeLock: PowerManager.WakeLock? = null

    private var currentWardTitle: String = "أذكار الصباح"
    private var isMonitoringActive = false
    private var snoozeUntilMillis: Long = 0L
    private var snoozeCount: Int = 0
    private val MAX_SNOOZE_COUNT: Int = 2

    companion object {
        const val ACTION_START = "com.shadyatef.hafiz_alahd.focus_poc.START"
        const val ACTION_STOP = "com.shadyatef.hafiz_alahd.focus_poc.STOP"
        const val ACTION_SNOOZE = "com.shadyatef.hafiz_alahd.focus_poc.SNOOZE"
        const val EXTRA_WARD_TITLE = "extra_ward_title"
        const val EXTRA_SESSION_ID = "extra_session_id"
        const val EXTRA_SNOOZE_MINUTES = "extra_snooze_minutes"

        var isRunning: Boolean = false
            private set

        var currentSessionId: String? = null
            private set

        var currentWardTitle: String = "أذكار الصباح"
            private set

        var isSnoozedState: Boolean = false
            private set

        var snoozeCountVal: Int = 0
            private set

        var startedAtMillis: Long = 0L
            private set

        fun getDetailedStatus(): Map<String, Any?> {
            val stateStr = when {
                !isRunning -> "stopped"
                isSnoozedState -> "snoozed"
                else -> "active"
            }
            return mapOf(
                "isRunning" to isRunning,
                "sessionId" to currentSessionId,
                "wardTitle" to currentWardTitle,
                "state" to stateStr,
                "snoozeRemaining" to (2 - snoozeCountVal).coerceAtLeast(0),
                "startedAt" to (if (startedAtMillis > 0) startedAtMillis else null),
                "lastError" to null
            )
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "FocusPoCService onCreate")
        usageStatsPoller = UsageStatsPoller(this)
        overlayShieldManager = OverlayShieldManager(this)

        overlayShieldManager.onSnoozeListener = {
            Log.i(TAG, "Snooze triggered from Overlay")
            handleSnooze(5)
        }

        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        Log.i(TAG, "onStartCommand received action: $action")

        when (action) {
            ACTION_START -> {
                currentWardTitle = intent?.getStringExtra(EXTRA_WARD_TITLE) ?: "أذكار الصباح"
                currentSessionId = intent?.getStringExtra(EXTRA_SESSION_ID)
                startedAtMillis = System.currentTimeMillis()
                isRunning = true
                isSnoozedState = false
                snoozeCountVal = 0
                snoozeUntilMillis = 0L
                snoozeCount = 0
                startForegroundWithNotification()
                startMonitoringLoop()
            }
            ACTION_STOP -> {
                stopMonitoring(reason = "USER_STOPPED_FROM_APP")
            }
            ACTION_SNOOZE -> {
                val minutes = intent?.getIntExtra(EXTRA_SNOOZE_MINUTES, 5) ?: 5
                handleSnooze(minutes)
            }
        }

        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundWithNotification() {
        createNotificationChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            putExtra("focus_ward_target", currentWardTitle)
        }
        val launchPendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notifBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🕌 جلسة تركيز نشطة — $currentWardTitle")
            .setContentText("الحافظ يراقب الورد لمساعدتك على الالتزام بعهدك.")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setContentIntent(launchPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)

        // Only add snooze action if user hasn't exhausted the limit (max 2)
        if (snoozeCount < MAX_SNOOZE_COUNT) {
            val remaining = MAX_SNOOZE_COUNT - snoozeCount
            val snoozeIntent = Intent(this, FocusPoCService::class.java).apply {
                action = ACTION_SNOOZE
                putExtra(EXTRA_SNOOZE_MINUTES, 5)
            }
            val snoozePendingIntent = PendingIntent.getService(
                this,
                1,
                snoozeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            notifBuilder.addAction(
                android.R.drawable.ic_popup_sync,
                "⏳ غفوة 5 دقائق (متبقي $remaining)",
                snoozePendingIntent
            )
        }

        startForeground(NOTIFICATION_ID, notifBuilder.build())
        isRunning = true
        isMonitoringActive = true
        Log.i(TAG, "Service started in foreground")
    }

    private fun startMonitoringLoop() {
        serviceJob?.cancel()
        serviceJob = serviceScope.launch {
            Log.i(TAG, "Monitoring loop started (interval: 3000ms)")
            FocusPoCChannelHandler.notifyEvent("SESSION_STARTED", mapOf("wardTitle" to currentWardTitle))

            while (isActive && isMonitoringActive) {
                try {
                    // Check if in Snooze mode
                    if (snoozeUntilMillis > 0L) {
                        if (System.currentTimeMillis() < snoozeUntilMillis) {
                            val remainingSec = (snoozeUntilMillis - System.currentTimeMillis()) / 1000L
                            Log.d(TAG, "In Snooze mode: ${remainingSec}s remaining")
                            delay(3000)
                            continue
                        } else {
                            // Snooze finished
                            Log.i(TAG, "Snooze duration ended. Resuming active monitoring.")
                            snoozeUntilMillis = 0L
                            isSnoozedState = false
                            updateNotificationActive()
                            FocusPoCChannelHandler.notifyEvent("SNOOZE_EXPIRED", mapOf(
                                "wardTitle" to currentWardTitle
                            ))
                        }
                    }

                    val currentPkg = usageStatsPoller.getForegroundPackage()
                    val isExempt = usageStatsPoller.isPackageExempted(currentPkg)

                    Log.d(TAG, "Polled foreground app: $currentPkg (Exempt: $isExempt)")

                    FocusPoCChannelHandler.notifyEvent("APP_POLLED", mapOf(
                        "packageName" to (currentPkg ?: "UNKNOWN"),
                        "isExempted" to isExempt,
                        "timestamp" to System.currentTimeMillis()
                    ))

                    if (currentPkg != null && !isExempt) {
                        // User switched to restricted external app -> Show Shield
                        if (!overlayShieldManager.isShowing()) {
                            val remainingSnoozes = MAX_SNOOZE_COUNT - snoozeCount
                            Log.w(TAG, "Restricted app active ($currentPkg) -> Showing shield (Remaining snoozes: $remainingSnoozes)")
                            overlayShieldManager.show(currentWardTitle, remainingSnoozes)
                            FocusPoCChannelHandler.notifyEvent("SHIELD_SHOWN", mapOf(
                                "triggeredBy" to currentPkg,
                                "remainingSnoozes" to remainingSnoozes
                            ))
                        }
                    } else if (currentPkg != null && isExempt) {
                        // User returned to Hafiz or dialer -> Hide Shield
                        if (overlayShieldManager.isShowing()) {
                            Log.i(TAG, "Safe app active ($currentPkg) -> Hiding shield")
                            overlayShieldManager.hide()
                            FocusPoCChannelHandler.notifyEvent("SHIELD_HIDDEN", mapOf(
                                "currentApp" to currentPkg
                            ))
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error in monitoring loop iteration: ${e.message}", e)
                }

                delay(3000) // 3 seconds polling
            }
        }
    }

    private fun handleSnooze(minutes: Int) {
        if (snoozeCount >= MAX_SNOOZE_COUNT) {
            Log.w(TAG, "Maximum snooze limit reached ($MAX_SNOOZE_COUNT). Snooze rejected.")
            FocusPoCChannelHandler.notifyEvent("SNOOZE_LIMIT_REACHED", mapOf(
                "wardTitle" to currentWardTitle,
                "maxLimit" to MAX_SNOOZE_COUNT
            ))
            return
        }

        snoozeCount++
        snoozeCountVal = snoozeCount
        isSnoozedState = true
        val remainingSnoozes = MAX_SNOOZE_COUNT - snoozeCount
        Log.w(TAG, "Snooze activated for $minutes minutes. Snooze count: $snoozeCount/$MAX_SNOOZE_COUNT")
        snoozeUntilMillis = System.currentTimeMillis() + (minutes * 60 * 1000L)
        overlayShieldManager.hide()

        updateNotificationSnoozed(minutes, remainingSnoozes)

        FocusPoCChannelHandler.notifyEvent("SESSION_SNOOZED", mapOf(
            "wardTitle" to currentWardTitle,
            "durationMinutes" to minutes,
            "snoozeCount" to snoozeCount,
            "remainingSnoozes" to remainingSnoozes,
            "snoozeUntil" to snoozeUntilMillis
        ))
    }

    private fun updateNotificationSnoozed(minutes: Int, remainingSnoozes: Int) {
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            val launchPendingIntent = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val snoozeNote = if (remainingSnoozes > 0) {
                "متبقي لك $remainingSnoozes غفوة إضافية"
            } else {
                "هذه آخر غفوة متاحة لليوم"
            }

            val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("⏳ في وضع الغفوة ($minutes دقائق) — $currentWardTitle")
                .setContentText("انقر للعودة للورد. ($snoozeNote).")
                .setSmallIcon(android.R.drawable.ic_popup_sync)
                .setOngoing(true)
                .setContentIntent(launchPendingIntent)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .build()

            val manager = getSystemService(NotificationManager::class.java)
            manager?.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error updating snoozed notification: ${e.message}", e)
        }
    }

    private fun updateNotificationActive() {
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            val launchPendingIntent = PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notifBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("🕌 جلسة تركيز نشطة — $currentWardTitle")
                .setContentText("الحافظ يراقب الورد لمساعدتك على الالتزام بعهدك.")
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setOngoing(true)
                .setContentIntent(launchPendingIntent)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)

            // Only add snooze action if limit not reached
            if (snoozeCount < MAX_SNOOZE_COUNT) {
                val remaining = MAX_SNOOZE_COUNT - snoozeCount
                val snoozeIntent = Intent(this, FocusPoCService::class.java).apply {
                    action = ACTION_SNOOZE
                    putExtra(EXTRA_SNOOZE_MINUTES, 5)
                }
                val snoozePendingIntent = PendingIntent.getService(
                    this,
                    1,
                    snoozeIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                notifBuilder.addAction(
                    android.R.drawable.ic_popup_sync,
                    "⏳ غفوة 5 دقائق (متبقي $remaining)",
                    snoozePendingIntent
                )
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager?.notify(NOTIFICATION_ID, notifBuilder.build())
        } catch (e: Exception) {
            Log.e(TAG, "Error updating active notification: ${e.message}", e)
        }
    }

    private fun stopMonitoring(reason: String) {
        Log.i(TAG, "Stopping monitoring. Reason: $reason")
        isMonitoringActive = false
        isRunning = false
        isSnoozedState = false
        currentSessionId = null
        startedAtMillis = 0L
        snoozeCountVal = 0
        serviceJob?.cancel()
        overlayShieldManager.hide()

        FocusPoCChannelHandler.notifyEvent("SESSION_STOPPED", mapOf(
            "reason" to reason,
            "wardTitle" to currentWardTitle
        ))

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "HafizAlAhd:FocusPoCWakeLock")
            wakeLock?.acquire(60 * 60 * 1000L) // Max 1 hour
        } catch (e: Exception) {
            Log.e(TAG, "Error acquiring wakelock: ${e.message}", e)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing wakelock: ${e.message}", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "مراقبة جلسة التركيز (PoC)",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "إشعار مستمر يظهر طوال مدة جلسة التركيز النشطة لمتابعة الورد"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i(TAG, "FocusPoCService onDestroy")
        isMonitoringActive = false
        isRunning = false
        isSnoozedState = false
        currentSessionId = null
        startedAtMillis = 0L
        snoozeCountVal = 0
        serviceJob?.cancel()
        overlayShieldManager.hide()
        releaseWakeLock()
    }
}
