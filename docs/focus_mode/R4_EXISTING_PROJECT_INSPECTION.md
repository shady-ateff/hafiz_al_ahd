# R4 — Existing Project Inspection
**Document ID:** `FOCUS_MODE_R4`
**Type:** Technical Inspection
**Platform:** Android Only
**Status:** COMPLETE
**Review Date:** 2026-11-21

---

## 1. Project Overview

| Property | Value |
|---|---|
| App Name | Hafiz Al-Ahd |
| Package ID | `com.shadyatef.hafiz_alahd` |
| Version | 3.4.0+13 |
| Flutter SDK | `^3.10.4` |
| Architecture | Clean Architecture (data / domain / presentation) |
| State Management | `flutter_bloc` (Cubit pattern) |
| DI | `get_it` (Service Locator) |
| Local DB | SQLite (`sqflite`), Hive, SharedPreferences |
| Branch | `feature/quran-audio` |

---

## 2. Android Configuration

### 2.1 SDK Versions

```
compileSdk  → flutter.compileSdkVersion (resolved at build time, typically 35 for Flutter 3.10+)
minSdk      → flutter.minSdkVersion    (typically 21)
targetSdk   → flutter.targetSdkVersion (typically 34)
```

> [!NOTE]
> القيم المحددة تُقرأ من `local.properties` في وقت البناء. الأرقام أعلاه هي القيم الافتراضية الشائعة لـ Flutter 3.10.x.

### 2.2 Permissions Already Declared (AndroidManifest.xml)

| Permission | Status | Relevance to Focus Mode |
|---|---|---|
| `INTERNET` | ✅ Declared | لا |
| `ACCESS_FINE_LOCATION` | ✅ Declared | لا |
| `ACCESS_COARSE_LOCATION` | ✅ Declared | لا |
| `RECEIVE_BOOT_COMPLETED` | ✅ Declared (×2) | ✅ نعم — مطلوب لاستعادة الجلسات بعد إعادة التشغيل |
| `POST_NOTIFICATIONS` | ✅ Declared | ✅ نعم — مطلوب لإشعارات Focus Shield |
| `SCHEDULE_EXACT_ALARM` | ✅ Declared | ✅ نعم — مطلوب للجدولة الدقيقة |
| `USE_EXACT_ALARM` | ✅ Declared | ✅ نعم — Android 13+ |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | ✅ Declared | ✅ نعم — مطلوب لاستمرار الخدمة |
| `WAKE_LOCK` | ✅ Declared | ✅ نعم — مطلوب لاستيقاظ الجهاز |
| `FOREGROUND_SERVICE` | ✅ Declared | ✅ نعم — مطلوب لخدمة المراقبة |
| `FOREGROUND_SERVICE_SPECIAL_USE` | ✅ Declared | ✅ نعم — النوع الحالي للـ BackgroundService |
| `SYSTEM_ALERT_WINDOW` | ✅ Declared | ✅ نعم — مطلوب لـ Focus Shield Overlay |
| `USE_FULL_SCREEN_INTENT` | ✅ Declared | ⚠️ قد يلزم لشاشة القفل |
| `VIBRATE` | ✅ Declared | ⚠️ ثانوي |
| `ACCESS_NOTIFICATION_POLICY` | ✅ Declared | ⚠️ ثانوي (Do Not Disturb) |
| `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | ✅ Declared | لا |

**ملاحظة حرجة:** `PACKAGE_USAGE_STATS` غير معلن — مطلوب لـ UsageStatsManager. يحتاج إعلاناً إضافياً.

> [!CAUTION]
> `PACKAGE_USAGE_STATS` هو إذن من نوع `appOps` وليس `runtime`. لا يُمنح تلقائياً ولا يظهر في `requestPermissions`. المستخدم يجب أن يذهب يدوياً إلى Settings > Apps > Special App Access > Usage Access.

### 2.3 Existing Services & Receivers

| Component | Type | Purpose |
|---|---|---|
| `PrayerUpdateReceiver` | BroadcastReceiver | استقبال أحداث أوقات الصلاة |
| `PrayerWidgetProvider` | AppWidgetProvider | ويدجت الصلاة |
| `ScheduledNotificationReceiver` | BroadcastReceiver (FLN) | إشعارات flutter_local_notifications |
| `ScheduledNotificationBootReceiver` | BroadcastReceiver (FLN) | استعادة الإشعارات بعد الإقلاع |
| `AlarmBroadcastReceiver` | BroadcastReceiver (AAM+) | android_alarm_manager_plus |
| `RebootBroadcastReceiver` | BroadcastReceiver (AAM+) | استعادة المنبهات بعد الإقلاع |
| `BackgroundService` | ForegroundService (specialUse) | flutter_background_service — الاستخدام الحالي غير محدد |
| `AudioService` | ForegroundService (mediaPlayback) | تشغيل القرآن في الخلفية |
| `MediaButtonReceiver` | BroadcastReceiver | أزرار الوسائط |

---

## 3. Existing Dependencies (pubspec.yaml)

### 3.1 ذات صلة بـ Focus Mode

| Package | Version | الصلة |
|---|---|---|
| `flutter_background_service` | ^5.1.0 | ✅ يمكن استخدامه لخدمة مراقبة الحضور |
| `android_alarm_manager_plus` | ^5.0.0 | ✅ جدولة جلسات التركيز |
| `flutter_local_notifications` | ^21.0.0 | ✅ إشعارات الـ Foreground و Focus Alerts |
| `permission_handler` | ^12.0.1 | ✅ طلب الأذونات |
| `shared_preferences` | ^2.5.4 | ✅ حفظ إعدادات Focus Mode |
| `hive` + `hive_flutter` | ^2.2.3 | ✅ حفظ حالة الجلسة |
| `get_it` | ^9.2.1 | ✅ DI للخدمات المستقلة |
| `device_info_plus` | ^12.4.0 | ✅ تحديد إصدار Android |
| `android_intent_plus` | ^6.0.0 | ✅ فتح إعدادات الأذونات |

### 3.2 غير موجودة (تحتاج قرار)

| Package | Purpose | ملاحظة |
|---|---|---|
| `flutter_usage_stats` / أي wrapper لـ UsageStatsManager | مراقبة التطبيقات | غير موجودة — يحتاج MethodChannel مخصص أو إضافة dependency |
| `workmanager` | دورية في الخلفية | غير موجودة — ليست مطلوبة بالضرورة إذا استُخدم flutter_background_service |

---

## 4. Existing Completion Tracking — Azkar

### 4.1 الملفات ذات الصلة

| File | Role |
|---|---|
| `azkar_tracker_cubit.dart` | يتتبع عدد مرات ذكر كل زكر داخل الجلسة |
| `azkar_state.dart` | `AzkarTrackerState { counts: Map<String, int>, lastUpdated: DateTime }` |
| `azkar_item.dart` | `{ category, text, description, reference, count }` |
| `azkar_list_screen.dart` | يحسب `completedCount` ويستدعي `_checkCategoryCompletion` |
| `celebration_dialog.dart` | يظهر عند اكتمال التصنيف |

### 4.2 منطق الاكتمال الحالي

```dart
// azkar_list_screen.dart — _checkCategoryCompletion
void _checkCategoryCompletion(int completedCount) {
  if (completedCount == widget.azkarList.length && !_isCategoryCompleted) {
    _isCategoryCompleted = true;
    context.read<GamificationCubit>().completeAzkarCategory(widget.categoryTitle);
    showCelebrationDialog(...);
  }
}

// completedCount يُحسب في build():
for (var item in widget.azkarList) {
  final target = item.count > 0 ? item.count : 1;
  final current = cubit.getZikrCount(item.text);
  if (current >= target) completedCount++;
}
```

### 4.3 المشاكل المعمارية للتكامل مع Focus Mode

| المشكلة | التفاصيل |
|---|---|
| **Cubit-bound** | `AzkarTrackerCubit` هو Presentation-layer. يمكن Dispose عند خروج المستخدم من الشاشة. لا يمكن الاعتماد عليه من طبقة Domain أو Background Service. |
| **In-memory only** | الحالة موجودة فقط في الذاكرة. لا يوجد persistence بين جلسات التطبيق. |
| **Reset غير مباشر** | non-daily categories تُعاد تهيئتها عند خروج الشاشة (`dispose()`). |
| **لا Domain event** | لا يوجد `Stream` أو `EventBus` يُصدر حدث الاكتمال خارج طبقة Presentation. |

> [!IMPORTANT]
> **Contract مطلوب:** لا يمكن لـ Focus Mode أن يستمع مباشرة إلى `AzkarTrackerCubit`. يجب إنشاء `AzkarCompletionContract` في طبقة Domain تُصدر `Stream<AzkarSessionResult>` يمكن الاستماع إليه من الـ Focus Session Service.

---

## 5. Existing MethodChannels

| Channel Name | File | Methods |
|---|---|---|
| `com.shadyatef.hafiz_alahd/alarm_channel` | `MainActivity.kt` | `scheduleExactAlarm`, `getDisplayRefreshRate` |

**ملاحظة:** الـ MethodChannel الحالي خاص بجدولة أوقات الصلاة والشاشة. لا يوجد MethodChannel مخصص لـ UsageStats أو Focus Mode.

---

## 6. Existing AlarmManager Usage

```kotlin
// MainActivity.kt — scheduleNativeAlarm()
alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerTimeMillis, pendingIntent)
// Android 14+ fallback: alarmManager.set(...)
```

وكذلك عبر `android_alarm_manager_plus` مسجّل في AndroidManifest كـ `AlarmService` و `AlarmBroadcastReceiver`.

---

## 7. flutter_background_service Status

الحزمة مُعلنة في Manifest:
```xml
<service
    android:name="id.flutter.flutter_background_service.BackgroundService"
    android:foregroundServiceType="specialUse"
    android:exported="true" />
```

**نوع الخدمة:** `specialUse` — مناسب للاستخدامات العامة التي لا تندرج تحت الأنواع الأخرى.

> [!WARNING]
> `foregroundServiceType="specialUse"` يتطلب تبريراً في Google Play عند الرفع. هذا موجود بالفعل لأغراض أخرى في التطبيق. Focus Mode Monitoring Service يمكن أن يستخدم نفس الخدمة أو خدمة منفصلة.

---

## 8. Gamification Integration

عند اكتمال تصنيف الأذكار:
```dart
context.read<GamificationCubit>().completeAzkarCategory(widget.categoryTitle);
```

هذا يعني أن الـ gamification event يُرسل من Presentation layer أيضاً.

**للـ Focus Mode:** لا يلزم تعديل هذا السلوك. Focus Mode يستمع للاكتمال بشكل مستقل.

---

## 9. Settings Feature Inspection

```
lib/features/settings/
```

يحتوي على إعدادات الصلاة وأوقات الإقامة. لا يوجد حالياً قسم "Focus Mode" في الإعدادات.

**المطلوب:** إضافة صفحة إعدادات مستقلة `Settings → Focus Mode` في مرحلة التنفيذ.

---

## 10. ملخص الاكتشافات

### ✅ ما يتوفر مسبقاً

- `SYSTEM_ALERT_WINDOW` ← مُعلن
- `FOREGROUND_SERVICE` ← مُعلن
- `RECEIVE_BOOT_COMPLETED` ← مُعلن
- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` ← مُعلنان
- `flutter_background_service` ← مُثبّت ومُعلن
- `android_alarm_manager_plus` ← مُثبّت ومُعلن
- `flutter_local_notifications` ← مُثبّت ومُعلن
- `permission_handler` ← مُثبّت
- منطق اكتمال الأذكار موجود (في Presentation layer)
- AlarmManager مُستخدم فعلياً

### ⚠️ ما يحتاج إضافة / قرار

- `PACKAGE_USAGE_STATS` ← **غير مُعلن** — ضروري لـ UsageStatsManager
- MethodChannel لـ UsageStatsManager ← **غير موجود** — يحتاج تطوير Android Native أو package
- `AzkarCompletionContract` (Domain Stream) ← **غير موجود** — يحتاج تصميم
- صفحة إعدادات Focus Mode ← **غير موجودة**
- تحديد هل يستخدم Focus Mode خدمة `BackgroundService` الحالية أم خدمة منفصلة

### ❌ ما هو غير موجود ولن يُضاف في R1

- أي كود تنفيذي لـ Focus Mode
- أي تعديل على AndroidManifest.xml
- أي dependency جديد

---

*Review Date: 2026-11-21 | Phase: Research Only*
