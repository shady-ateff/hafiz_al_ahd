# Focus Mode — Phase 4 Plan: App Selection & Exemptions
## خطة المرحلة الرابعة: إدارة قائمة التطبيقات المستثناة واسترجاع تطبيقات الهاتف

**تاريخ الوثيقة:** 22 نوفمبر 2026  
**الفرع:** `poc/focus-mode`  
**الحالة:** مقترحة للمراجعة والاعتماد (STOP GATE)

---

## 1. أهداف المرحلة الرابعة (Executive Summary & Objectives)

بعد إنجاز:
1. فصل منطق الأوراد وإتمام القرآن الذكي عن طبقة العرض (Phase 1).
2. استمرارية الجلسة عبر SQLite وضمان اتساق الحالة التام (Crash Consistency) ومصفوفة المصالحة (Phase 2).
3. الجدولة المسبقة الدقيقة والاستعادة التلقائية بعد إعادة تشغيل الجهاز (Phase 3).

تأتي **المرحلة الرابعة (Phase 4)** لنقل درع الحماية من نمط الحظر الشامل التجريبي (PoC Hardcoded Blocking) إلى **نظام مرن ومنضبط لإدارة التطبيقات (Dynamic App Selection & Exemption Engine)** يتيح للمستخدم:
- استعراض قائمة التطبيقات المثبتة على جهازه بأسماءها الحقيقية وأيقوناتها.
- تحديد التطبيقات المسموح باستخدامها أثناء جلسة الورد (مثل: الآلة الحاسبة، الملاحظات، أو تطبيق ديني آخر).
- فرض **حماية حتمية للتطبيقات السيادية (System Critical Invariant)**: الهاتف والاتصال في الطوارئ (`Dialer` / `InCallUI`)، شاشة النظام الرئيسية (`Home Launcher`)، وتطبيق حافظ العهد نفسه؛ بحيث يستحيل حجبها تحت أي ظرف.
- مزامنة قائمة التطبيقات المستثناة ديناميكيًا بين Flutter ومحرك الفحص الأصلي في أندرويد (`UsageStatsPoller` و `FocusPoCService`) دون الحاجة لإعادة تشغيل الخدمة.
- حفظ خيارات وتفضيلات الاستثناء بشكل دائم في قاعدة بيانات SQLite.

---

## 2. التحليل المعماري وتوزيع المسؤوليات (Architecture & Design)

```
┌────────────────────────────────────────────────────────┐
│                      Domain Layer                      │
│                                                        │
│  [InstalledAppInfo] ──► [AppExemptionPolicy]           │
│         │                      │                       │
│         ▼                      ▼                       │
│  [AppExemptionRepo]    [FocusAppManagerCoordinator]    │
│         │                      │                       │
│         └──────────┬───────────┘                       │
│                    ▼                                   │
│       [FocusAppExemptionPort]  (Abstract Contract)     │
└────────────────────┬───────────────────────────────────┘
                     │ (MethodChannel & Data Persistence)
┌────────────────────▼───────────────────────────────────┐
│              Platform / Infrastructure                 │
│                                                        │
│  [AppExemptionLocalDataSource] (SQLite: focus_mode)    │
│  [NativeFocusAppExemptionPort]                         │
│                    │                                   │
│  ══════════════════╪═════════════════════════════════  │
│                    ▼ (Android Native Kotlin)           │
│  [FocusAppManager]                                     │
│         ├──► [AppInfoCollector] (PackageManager query) │
│         └──► [ExemptionRegistry] (Thread-safe Set)     │
│                    │                                   │
│                    ▼                                   │
│         [UsageStatsPoller.isPackageExempted()]         │
│                    │                                   │
│                    ▼                                   │
│         [OverlayShieldManager.showShield()]            │
└────────────────────────────────────────────────────────┘
```

---

## 3. تفاصيل المكونات (Core Components)

### 3.1. الكيانات والعقود في طبقة النطاق (Domain Entities & Ports)

1. **`InstalledAppInfo` Entity:**
   - `packageName`: المعرف الفريد لحزمة التطبيق (مثل: `com.google.android.calculator`).
   - `appName`: الاسم الظاهر للتطبيق المعرب/المحلي (مثل: "الآلة الحاسبة").
   - `isSystemApp`: هل هو تطبيق نظام أم مثبت من المستخدم.
   - `isSystemCritical`: هل هو تطبيق سيادي يستحيل حجبه (مثل: الهاتف ومشغل النظام).
   - `isExempt`: هل هو مستثنى ومسموح بفتحه أثناء الورد.
   - `iconBase64`: أيقونة التطبيق مرمزة بصيغة Base64 لعرضها بسلاسة في واجهة Flutter.

2. **`AppExemptionPolicy` (Domain Service):**
   - تحديد قرار السماح أو الحظر (`isPackageAllowed`):
     - إذا كان التطبيق هو حافظ العهد نفسه (`context.packageName`) ⬅️ **مسموح دائمًا**.
     - إذا كان تطبيقًا سياديًا (Dialer, Emergency, Home Launcher) ⬅️ **مسموح دائمًا (System Critical Invariant)**.
     - إذا كان مضافًا في قائمة الاستثناءات المعتمدة من المستخدم ⬅️ **مسموح**.
     - في غير ذلك ⬅️ **محظور (Trigger Overlay Shield)**.

3. **`FocusAppExemptionPort` (Abstract Port):**
   ```dart
   abstract class FocusAppExemptionPort {
     /// يسترجع التطبيقات المثبتة التي تملك واجهة تشغيل (Launchable Apps)
     Future<List<InstalledAppInfo>> getInstalledApps();

     /// يرسل قائمة أسماء الحزم المستثناة للمحرك الأصلي في أندرويد
     Future<bool> syncExemptionsToNative(List<String> exemptPackages);

     /// يسترجع الحزم السيادية للنظام (Dialer, Home Launcher)
     Future<List<String>> getSystemCriticalPackages();
   }
   ```

4. **`FocusAppExemptionRepository` (Domain Repository):**
   - إدارة حفظ وقراءة تفضيلات الاستثناء لكل حزمة في قاعدة بيانات SQLite.

5. **`FocusAppManagerCoordinator` (Domain Service):**
   - استرجاع التطبيقات من النظام ودمجها مع التفضيلات المخزنة في SQLite.
   - تحديث تفضيلات الاستثناء وإرسال القائمة المحدثة فورًا للمحرك الأصلي في أندرويد.

---

### 3.2. استمرارية البيانات (SQLite Schema for Exemptions)

ترقية قاعدة البيانات `focus_mode.db` من الإصدار 2 إلى الإصدار 3 بإضافة جدول `focus_app_exemptions`:

```sql
CREATE TABLE focus_app_exemptions (
    package_name TEXT PRIMARY KEY,
    app_name TEXT NOT NULL,
    is_exempt INTEGER NOT NULL DEFAULT 0,
    is_system_critical INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL
);
CREATE INDEX idx_focus_app_exemptions_is_exempt ON focus_app_exemptions(is_exempt);
```

---

### 3.3. المحرك الأصلي على أندرويد (Android Native Implementation)

#### أ. مسترجع التطبيقات المثبتة (`AppInfoCollector.kt`):
- استعلام `PackageManager` عن التطبيقات القابلة للتشغيل فقط عبر فلتر:
  `Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)`
- استبعاد التطبيقات والخدمات الخلفية الصامتة لتوفير قائمة نظيفة للمستخدم.
- استخراج اسم التطبيق المترجم (`loadLabel`) وأيقونة التطبيق وتحويلها إلى Base64 PNG مصغر (بحجم 64x64 أو 96x96) لضمان سرعة نقل البيانات وتفادي استهلاك الذاكرة.

#### ب. سجل الاستثناءات الحي المتزامن (`ExemptionRegistry.kt`):
- هيكل بيانات متزامن آمن للخيوط (`ConcurrentHashMap.newKeySet<String>()`) يحتفظ بأسماء الحزم المسموحة في الذاكرة.
- يُغذى تلقائيًا بالحزم السيادية للنظام (Default Dialer، Home Launcher، و InCallUI).
- يستقبل أوامر التحديث من Flutter فور قيام المستخدم بتعديل خياراته عبر استدعاء MethodChannel `"setExemptions"`.
- يقوم بحفظ نسخة محلية في `SharedPreferences` (`focus_exemptions_native_prefs`) لضمان توفرها فور إقلاع الخدمة دون انتظار Flutter.

#### ج. تكامل محرك المراقبة (`UsageStatsPoller.kt`):
- استبدال القائمة الثابتة في `isPackageExempted(packageName)` بالاستعلام المباشر فائق السرعة O(1) من `ExemptionRegistry`.
- عند فتح المستخدم لتطبيق غير مستثنى، يقوم الدرع `OverlayShieldManager` بالحظر الفوري.
- عند فتح تطبيق مستثنى، يُسمح له بالمرور فورًا دون إظهار الدرع.

---

## 4. مصفوفة الاختبارات المقترحة للمرحلة الرابعة (Testing Matrix)

| نوع الاختبار | الملف المستهدف | نطاق التغطية |
|---|---|---|
| **Domain Logic** | `app_exemption_policy_test.dart` | التحقق من منع حظر التطبيقات السيادية، فحص قائمة المستثنيات، والرفض الافتراضي للمشتتات. |
| **Domain Logic** | `focus_app_manager_coordinator_test.dart` | دمج التطبيقات المسترجعة مع تفضيلات SQLite، ومزامنة القوائم مع المنفذ الأصلي. |
| **Data / Storage** | `focus_app_exemption_repository_test.dart` | العمليات الذرية لحفظ، قراءة، وتعديل حالة الاستثناء في جدول `focus_app_exemptions`. |
| **Platform Channel** | `native_focus_app_exemption_port_test.dart` | التحقق من رسائل واستجابات MethodChannel (`getInstalledApps`, `setExemptions`, `getSystemCriticalPackages`). |
| **Android Native Verification** | `compileDebugKotlin` | بناء كود Kotlin والتأكد من خلوه من أي أخطاء تجميعية في `AppInfoCollector` و `ExemptionRegistry`. |

---

## 5. خطة التنفيذ خطوة بخطوة (Implementation Steps)

1. **الخطوة 4.1 — Domain Contracts & Entities:**
   - كتابة الكيان `InstalledAppInfo`.
   - كتابة خدمة النطاق `AppExemptionPolicy`.
   - كتابة العقود المجردة: `FocusAppExemptionPort` و `FocusAppExemptionRepository`.
   - كتابة منسق النطاق `FocusAppManagerCoordinator`.
   - كتابة اختبارات النطاق الآلية (Unit Tests).

2. **الخطوة 4.2 — SQLite Persistence for Exemptions:**
   - ترقية `FocusDatabase` إلى الإصدار 3 وإضافة جدول `focus_app_exemptions`.
   - إنشاء `FocusAppExemptionModel` و `FocusAppExemptionRepositoryImpl`.
   - كتابة اختبارات التخزين الذري.

3. **الخطوة 4.3 — Android Native App Collector & Exemption Registry:**
   - إنشاء `ExemptionRegistry.kt` لإدارة قائمة الحزم المستثناة والسيادية.
   - إنشاء `AppInfoCollector.kt` لاستخراج التطبيقات المثبتة وأيقوناتها.
   - تحديث `UsageStatsPoller.kt` للاعتماد على `ExemptionRegistry`.
   - تحديث `FocusPoCChannelHandler.kt` لتوفير استدعاءات: `getInstalledApps`، `setExemptions`، `getSystemCriticalPackages`.

4. **الخطوة 4.4 — Integration, Service Locator & Full Verification:**
   - إنشاء `NativeFocusAppExemptionPort` و `InMemoryFocusAppExemptionPort`.
   - تسجيل المكونات الجديدة في `service_locator.dart`.
   - تشغيل حزمة الاختبارات الشاملة (Flutter Tests + Analyzer + Kotlin Compilation).
   - إعداد تقرير اكتمال المرحلة الرابعة `PHASE_4_COMPLETION_REPORT.md` ورفعه للمراجعة والاعتماد.

---

## 6. بوابة التوقف (STOP GATE)

وفقًا للسياسة المتبعة، **لن يتم الانتقال إلى المرحلة الخامسة (Phase 5 — Settings & Onboarding UI) إلا بعد اكتمال تنفيذ المرحلة الرابعة بالكامل واعتماد تقريرها واختباراتها الآلية.**
