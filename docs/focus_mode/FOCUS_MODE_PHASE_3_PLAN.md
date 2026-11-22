# Focus Mode — Phase 3 Plan: Scheduling & Boot Recovery
## خطة المرحلة الثالثة: الجدولة المسبقة الدقيقة والاستعادة بعد إعادة تشغيل الجهاز

**تاريخ الوثيقة:** 22 نوفمبر 2026  
**الفرع:** `poc/focus-mode`  
**الحالة:** مقترحة للمراجعة والاعتماد (STOP GATE)

---

## 1. أهداف المرحلة الثالثة (Executive Summary & Objectives)

بعد أن أثبتت المرحلتان الأولى والثانية بنجاح:
1. فصل منطق إتمام الورد وحساب القراءة الحقيقية عن طبقة العرض (Phase 1).
2. استمرارية الجلسة عبر SQLite وضمان اتساق الحالة التام (Crash Consistency) والمصالحة العميقة (Phase 2).

تنتقل **المرحلة الثالثة (Phase 3)** إلى تحويل وضع التركيز من **جلسة يدوية التشغيل فقط** إلى **نظام منضبط ذاتيًا (Automated & Scheduled Enforcement)** قادر على:
- إطلاق جلسات التركيز تلقائيًا في مواعيد الأوراد المحددة مسبقًا (مثل: أذكار الصباح، أذكار المساء، ورد القرآن اليومي).
- العمل بدقة متناهية حتى لو كان الهاتف في وضع الخمول العميق (Android Doze Mode).
- الاستعادة التلقائية لجميع المواعيد المجدولة بعد إعادة تشغيل الهاتف (`BOOT_COMPLETED`) أو تغيير التوقيت والمنطقة الزمنية دون الحاجة لفتح التطبيق.
- معالجة المواعيد الفائتة بذكاء (Missed Schedules Policy) إذا كان الهاتف مغلقًا وقت استحقاق الجلسة.
- كفاءة استهلاك الموارد: صفر استهلاك للبطارية أثناء فترة الانتظار (لا يعمل أي Service أو Isolate في الخلفية حتى يحين موعد المنبه بدقة).

---

## 2. التحليل المعماري وتوزيع المسؤوليات (Architecture & Design)

```
┌────────────────────────────────────────────────────────┐
│                      Domain Layer                      │
│                                                        │
│  [FocusSchedule] ───► [FocusScheduleCalculator]       │
│         │                      │                       │
│         ▼                      ▼                       │
│  [FocusScheduleRepo]   [MissedSchedulePolicy]          │
│         │                      │                       │
│         └──────────┬───────────┘                       │
│                    ▼                                   │
│           [FocusSchedulingPort]  (Abstract Contract)   │
└────────────────────┬───────────────────────────────────┘
                     │ (MethodChannel & Data Persistence)
┌────────────────────▼───────────────────────────────────┐
│              Platform / Infrastructure                 │
│                                                        │
│  [FocusSchedulingLocalDataSource] (SQLite: focus_mode) │
│  [NativeFocusSchedulingPort]                           │
│                    │                                   │
│  ══════════════════╪═════════════════════════════════  │
│                    ▼ (Android Native Kotlin)           │
│  [AlarmManager.setExactAndAllowWhileIdle]              │
│         │                                              │
│         ├──► [FocusAlarmReceiver] ──► (Triggers Guard) │
│         │                                              │
│         └──► [FocusBootReceiver]  ──► (Reschedules)    │
│               - ACTION_BOOT_COMPLETED                  │
│               - ACTION_MY_PACKAGE_REPLACED             │
│               - ACTION_TIME_CHANGED / TIMEZONE_CHANGED │
└────────────────────────────────────────────────────────┘
```

---

## 3. تفاصيل المكونات (Core Components)

### 3.1. الكيانات والعقود في طبقة النطاق (Domain Entities & Ports)

1. **`FocusSchedule` Entity:**
   - `id`: المعرف الفريد للجدول (UUID/String).
   - `wardType`: نوع الورد (`FocusWardType`: صباح، مساء، نوم، قرآن، مخصص).
   - `title`: اسم الموعد المعروض للمستخدم.
   - `targetTime`: وقت التفعيل اليومي (الساعة والدقيقة `TimeOfDay`).
   - `daysOfWeek`: أيام التكرار في الأسبوع (1 = الاثنين، 7 = الأحد، أو يوميًا).
   - `isEnabled`: تفعيل أو تعطيل الجدولة.
   - `targetQuranGoal`: هدف القرآن في حال كان الورد قرآنيًا.
   - `preNotificationMinutes`: تنبيه استباقي اختياري (مثل: تنبيه قبل بدء الحماية بـ 5 دقائق).
   - `createdAt`, `updatedAt`.

2. **`FocusScheduleCalculator` (Domain Service):**
   - حساب لحظة التفعيل القادمة الدقيقة (`DateTime calculateNextTrigger(FocusSchedule schedule, DateTime now)`).
   - معالجة تجاوز منتصف الليل، أيام الأسبوع المحددة، واختلافات التوقيت الصيفي/الشتوي.

3. **`MissedSchedulePolicy` (Domain Service):**
   - تحديد الإجراء المناسب إذا فتح التطبيق أو أعيد تشغيل الجهاز بعد موعد التفعيل المحدد:
     - **نافذة السماح (Grace Period - مثلاً 30 دقيقة):** إذا كان التأخير أقل من 30 دقيقة ولم تُنجز الجلسة اليوم، يتم اقتراح إطلاق الجلسة فورًا أو تفعيلها.
     - **تجاوز النافذة (> 30 دقيقة):** تفويت الموعد لليوم الحالي والانتقال تلقائيًا إلى موعد اليوم التالي لمنع إرباك المستخدم في أوقات غير مناسبة.

4. **`FocusSchedulingPort` (Abstract Port):**
   ```dart
   abstract class FocusSchedulingPort {
     Future<bool> scheduleAlarm({
       required String scheduleId,
       required DateTime triggerAt,
       required String wardTitle,
       required FocusWardType wardType,
     });
     Future<bool> cancelAlarm(String scheduleId);
     Future<bool> canScheduleExactAlarms();
     Future<void> requestExactAlarmPermission();
   }
   ```

---

### 3.2. استمرارية البيانات (SQLite Schema for Schedules)

إضافة جدول `focus_schedules` إلى قاعدة البيانات الحالية `focus_mode.db`:

```sql
CREATE TABLE focus_schedules (
    id TEXT PRIMARY KEY,
    ward_type TEXT NOT NULL,
    title TEXT NOT NULL,
    hour INTEGER NOT NULL,
    minute INTEGER NOT NULL,
    days_of_week TEXT NOT NULL, -- JSON array: e.g. "[1,2,3,4,5,6,7]"
    is_enabled INTEGER NOT NULL DEFAULT 1,
    pre_notification_minutes INTEGER NOT NULL DEFAULT 0,
    quran_goal_json TEXT,
    last_triggered_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX idx_focus_schedules_enabled ON focus_schedules(is_enabled);
```

---

### 3.3. المحرك الأصلي على أندرويد (Android Native Architecture)

#### أ. الجدولة الدقيقة (Exact Alarm Management):
- استخدام `AlarmManager.setExactAndAllowWhileIdle()` مع `PendingIntent` مخصص لكل `scheduleId` (`requestCode = scheduleId.hashCode`).
- فحص ترخيص `AlarmManager.canScheduleExactAlarms()` للأجهزة التي تعمل بنظام Android 12 (API 31) فما فوق:
  - إذا كان مسموحًا: الجدولة المباشرة عبر المنبه الدقيق.
  - إذا تم رفضه أو سحبه من المستخدم: تقديم طلب التوجيه إلى `Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM`.

#### ب. مستقبل التنبيه وتشغيل الحماية (`FocusAlarmReceiver`):
- استقبال حدث المنبه الدقيق.
- حيازة `WakeLock` مؤقت محدود بمدة قصوى (مثلاً 10 ثوانٍ) لمنع نوم المعالج أثناء بدء الخدمة.
- إطلاق خدمة الحماية `FocusPoCService` فورًا مع تمرير `sessionId` جديد و `wardTitle`.
- إرسال إشعار كامل الأهمية (High Priority Notification) ينبه المستخدم ببدء ورد التركيز.

#### ج. مستقبل استعادة التشغيل (`FocusBootReceiver`):
- التسجيل في `AndroidManifest.xml` للاستماع إلى:
  - `android.intent.action.BOOT_COMPLETED`
  - `android.intent.action.MY_PACKAGE_REPLACED`
  - `android.intent.action.TIME_SET`
  - `android.intent.action.TIMEZONE_CHANGED`
- عند إعادة تشغيل الهاتف، يقوم الـ Receiver بقراءة الجداول المفعلة من التخزين وإعادة برمجتها في `AlarmManager` دون الحاجة لفتح واجهة التطبيق إطلاقًا.

---

## 4. مصفوفة الاختبارات المقترحة للمرحلة الثالثة (Testing Matrix)

| نوع الاختبار | الملف المستهدف | نطاق التغطية |
|---|---|---|
| **Domain Logic** | `focus_schedule_calculator_test.dart` | حساب الموعد القادم، تجاوز منتصف الليل، أيام الأسبوع، التكرار اليومي. |
| **Domain Logic** | `missed_schedule_policy_test.dart` | التحقق من سلوك نافذة السماح (ضمن 30 دقيقة) وتفويت الموعد عند تجاوزه. |
| **Data / Storage** | `focus_schedule_repository_test.dart` | العمليات الذرية على جداول `focus_schedules`، الحفظ، التعديل، والحذف. |
| **Domain Coordinator** | `focus_schedule_coordinator_test.dart` | التنسيق بين إنشاء الجداول، استدعاء الـ Port، وتحديث SQLite. |
| **Platform Channel** | `native_focus_scheduling_port_test.dart` | التحقق من صحة الرسائل المتبادلة وتمرير المعاملات للـ Native Channel. |
| **Android Native Verification** | `compileDebugKotlin` | بناء كود Kotlin والتأكد من خلوه من أي أخطاء تجميعية. |

---

## 5. خطة التنفيذ خطوة بخطوة (Implementation Steps)

1. **الخطوة 3.1 — Domain Contracts & Calculator:**
   - كتابة الكيانات: `FocusSchedule` و `FocusScheduleType`.
   - كتابة خدمات النطاق: `FocusScheduleCalculator` و `MissedSchedulePolicy`.
   - كتابة العقد المجرد: `FocusSchedulingPort`.
   - كتابة اختبارات النطاق الآلية (Unit Tests).

2. **الخطوة 3.2 — SQLite Persistence for Schedules:**
   - ترقية قاعدة بيانات `FocusDatabase` لإضافة جدول `focus_schedules`.
   - إنشاء `FocusScheduleModel` و `FocusScheduleRepositoryImpl`.
   - كتابة اختبارات التخزين الذري.

3. **الخطوة 3.3 — Android Native Exact Alarm & Boot Handlers:**
   - إنشاء `FocusAlarmReceiver.kt` للتعامل مع رنين المنبه وحيازة الـ WakeLock وتفعيل الخدمة.
   - إنشاء `FocusBootReceiver.kt` للتعامل مع `BOOT_COMPLETED` وتغيير التوقيت.
   - تحديث `FocusPoCChannelHandler.kt` لتوفير دوال الجدولة، الإلغاء، وفحص صلاحيات المنبه الدقيق.
   - تسجيل المكونات في `AndroidManifest.xml`.

4. **الخطوة 3.4 — Platform Integration & Verification:**
   - إنشاء `NativeFocusSchedulingPort` وربطه بالـ Service Locator.
   - تشغيل حزمة الاختبارات الشاملة (Flutter Tests + Analyzer + Kotlin Compilation).
   - إعداد تقرير اكتمال المرحلة الثالثة `PHASE_3_COMPLETION_REPORT.md` ورفعه للمراجعة والاعتماد.

---

## 6. بوابة التوقف (STOP GATE)

كما هو متبع، **لن يتم الانتقال إلى المرحلة الرابعة (Phase 4 — App Selection & Exemptions) إلا بعد اكتمال تنفيذ المرحلة الثالثة بالكامل واعتماد تقريرها واختباراتها الآلية.**
