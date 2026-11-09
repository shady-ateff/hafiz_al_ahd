# خطة التحقق المادي لإشعارات الصلاة — Phase 2D.2: Prayer Notification Physical Delivery
## Architecture, Verification Protocol & Dual-Device Delivery Plan

**تاريخ الخطة:** 2026-11-09  
**المرحلة:** Phase 2D.2 — Prayer Notification Physical Delivery  
**الحالة:** جاهز للاعتماد الهندسي (Ready for Review & Approval)  
**الأجهزة المستهدفة للتحقق المادي:**
1. **الجهاز الأساسي:** Xiaomi Redmi Note 14 Pro+ 5G (`dfa9f629` / Android 16 / API 36 / HyperOS)
2. **الجهاز الثانوي:** Samsung Galaxy Tab A7 LTE (`192.168.1.186:45067` / `SM-T505N` / Android 12 / API 31 / One UI)

**الـ Baseline Git Commit:** `9b016573cac649c421f6414eeba29e720e9d30ef` (Strictly 0 production diff on `lib/` & `android/`)  
**استراتيجية المعرفات:** Option B — معرفات مستقلة مخصصة لاختبارات الإشعارات:
- التنبيه المستهدف الأساسي: Notification #`999902`
- التنبيه المستهدف الثانوي (لتعدد الإشعارات): Notification #`999903`

---

## 1. الأهداف الهندسية للمرحلة (Core Objectives)

وفق توجيهات المراجعة الهندسية، لا يُعد اختفاء `pendingNotificationRequests` أو مجرد استدعاء دالة الجدولة في كود دارت دليلاً على النجاح. الهدف الجوهري لـ **Phase 2D.2** هو:

1. **إثبات التسليم الحقيقي في نظام التشغيل (Real OS Notification Delivery):**
   - إثبات تسجيل طلب الجدولة في `AlarmManager` الخاص بنظام أندرويد تحت الـ Receiver المخصص:  
     `com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver`
   - إثبات انطلاق الـ Broadcast واستقباله من قِبل الـ Receiver عند حلول الموعد.
   - إثبات تسجيل الإشعار فعلياً داخل `NotificationManagerService` كـ `NotificationRecord` نشط ومعروض في شريط الإشعارات (`Notification Shade`).
2. **فصل طبقات التحقق بدقة (Multi-Tier Notification Evidence):**
   - **Tier 1:** استعلامات الـ Plugin (`pendingNotificationRequests` و `getActiveNotifications`).
   - **Tier 2:** طابور الجدولة الزمني في نظام أندرويد (`dumpsys alarm` للـ `ScheduledNotificationReceiver`).
   - **Tier 3 (الدليل الحاسم):** سجلات نظام الإشعارات في أندرويد (`dumpsys notification` كـ `NotificationRecord` معروض) وسجلات `NotificationService` في الـ Logcat.
   - **Tier 4:** دورة حياة الإشعار والتنظيف الجراحي الحصري (`cancel(999902)` دون مساس بالتنبيهات الأخرى).
3. **التحقق عبر كافة حالات دورة حياة التطبيق (Lifecycle Coverage):**
   - الواجهة النشطة (Foreground)
   - الخلفية (Background)
   - **موت العملية التام (Process Death)** عبر إشارة `SIGKILL` غير القسرية.

---

## 2. مصفوفة السيناريوهات التنفيذية (Scenario Test Matrix)

| السيناريو | اسم السيناريو | حالة العملية وبيئة التشغيل | المدى الزمني المستهدف | محاور الإثبات والتحقق الحاسم | ملفات الأدلة المستهدفة |
|---|---|---|---|---|---|
| **2D.2.1** | **Foreground Delivery** | التطبيق في الواجهة النشطة | `now + 15s` | 1. مطابقة الجدولة في `dumpsys alarm`<br>2. ظهور `NotificationRecord` في `dumpsys notification`<br>3. التحقق عبر `getActiveNotifications()`<br>4. قياس الفارق الزمني `delivery_delta_ms` | `scenario_2d_2_1_foreground_<dev>_<ts>.json` |
| **2D.2.2** | **Background Delivery** | التطبيق في الخلفية (`KEYCODE_HOME`) | `now + 25s` | 1. استمرار بقاء العملية في الخلفية<br>2. انطلاق بث `ScheduledNotificationReceiver`<br>3. ظهور الإشعار في الـ Notification Shade أثناء وجود التطبيق بالخلفية | `scenario_2d_2_2_background_<dev>_<ts>.json` |
| **2D.2.3** | **Process-Death Delivery** *(الاختبار الحاسم)* | العملية ميتة بـ `SIGKILL` غير قسري | `now + 45s` | 1. صمام الأمان الزمني (> 12,000 ms)<br>2. **إثبات بقاء الـ PendingIntent والـ `origWhen` في `AlarmManager` أثناء موت العملية**<br>3. إطلاق أندرويد للـ Broadcast وتسليم الإشعار في الـ Shade دون أن يكون التطبيق قيد التشغيل<br>4. ظهور `NotificationRecord` في `dumpsys notification` | `scenario_2d_2_3_process_death_<dev>_<ts>.json` |
| **2D.2.4** | **Multiple Notifications & Non-Interference** | واجهة وخلفية | `+20s` (#999902)<br>`+40s` (#999903) | 1. جدولة إشعارين برقمين مختلفين<br>2. إثبات ظهور الإشعار الأول دون إلغاء الثاني<br>3. ظهور الإشعار الثاني بجانب الأول في الـ Shade<br>4. عدم تداخل البيانات أو المعرفات | `scenario_2d_2_4_multi_<dev>_<ts>.json` |
| **2D.2.5** | **Channel & Permission Boundary Profile** | فحص المنظومة | فوري | 1. فحص قناة `prayer_channel_v10_default` (الأهمية والصوت والاهتزاز)<br>2. مقارنة صلاحية `POST_NOTIFICATIONS` بين Android 16 و Android 12 | `scenario_2d_2_5_channel_profile_<dev>_<ts>.json` |
| **2D.2.6** | **Dual-Device Comparison** | كلا الجهازين | مجمع | مقارنة أداء شاومي (Android 16) وسامسونج (Android 12) في زمن التسليم وعرض الإشعارات في الـ Shade | `dual_device_2d2_final_comparison.json` |

---

## 3. البروتوكول التفصيلي للاختبار الحاسم: Scenario 2D.2.3 (Process-Death Notification Delivery)

يمثل هذا السيناريو المعيار الحاسم لإثبات قدرة إشعارات الصلاة على العمل حتى في حال إنهاء نظام التشغيل لعملية التطبيق:

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. PREFLIGHT: Verify ID 999902 is ABSENT from AlarmManager & NotifMgr  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 2. SCHEDULE: Schedule FLN Notification #999902 for Target (Now + 45s)  │
│    Record ScheduledEpochMs                                             │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 3. PRE-KILL OBSERVER TRACE:                                            │
│    Capture 8 Identity Attributes for ScheduledNotificationReceiver     │
│    (origWhen, whenElapsed, PendingIntentRecord, Receiver Component)    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 4. TIMING GUARD: Verify Remaining Time > 12,000 ms                     │
│    If < 12000ms -> Abort with INVALID_TEST_TIMING                      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 5. PROCESS TERMINATION: Execute run-as /system/bin/kill <PID>          │
│    Verify PID is null (CONFIRMED DEAD)                                 │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 6. POST-KILL ALARMMANAGER PERSISTENCE PROOF:                           │
│    Query dumpsys alarm while process is DEAD.                          │
│    Assert exact origWhen, whenElapsed, and PendingIntent still exist   │
│    Classification: TARGET_NOTIFICATION_ALARM_PERSISTENCE_PROVEN        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 7. DELIVERY WINDOW MONITORING: Wait until TargetEpochMs                │
│    - Monitor Logcat for Broadcast dispatch to ScheduledNotificationRcvr│
│    - Monitor dumpsys notification for NotificationRecord creation      │
│    - Verify Channel ID, Title, and Body                                │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 8. 4-POINT SURGICAL CLEANUP:                                           │
│    Execute cancel(999902) via Dedicated Cleanup Harness                │
│    Verify NotificationRecord disappears from NotificationManager       │
│    Verify Sibling / non-target notifications are UNTOUCHED             │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. نموذج هيكل الأدلة المادية (Target Evidence Schema)

سيتم تسجيل كافة البيانات في ملفات JSON مهيكلة تحتوي على:

```json
{
  "scenario_id": "2D.2.3.NotificationProcessDeathDelivery",
  "device_id": "dfa9f629",
  "target_notification_id": 999902,
  "scheduled_epoch_ms": 1794236000000,
  "timing_guard": {
    "remaining_ms_at_kill": 41200,
    "guard_passed": true
  },
  "process_termination": {
    "pid_before_kill": "12345",
    "pid_after_kill": null,
    "process_confirmed_dead": true
  },
  "alarm_persistence": {
    "pre_kill_matched": true,
    "post_kill_matched": true,
    "state_classification": "TARGET_NOTIFICATION_ALARM_PERSISTENCE_PROVEN",
    "receiver_component": "com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver",
    "pending_intent_identity": "PendingIntentRecord{...}"
  },
  "notification_delivery": {
    "broadcast_dispatched": true,
    "notification_record_found": true,
    "channel_id": "prayer_channel_v10_default",
    "importance": "IMPORTANCE_HIGH",
    "notification_visible_in_shade": true,
    "os_dispatch_delta_ms": 25,
    "classification": "NOTIFICATION_POSTED_TO_SHADE_FROM_PROCESS_DEATH"
  },
  "surgical_cleanup": {
    "target_notification_removed": true,
    "plugin_notification_absent": true,
    "shade_notification_cleared": true,
    "non_target_notifications_intact": true
  }
}
```

---

## 5. معايير الإغلاق والانتقال (Exit Criteria for STOP GATE 2D.2)

1. **دليل الواجهة (2D.2.1):** وصول الإشعار وظهوره في الـ Notification Shade بفارق زمني $\le 1000$ ms على كلا الجهازين.
2. **دليل الخلفية (2D.2.2):** بث الإشعار وظهوره للمستخدم أثناء وجود التطبيق في الخلفية.
3. **دليل موت العملية (2D.2.3):**
   - إثبات بقاء الـ `ScheduledNotificationReceiver` والـ `PendingIntent` في `AlarmManager` أثناء موت العملية.
   - إثبات قيام نظام أندرويد بنشر الـ `NotificationRecord` وعرضه في شريط الإشعارات أثناء موت التطبيق.
4. **التنظيف الجراحي الصارم (B5):** إثبات مسح الإشعار المستهدف فقط عند الإلغاء، دون استخدام `cancelAllNotifications()`.
5. **سلامة كود الإنتاج (Production Isolation):** بقاء `git diff lib/ android/` عند **Strictly 0 Lines Diff**.
6. **المقارنة بين الجهازين:** توثيق الفروق بين Android 16 (HyperOS) و Android 12 (One UI) في معالجة القنوات والصلاحيات.

---

> [!IMPORTANT]
> **حدود التفويض الحالية:**
> ننتظر مراجعتكم واعتمادكم لهذه الخطة لبدء إعداد سكربتات الرصد المخصصة لـ NotificationManager وادوات الـ Harness والشروع في تنفيذ سيناريوهات Phase 2D.2.

