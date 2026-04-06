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
        
        val locationName = widgetData.getString("location_name", "")
        val hijriDate = widgetData.getString("hijri_date", "")

        views.setTextViewText(R.id.tv_prayer_name, prayerName)
        views.setTextViewText(R.id.tv_prayer_time, prayerTime)
        views.setTextViewText(R.id.tv_location, locationName)
        views.setTextViewText(R.id.tv_hijri_date, hijriDate)

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

            // --- المعالجة الديناميكية: تعليم الصلاة القادمة فقط ---
            val defaultBg = 0 
            val activeBgColor = android.graphics.Color.parseColor("#33B89B5E")
            val defaultTitleColor = android.graphics.Color.parseColor("#888888")
            val defaultTimeColor = android.graphics.Color.parseColor("#FFFFFF")
            val activeColor = android.graphics.Color.parseColor("#B89B5E")

            val prayerLayouts = listOf(R.id.ll_fajr, R.id.ll_dhuhr, R.id.ll_asr, R.id.ll_maghrib, R.id.ll_isha)
            val titleViews = listOf(R.id.tv_fajr_title, R.id.tv_dhuhr_title, R.id.tv_asr_title, R.id.tv_maghrib_title, R.id.tv_isha_title)
            val timeViews = listOf(R.id.tv_fajr_time, R.id.tv_dhuhr_time, R.id.tv_asr_time, R.id.tv_maghrib_time, R.id.tv_isha_time)

            // إعادة كل الصلوات للحالة الافتراضية
            for (i in prayerLayouts.indices) {
                views.setInt(prayerLayouts[i], "setBackgroundColor", defaultBg)
                views.setTextColor(titleViews[i], defaultTitleColor)
                views.setTextColor(timeViews[i], defaultTimeColor)
            }

            // تفعيل الصلاة القادمة فقط
            var activeIndex = -1
            when (prayerName) {
                "الفجر" -> activeIndex = 0
                "الظهر" -> activeIndex = 1
                "العصر" -> activeIndex = 2
                "المغرب" -> activeIndex = 3
                "العشاء" -> activeIndex = 4
            }

            if (activeIndex != -1) {
                views.setInt(prayerLayouts[activeIndex], "setBackgroundColor", activeBgColor)
                views.setTextColor(titleViews[activeIndex], activeColor)
                views.setTextColor(timeViews[activeIndex], activeColor)
            }
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