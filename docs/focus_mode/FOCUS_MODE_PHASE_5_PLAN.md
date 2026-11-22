# Focus Mode — Phase 5 Plan: Settings & Onboarding UI
## خطة المرحلة الخامسة: واجهات الإعدادات، التوجيه، واختيار التطبيقات المستثناة

**تاريخ الوثيقة:** 22 نوفمبر 2026  
**الفرع:** `poc/focus-mode`  
**الحالة:** مقترحة للمراجعة والاعتماد (STOP GATE)

---

## 1. أهداف المرحلة الخامسة (Executive Summary & Objectives)

بعد إنجاز المحركات المعمارية والتشغيلية الأربعة:
1. عقود إتمام الورد وحساب القراءة الحقيقية (Phase 1).
2. استمرارية الجلسة عبر SQLite والمصالحة العميقة واتساق الانهيار (Phase 2).
3. الجدولة المسبقة الدقيقة والاستعادة التلقائية بعد إعادة تشغيل الهاتف (Phase 3).
4. استرجاع التطبيقات وتوليد الأيقونات وحماية التطبيقات السيادية (Phase 4).

تنتقل **المرحلة الخامسة (Phase 5)** إلى بناء **الطبقة التقديمية المرئية (Presentation Layer)** بالكامل، لتحويل كل هذه القدرات المعقدة إلى واجهة مستخدم إسلامية راقية وسلسة تلتزم بهوية "حافظ العهد":
- **التصميم والهوية البصرية:** التزام كامل بتدرج الذهب الخاص بالتطبيق (`AppColors.goldenGradient`)، والوضع الليلي، وشعار التطبيق، والعنوان المعتمد: **"حافظ على عهدك مع الله"**.
- **دليل التوجيه والصلاحيات (Onboarding & Permissions Guide):** شرح تفاعلي ودود للمستخدم يبين سبب الحاجة لكل صلاحية (الوصول لبيانات الاستخدام، الظهور فوق التطبيقات، المنبهات الدقيقة) مع فحص حي لحالتها وزر للانتقال المباشر للإعدادات.
- **شاشة إعدادات وضع التركيز (Focus Mode Settings Screen):**
  - المفتاح الرئيسي لتفعيل وضع التركيز.
  - قسم جدولة الأوراد اليومية (أذكار الصباح، أذكار المساء، ورد القرآن) وتحديد أوقاتها وأيام تكرارها.
  - بطاقة حالة الجلسة الحالية وإظهار رصيد الغفوة المتاح (بحد أقصى مرتين).
  - بطاقة الانتقال لإدارة التطبيقات المستثناة.
- **شاشة اختيار التطبيقات المستثناة (Focus App Selection Screen):**
  - شريط بحث سريع.
  - عرض أيقونات التطبيقات الحقيقية (المستخرجة بصيغة Base64).
  - تمييز التطبيقات السيادية (الهاتف، الطوارئ، الشاشة الرئيسية، حافظ العهد) بشارة خاصة وقفل مفتاح التبديل لمنع تعطيلها.
  - حفظ وتطبيق الاستثناءات لحظيًا مع المحرك الأصلي.
- **إدارة الحالة (State Management):** بناء Cubits مستقلة وفق نمط BLoC/Cubit המتبع في المشروع.

---

## 2. الهيكل المعماري للطبقة التقديمية (Presentation Architecture)

```
lib/features/focus_mode/presentation/
├── cubits/
│   ├── focus_settings/
│   │   ├── focus_settings_cubit.dart
│   │   └── focus_settings_state.dart
│   ├── focus_app_selection/
│   │   ├── focus_app_selection_cubit.dart
│   │   └── focus_app_selection_state.dart
│   └── focus_permissions/
│       ├── focus_permissions_cubit.dart
│       └── focus_permissions_state.dart
├── screens/
│   ├── focus_mode_settings_screen.dart
│   └── focus_app_selection_screen.dart
└── widgets/
    ├── focus_permission_card.dart
    ├── focus_schedule_card.dart
    ├── focus_active_session_card.dart
    ├── focus_app_tile.dart
    └── focus_onboarding_sheet.dart
```

---

## 3. تفاصيل المكونات (Core Components)

### 3.1. إدارة الحالة (Cubits)

1. **`FocusSettingsCubit`:**
   - المسؤول عن الشاشة الرئيسية لوضع التركيز.
   - يتكامل مع: `FocusSessionCoordinator`، `FocusScheduleCoordinator`، و `FocusSessionRecoveryManager`.
   - الدوال:
     - `loadSettings()`: استرجاع الجداول، الجلسة النشطة الحالية، وحالة الصلاحيات.
     - `toggleSchedule(String scheduleId, bool isEnabled)`.
     - `updateScheduleTime(String scheduleId, int hour, int minute)`.
     - `startManualSession(FocusWardType wardType)`.
     - `snoozeActiveSession()` / `cancelActiveSession()`.

2. **`FocusAppSelectionCubit`:**
   - المسؤول عن شاشة اختيار التطبيقات.
   - يتكامل مع: `FocusAppManagerCoordinator`.
   - الدوال:
     - `loadApps()`: استرجاع قائمة التطبيقات مع الأيقونات وحالة الاستثناء.
     - `search(String query)`: تصفية التطبيقات حسب الاسم أو اسم الحزمة.
     - `filterByTab(AppFilterTab tab)`: (الكل، المستثناة، السيادية).
     - `toggleExemption(String packageName, bool isExempt)`.

3. **`FocusPermissionsCubit`:**
   - مراقبة الصلاحيات الثلاث الأساسية:
     - `hasUsageAccess`
     - `hasOverlayPermission`
     - `canScheduleExactAlarms`
   - توفير روابط مباشرة:
     - `openUsageAccessSettings()`
     - `openOverlaySettings()`
     - `openExactAlarmSettings()`

---

### 3.2. الشاشات وواجهات المستخدم (Screens & Widgets)

#### أ. شاشة الإعدادات (`FocusModeSettingsScreen`):
- **الترويسة (Header):**
  - شعار التطبيق (`assets/images/app_icon_transparent.png`).
  - عنوان الصفحة: **"حافظ على عهدك مع الله"** بخط الثلث/الأميري مع تدرج الذهب (`AppColors.goldenGradient`).
  - وصف تحفيزي: "اضبط أوقات أورادك، ودع التطبيق يعينك على إتمامها بحجب المشتتات حتى تفرغ من عهدك".
- **بطاقة التحقق من الصلاحيات (Permissions Readiness Card):**
  - إذا كانت كل الصلاحيات ممنوحة ⬅️ تظهر بشارة خضراء أنيقة "النظام جاهز للعمل".
  - إذا كانت إحداها مفقودة ⬅️ تظهر بطاقة تنبيهية ترشد المستخدم لمنح الصلاحية الناقصة بضغطة واحدة.
- **بطاقة الجلسة النشطة (Active Session Card):**
  - تظهر فقط أثناء تشغيل جلسة ورد حالية.
  - تعرض اسم الورد، الوقت المنقضي، ورصيد الغفوة المتبقي (مثلاً: "غفوة واحدة متبقية من أصل 2").
- **قسم الأوراد المجدولة (Scheduled Wards):**
  - أذكار الصباح (الوقت الافتراضي: 06:30 ص).
  - أذكار المساء (الوقت الافتراضي: 05:00 م).
  - ورد القرآن الكريم (الوقت الافتراضي: 09:00 م).
  - حوار تعديل الوقت وتكرار الأيام (`TimePickerDialog`).
- **بطاقة التطبيقات المستثناة (Exemptions Entry Tile):**
  - تعرض عدد التطبيقات المسموح بها حاليًا (مثلاً: "4 تطبيقات مستثناة").
  - زر يفتح شاشة `FocusAppSelectionScreen`.

#### ب. شاشة اختيار التطبيقات (`FocusAppSelectionScreen`):
- حقل بحث في الأعلى لتصفية التطبيقات.
- شارات التبويب (Tabs): الكل | المستثناة | السيادية.
- كل عنصر في القائمة (`FocusAppTile`):
  - أيقونة التطبيق الحقيقية المستخرجة من Base64.
  - اسم التطبيق بحجم خط واضح.
  - اسم الحزمة (`package_name`) بلون رمادي خافت.
  - شارة "سيادي - لا يمكن حجبه" للتطبيقات السيادية مع قفل المفتاح.
  - مفتاح تبديل (Switch) بتدرج الذهب للتطبيقات القابلة للاستثناء.

---

## 4. مصفوفة الاختبارات المقترحة للمرحلة الخامسة (Testing Matrix)

| نوع الاختبار | الملف المستهدف | نطاق التغطية |
|---|---|---|
| **Cubit Logic** | `focus_settings_cubit_test.dart` | تحميل الإعدادات، تفعيل وتعطيل الجداول، تعديل الأوقات، والغفوة. |
| **Cubit Logic** | `focus_app_selection_cubit_test.dart` | تحميل التطبيقات، البحث، التصفية بالتبويب، وتبديل الاستثناء. |
| **Cubit Logic** | `focus_permissions_cubit_test.dart` | فحص الصلاحيات، تحديث الحالة عند منح الصلاحية، وفتح الإعدادات. |
| **Widget UI** | `focus_mode_settings_screen_test.dart` | التحقق من ظهور الترويسة بالذهب والشعار وبطاقات الأوراد والصلاحيات. |
| **Widget UI** | `focus_app_selection_screen_test.dart` | التحقق من عرض القائمة، البحث، وشارة التطبيقات السيادية المقفلة. |
| **Verification** | `flutter analyze` & `compileDebugKotlin` | التأكد من سلامة التحليل الساكن والبناء الأصلي للأندرويد. |

---

## 5. خطة التنفيذ خطوة بخطوة (Implementation Steps)

1. **الخطوة 5.1 — Cubits & Presentation State:**
   - إنشاء `FocusSettingsCubit` و `FocusSettingsState`.
   - إنشاء `FocusAppSelectionCubit` و `FocusAppSelectionState`.
   - إنشاء `FocusPermissionsCubit` و `FocusPermissionsState`.
   - تسجيل الـ Cubits في `service_locator.dart`.
   - كتابة اختبارات الـ Cubits الآلية.

2. **الخطوة 5.2 — Reusable Presentation Widgets:**
   - إنشاء `FocusPermissionCard` و `FocusScheduleCard`.
   - إنشاء `FocusActiveSessionCard` مع مؤشر الغفوة (Max 2).
   - إنشاء `FocusAppTile` مع فك تشفير أيقونة Base64.
   - إنشاء `FocusOnboardingSheet`.

3. **الخطوة 5.3 — Main Screens:**
   - إنشاء `FocusModeSettingsScreen`.
   - إنشاء `FocusAppSelectionScreen`.
   - ربط التنقل السلس بين الشاشات.

4. **الخطوة 5.4 — Verification & Reporting:**
   - كتابة وتشغيل اختبارات الواجهات (`Widget Tests`).
   - تشغيل حزمة الاختبارات الشاملة والفحص الساكن وبناء Gradle.
   - إعداد تقرير اكتمال المرحلة الخامسة `PHASE_5_COMPLETION_REPORT.md` ورفعه للمراجعة والاعتماد.

---

## 6. بوابة التوقف (STOP GATE)

وفقًا للسياسة المتبعة، **لن يتم الانتقال إلى المرحلة السادسة (Phase 6 — Production Integration) إلا بعد اكتمال تنفيذ المرحلة الخامسة بالكامل واعتماد تقريرها واختباراتها الآلية.**
