# R3 — Google Play Policy Research
**Document ID:** `FOCUS_MODE_R3`
**Type:** Policy Research
**Platform:** Android Only
**Status:** COMPLETE
**Review Date:** 2026-11-21

---

> [!IMPORTANT]
> المصدر الأساسي: [Google Play Developer Policy Center](https://support.google.com/googleplay/android-developer/answer/9888170)
> تُصنَّف أي معلومة غير مؤكدة من السياسة الرسمية بـ **UNVERIFIED**.

---

## 1. Accessibility Services Policy

### 1.1 الموقف الرسمي لـ Google Play

> **[مصدر رسمي]** Google Play يقصر استخدام `AccessibilityService` على التطبيقات التي تهدف فعلياً إلى مساعدة المستخدمين ذوي الاحتياجات الخاصة أو التي توفر ميزات إمكانية الوصول التي تعالج احتياجات وصول موثقة.
>
> التطبيقات التي تستخدم `AccessibilityService` لأغراض لا تتعلق بإمكانية الوصول (مثل مراقبة التطبيقات أو تقديم ميزات الإنتاجية) ترفضها Google Play.

**الحكم:** `AccessibilityService` **محظور** لـ Focus Mode.

---

## 2. PACKAGE_USAGE_STATS Policy

### 2.1 استخدام بيانات الاستخدام

Google Play يسمح باستخدام `PACKAGE_USAGE_STATS` بشرط:
- الإفصاح الكامل عن البيانات المجمعة وطريقة استخدامها في سياسة الخصوصية
- عدم بيع بيانات الاستخدام أو مشاركتها مع أطراف ثالثة
- جمع البيانات لغرض واضح ومرتبط بالوظيفة الأساسية للتطبيق

**التقييم:** ✅ مسموح لـ Focus Mode شريطة:
- إضافة بند في Privacy Policy يوضح جمع بيانات استخدام التطبيقات
- استخدام البيانات فقط لتفعيل/إلغاء Focus Shield
- عدم إرسال البيانات خارج الجهاز

---

## 3. SYSTEM_ALERT_WINDOW Policy

### 3.1 الموقف الرسمي

> **[مصدر رسمي]** الإذن `SYSTEM_ALERT_WINDOW` حساس ويتطلب مراجعة. Google Play يقبله للتطبيقات التي لها حالة استخدام شرعية واضحة، مثل:
> - تطبيقات الإنتاجية
> - أدوات العرض (Heads-up displays)
> - تطبيقات المساعدة

**التقييم:** ✅ مسموح لـ Focus Mode — تطبيق العبادة والإنتاجية هو حالة استخدام شرعية.

> [!NOTE]
> `SYSTEM_ALERT_WINDOW` مُعلن بالفعل في التطبيق ومقبول من Google Play في الإصدارات السابقة. هذا يعني أن التطبيق اجتاز هذا الفحص مسبقاً.

---

## 4. QUERY_ALL_PACKAGES Policy

### 4.1 الموقف الرسمي

> **[مصدر رسمي]** الإذن `QUERY_ALL_PACKAGES` محظور إلا للتطبيقات التي تحتاجه لأغراض محددة موثقة (مثل مديري الملفات، متاجر التطبيقات، برامج مكافحة الفيروسات).

**ملاحظة:** `QUERY_ALL_PACKAGES` **غير مطلوب** لـ Focus Mode. `UsageStatsManager` لا يحتاجه.

للحصول على قائمة التطبيقات المثبتة (لشاشة "Protected Apps"):
```xml
<!-- في AndroidManifest.xml داخل <queries> -->
<queries>
    <intent>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
    </intent>
</queries>
```
هذا مسموح ولا يحتاج `QUERY_ALL_PACKAGES`.

**التقييم:** ✅ لا توجد مشكلة — نستخدم `<queries>` بدل `QUERY_ALL_PACKAGES`.

---

## 5. Exact Alarm Permission Policy

### 5.1 `SCHEDULE_EXACT_ALARM` (Android 12+)

> **[مصدر رسمي — Android Documentation]** بدءاً من Android 12 (API 31)، التطبيقات التي تحتاج جدولة دقيقة يجب أن:
> 1. تُعلن `SCHEDULE_EXACT_ALARM`
> 2. تتحقق من `AlarmManager.canScheduleExactAlarms()` قبل الجدولة
> 3. توجّه المستخدم إلى `Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM` إذا لم يُمنح الإذن

> **[مصدر رسمي — Google Play Policy]** في Google Play، `SCHEDULE_EXACT_ALARM` مقبول للتطبيقات التي لها حالة استخدام شرعية تتطلب دقة زمنية، مثل التطبيقات الدينية وتطبيقات التنبيه.

**التقييم:** ✅ مسموح — التطبيق مُرخّص بالفعل ولديه سابقة في استخدام الجدولة الدقيقة (أوقات الصلاة).

### 5.2 `USE_EXACT_ALARM` (Android 13+)

> **[مصدر رسمي]** مخصص لـ Calendar apps و Alarm Clock apps فقط. تطبيقات أخرى تستخدمه قد تُرفض من Google Play.

> [!WARNING]
> `USE_EXACT_ALARM` مُعلن في AndroidManifest.xml الحالي. إذا كانت Google Play تُصنّف التطبيق كـ "Alarm Clock" (وهو محتمل بسبب ميزة أوقات الصلاة)، فهذا مقبول. إذا لا، يجب إزالته واستخدام `SCHEDULE_EXACT_ALARM` فقط.
>
> **هذا ليس من نطاق Focus Mode Research — يُرفع كـ issue منفصل.**

---

## 6. Foreground Service Policy

### 6.1 Google Play و Foreground Services

> **[مصدر رسمي — Google Play Policy]** منذ أغسطس 2023، Google Play يفحص نوع الـ Foreground Service (`foregroundServiceType`) للتأكد من توافقه مع الغرض المُعلن.

| النوع | التطبيقات المسموحة |
|---|---|
| `mediaPlayback` | مشغلات الموسيقى، البودكاست، القرآن ✅ |
| `location` | تطبيقات التتبع، الملاحة ✅ |
| `specialUse` | استخدامات مشروعة غير مصنفة ✅ (مع تبرير) |

**للـ Focus Mode:** `specialUse` مقبول مع تبرير في الـ manifest.

```xml
<property
    android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
    android:value="Monitors active session for Islamic adhkar completion tracking"/>
```

**التقييم:** ✅ مقبول مع توثيق مناسب.

---

## 7. User Consent & Disclosure Requirements

### 7.1 ما يجب الإفصاح عنه

| البيانات المجمعة | طريقة الإفصاح المطلوبة |
|---|---|
| قائمة التطبيقات المستخدمة | Privacy Policy + شاشة onboarding للميزة |
| أوقات استخدام التطبيقات | Privacy Policy |
| حالة جلسة التركيز | لا يلزم — بيانات محلية فقط |

### 7.2 Data Safety Section في Play Console

عند تفعيل Focus Mode، يجب تحديث بيان "Data Safety" في Play Console:

| النوع | البيانات | الغرض | مشاركة؟ |
|---|---|---|---|
| App activity | قائمة التطبيقات المستخدمة | App functionality | لا |

---

## 8. ملخص التقييم

| الموضوع | الحكم | الملاحظة |
|---|---|---|
| AccessibilityService | ❌ محظور | لا يجوز استخدامه |
| PACKAGE_USAGE_STATS | ✅ مسموح | مع إفصاح في Privacy Policy |
| SYSTEM_ALERT_WINDOW | ✅ مسموح | حالة استخدام شرعية |
| QUERY_ALL_PACKAGES | ✅ غير مطلوب | نستخدم `<queries>` |
| SCHEDULE_EXACT_ALARM | ✅ مسموح | مُستخدم بالفعل |
| Foreground Service (specialUse) | ✅ مسموح | مع تبرير في manifest |
| جمع بيانات الاستخدام | ✅ مسموح | مع إفصاح |

> [!NOTE]
> **الخلاصة:** Focus Mode كما هو مُصمَّم متوافق مع سياسات Google Play بشرط:
> 1. تحديث Privacy Policy
> 2. تحديث Data Safety في Play Console
> 3. عدم استخدام AccessibilityService
> 4. توثيق `specialUse` في manifest

---

*Review Date: 2026-11-21 | Sources: developer.android.com, support.google.com/googleplay | Phase: Research Only*
