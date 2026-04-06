package com.shadyatef.hafiz_alahd

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle // 👈 مهم لقياس المساحة
import android.os.SystemClock
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetPlugin

class PrayerWidgetProvider : HomeWidgetProvider() {

    // دالة مسؤولة عن تحديد التصميم بناءً على المساحة
    private fun getRemoteViews(context: Context, widgetData: SharedPreferences, width: Int): RemoteViews {
        // تحديد نقطة التحول (Breakpoint) بالعرض
        val isSmall = width < 180 // dp

        // 👈 اختيار ملف الـ XML المناسب
        val layoutId = if (isSmall) R.layout.widget_prayer_small else R.layout.widget_prayer_responsive
        val views = RemoteViews(context.packageName, layoutId)

        // --- تعبئة البيانات المشتركة بين التصميمين ---
        val prayerName = widgetData.getString("next_prayer_name", "غير محدد")
        val prayerTime = widgetData.getString("next_prayer_time", "--:--")
        val targetTimeMillis = widgetData.getLong("next_prayer_millis", 0)

        views.setTextViewText(R.id.tv_prayer_name, prayerName)
        views.setTextViewText(R.id.tv_prayer_time, prayerTime)

        // تشغيل العداد التنازلي
        if (targetTimeMillis > 0) {
            val elapsedRealtimeOffset = System.currentTimeMillis() - SystemClock.elapsedRealtime()
            val chronometerBase = targetTimeMillis - elapsedRealtimeOffset
            views.setChronometer(R.id.chronometer_remaining, chronometerBase, null, true)
        }

        // --- تعبئة البيانات الخاصة بالتصميم الكبير فقط (Timeline) ---
        if (!isSmall) {
            val fajr = widgetData.getString("fajr_time", "--:--")
            val dhuhr = widgetData.getString("dhuhr_time", "--:--")
            val asr = widgetData.getString("asr_time", "--:--")
            val maghrib = widgetData.getString("maghrib_time", "--:--")
            val isha = widgetData.getString("isha_time", "--:--")

            views.setTextViewText(R.id.tv_fajr_time, fajr)
            views.setTextViewText(R.id.tv_dhuhr_time, dhuhr)
            views.setTextViewText(R.id.tv_asr_time, asr)
            views.setTextViewText(R.id.tv_maghrib_time, maghrib)
            views.setTextViewText(R.id.tv_isha_time, isha)
        }

        return views
    }

    // الدالة القياسية التي تناديها الباكيدج للتحديث العادي
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (appWidgetId in appWidgetIds) {
            // جلب خيارات الويدجت للحصول على العرض الحالي
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            
            val views = getRemoteViews(context, widgetData, width)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    // 👈 دالة مهمة جداً: تنادى عندما يقوم المستخدم بتغيير حجم الويدجت يدوياً
    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle) {
        
        // 👈 السطر ده اللي اتعدل
        val widgetData = HomeWidgetPlugin.getData(context)
        
        // الحصول على العرض الجديد بعد تغيير الحجم
        val width = newOptions.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        
        val views = getRemoteViews(context, widgetData, width)
        appWidgetManager.updateAppWidget(appWidgetId, views)
        
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    }
}