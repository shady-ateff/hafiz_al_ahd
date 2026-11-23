# R8 — Device Testing Matrix
**Document ID:** `FOCUS_MODE_R8`
**Type:** Test Planning
**Platform:** Android Only
**Status:** COMPLETE (PLANNED — NOT EXECUTED)
**Review Date:** 2026-11-21

---

> [!NOTE]
> هذه المصفوفة مخططة وليست منفذة. الاختبارات تُجرى في مرحلة PoC بعد الموافقة.

---

## 1. Android Versions Matrix

| الإصدار | API Level | الأهمية | السبب |
|---|---|---|---|
| Android 12 | 31 | 🔴 عالية | SCHEDULE_EXACT_ALARM أصبح إلزامياً |
| Android 13 | 33 | 🔴 عالية | POST_NOTIFICATIONS أصبح إلزامياً |
| Android 14 | 34 | 🔴 عالية | Foreground Service Type إلزامي |
| Android 15 | 35 | 🟡 متوسطة | قيود إضافية على shortService |
| Android 11 | 30 | 🟡 متوسطة | package visibility changes |
| Android 10 | 29 | 🟢 منخفضة | قاعدة المستخدمين القديمة |

---

## 2. OEM Matrix

### 2.1 Samsung One UI

| الاختبار | المتوقع | السبب |
|---|---|---|
| Foreground Service استمرارية | ⚠️ قد يُوقف | Battery optimization قاسية |
| SYSTEM_ALERT_WINDOW | ✅ يعمل عادةً | — |
| UsageStats polling | ✅ يعمل | — |
| BOOT_COMPLETED | ✅ يعمل عادةً | — |

**التوصية:** اختبار على Samsung Galaxy S23 أو S24 (One UI 6.x)

### 2.2 Xiaomi MIUI / HyperOS

| الاختبار | المتوقع | السبب |
|---|---|---|
| Foreground Service استمرارية | ⚠️ خطر عالٍ | MIUI Autostart مُعطَّل بالافتراضي |
| SYSTEM_ALERT_WINDOW | ⚠️ يحتاج إذن إضافي | MIUI لديه قيود إضافية على Overlay |
| UsageStats polling | ✅ يعمل إذا مُنح الإذن | — |
| BOOT_COMPLETED | ⚠️ يحتاج Autostart | — |

**التوصية:** اختبار على Xiaomi Redmi Note 12 أو Poco X5

### 2.3 Google Pixel (Stock Android)

| الاختبار | المتوقع | السبب |
|---|---|---|
| Foreground Service استمرارية | ✅ يعمل | Stock Android بدون OEM customizations |
| SYSTEM_ALERT_WINDOW | ✅ يعمل | — |
| UsageStats polling | ✅ يعمل | — |
| BOOT_COMPLETED | ✅ يعمل | — |

**التوصية:** اختبار أساسي على Pixel 7 أو Pixel 8 (Android 14)

### 2.4 OnePlus / Oppo (OxygenOS / ColorOS)

| الاختبار | المتوقع | السبب |
|---|---|---|
| Foreground Service استمرارية | ⚠️ ممكن | قيود Battery optimization |
| Overlay | ✅ يعمل عادةً | — |

---

## 3. سيناريوهات الاختبار

### 3.1 اختبارات الأساس (يجب اجتيازها)

| TC | الوصف | الخطوات | النتيجة المتوقعة |
|---|---|---|---|
| TC-01 | بدء جلسة مجدولة | 1. اضبط موعد Focus + 2. انتظر | يظهر إشعار الجلسة في الوقت المحدد |
| TC-02 | ظهور Shield عند تطبيق محظور | أثناء جلسة نشطة، افتح تطبيقاً محظوراً | يظهر Shield خلال 5 ثوانٍ |
| TC-03 | إخفاء Shield عند العودة | من Shield، اضغط "العودة للأذكار" | يختفي Shield، يظهر التطبيق |
| TC-04 | إنهاء جلسة عند اكتمال الورد | أكمل كل الأذكار | تُنهى الجلسة، إشعار تهنئة |
| TC-05 | إيقاف يدوي | اضغط "إيقاف التركيز" في الإشعار | تُنهى الجلسة فوراً |
| TC-06 | استمرار بعد إعادة التشغيل | أعد تشغيل الجهاز، انتظر موعد الجلسة | الجلسة تبدأ في موعدها |
| TC-07 | الهاتف مستثنى دائماً | أثناء جلسة، استقبل اتصالاً | لا يظهر Shield أثناء المكالمة |
| TC-08 | PACKAGE_USAGE_STATS غير ممنوح | حاول بدء جلسة بدون الإذن | رسالة توضيحية + رابط للإعدادات |

### 3.2 اختبارات الحافة (يجب التوثيق)

| TC | الوصف | النتيجة المقبولة |
|---|---|---|
| TC-09 | OEM يُوقف Service | توثيق السلوك + إشعار للمستخدم |
| TC-10 | SYSTEM_ALERT_WINDOW يُسحب أثناء الجلسة | توقف Shield مع إشعار |
| TC-11 | شاشة القفل أثناء الجلسة | استئناف polling بعد الفتح |
| TC-12 | استهلاك البطارية بعد ساعة | قياس الاستهلاك + التوثيق |

---

## 4. قياسات الأداء المستهدفة

| المقياس | الهدف | الحد الأقصى المقبول |
|---|---|---|
| كمون ظهور Shield | ≤ 3 ثوانٍ | ≤ 5 ثوانٍ |
| استهلاك CPU (polling) | < 1% | < 3% |
| استهلاك Battery/hour | < 0.5% | < 1% |
| RAM المستهلكة | < 20 MB | < 40 MB |

---

## 5. الأجهزة الافتراضية (Emulator) للاختبار الأولي

| AVD | API | الغرض |
|---|---|---|
| Pixel 7 Pro API 34 | 34 | الاختبار الأساسي |
| Pixel 6 API 33 | 33 | POST_NOTIFICATIONS behavior |
| Pixel 5 API 31 | 31 | SCHEDULE_EXACT_ALARM |

> [!NOTE]
> الاختبار على المحاكي غير كافٍ لـ:
> - OEM-specific behavior
> - Battery optimization
> - Doze Mode behavior الحقيقي
>
> يجب اختبار على أجهزة حقيقية قبل الإطلاق.

---

## 6. Known Limitations المتوقعة

| القيد | التفاصيل | الحل المقترح |
|---|---|---|
| Xiaomi MIUI Autostart | الخدمة تُوقف إلا إذا مُنح Autostart | توجيه المستخدم لتفعيله في الإعدادات |
| Shield ليس حظراً حقيقياً | المستخدم يمكنه التحايل | هذا بالتصميم — reminder وليس lock |
| Polling latency | قد يصل لـ 10 ثوانٍ في Doze | مقبول — documented limitation |
| Shield على بعض أنواع الشاشات | قد لا يظهر فوق بعض system apps | توثيق + استثناء system apps |

---

*Review Date: 2026-11-21 | Phase: Research Only — Tests Not Executed*
