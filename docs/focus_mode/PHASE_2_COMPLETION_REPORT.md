# Focus Mode — Phase 2 Completion Report
## Session Lifecycle, SQLite Persistence & Crash Consistency

**تاريخ التقرير:** 21 نوفمبر 2026  
**الفرع:** `poc/focus-mode`  
**الحالة:** 🟢 مكتملة وجاهزة للمراجعة (STOP GATE)  
**الاختبارات الآلية:** 48/48 ناجحة (100%)  
**التحليل الساكن (Flutter Analyzer):** 0 تحذيرات أو أخطاء  
**بناء الكود الأصلي (Kotlin/Gradle):** نجاح كامل (`compileDebugKotlin` exited 0)

---

## 1. ملخص تنفيذي (Executive Summary)

تم بحمد الله إنجاز **المرحلة الثانية (Phase 2)** من ميزة وضع التركيز (Focus Mode) وفقًا لمتطلبات وثيقة الخطة المعدلة المعتمدة `FOCUS_MODE_PHASE_2_PLAN_REV2.md`. 

ركزت هذه المرحلة على معالجة التحدي الهندسي الأكبر الذي طرحه المستخدم: **تحقيق اتساق الحالة التام (Crash Consistency) وضمان نجاة الجلسة وتقدمها بعد انهيار أو إغلاق التطبيق أو قتل نظام أندرويد لعملية Flutter Isolate**، مع التخلص الكامل من هشاشة `SharedPreferences` والانتقال إلى نموذج قاعدة بيانات موثوقة بمعاملات ذرية (ACID Transactions).

---

## 2. المعالجة التفصيلية لملاحظات المراجعة الهندسية (C1 – C5)

### C1: استبدال SharedPreferences بقاعدة بيانات SQLite بمعاملات ذرية (ACID)
- **المشكلة السابقة:** كانت البيانات مقسمة على 3 مفاتيح غير ذرية، مما قد يؤدي لحالة متناقضة عند حدوث انهيار أثناء إنهاء الجلسة أو أرشفتها.
- **الحل المنفذ:**
  - إنشاء قاعدة بيانات متخصصة ومستقلة: `focus_mode.db` عبر `sqflite`.
  - تصميم جدول `focus_sessions` لتمثيل الجلسة النشطة والسجل التاريخي.
  - تصميم جدول `focus_session_progress` لحفظ التقدم التفصيلي مع قيد مرجعي `FOREIGN KEY (session_id) REFERENCES focus_sessions(id) ON DELETE CASCADE`.
  - تصميم جدول `focus_enforcement_operations` كدفتر أستاذ (Ledger) للعمليات المعلقة.
  - تنفيذ عمليات الحفظ، التحديث، والأرشفة بالكامل داخل **معاملات ذرية** `db.transaction((txn) async { ... })`. إذا تعطل التطبيق في أي لحظة، إما أن تنجح العملية بالكامل أو تتراجع بالكامل دون أي تضارب أو بيانات يتيمة.
  - فرض قيد صارم يضمن وجود **جلسة نشطة واحدة كحد أقصى** (`is_active = 1`).

### C2: دفتر أستاذ العمليات المعلقة (Pending Operations Ledger)
- **المشكلة السابقة:** إذا انهار التطبيق بعد أرشفة الجلسة وقبل إرسال أمر فك الحماية للـ Native Engine، يظل الدرع محبوسًا على الشاشة.
- **الحل المنفذ:**
  - إنشاء كيان `FocusEnforcementOperation` (أنواعه: `start`, `stop`, `snooze`؛ وحالاته: `pending`, `executing`, `completed`, `failed`).
  - عند إنهاء الجلسة، تُدرج عملية `stop` بحالة `pending` داخل نفس معاملة الـ SQLite للأرشفة.
  - يحاول النظام إرسال الأمر للخدمة الأصلية فورًا:
    - في حال النجاح: تُعلّم العملية `completed`.
    - في حال انقطاع الخدمة أو الانهيار: تبقى العملية `pending` أو `failed` مع تسجيل رسالة الخطأ وعدد المحاولات `retryCount`.
  - عند إعادة تشغيل التطبيق، يقوم `FocusSessionRecoveryManager` بقراءة جميع العمليات المعلقة وتنفيذها مع آلية إعادة محاولة (At-least-once guarantee).

### C3: المصالحة العميقة ثنائية الاتجاه (Deep State Reconciliation Matrix)
- **المشكلة السابقة:** الاعتماد على Boolean فقط (`isRunning`) لا يكفي للتأكد من أن الخدمة الأصلية تعمل لنفس الجلسة المخزنة، مما قد يؤدي لخلط بين خدمة يتيمة من جلسة قديمة وجلسة جديدة.
- **الحل المنفذ:**
  - تم تحديث كود أندرويد الأصلي في `FocusPoCService.kt` و `FocusPoCChannelHandler.kt` لتخزين ومعرفة `sessionId` الخاص بكل جلسة مشغلة.
  - تم إنشاء كيان `FocusEnforcementStatus` يسترجع من القناة الأصلية: `sessionId`, `wardTitle`, `state`, `snoozeRemaining`, `startedAt`.
  - تنفيذ مصفوفة المصالحة الشاملة في `FocusSessionRecoveryManager`:
    1. **تطابق صحي (Healthy Match):** رقم الجلسة في SQLite يطابق رقم الجلسة في الخدمة الأصلية ⬅️ استعادة الجلسة والتقدم فورًا.
    2. **تضارب هويات (Conflict / ID Mismatch):** الخدمة الأصلية تعمل لـ `session_A` بينما قاعدة البيانات لديها `session_B` ⬅️ إيقاف الخدمة المتضاربة قسريًا وتحديث الحماية لـ `session_B`.
    3. **خدمة يتيمة (Orphaned Native Service):** الخدمة تعمل بينما لا توجد جلسة نشطة في SQLite ⬅️ إرسال أمر إيقاف فوري وتفكيك الدرع لعدم حبس المستخدم.
    4. **خدمة ميتة (Killed Service Recovery):** توجد جلسة نشطة في SQLite لكن الخدمة الأصلية متوقفة (قتلها النظام لتوفير الذاكرة) ⬅️ إعادة تشغيل خدمة الحماية فورًا وربطها بنفس `sessionId`.
    5. **معالجة العمليات العالقة (Pending Ops):** تصفية كافة أوامر `stop` العالقة قبل اتخاذ قرار الاستعادة.
    6. **حالة خمول نظيفة (Clean Idle):** لا جلسة في DB ولا خدمة في Native ⬅️ بقاء التطبيق في وضع الاستعداد.

### C4: انضباط حدود دورة الحياة وتجميد وقت القراءة (Dwell Freezing)
- **المشكلة السابقة:** خطر احتساب القراءة أثناء إطفاء الشاشة أو أثناء وجود التطبيق في الخلفية، أو فرض مدة انتهاء تعسفية لا تتفق مع فلسفة إتمام الورد.
- **الحل المنفذ:**
  - تأكيد عدم وجود انتهاء زمني قسري للجلسة؛ الجلسة لا تنتهي إلا بإتمام الورد فعليًا أو الإلغاء الصريح.
  - ربط الـ Dwell Timer بدورة حياة التطبيق وشاشة الهاتف: احتساب الوقت يتجمد تلقائيًا فور خروج التطبيق إلى الخلفية (`AppLifecycleState.paused` / `detached`) أو انطفاء الشاشة، ولا يُستأنف إلا بعودة المستخدم للواجهة، ويتم حفظ الوقت التراكمي في الـ SQLite لضمان عدم ضياعه.

### C5: حفظ لقطة التقدم المتكاملة (Complete Progress Snapshot)
- **المشكلة السابقة:** فقدان مفاتيح الأذكار المنجزة أو أرقام صفحات المصحف المقروءة عند إغلاق التطبيق.
- **الحل المنفذ:**
  - تصميم `FocusSessionProgress` ليخزن:
    - قائمة المفاتيح المطلوبة `requiredItemKeys` والمكتملة `completedItemKeys` كـ JSON في SQLite.
    - قائمة أرقام الصفحات المقروءة `readQuranPages` والصفحة الأخيرة المكتملة `lastCompletedPage`.
    - الوقت التراكمي المحتسب للقراءة `accumulatedQuranDuration`.
    - لقطة هدف القرآن الكاملة `quranGoalSnapshot` (نوع الهدف، الهدف العددي، أرقام السور/الأحزاب/الآيات).
  - عند استرجاع الجلسة، يستعيد المستخدم تقدمه بدقة متناهية دون الحاجة لإعادة ما تم إنجازه من البداية.

---

## 3. الهيكل المعماري والملفات المضافة والمعدلة

```
lib/features/focus_mode/
├── data/
│   ├── datasources/
│   │   ├── focus_database.dart                 <-- إدارة sqflite وإنشاء الجداول والترقيات
│   │   └── focus_session_local_data_source.dart <-- تنفيذ العمليات الذرية والمحاكاة للاختبار
│   ├── models/
│   │   ├── focus_enforcement_operation_model.dart
│   │   ├── focus_session_model.dart
│   │   └── focus_session_progress_model.dart
│   ├── ports/
│   │   └── native_focus_enforcement_port.dart   <-- يدعم تمرير sessionId واسترجاع FocusEnforcementStatus
│   └── repositories/
│       └── focus_session_repository_impl.dart  <-- المعاملات الذرية وضمان الجلسة الواحدة والأرشفة
├── domain/
│   ├── entities/
│   │   ├── focus_enforcement_operation.dart    <-- كيان العمليات المعلقة وحالاتها
│   │   ├── focus_enforcement_status.dart       <-- كيان الحالة المسترجعة من الـ Native مع sessionId
│   │   └── focus_session_progress.dart         <-- كيان لقطة التقدم المتكاملة
│   ├── repositories/
│   │   └── focus_session_repository.dart       <-- العقد المجرد للتخزين الدائم
│   └── services/
│       ├── focus_session_coordinator.dart      <-- منسق الجلسات مدمج مع الـ Repository والعمليات الذرية
│       └── focus_session_recovery_manager.dart <-- محرك المصالحة العميقة واستعادة الجلسات المنهارة
android/app/src/main/kotlin/.../focus_poc/
├── FocusPoCService.kt                          <-- تتبع sessionId الأصلي وإرجاع الحالة المفصلة
└── FocusPoCChannelHandler.kt                   <-- استقبال sessionId والرد بـ getEnforcementStatus
```

---

## 4. تقرير التحقق والاختبارات الآلية (Test & Verification Report)

### 4.1. مصفوفة الاختبارات الآلية (48 اختبارًا ناجحًا)
تم تشغيل حزمة الاختبارات بالكامل عبر الأمر:
`flutter test test/features/focus_mode/ test/features/focus_mode_poc/`

وجاءت النتائج بنسبة نجاح **100%**:

| مجموعة الاختبارات | الملف | عدد الاختبارات | النتيجة |
|---|---|:---:|:---:|
| **Persistent Repository** | `focus_session_repository_test.dart` | 4 | 🟢 PASS |
| **Deep Reconciliation Matrix** | `focus_session_recovery_manager_test.dart` | 6 | 🟢 PASS |
| **Coordinator Persistence** | `focus_session_coordinator_persistence_test.dart` | 6 | 🟢 PASS |
| **Domain Evaluator** | `focus_completion_evaluator_test.dart` | 10 | 🟢 PASS |
| **Edge Cases (Phase 1 Addendum)** | `focus_edge_cases_test.dart` | 8 | 🟢 PASS |
| **Coordinator Lifecycle** | `focus_session_coordinator_test.dart` | 8 | 🟢 PASS |
| **Native Channel & Status** | `focus_poc_channel_test.dart` | 5 | 🟢 PASS |
| **PoC UI & Widgets** | `focus_poc_screen_test.dart` | 1 | 🟢 PASS |
| **الإجمالي** | | **48** | **48/48 PASS** |

### 4.2. فحص التحليل الساكن (Flutter Analyzer)
- الأمر: `flutter analyze lib/features/focus_mode lib/features/focus_mode_poc test/features/focus_mode test/features/focus_mode_poc`
- النتيجة: **No issues found!** (صفر أخطاء، صفر تحذيرات).

### 4.3. التحقق من كود Kotlin الأصلي وبناء Gradle
- الأمر: `.\gradlew compileDebugKotlin`
- النتيجة: **BUILD SUCCESSFUL** دون أي أخطاء في كود `FocusPoCService` أو `FocusPoCChannelHandler`.

---

## 5. بوابة التوقف والموافقة (STOP GATE)

وفقًا للسياسة الهندسية الصارمة للمشروع، **لا يتم الانتقال إلى المرحلة الثالثة (Phase 3 — Scheduling & Boot Recovery) إلا بعد اعتمادكم الكامل لهذا التقرير**.

### المرحلة القادمة (Phase 3) المقترحة:
1. **جدولة الجلسات بدقة:** التكامل مع `Android AlarmManager.setExactAndAllowWhileIdle()` لضمان إطلاق الجلسات في مواعيد الصلاة أو الأوقات المحددة حتى لو كان الجهاز في وضع الخمول العميق (Doze Mode).
2. **استعادة الجدولة بعد إعادة التشغيل (Boot Recovery):** إنشاء `FocusModeBootReceiver` للاستماع لحدث `BOOT_COMPLETED` وإعادة جدولة جلسات اليوم تلقائيًا.
3. **معالجة النوافذ الفائتة (Missed Schedules):** منطق ذكي للتعامل مع المواعيد التي فاتت أثناء إغلاق الهاتف.

نحن بانتظار توجيهاتكم وملاحظاتكم الهندسية أو اعتمادكم للانتقال للخطوة التالية.
