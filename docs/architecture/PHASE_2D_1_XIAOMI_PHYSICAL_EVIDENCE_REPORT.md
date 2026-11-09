# تقرير الأدلة المادية الشامل — Phase 2D.1: Prayer Alarm Physical Delivery
## Primary Device: Xiaomi Redmi Note 14 Pro+ 5G (Android 16 / HyperOS)

**تاريخ الاختبار:** 2026-11-09  
**الجهاز المستهدف:** Xiaomi Redmi Note 14 Pro+ 5G (`dfa9f629` / Android 16 / API 36 / HyperOS)  
**معرف حزمة التطبيق:** `com.shadyatef.hafiz_alahd`  
**الـ Commit الأساسي (Baseline):** `9b016573cac649c421f6414eeba29e720e9d30ef` (Zero production diff on `lib/` & `android/`)  
**استراتيجية المعرفات:** Option B (معرفات مخصصة لاختبارات الـ Plugin: Alarm #`999901`)  
**حالة الجهاز الثانوي (Samsung):** **مُعلّق (Strictly Held)** بانتظار المراجعة والاعتماد الكامل لأدلة جهاز شاومي.

---

## 1. ملخص نتائج السيناريوهات التنفيذية (Executive Summary)

| السيناريو | الحالة الزمنية / بيئة التشغيل | الفارق الزمني (Delta) | حالة البقاء / التسليم | حالة الصوت (Tier 3) | التنظيف الجراحي | النتيجة |
|---|---|---|---|---|---|---|
| **2D.1.1 (Foreground)** | التطبيق في الواجهة النشطة | **+132 ms** | وصل الـ Callback عبر `Alarm.ringing` | تم تفعيل التشغيل | تم التحقق من اختفاء #`999901` | **PASS** |
| **2D.1.2 (Background)** | التطبيق في الخلفية (`KEYCODE_HOME`) | **+16 ms** | انطلاق الـ FGS عبر `ActivityManager` | `AudioTrack` على الـ Speaker وفيد 0.0 ← 1.0 | تم التحقق من اختفاء #`999901` | **PASS** |
| **2D.1.3 (Process Death)** | العملية ميتة بـ `SIGKILL` غير قسري | **+21 ms** | **إحياء عملية جديدة (PID 21846)** للتسليم | `AudioTrack` على الـ Speaker وفيد 0.0 ← 1.0 | تم التحقق من اختفاء #`999901` | **PASS** |

> [!IMPORTANT]
> **التزام الفصل الصارم بين الطبقات (Tier 3 vs Tier 4):**
> تم إثبات وصول وتفعيل الصوت على مستوى محرك الصوت في نظام التشغيل (Tier 3 Native Audio Request via `AudioTrack` session 11409/11473 on `AUDIO_DEVICE_OUT_SPEAKER`). التوثيق الصوتي الفيزيائي الخارجي (Tier 4 Hardware Acoustic) مؤجل صراحة ومحفوظ لـ **Phase 2D.3**.

---

## 2. التحقق المعياري الحاسم: Scenario 2D.1.3 (Process-Death Delivery)

يمثل هذا السيناريو الاختبار الأكثر صرامة للإجابة على التحفظ الحاسم من بوابة 2D.0: **إثبات بقاء الـ `PendingIntent` المستهدف بعينه داخل `AlarmManager` أثناء موت العملية، ثم قيام نظام أندرويد بإعادة إحياء العملية وتسليم الأذان صوتياً فور حلول الموعد.**

### أ. القياسات الزمنية وصمام الأمان (Remaining Time Guard)
- **موعد الجدولة المستهدف:** `1794230581552` (`2026-11-09 15:23:01.552`)
- **وقت إنهاء العملية بـ `SIGKILL`:** `15:22:20`
- **الوقت المتبقي عند القتل:** **`41,874 ms`** (تجاوز صمام الأمان المطلوب `12,000 ms` بأكثر من 3 أضعاف)
- **صمام الأمان (Guard Passed):** **TRUE**

### ب. إثبات هوية التنبيه أثناء موت العملية (Target Identity Persistence)

تم استخراج سمات الهوية الـ 8 من `dumpsys alarm` قبل القتل وأثناء موت العملية بعد `SIGKILL`:

```json
{
  "package": "com.shadyatef.hafiz_alahd",
  "receiver_component": "com.shadyatef.hafiz_alahd/com.gdelataillade.alarm.alarm.AlarmReceiver",
  "pending_intent_identity": "PendingIntent{bbf9ba9: PendingIntentRecord{fb8f52e com.shadyatef.hafiz_alahd broadcastIntent}}",
  "intent_request_code": "NOT_SURFACED_IN_DUMPSYS",
  "orig_when_epoch_ms": 1794230581552,
  "orig_when_local_time": "2026-11-09 15:23:01.552",
  "when_elapsed_ms": 280496377,
  "alarm_type": "RTC_WAKEUP",
  "alarm_tag": "*walarm*:com.shadyatef.hafiz_alahd/com.gdelataillade.alarm.alarm.AlarmReceiver"
}
```

| السمة | الحالة قبل القتل (PID 16849) | الحالة أثناء موت العملية (PID null) | المطابقة والتطابق |
|---|---|---|---|
| **Process State** | `RUNNING (PID: 16849)` | `DEAD (PID: null)` | تم تأكيد الموت |
| **`origWhen` Epoch** | `1794230581552` | `1794230581552` | **تطابق فيزيائي تام** |
| **`whenElapsed`** | `280496377` | `280496377` | **تطابق تام** |
| **PendingIntent Record** | `PendingIntentRecord{fb8f52e}` | `PendingIntentRecord{fb8f52e}` | **نفس الكائن المسجل** |
| **Alarm Tag** | `*walarm*:.../AlarmReceiver` | `*walarm*:.../AlarmReceiver` | **تطابق تام** |
| **التصنيف النهائي للبقاء** | `TARGET_ALARM_SCHEDULED` | `TARGET_ALARM_PERSISTENCE_PROVEN` | **PASS** |

### ج. أدلة نظام التشغيل عند موعد التسليم (OS Resurrect & Native Delivery)

عند حلول الموعد المحدد في تمام `15:23:01.552`، سجل الـ Logcat ما يلي:

1. **إعادة إحياء العملية من قِبل نظام التشغيل للـ Broadcast:**
   ```text
   11-09 15:23:01.573  2539  2665 I ActivityManager: Start proc 21846:com.shadyatef.hafiz_alahd/u0a498 for broadcast {com.shadyatef.hafiz_alahd/com.gdelataillade.alarm.alarm.AlarmReceiver} caller=com.shadyatef.hafiz_alahd
   ```
2. **سماح أندرويد بإطلاق خدمة المقدمة (Foreground Service) أثناء خمول الجهاز:**
   ```text
   11-09 15:23:02.007  2539  5353 I ActivityManager: Background started FGS: Allowed [callingPackage: com.shadyatef.hafiz_alahd; callingUid: 10498; uidState: RCVR; intent: Intent { cmp=com.shadyatef.hafiz_alahd/com.gdelataillade.alarm.alarm.AlarmService (has extras) }; code:ALARM_MANAGER_WHILE_IDLE; tempAllowListReason:<... Intent { cmp=.../AlarmReceiver (has extras) }/u0,reasonCode:ALARM_MANAGER_WHILE_IDLE,duration:10000>]
   ```
3. **بدء خدمة التنبيه وتوليها المسؤولية:**
   ```text
   11-09 15:23:02.210 D/AlarmService(21846): Turning off the warning notification.
   ```
4. **تشغيل الصوت على مكبر الصوت الفيزيائي (Tier 3 Native Audio Request):**
   ```text
   11-09 15:23:02.232 D/AudioTrack( 1935): set(): (sessionId=11409), streamType 4, sampleRate 44100, packageName: com.shadyatef.hafiz_alahd
   11-09 15:23:02.247 I/AudioTrack( 1935): start(1139): prior state:STATE_STOPPED packageName: com.shadyatef.hafiz_alahd
   11-09 15:23:02.355 D/AudioTrack( 1935): onAudioDeviceUpdate AudioPortDebug[ID:00000003] deviceType:AUDIO_DEVICE_OUT_SPEAKER(00000002)
   ```
5. **تدرج مستوى الصوت التدريجي (Fade In Sequence):**
   ```text
   11-09 15:23:02.365 D/AudioTrack: AudioTrack::setVolume L:0.100000 R:0.100000 sessionid=11409
   11-09 15:23:02.466 D/AudioTrack: AudioTrack::setVolume L:0.150000 R:0.150000 sessionid=11409
   ...
   11-09 15:23:04.070 D/AudioTrack: AudioTrack::setVolume L:1.000000 R:1.000000 sessionid=11409
   ```

### د. التسلسل الزمني التفصيلي الدقيق (Granular Delivery Timeline Breakdown)

امتثالاً لتوجيهات المراجعة الهندسية، يتم هنا تفصيل كافة المحطات الزمنية وعدم اختزالها في دلتا موحدة:

| المحطة الزمنية (Milestone) | الطابع الزمني (Timestamp) | الفارق بالنسبة للموعد المستهدف | الملاحظة والوصف |
|---|---|---|---|
| **Alarm Target Timestamp** | `15:23:01.552` | `0 ms` (Baseline) | موعد الجدولة المسجل في `origWhen` |
| **Android Dispatch Timestamp** | `15:23:01.573` | **`+21 ms`** | إطلاق نظام التشغيل للـ Broadcast عبر `ActivityManager` |
| **Process Recreation Timestamp** | `15:23:01.573` | **`+21 ms`** | استنساخ العملية الجديدة `PID: 21846` من قِبل Zygote |
| **Receiver Execution Timestamp** | `15:23:02.007` | **`+455 ms`** | تنفيذ `AlarmReceiver.onReceive()` وطلب تصريح الـ FGS |
| **FGS Startup Timestamp** | `15:23:02.210` | **`+658 ms`** | بدء تنفيذ `AlarmService` في المقدمة وإيقاف إشعار التحذير |
| **Audio Playback Request Timestamp** | `15:23:02.232` | **`+680 ms`** | إنشاء جلسة `AudioTrack` رقم `11409` بنظام الصوت الأصلي |
| **Audio Routing & Hardware Speaker** | `15:23:02.355` | **`+803 ms`** | توجيه الصوت لمخرج السماعة `AUDIO_DEVICE_OUT_SPEAKER` |
| **Audio Peak Volume Timestamp** | `15:23:04.070` | **`+2518 ms`** | اكتمال تدرج مستوى الصوت وصولاً إلى `1.0` (Fade-in 2s) |

---

## 3. نتائج سيناريوهات الواجهة والخلفية (Scenarios 2D.1.1 & 2D.1.2)

### أ. سيناريو 2D.1.1 (Foreground Delivery)
- **ملف الدليل:** من خلال مخرجات اختبار الـ Integration الرسمي
- **الموعد المستهدف:** `2026-11-09T13:44:27.578140Z`
- **وقت التسليم الفعلي:** `2026-11-09T13:44:27.710244Z`
- **الفارق الزمني (Latency Delta):** **`132 ms`**
- **وصول الـ Ringstream Stream Callback:** **مؤكد** (`plugin_ringstream_fired: true`)

### ب. سيناريو 2D.1.2 (Background Delivery)
- **ملف الدليل:** [`test_evidence/scenario_2d_1_2_master_evidence_dfa9f629_20261109_155217.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/scenario_2d_1_2_master_evidence_dfa9f629_20261109_155217.json)
- **حالة العملية:** التطبيق تم نقله للخلفية عبر `KEYCODE_HOME` والعملية مستمرة برقم `PID: 7598`.
- **الموعد المستهدف:** `1794232470069` (`15:54:30.069`)
- **وقت إطلاق البث الفعلي من `ActivityManager`:** `15:54:30.085` (**فارق `16 ms` فقط!**)
- **تشغيل الـ FGS:**
  ```text
  11-09 15:54:30.085 I/ActivityManager( 2539): Background started FGS: Allowed [callingPackage: com.shadyatef.hafiz_alahd ... code:ALARM_MANAGER_WHILE_IDLE ... cmp=.../AlarmService (has extras)]
  ```
- **تشغيل الصوت والـ Fade In:** `AudioTrack` Session 11473 بدأت على `AUDIO_DEVICE_OUT_SPEAKER` وصعدت من 0.05 إلى 1.00 بسلاسة.

---

## 4. إثبات التنظيف الجراحي الصارم (Targeted Surgical Cleanup)

امتثالاً لقواعد البند **B5** وملاحظات المراجعة الهندسية، تم تفصيل عناصر التنظيف الجراحي والتأكد من عدم استخدام أي استدعاءات إبادة جماعية (`cancelAllAlarms` أو `cancelAllNotifications`):

### مصفوفة التحقق من إنهاء آثار التنبيه (Cleanup State Matrix):

| البند الرقابي | القيمة | طريقة الإثبات والأثر الفيزيائي |
|---|---|---|
| **`target_alarm_removed`** | **`true`** | تم التحقق عبر `dumpsys alarm` من حذف السجل #`999901` تماماً من جدول AlarmManager. |
| **`plugin_alarm_absent`** | **`true`** | استعلام الـ Plugin عبر `Alarm.getAlarm(999901)` عاد بقيمة `null`. |
| **`alarm_service_stopped`** | **`true`** | معالجة الـ Service لأمر `ACTION_STOP` وتدمير خدمة المقدمة FGS وتحرير الـ Wakelocks. |
| **`audio_playback_stopped`** | **`true`** | إيقاف تدفق الصوت على `AudioTrack` واستدعاء `stop()` و `release()` وإغلاق الجلسة الصوتية. |

- **سلامة التنبيهات الشقيقة (Non-Target Alarms):**
  - أظهر الفحص عبر `dumpsys alarm` أن كافة التنبيهات الأخرى غير المستهدفة ظلت تعمل دون أدنى تأثر.
  - التصنيف الرسمي بعد التنظيف: `TARGET_ALARM_ABSENT_OR_DISPATCHED`.

---

## 5. مصفوفة ملفات الأدلة (Evidence Bundle Index)

| معرف الدليل | مسار الملف | الوصف |
|---|---|---|
| **Scenario 2D.1.3 Master Bundle** | [`test_evidence/scenario_2d_1_3_master_evidence_dfa9f629_20261109_152106.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/scenario_2d_1_3_master_evidence_dfa9f629_20261109_152106.json) | حزمة أدلة موت العملية وبقاء التنبيه وإحيائه |
| **Scenario 2D.1.2 Master Bundle** | [`test_evidence/scenario_2d_1_2_master_evidence_dfa9f629_20261109_155217.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/scenario_2d_1_2_master_evidence_dfa9f629_20261109_155217.json) | حزمة أدلة تسليم الخلفية واستجابة الصوت |
| **Pre-Kill Identity Evidence** | [`test_evidence/target_alarm_identity_dfa9f629_20261109_152219.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/target_alarm_identity_dfa9f629_20261109_152219.json) | سمات هوية التنبيه الـ 8 أثناء عمل التطبيق |
| **Post-Kill Identity Evidence** | [`test_evidence/target_alarm_identity_dfa9f629_20261109_152222.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/target_alarm_identity_dfa9f629_20261109_152222.json) | إثبات بقاء نفس سمات الهوية والـ PendingIntent أثناء موت التطبيق |
| **Lifecycle Delivery Evidence** | [`test_evidence/lifecycle_evidence_dfa9f629_20261109_152222.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/lifecycle_evidence_dfa9f629_20261109_152222.json) | لقطات Logcat الرسمية لبدء `AlarmService` وتشغيل `AudioTrack` |
| **Post-Cleanup Verification** | [`test_evidence/target_alarm_identity_dfa9f629_20261109_152424.json`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/target_alarm_identity_dfa9f629_20261109_152424.json) | إثبات اختفاء التنبيه المستهدف جراحياً |
| **Raw Dumpsys Alarm (Pre-Kill)** | [`test_evidence/raw_dumpsys_alarm_dfa9f629_20261109_152219.txt`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/raw_dumpsys_alarm_dfa9f629_20261109_152219.txt) | السجل الخام المباشر لـ AlarmManager |
| **Raw Dumpsys Alarm (Post-Kill)** | [`test_evidence/raw_dumpsys_alarm_dfa9f629_20261109_152222.txt`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/raw_dumpsys_alarm_dfa9f629_20261109_152222.txt) | السجل الخام المباشر أثناء موت العملية |
| **Raw Dumpsys Alarm (Cleanup)** | [`test_evidence/raw_dumpsys_alarm_dfa9f629_20261109_152424.txt`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/raw_dumpsys_alarm_dfa9f629_20261109_152424.txt) | السجل الخام المباشر بعد التنظيف |
| **Raw Logcat Lifecycle Stream** | [`test_evidence/raw_logcat_lifecycle_dfa9f629_20261109_152222.txt`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test_evidence/raw_logcat_lifecycle_dfa9f629_20261109_152222.txt) | السجل الخام لتسلسل إطلاق الصوت والخدمة |

---

## 6. سلامة كود الإنتاج (Production Code Integrity)

- تم فحص شجرة الكود بالكامل عبر `git diff lib/ android/`.
- النتيجة: **Strictly 0 Diff Lines** (لا يوجد سطر واحد معدل في كود الإنتاج أو تكوينات الأندرويد).
- التغييرات اقتصرت حصراً على إضافة تبعية `integration_test` ومستندات وسكربتات الاختبار المستقلة.

---

## 7. القرار والتوصية للانتقال

1. اكتملت كافة متطلبات التحقق الفيزيائي على الجهاز الأساسي **Xiaomi Redmi Note 14 Pro+ 5G** بنجاح تام وفق الشروط الصارمة (B1 - B5).
2. الجهاز الثانوي **Samsung Galaxy Tab A7 LTE (`SM_T505N` / Android 12)** جاهز للبدء فور صدور موافقتكم واعتماد أدلة شاومي للانتقال إلى **Scenario 2D.1.4 (Dual-Device Verification & Comparison)**.

