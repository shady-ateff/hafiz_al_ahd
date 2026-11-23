# R9 — PoC Proposal
**Document ID:** `FOCUS_MODE_R9`
**Type:** Proof of Concept Proposal
**Platform:** Android Only
**Status:** PROPOSED — AWAITING AUTHORIZATION
**Review Date:** 2026-11-21

---

> [!IMPORTANT]
> هذه وثيقة وصف PoC فقط. لا يوجد كود تنفيذي. التنفيذ يتطلب موافقة صريحة منفصلة.

---

## 1. هدف الـ PoC

إثبات جدوى الافتراضات التقنية التالية على جهاز حقيقي:

| الافتراض | ما يُختبر |
|---|---|
| `UsageStatsManager` يمكنه اكتشاف foreground app | الكمون الفعلي + الموثوقية |
| `SYSTEM_ALERT_WINDOW` يعمل فوق التطبيقات المحظورة | قابلية الظهور + سلوك الإخفاء |
| `Foreground Service (specialUse)` يستمر لساعة كاملة | الاستمرارية على أجهزة مختلفة |
| `AlarmManager.setExactAndAllowWhileIdle` يُطلق الجلسة بدقة | الدقة الزمنية بعد Doze |
| استهلاك البطارية مقبول | القياس الفعلي لـ CPU + RAM + Battery |

---

## 2. نطاق الـ PoC (Scope)

### 2.1 ما يشمله

- [ ] إنشاء `FocusMonitorService.kt` بسيط مع polling
- [ ] إنشاء `UsageStatsHelper.kt` مع منطق استطلاع أساسي
- [ ] إنشاء Overlay بسيط (نص فقط) عبر `WindowManager`
- [ ] تسجيل الـ Service في manifest جديد (branch منفصل)
- [ ] MethodChannel بسيط لبدء/إيقاف الـ Service من Flutter
- [ ] شاشة اختبار مؤقتة في Flutter تعرض الـ foreground app الحالي
- [ ] قياس وتسجيل استهلاك البطارية والـ CPU

### 2.2 ما لا يشمله

- [ ] واجهة إعدادات كاملة
- [ ] منطق اكتمال الأذكار
- [ ] تكامل مع AlarmManager للجدولة
- [ ] دعم BOOT_COMPLETED
- [ ] أي تعديل على features الحالية
- [ ] كود Production-ready

---

## 3. الملفات المقترح إنشاؤها في الـ PoC

### 3.1 Kotlin (Android)

```
android/app/src/main/kotlin/com/shadyatef/hafiz_alahd/poc/
├── FocusPoCService.kt        # Foreground Service مبسط
├── UsageStatsPoller.kt       # polling مع تسجيل النتائج
└── OverlayWindowManager.kt   # Overlay بسيط
```

### 3.2 Flutter

```
lib/features/focus_mode_poc/     # مجلد مؤقت معزول
├── poc_screen.dart               # شاشة اختبار مؤقتة
└── focus_poc_channel.dart        # MethodChannel بسيط
```

---

## 4. شروط النجاح

الـ PoC يُعتبر ناجحاً إذا:

| الشرط | المعيار |
|---|---|
| اكتشاف Foreground App | ≤ 5 ثوانٍ كمون على Pixel + Samsung |
| Overlay يظهر | يظهر فوق 90% من التطبيقات المختبرة |
| Service يستمر | يستمر 60 دقيقة على Pixel بدون إيقاف |
| استهلاك البطارية | < 1% لكل ساعة |
| لا Crash | لا أخطاء غير معالجة خلال الاختبار |

---

## 5. الجدول الزمني المقترح

| المرحلة | المدة المقدرة |
|---|---|
| إعداد Branch + Manifest | 1 يوم |
| تطوير FocusPoCService | 2-3 أيام |
| اختبار Pixel (Emulator) | 1 يوم |
| اختبار أجهزة حقيقية | 2-3 أيام |
| تسجيل النتائج + القرار | 1 يوم |
| **الإجمالي** | **~1 أسبوع** |

---

## 6. قرار ما بعد الـ PoC

بناءً على نتائج الـ PoC:

| النتيجة | القرار |
|---|---|
| كل شروط النجاح تحققت | المتابعة للتنفيذ الكامل |
| معظم الشروط تحققت مع قيود | تعديل النطاق + المتابعة مع تحفظات |
| فشل شرط جوهري (مثلاً: Battery > 3%) | إعادة النظر في المعمارية |
| الـ Service لا يستمر على Samsung | توثيق كـ known limitation على هذا OEM |

---

> [!CAUTION]
> **هذا الـ PoC يجب أن يكون في branch منفصل تماماً.**
> لا يُدمج مع `feature/quran-audio` أو main.
> الكود كله مؤقت ويُحذف أو يُعاد كتابته في مرحلة التنفيذ الحقيقية.

---

*Review Date: 2026-11-21 | Phase: Research Only — Awaiting Authorization*
