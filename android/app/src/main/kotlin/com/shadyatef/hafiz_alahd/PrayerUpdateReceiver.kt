package com.shadyatef.hafiz_alahd

import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import es.antonborri.home_widget.HomeWidgetPlugin

class PrayerUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nextPrayerName = intent.getStringExtra("next_prayer_name") ?: return
        val nextPrayerTime = intent.getStringExtra("next_prayer_time") ?: return
        val nextPrayerMillis = intent.getLongExtra("next_prayer_millis", 0L)
        
        val fajr = intent.getStringExtra("fajr_time") ?: "--:--"
        val dhuhr = intent.getStringExtra("dhuhr_time") ?: "--:--"
        val asr = intent.getStringExtra("asr_time") ?: "--:--"
        val maghrib = intent.getStringExtra("maghrib_time") ?: "--:--"
        val isha = intent.getStringExtra("isha_time") ?: "--:--"

        val notificationId = intent.getIntExtra("notification_id", 888)
        val notificationTitle = intent.getStringExtra("notification_title") ?: nextPrayerName
        val notificationBody = intent.getStringExtra("notification_body") ?: "الصلاة القادمة"

        // 1. Save data directly to HomeWidget SharedPreferences natively
        val widgetData = HomeWidgetPlugin.getData(context)
        val editor = widgetData.edit()
        editor.putString("next_prayer_name", nextPrayerName)
        editor.putString("next_prayer_time", nextPrayerTime)
        editor.putLong("next_prayer_millis", nextPrayerMillis)
        editor.putString("fajr_time", fajr)
        editor.putString("dhuhr_time", dhuhr)
        editor.putString("asr_time", asr)
        editor.putString("maghrib_time", maghrib)
        editor.putString("isha_time", isha)
        editor.apply()

        // 2. Broadcast immediately to standard AppWidgetProvider to refresh the Chronometer perfectly
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, PrayerWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        
        val updateIntent = Intent(context, PrayerWidgetProvider::class.java)
        updateIntent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
        updateIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, appWidgetIds)
        context.sendBroadcast(updateIntent)

        // 3. Immediately refresh the Sticky Notification without launching Flutter Engine
        if (nextPrayerMillis > 0) {
            
            // 👈 هنا تعريف pendingTapIntent اللي كان ناقص عندك
            val tapIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingTapIntent = PendingIntent.getActivity(
                context, 0, tapIntent, pendingIntentFlags
            )

            // ضبط الأيقونة بأمان وصناعة الـ Bitmap للأيقونة الكبيرة
            val safeIcon = context.resources.getIdentifier("ic_stat_icon", "drawable", context.packageName).takeIf { it != 0 } ?: R.mipmap.ic_launcher
            val largeIconBitmap = android.graphics.BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)

            // بناء الإشعار
            val builder = NotificationCompat.Builder(context, "sticky_countdown_channel_v1")
                .setContentTitle(notificationTitle)
                .setContentText(notificationBody)
                .setSmallIcon(safeIcon)
                .setLargeIcon(largeIconBitmap)
                .setOngoing(true)
                .setAutoCancel(false)
                .setShowWhen(true)
                .setWhen(nextPrayerMillis)
                .setUsesChronometer(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setContentIntent(pendingTapIntent) // 👈 دلوقتي هيقرأها من غير مشاكل
                
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                builder.setChronometerCountDown(true)
            }

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(notificationId, builder.build())
        }
    }
}