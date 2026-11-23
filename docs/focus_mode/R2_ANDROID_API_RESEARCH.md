# R2 — Android API Research
**Document ID:** `FOCUS_MODE_R2`
**Type:** Technical API Research
**Platform:** Android Only
**Status:** COMPLETE
**Review Date:** 2026-11-21

---

> [!IMPORTANT]
> هذه الوثيقة تعتمد على البحث في التوثيق الرسمي لـ Android. أي معلومة غير مؤكدة من مصدر رسمي تُصنَّف **UNVERIFIED**.

---

## 1. UsageStatsManager (R1.1)

### 1.1 الغرض

الحصول على التطبيق الذي يعمل في المقدمة حالياً لاكتشاف انتقال المستخدم بعيداً عن التطبيق.

### 1.2 الـ API

```kotlin
val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
val endTime = System.currentTimeMillis()
val startTime = endTime - 5000 // آخر 5 ثوانٍ
val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startTime, endTime)
val foreground = stats.maxByOrNull { it.lastTimeUsed }?.packageName
```

### 1.3 الإذن المطلوب

```xml
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
    tools:ignore="ProtectedPermissions"/>
```

> [!CAUTION]
> `PACKAGE_USAGE_STATS` هو **special app op permission** — لا يُمنح تلقائياً ولا يظهر في `requestPermissions()` العادية. المستخدم يجب أن يذهب يدوياً إلى:
> `Settings → Apps → Special App Access → Usage Access → {App Name}`

**طريقة التحقق من المنح:**
```kotlin
val appOpsManager = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
val mode = appOpsManager.checkOpNoThrow(
    AppOpsManager.OPSTR_GET_USAGE_STATS,
    android.os.Process.myUid(),
    context.packageName
)
val granted = mode == AppOpsManager.MODE_ALLOWED
```

**طريقة توجيه المستخدم:**
```kotlin
val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
context.startActivity(intent)
```

### 1.4 استراتيجية الاستطلاع (Polling)

UsageStatsManager لا يوفر callbacks أو event-based API. الوصول إليه يتطلب **polling دوري**.

| Interval المقترح | الكمون | التأثير على البطارية |
|---|---|---|
| 1 ثانية | ~1 ثانية | مرتفع جداً |
| 3 ثوانٍ | ~3 ثوانٍ | مرتفع |
| 5 ثوانٍ | ~5 ثوانٍ | متوسط |
| 10 ثوانٍ | ~10 ثوانٍ | منخفض |

**التوصية:** 5 ثوانٍ كحد أقصى مقبول للتجربة، 3 ثوانٍ للاستجابة الجيدة.

> [!WARNING]
> Doze Mode يُعيق الـ polling. الحل: تشغيل الـ polling داخل **Foreground Service** الذي يعمل بشكل مستمر مع Wakeful.

### 1.5 قيود OEM — UNVERIFIED

بعض OEMs (Samsung One UI، Xiaomi MIUI، Huawei) تفرض قيوداً إضافية على الخدمات التي تعمل في الخلفية:

| OEM | السلوك المُبلَّغ عنه | المصدر |
|---|---|---|
| Xiaomi MIUI | يُوقف خدمات الخلفية بعد مدة قصيرة | UNVERIFIED — مُبلَّغ من تقارير المطورين |
| Samsung One UI | Battery optimization قاسية بشكل افتراضي | UNVERIFIED |
| Huawei | AppLock يمنع الخدمات من الإقلاع تلقائياً | UNVERIFIED |

> [!NOTE]
> هذه القيود لا يمكن التحقق منها بدون اختبار فعلي على أجهزة حقيقية. يُرجى الرجوع إلى R8 (Device Testing Matrix).

### 1.6 UsageStatsManager vs AccessibilityService

| الخيار | UsageStatsManager | AccessibilityService |
|---|---|---|
| يكتشف foreground app | ✅ نعم (بتأخر 1-10 ثوانٍ) | ✅ نعم (فوري تقريباً) |
| إذن خاص | ✅ PACKAGE_USAGE_STATS | ✅ Accessibility |
| Google Play policy | ✅ مسموح للاستخدام الشرعي | ⚠️ مقيّد — يُمنع إلا للإمكانية الوصول |
| Doze Mode | ⚠️ تأثر بدون Foreground Service | ⚠️ تأثر |
| OEM restrictions | ⚠️ تتباين | ⚠️ تتباين |

**القرار:** `UsageStatsManager` هو الخيار الوحيد القابل للدفاع أمام Google Play. `AccessibilityService` محظور سياسياً إلا لأغراض إمكانية الوصول الحقيقية.

---

## 2. SYSTEM_ALERT_WINDOW (R1.2)

### 2.1 الغرض

عرض Focus Shield Overlay فوق كل التطبيقات، بما فيها التطبيقات المحظورة، لمنع استخدامها.

### 2.2 الإذن

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
```

هذا الإذن **مُعلن بالفعل** في AndroidManifest.xml.

### 2.3 التحقق والمنح

```kotlin
if (!Settings.canDrawOverlays(context)) {
    val intent = Intent(
        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
        Uri.parse("package:${context.packageName}")
    )
    startActivity(intent)
}
```

### 2.4 النوع المستخدم

```kotlin
val params = WindowManager.LayoutParams(
    WindowManager.LayoutParams.MATCH_PARENT,
    WindowManager.LayoutParams.MATCH_PARENT,
    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY, // API 26+
    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
    PixelFormat.TRANSLUCENT
)
```

> [!NOTE]
> `TYPE_APPLICATION_OVERLAY` هو النوع الصحيح منذ Android 8.0 (API 26). الأنواع القديمة مهملة ولا تعمل على Android الحديث.

### 2.5 القيود على Android 12+ / 13+ / 14+ / 15+

| الإصدار | القيود الإضافية |
|---|---|
| Android 12 (API 31) | Overlay من تطبيق يستهدف API 31+ لا يمكنه intercepting touches إذا كانت `FLAG_NOT_TOUCHABLE` غير مضبوطة بشكل صحيح |
| Android 12 (API 31) | مطلوب `FLAG_NOT_FOCUSABLE` لبعض أنواع الـ overlay أو إلا يُظهر النظام تحذيراً |
| Android 13+ | لا تغييرات جوهرية على `SYSTEM_ALERT_WINDOW` بحد ذاتها |
| Android 14 (API 34) | تشديد على الـ Foreground Services — لا تأثير مباشر على الـ overlay |
| Android 15 | UNVERIFIED — لا تغييرات موثقة على `SYSTEM_ALERT_WINDOW` |

### 2.6 حدود ما يمكن تحقيقه

> [!CAUTION]
> **Focus Shield ليس حظراً حقيقياً.** هو مجرد overlay يُظهر شاشة فوق التطبيق.
> - المستخدم يمكنه الضغط على زر Back أو تمرير الـ overlay
> - بعض التطبيقات (Phone، لوحة الإشعارات) تتجاوز الـ overlay
> - الـ Overlay لا يمنع التطبيق من العمل في الخلفية

**الحل:** تصميم Focus Shield كـ "gentle reminder" وليس "hard block". الصياغة والـ UX أهم من القيد التقني.

---

## 3. AlarmManager (R1.3)

### 3.1 الغرض

جدولة بداية جلسات التركيز في أوقات محددة (Scheduled Focus).

### 3.2 أنواع الـ Alarms

| النوع | الدقة | Doze | متى يُستخدم |
|---|---|---|---|
| `set()` | غير دقيق | يُؤجل | مهام غير حساسة للوقت |
| `setExact()` | دقيق | يُؤجل | دقيقة زمنياً لكن قابل للتأجيل |
| `setExactAndAllowWhileIdle()` | دقيق | لا يُؤجل | ⭐ المثالي لـ Focus Mode |
| `setAlarmClock()` | دقيق | لا يُؤجل | يظهر في status bar كمنبه — مناسب |

### 3.3 الأذونات على Android 12+

```xml
<!-- SCHEDULE_EXACT_ALARM: للتطبيقات التي لا تندرج تحت تصنيف Calendar/Alarm -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />

<!-- USE_EXACT_ALARM: فقط لـ Calendar و Alarm Clock apps (Android 13+) -->
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

**كلا الإذنين مُعلنان بالفعل** في AndroidManifest.xml.

> [!WARNING]
> `SCHEDULE_EXACT_ALARM` يمكن أن يُسحب من المستخدم (revoke) في Settings. يجب التحقق منه دائماً:
> ```kotlin
> val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
>     val canSchedule = am.canScheduleExactAlarms()
>     // if (!canSchedule) → go to Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM
> }
> ```

### 3.4 إعادة الجدولة بعد إعادة التشغيل (Reboot)

AlarmManager لا يحتفظ بالمنبهات بعد إعادة تشغيل الجهاز. لاستعادتها:

```kotlin
// BroadcastReceiver يستمع لـ BOOT_COMPLETED
class FocusModeBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // استعادة الجلسات المجدولة من SharedPreferences/DB
        }
    }
}
```

**مُعلن بالفعل:** `RECEIVE_BOOT_COMPLETED` و `RebootBroadcastReceiver` (لـ android_alarm_manager_plus).

### 3.5 Timezone Changes

AlarmManager يستخدم `RTC_WAKEUP` (وقت الساعة). عند تغيير المنطقة الزمنية، قد يُطلَق المنبه في وقت خاطئ.

**الحل:** الاستماع لـ `ACTION_TIMEZONE_CHANGED` وإعادة جدولة المنبهات.

---

## 4. Foreground Service (R1.4)

### 4.1 الغرض

تشغيل خدمة مراقبة مستمرة (polling على UsageStatsManager) أثناء جلسة التركيز.

### 4.2 الأنواع المتاحة (Android 14+)

| النوع | متى يُستخدم |
|---|---|
| `dataSync` | مزامنة البيانات |
| `mediaPlayback` | تشغيل الوسائط |
| `location` | تتبع الموقع |
| `camera` | استخدام الكاميرا |
| `microphone` | استخدام الميكروفون |
| `mediaProjection` | تسجيل الشاشة |
| `phoneCall` | مكالمات هاتفية |
| `health` | تتبع الصحة |
| `remoteMessaging` | رسائل فورية |
| `shortService` | مهام قصيرة (< 3 دقائق) |
| `fileManagement` | إدارة الملفات |
| `specialUse` | ⭐ استخدامات مخصصة |

**التوصية:** `specialUse` هو النوع الأنسب لخدمة مراقبة Focus Mode.

> [!IMPORTANT]
> `specialUse` يتطلب:
> 1. إضافة `property` في الـ manifest يشرح السبب.
> 2. مراجعة Google Play عند رفع التطبيق.
> ```xml
> <service android:name=".FocusMonitorService"
>     android:foregroundServiceType="specialUse">
>     <property
>         android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
>         android:value="Focus session monitoring for Islamic worship adherence"/>
> </service>
> ```

### 4.3 Background Start Restrictions (Android 12+)

منذ Android 12، لا يمكن بدء Foreground Service من الخلفية إلا في حالات محددة:

| الحالة | مسموح؟ |
|---|---|
| التطبيق في المقدمة | ✅ نعم |
| من BroadcastReceiver (AlarmManager) | ✅ نعم (مؤقتاً) |
| من JobScheduler | ✅ نعم |
| من BOOT_COMPLETED | ✅ نعم |
| من اشعار المستخدم | ✅ نعم |
| تلقائياً من الخلفية | ❌ لا — `ForegroundServiceStartNotAllowedException` |

**للـ Focus Mode المجدول:** يجب بدء الخدمة من `BroadcastReceiver` المرتبط بـ AlarmManager.

```kotlin
class FocusAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // هذا مسموح حتى على Android 12+
        val serviceIntent = Intent(context, FocusMonitorService::class.java)
        context.startForegroundService(serviceIntent)
    }
}
```

### 4.4 Android 15 Restrictions

> [!WARNING]
> Android 15 (API 35) أضاف قيوداً على `shortService`:
> - `shortService` محدود بـ 3 دقائق فقط
> - هذا لا يؤثر على `specialUse` التي تبقى غير محدودة الوقت

---

## 5. BootReceiver (R1.5)

### 5.1 الأحداث المدعومة

```xml
<receiver android:name=".FocusModeBootReceiver" android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
        <!-- QUICKBOOT_POWERON لـ HTC/OnePlus -->
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
    </intent-filter>
</receiver>
```

> [!NOTE]
> `BOOT_COMPLETED` يُطلَق بعد انتهاء إقلاع النظام بالكامل. على بعض الأجهزة قد يتأخر عدة دقائق.

### 5.2 ما يجب استعادته

عند استقبال `BOOT_COMPLETED`:

1. قراءة إعدادات Focus Mode من `SharedPreferences`
2. إن كان Focus Mode مُفعَّلاً، إعادة جدولة كل المنبهات المحفوظة
3. التحقق مما إذا كانت جلسة نشطة وقت الإقلاع (غير محتمل لكن يجب التعامل معه)

---

## 6. DevicePolicyManager (R1.6)

### 6.1 `setPackagesSuspended()`

```kotlin
// يتطلب Device Owner أو Profile Owner
devicePolicyManager.setPackagesSuspended(adminComponent, packageNames, suspend)
```

### 6.2 الحكم

> [!CAUTION]
> **غير قابل للتطبيق** في تطبيق Play Store عادي.
> - يتطلب أن يكون التطبيق **Device Owner** أو **Profile Owner**
> - Device Owner يتطلب تهيئة المؤسسة (Enterprise provisioning)
> - Play Store لا يسمح بتطبيقات تطلب هذه الصلاحيات لأغراض عامة
>
> **التصنيف: NOT FEASIBLE** — مُستبعد تماماً من النطاق.

---

## 7. ملخص الـ APIs

| API | الجدوى | الملاحظة |
|---|---|---|
| `UsageStatsManager` | ✅ ممكن | يتطلب PACKAGE_USAGE_STATS + polling |
| `SYSTEM_ALERT_WINDOW` | ✅ ممكن (محدود) | ليس حظراً حقيقياً |
| `AlarmManager.setExactAndAllowWhileIdle` | ✅ ممكن | مُستخدم بالفعل في المشروع |
| `Foreground Service (specialUse)` | ✅ ممكن | يحتاج تبرير في Play |
| `BOOT_COMPLETED` | ✅ ممكن | مُعلن بالفعل |
| `DevicePolicyManager.setPackagesSuspended` | ❌ غير ممكن | يتطلب Device Owner |
| `AccessibilityService` | ❌ محظور | Google Play policy |

---

*Review Date: 2026-11-21 | Phase: Research Only*
