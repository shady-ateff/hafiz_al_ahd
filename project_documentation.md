# توثيق شامل وخطة تطوير تطبيق "حافظ العهد" (Hafiz Al-Ahd)

## 1. التوثيق الحالي للتطبيق (Current Architecture & Features)

*   **الهدف الأساسي**: تطبيق إسلامي شامل يعرض المصحف الشريف الذكي، مواقيت الصلاة، الأذكار والمسبحة، والقبلة، مع إشعارات متقدمة وتصميم فاخر.
*   **الإصدار الحالي**: `V3.0.0` (Build 8)
*   **البنية التقنية (Tech Stack)**:
    *   **إطار العمل**: Flutter (SDK ^3.10.4)
    *   **إدارة الحالة**: `flutter_bloc` (Cubit pattern)
    *   **البنية**: Clean Architecture لكل ميزة (data → domain → presentation)
    *   **الثيم**: نظام ثيم متعدد (فاتح/داكن/مخصص للقرآن) مع ThemeCubit + ThemeHelper extension + SharedPreferences persistence
    *   **المنصات المدعومة**: Android, iOS, Windows, Linux, macOS
    *   **تحميل الملفات الخارجية**: `archive` + `path_provider` لفك ضغط خطوط المصحف ديناميكياً وتقليل الحجم.

### المميزات المنجزة

| الميزة | التفاصيل |
|---|---|
| **القرآن الكريم (Smart Mushaf)** | مصحف مطابق لمصحف المدينة (15 سطر)، يعتمد على خطوط QCFv2 بدقة عالية (بدون بكسلة)، ترويسات وزخارف SVG، ثيم ليلي مخصص، وتحميل خطوط ديناميكي (Dynamic Font Loading) لتقليل حجم التطبيق الأولي. |
| **مواقيت الصلاة** | عرض الصلوات الخمس + الشروق بناءً على GPS أو موقع يدوي، تخزين محلي (cache)، 3 مراحل بصرية للكارت (عادي → قبل نص ساعة → إقامة) |
| **الإشعارات والأذان** | جدولة آمنة لـ 6 أيام قادمة عبر `Throttling` في الـ Main Isolate لتجنب تجميد الواجهة. حماية من تراكم الأذانات (Stacked Adhans). أصوات مخصصة (أذان عادي، أذان فجر، صوت إقامة). |
| **تأخير الإقامة** | إعداد مستقل لكل صلاة (5-30 دقيقة) محفوظ في SharedPreferences |
| **الأذكار والتتبع الذكي** | أذكار الصباح/المساء وغيرها. نظام تتبع متقدم يحفظ التقدم اليومي، ويعيد تصفير الأذكار بعد منتصف الليل. جدولة أوتوماتيكية لإشعارات أذكار الصباح (بعد الفجر) والمساء (بعد العصر). |
| **المسبحة والاحتفال** | عداد تفاعلي مع Haptic feedback ونبض ذهبي. نافذة احتفالية (Celebration Dialog) عند إتمام الورد تتيح إعادة الضبط أو العودة. |
| **القبلة** | بوصلة حية (Live Compass) مع أيقونة الكعبة + dialog معايرة |
| **التصميم** | Responsive (Mobile, Tablet, Desktop, Watch)، تدرجات ذهبية/فضية، ثيم فاتح وداكن، إشعارات داخلية فخمة (Luxurious Snackbars). |
| **الواجهة والإعدادات** | صفحة إعدادات مقسمة، وصفحة "عن التطبيق" مع روابط مباشرة (url_launcher). |
| **Desktop** | Window manager, system tray icon, launch at startup, hide-on-close |

---

## 2. هيكل المشروع

```
lib/
├── main.dart                          ← Entry point + platform setup + routing logic
├── app/view/app.dart                  ← MultiBlocProvider (Global cubits)
├── core/
│   ├── theme/                         ← ThemeCubit, ThemeState, ThemeHelper
│   ├── utils/                         ← AppColors, AppTheme, AppPermissions, CalculationMethodHelper
│   ├── widgets/                       ← AppSnackBar, GradientText, GradientIcon, DownloadOverlay
│   ├── services/                      ← LocationService, DesktopWindowService
│   ├── errors/                        ← Exception, Failure classes
│   └── helpers/                       ← Arabic text normalizer
├── features/
│   ├── quran/                         ← Smart Mushaf (QCFv2 lines, SVG headers, Dynamic Fonts, QuranCubit)
│   ├── home/                          ← Prayer times (cubit, widgets, data sources)
│   ├── azkar/                         ← Azkar + Misbaha (clean arch, AzkarTrackerCubit, CelebrationDialog)
│   ├── qibla/                         ← Compass screen
│   ├── notifications/                 ← Notification scheduling (Throttling logic, cancellation tokens)
│   ├── settings/                      ← Modular settings screen, About App, Theme toggles
│   └── main/                          ← Bottom nav + global overlays + screen switching
```

---

## 3. قائمة المهام — الإنجازات (Done)

### ✅ تحديث الإصدار V3.0.0 (القرآن والاستقرار)
- [x] بناء **المصحف الذكي** بمطابقة 100% لمصحف المدينة (15 سطر).
- [x] تطبيق خطوط QCFv2 وتقسيم الآيات ديناميكياً بدلاً من الاعتماد على نصوص عادية.
- [x] دعم الوضع الليلي المنفصل والمخصص للقرآن الكريم (يحول الزخارف لذهبي).
- [x] تصميم واجهة تحميل فخمة (Circular Progress Overlay) لخطوط المصحف.
- [x] إعادة هندسة الإشعارات عبر الـ Main Thread Throttling لحل جميع مشاكل הـ (UI Lag).
- [x] إصلاح جذري لمشكلة الـ Stacked Adhans و Routing Bugs.
- [x] تطوير التتبع الذكي للأذكار ونافذة الإنجاز (Celebration Dialog).
- [x] جدولة تذكيرات أذكار الصباح والمساء أوتوماتيكياً بعد الفجر والعصر.
- [x] إعادة تصميم شاشة الإعدادات بالكامل وإضافة شاشة "عن التطبيق" (About App).
- [x] استبدال `withOpacity()` بـ `withValues()` في التطبيق.

### ✅ الإصدار الأول (v1.0.0)
- [x] بنية التطبيق الأساسية (Clean Architecture)
- [x] الصفحة الرئيسية المتجاوبة (Mobile/Tablet/Desktop/Watch)
- [x] مواقيت الصلاة (GPS + يدوي) والتخزين المحلي
- [x] نظام الإشعارات المحلية مع أصوات مخصصة
- [x] تأخير إقامة قابل للتخصيص لكل صلاة
- [x] بوصلة القبلة الحية
- [x] بحث فوري في الأذكار
- [x] نظام ثيم مزدوج + شريط تنقل سفلي
- [x] دعم Desktop (window manager, tray icon, auto-start)

---

## 4. خطة الإصدار القادم (V3.1.0 TODO)

### 🔴 أولوية عالية (Critical)
- [ ] **حذف `testNotification()`** من `prayer_times_cubit.dart` أو إخفاؤه وراء `kDebugMode`
- [ ] **تقليل حجم ملفات الصوت** — `fajr_azan.mp3` و `adhan.mp3` يجب تقليلهما لـ 10-15 ثانية لتخفيف حجم التطبيق.

### 🟡 أولوية متوسطة (Important)
- [ ] **Error Handling UI** — شاشة خطأ موحدة (بدل SnackBar) مع retry button للاتصال بالإنترنت.
- [ ] **Onboarding screen** — شاشة تعريفية لأول مرة (طلب permissions + شرح الميزات).
- [ ] **Widget Tests** — اختبارات للـ Cubits المعقدة مثل `AzkarTrackerCubit` و `QuranCubit`.

### 🟢 أولوية منخفضة (Nice to Have)
- [ ] **التلاوات الصوتية (Quran Audio Player)** — تشغيل تلاوات لأشهر القراء وتظليل الآية المقروءة.
- [ ] **التفاسير والترجمة (Tafseer & Translation)** — توفير تفسير الميسر وترجمة المعاني للغات أخرى.
- [ ] **Islamic Calendar** — عرض الأيام البيض ومواسم الطاعات في نتيجة تفاعلية.
- [ ] **Habit Tracker** — تتبع الصلاة في وقتها والورد اليومي في رسم بياني.
- [ ] **Multi-language** — إنجليزي + فرنسي + أوردو + تركي.

---

## 5. الحزم المستخدمة (Dependencies)

| الحزمة | الغرض |
|---|---|
| `flutter_bloc` / `bloc` | إدارة الحالة |
| `adhan` | حساب مواقيت الصلاة |
| `geolocator` + `geocoding` | الموقع الجغرافي |
| `shared_preferences` | تخزين محلي وتفضيلات المستخدم |
| `flutter_local_notifications` + `timezone` | إشعارات مجدولة صامتة وصوتية |
| `alarm` | الأذان الطويل والإشعارات الحرجة |
| `flutter_qiblah` | بوصلة القبلة |
| `google_nav_bar` | شريط تنقل سفلي |
| `google_fonts` | خطوط النظام العادية |
| `hijri` | التقويم الهجري |
| `lottie` | الأنميشنز (Splash/Animations) |
| `dartz` | Either type (Clean Architecture) |
| `intl` | تنسيق التاريخ والوقت |
| `window_manager` + `tray_manager` + `launch_at_startup` | دعم Desktop |
| `country_state_city_picker` | اختيار الموقع يدوياً |
| `wakelock_plus` | منع قفل الشاشة أثناء الأذان وقراءة القرآن |
| `permission_handler` | إدارة الصلاحيات بشكل آمن |
| `url_launcher` | فتح الروابط الخارجية (واتساب / موقع الويب) في صفحة About |
| `package_info_plus` | جلب رقم الإصدار برمجياً |
| `archive` + `path_provider` | فك ضغط وحفظ ملفات الـ ZIP للخطوط دینامیکیاً |
