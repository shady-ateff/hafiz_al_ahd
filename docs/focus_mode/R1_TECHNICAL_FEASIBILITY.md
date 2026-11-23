# R1 — Technical Feasibility Study
**Document ID:** `FOCUS_MODE_R1`
**Type:** Technical Feasibility — STOP GATE
**Platform:** Android Only
**Status:** COMPLETE — AWAITING USER REVIEW
**Review Date:** 2026-11-21

---

## 1. ملخص تنفيذي

بناءً على البحث التقني الشامل في الوثائق R2–R9، تُصدر هذه الوثيقة الحكم النهائي على جدوى ميزة **Focus Mode** في تطبيق Hafiz Al-Ahd.

**التوصية النهائية:**

> ### ✅ Option B — PARTIALLY FEASIBLE
>
> الميزة **قابلة للتنفيذ** مع قيود واضحة يجب توثيقها وتوصيلها للمستخدم قبل الشروع في التطوير.

---

## 2. الإجابة على الأسئلة الـ 12

### Q1 — هل يمكن اكتشاف انتقال المستخدم لتطبيق آخر؟

**الإجابة:** `VERIFIED — مع قيود`

نعم، عبر `UsageStatsManager` باستخدام الـ polling كل 3-5 ثوانٍ.

**القيود:**
- يتطلب إذن `PACKAGE_USAGE_STATS` الذي لا يُمنح تلقائياً
- الكمون 3-10 ثوانٍ وليس فورياً
- يعمل فقط داخل Foreground Service
- OEMs قد يُقيّدون الـ polling على بعض الأجهزة

**الحل:** Foreground Service (specialUse) مع WakeLock + إذن Usage Stats + توثيق كمون ≤ 5 ثوانٍ

---

### Q2 — هل يمكن عرض Focus Shield فوق التطبيقات؟

**الإجابة:** `VERIFIED — مع قيود`

نعم، عبر `SYSTEM_ALERT_WINDOW` و `TYPE_APPLICATION_OVERLAY`.

**القيود:**
- المستخدم يمكنه الضغط Back للتجاوز
- لا يعمل فوق بعض system apps
- يتطلب موافقة المستخدم (Settings > Special App Access)

**ملاحظة:** `SYSTEM_ALERT_WINDOW` **مُعلن بالفعل** في AndroidManifest.xml.

---

### Q3 — هل يمكن منع استخدام التطبيقات المحظورة؟

**الإجابة:** `PARTIALLY VERIFIED`

**ما يمكن:** عرض Overlay (تذكير قوي) فوق التطبيق المحظور.

**ما لا يمكن:** منع حقيقي وكامل. المستخدم يمكنه دائماً تجاوز الـ Overlay.

**غير الممكن:**
- `DevicePolicyManager.setPackagesSuspended()` ← يتطلب Device Owner
- `AccessibilityService` ← محظور بـ Google Play Policy

**التوصية:** تصميم الميزة كـ "gentle reminder" وليس "hard block" — وهذا مقبول وفق الهدف الأصلي للميزة.

---

### Q4 — هل يمكن جدولة جلسات تلقائية؟

**الإجابة:** `VERIFIED`

نعم، عبر `AlarmManager.setExactAndAllowWhileIdle()`.

**الملاحظات:**
- `SCHEDULE_EXACT_ALARM` و `USE_EXACT_ALARM` **مُعلَّنان بالفعل**
- `android_alarm_manager_plus` **مُثبَّت بالفعل**
- يلزم إعادة الجدولة عند BOOT_COMPLETED
- يلزم التعامل مع تغييرات المنطقة الزمنية

---

### Q5 — هل يمكن تفعيل الجلسة تلقائياً عند بدء الورد؟ (Activity-Based)

**الإجابة:** `PARTIALLY VERIFIED`

**ما يمكن:** بدء جلسة عند فتح المستخدم لشاشة الأذكار.

**التحدي:** التطبيق يحتاج أن يكون في المقدمة لبدء Foreground Service على Android 12+. بمجرد الانتقال للخلفية، الـ Service يمكن أن يستمر، لكن البدء من الخلفية محظور.

**الحل:** بدء الخدمة أثناء وجود التطبيق مفتوحاً، ثم تعمل في الخلفية بعد ذلك.

---

### Q6 — هل يمكن الكشف عن اكتمال الورد؟

**الإجابة:** `PARTIALLY VERIFIED — يتطلب Contract جديد`

**الحالة الحالية:** منطق الاكتمال موجود في `AzkarTrackerCubit` (Presentation layer فقط).

**المطلوب:** إنشاء `AzkarCompletionPort` في طبقة Domain لنشر أحداث الاكتمال بشكل مستقل عن دورة حياة الواجهة.

**التحدي المعماري:** يجب حل مشكلة ربط Presentation Cubit بـ Domain Contract دون كسر Clean Architecture.

---

### Q7 — هل يمكن الاستمرار بعد إعادة تشغيل الجهاز؟

**الإجابة:** `VERIFIED`

نعم، عبر `BOOT_COMPLETED` receiver.

**الملاحظات:**
- `RECEIVE_BOOT_COMPLETED` **مُعلن بالفعل**
- `ScheduledNotificationBootReceiver` موجود بالفعل (لـ FLN)
- يلزم إنشاء `FocusModeBootReceiver` منفصل

---

### Q8 — هل الميزة متوافقة مع سياسة Google Play؟

**الإجابة:** `VERIFIED — مع شروط`

| المكوّن | الحكم |
|---|---|
| `UsageStatsManager` | ✅ مسموح مع إفصاح في Privacy Policy |
| `SYSTEM_ALERT_WINDOW` | ✅ مسموح — مُستخدم بالفعل |
| `Foreground Service (specialUse)` | ✅ مسموح مع تبرير في manifest |
| `AccessibilityService` | ❌ محظور — غير مستخدم |
| `DevicePolicyManager` | ❌ محظور — غير مستخدم |

**الشروط المطلوبة:**
1. تحديث Privacy Policy بإضافة بند بيانات استخدام التطبيقات
2. تحديث Data Safety في Play Console
3. إضافة `property` تبرير `specialUse` في manifest

---

### Q9 — هل استهلاك البطارية مقبول؟

**الإجابة:** `PARTIALLY VERIFIED — يتطلب قياساً فعلياً`

**التقدير النظري:**
- Polling كل 5 ثوانٍ: استهلاك منخفض إلى متوسط
- Foreground Service بدون عمليات ثقيلة: < 1% / ساعة

**التحقق الكامل:** يتطلب قياساً على أجهزة حقيقية في الـ PoC (انظر R9).

---

### Q10 — هل الميزة تعمل بشكل موثوق على أجهزة OEM مختلفة؟

**الإجابة:** `UNVERIFIED — يتطلب اختباراً فعلياً`

**التوقعات:**
- Google Pixel: موثوق
- Samsung One UI: محتمل مع تحفظات على Battery optimization
- Xiaomi MIUI: خطر على استمرارية الـ Service — UNVERIFIED

**الحل المقترح:** اختبار فعلي في الـ PoC + توثيق القيود لكل OEM.

---

### Q11 — هل يمكن الاستثناء التلقائي للتطبيقات الضرورية (Phone, Settings)?

**الإجابة:** `VERIFIED`

نعم، قائمة التطبيقات المستثناة ثابتة (Hard-coded) في الـ Service تتضمن:
- التطبيق نفسه (Hafiz Al-Ahd)
- Phone app
- Settings
- Emergency apps

---

### Q12 — هل يمكن بناء الميزة دون تعديل features الحالية؟

**الإجابة:** `PARTIALLY VERIFIED`

**ما لا يحتاج تعديل (90%):** كل features الحالية (أوقات الصلاة، الأذكار، المصحف، الصوت) لا تُعدَّل.

**ما يحتاج إضافة Contract (10%):**
- `AzkarCompletionPort` — مطلوب في Domain layer
- هذا لا يُعدِّل السلوك الحالي، يُضيف فقط Stream جديد

**التحقق:** ممكن مع تصميم معماري دقيق.

---

## 3. ملخص التقييمات

| السؤال | التصنيف |
|---|---|
| Q1 — اكتشاف انتقال المستخدم | VERIFIED — مع قيود |
| Q2 — عرض Focus Shield | VERIFIED — مع قيود |
| Q3 — منع استخدام التطبيقات | PARTIALLY VERIFIED |
| Q4 — جدولة الجلسات | VERIFIED |
| Q5 — Activity-Based Focus | PARTIALLY VERIFIED |
| Q6 — اكتشاف اكتمال الورد | PARTIALLY VERIFIED — يتطلب Contract |
| Q7 — الاستمرار بعد الإقلاع | VERIFIED |
| Q8 — توافق Google Play | VERIFIED — مع شروط |
| Q9 — استهلاك البطارية | PARTIALLY VERIFIED |
| Q10 — موثوقية على OEMs | UNVERIFIED |
| Q11 — استثناء التطبيقات الضرورية | VERIFIED |
| Q12 — الاستقلالية عن features الحالية | PARTIALLY VERIFIED |

---

## 4. الوثائق الداعمة

| الوثيقة | المحتوى |
|---|---|
| [R2 — Android API Research](R2_ANDROID_API_RESEARCH.md) | UsageStats, Overlay, AlarmManager, Foreground Service |
| [R3 — Google Play Policy](R3_GOOGLE_PLAY_POLICY.md) | توافق كل إذن مع سياسة Play |
| [R4 — Existing Project Inspection](R4_EXISTING_PROJECT_INSPECTION.md) | ما هو موجود بالفعل في المشروع |
| [R5 — Product Behavior](R5_PRODUCT_BEHAVIOR.md) | سيناريوهات وشروط الاكتمال |
| [R6 — Proposed Architecture](R6_PROPOSED_ARCHITECTURE.md) | التصميم المعماري المقترح |
| [R7 — State Machine](R7_STATE_MACHINE.md) | الحالات والانتقالات الكاملة |
| [R8 — Device Testing Matrix](R8_DEVICE_TESTING_MATRIX.md) | خطة الاختبار |
| [R9 — PoC Proposal](R9_POC_PROPOSAL.md) | مقترح إثبات المفهوم |

---

## 5. الأسئلة المفتوحة (يلزم إجابة قبل التنفيذ)

| # | السؤال | الأثر |
|---|---|---|
| Q-open-1 | هل يُفعَّل Focus Mode تلقائياً عند فتح شاشة الورد يدوياً؟ | يؤثر على Activity-Based Flow |
| Q-open-2 | ما سلوك Shield أثناء الاتصالات الهاتفية؟ | يؤثر على Exemption Logic |
| Q-open-3 | ماذا يحدث إذا انقضى وقت الجلسة قبل الاكتمال؟ | Timeout Logic |
| Q-open-4 | ما شرط اكتمال أذكار ما بعد الصلاة؟ | Completion Contract |
| Q-open-5 | ما يعني "اكتمال جلسة قراءة القرآن"؟ | Quran Completion Contract |
| Q-open-6 | هل يُسمح بالتجاوز المؤقت للمستخدم؟ | Shield UX |

---

## 6. التوصية النهائية

### ✅ Option B — PARTIALLY FEASIBLE

**المبررات:**
1. البنية التحتية الأساسية موجودة (Foreground Service, AlarmManager, Permissions)
2. الأذونات الرئيسية مُعلنة بالفعل
3. الميزة قابلة للبناء كـ feature مستقلة تماماً
4. Google Play لن ترفض التطبيق بسبب هذه الميزة

**القيود الموثقة:**
1. الـ Shield ليس حظراً حقيقياً — هذا بالتصميم وليس قصوراً
2. OEMs مثل Xiaomi قد تُوقف الخدمة — يحتاج اختبار + توثيق
3. `AzkarCompletionPort` يحتاج تصميم معماري دقيق
4. كمون 3-5 ثوانٍ لظهور الـ Shield — مقبول للاستخدام الديني

**الخطوة التالية المقترحة:**
1. الإجابة على الأسئلة الـ 6 المفتوحة أعلاه
2. الموافقة على الـ PoC (R9) في branch منفصل
3. تنفيذ الـ PoC لإثبات الجدوى الفعلية على أجهزة حقيقية
4. بناءً على نتائج الـ PoC: قرار المتابعة للتنفيذ الكامل

---

> [!IMPORTANT]
> **STOP GATE R1 — انتظر موافقة المستخدم قبل أي تنفيذ.**

---

*Review Date: 2026-11-21 | Phase: Research Complete — Awaiting User Decision*
