# Focus Mode — PoC Implementation Status
**Document ID:** `POC_IMPLEMENTATION_STATUS_V1`  
**Branch:** `poc/focus-mode`  
**Status:** IMPLEMENTED & VERIFIED LOCALLY — READY FOR DEVICE TESTING  
**Review Date:** 2026-11-21  

---

## 1. ملخص الإنجاز (Implementation Summary)

تم تنفيذ مكونات إثبات المفهوم (PoC) بالكامل وفق الخطة المعتمدة في الفرع المعزول `poc/focus-mode`، دون المساس بأي من ميزات التطبيق الإنتاجية (الأذكار، المصحف، الصوت، الأذان).

### المكونات المنفذة

| المكون | المسار | الحالة |
|---|---|---|
| **الفرع المعزول** | `poc/focus-mode` | ✅ مفعل |
| **تصريح الاستخدام** | `AndroidManifest.xml` (`PACKAGE_USAGE_STATS`) | ✅ مضاف وموثق |
| **خدمة الـ PoC** | `AndroidManifest.xml` (`FocusPoCService`) | ✅ مسجلة بنوع `specialUse` |
| **مراقب التطبيقات** | `android/.../focus_poc/UsageStatsPoller.kt` | ✅ فحص AppOps + UsageEvents |
| **درع التركيز** | `android/.../focus_poc/OverlayShieldManager.kt` | ✅ WindowManager Overlay مع زر عودة وطوارئ |
| **خدمة الخلفية الأصلية** | `android/.../focus_poc/FocusPoCService.kt` | ✅ Foreground Service + Polling Loop (3s) |
| **قناة الاتصال** | `android/.../focus_poc/FocusPoCChannelHandler.kt` | ✅ MethodChannel + EventChannel |
| **جسر Flutter** | `lib/features/focus_mode_poc/data/focus_poc_channel.dart` | ✅ استدعاءات وبث أحداث مباشر |
| **بطاقة الحالة** | `lib/features/focus_mode_poc/presentation/widgets/poc_status_card.dart` | ✅ شارات الصلاحيات وزر التفعيل |
| **شاشة المختبر** | `lib/features/focus_mode_poc/presentation/screens/focus_poc_screen.dart` | ✅ تحكم كامل + Live Console للأحداث |
| **اختبارات الوحدة** | `test/features/focus_mode_poc/focus_poc_channel_test.dart` | ✅ 6 اختبارات اجتازت بنجاح |
| **اختبارات الواجهة** | `test/features/focus_mode_poc/focus_poc_screen_test.dart` | ✅ اجتاز بنجاح |
| **التحقق من البناء** | Gradle `compileDebugKotlin` | ✅ BUILD SUCCESSFUL (0 errors) |
| **تحليل Dart** | `flutter analyze lib/features/focus_mode_poc` | ✅ No issues found |

---

## 2. كيفية فتح شاشة المختبر على الأجهزة الفعلية

تم توفير طريقتين للوصول إلى `FocusPoCScreen`:
1. **عبر واجهة التطبيق (Easter Egg للمختبر):**
   - افتح: `الإعدادات` $\to$ `عن التطبيق`.
   - اضغط **ضغطة مطولة (Long Press)** على صف **"الإصدار"** (Version).
   - ستفتح لك مباشرة شاشة **"مختبر Focus Mode (PoC)"**.
2. **عبر المسار المباشر (Named Route):**
   - المسار مسجل في `MaterialApp`: `/focus_poc`.

---

## 3. خطوات الاختبار الميداني (Testing Guide)

### الخطوة 1: فحص ومنح الصلاحيات
1. في شاشة المختبر، ستظهر لك بطاقة الصلاحيات:
   - **Usage Access**: اضغط "تفعيل" لمنح الإذن من إعدادات النظام.
   - **Display Over Apps**: اضغط "تفعيل" لمنح إذن الظهور فوق التطبيقات.
   - **Alarms & Reminders**: ستظهر خضراء إذا كانت ممنوحة.
2. عند العودة لشاشة المختبر، ستتحول كل الشارات للأخضر وتصبح الخدمة جاهزة للبدء.

### الخطوة 2: اختبار كشف التطبيقات والدرع (TP-01 & TP-02)
1. اختر الورد (مثلاً: أذكار الصباح).
2. اضغط **"بدء الجلسة"**.
3. ستتحول حالة الخدمة إلى **"نشطة (Monitoring)"** مع ظهور إشعار مستمر في لوحة إشعارات النظام.
4. اخرج من تطبيق الحافظ وافتح أي تطبيق خارجي (مثل: YouTube أو Chrome أو WhatsApp).
5. **النتيجة المتوقعة:** خلال 1 إلى 5 ثوانٍ كحد أقصى، سيظهر درع Focus Shield فوق التطبيق بنمطه الإسلامي الذهبي.

### الخطوة 3: اختبار العودة للورد (TP-04)
1. اضغط على زر **"العودة للورد الآن"** الموجود في منتصف الدرع.
2. **النتيجة المتوقعة:** يتم إخفاء الدرع فورا ونقلك مباشرة إلى شاشة تطبيق الحافظ.

### الخطوة 4: اختبار التجاوز الطارئ (TP-05)
1. أثناء ظهور الدرع، اضغط زر **"تجاوز طارئ (Emergency Bypass)"** (أو من زر التجاوز في الإشعار).
2. **النتيجة المتوقعة:** يختفي الدرع فوراً، وتتوقف الخدمة، ويتم تسجيل الجلسة في الـ Live Console كـ `INTERRUPTED`.

### الخطوة 5: استثناء المكالمات والطوارئ (TP-03)
1. أثناء وجود جلسة نشطة، قم بتشغيل تطبيق الهاتف (Dialer) أو استقبل مكالمة.
2. **النتيجة المتوقعة:** لن يظهر الدرع نهائياً فوق واجهة الاتصال لأنه مستثنى برمجياً عبر `TelecomManager`.

### الخطوة 6: اختبار إغلاق التطبيق من الـ Recent Apps (TP-06)
1. أثناء الجلسة النشطة، قم بقتل تطبيق الحافظ من قائمة التطبيقات الحديثة (Swipe to dismiss).
2. افتح تطبيقاً خارجياً.
3. **النتيجة المتوقعة:** تظل الخدمة الأصلية `FocusPoCService` مستمرة وتظهر الدرع حتى بعد إغلاق واجهة Flutter.

---

*Review Date: 2026-11-21 | Implementation Complete on `poc/focus-mode`*
