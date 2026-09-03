# توثيق شامل وخطة تطوير تطبيق "حافظ العهد" (Hafiz Al-Ahd)

## 1. التوثيق الحالي للتطبيق (Current Architecture & Features)

*   **الهدف الأساسي**: تطبيق إسلامي شامل يعرض مواقيت الصلاة، الأذكار، القبلة، مع إشعارات صوتية مخصصة وتصميم فاخر.
*   **الإصدار الحالي**: `v1.0.0+1`
*   **البنية التقنية (Tech Stack)**:
    *   **إطار العمل**: Flutter (SDK ^3.10.4)
    *   **إدارة الحالة**: `flutter_bloc` (Cubit pattern)
    *   **البنية**: Clean Architecture لكل feature (data → domain → presentation)
    *   **الثيم**: نظام ثيم مزدوج (فاتح/داكن) مع ThemeCubit + ThemeHelper extension + SharedPreferences persistence
    *   **المنصات المدعومة**: Android, iOS, Windows, Linux, macOS

### المميزات المنجزة

| الميزة | التفاصيل |
|---|---|
| **مواقيت الصلاة** | عرض الصلوات الخمس + الشروق بناءً على GPS أو موقع يدوي، تخزين محلي (cache)، 3 مراحل بصرية للكارت (عادي → قبل نص ساعة → إقامة) |
| **الإشعارات** | جدولة لـ 6 أيام قادمة، أصوات مخصصة (أذان عادي، أذان فجر، صوت إقامة)، دعم boot receiver لإعادة الجدولة |
| **تأخير الإقامة** | إعداد مستقل لكل صلاة (5-30 دقيقة) محفوظ في SharedPreferences |
| **الأذكار** | أذكار الصباح/المساء، بعد الصلاة وغيرها من `azkar.json`. نظام تتبع ذكي مشترك مع المسبحة، يعيد تصفير الأذكار العادية عند الخروج ويحفظ الأذكار اليومية حتى منتصف الليل |
| **المسبحة** | عداد تفاعلي مع Haptic feedback ونبض ذهبي. يفتح تلقائياً على الذكر غير المكتمل مع شريط سفلي مختصر. تظهر نافذة احتفالية (Celebration Dialog) عند إتمام الأذكار |
| **بحث الأذكار** | بحث فوري بتنظيف نص عربي (بدون تشكيل) |
| **القبلة** | بوصلة حية (Live Compass) مع أيقونة الكعبة + dialog معايرة |
| **التصميم** | Responsive (Mobile, Tablet, Desktop, Watch)، تدرجات ذهبية/فضية، ثيم فاتح وداكن |
| **الثيم** | Dark (AMOLED أسود)، Light (كريمي ذهبي دافئ)، بتبرسيست في SharedPreferences |
| **Desktop** | Window manager, system tray icon, launch at startup, hide-on-close |
| **شريط التنقل** | `google_nav_bar` مع gradient ذهبي وتأثيرات haptic |

---

## 2. هيكل المشروع

```
lib/
├── main.dart                          ← Entry point + platform setup
├── app/view/app.dart                  ← MultiBlocProvider (4 cubits)
├── core/
│   ├── theme/                         ← ThemeCubit, ThemeState, ThemeHelper
│   ├── utils/                         ← AppColors, AppTheme, AppPermissions, CalculationMethodHelper
│   ├── widgets/                       ← GradientText, GradientIcon
│   ├── services/                      ← LocationService, DesktopWindowService
│   ├── errors/                        ← Exception, Failure classes
│   └── helpers/                       ← Arabic text normalizer
├── features/
│   ├── home/                          ← Prayer times (cubit, widgets, data sources)
│   ├── azkar/                         ← Azkar + Misbaha (clean arch, AzkarTrackerCubit)
│   ├── qibla/                         ← Compass screen
│   ├── notifications/                 ← Notification scheduling (repos, use cases)
│   ├── settings/                      ← Iqama delays + theme toggle
│   └── main/                          ← Bottom nav + screen switching
```

---

## 3. قائمة المهام — الإنجازات (Done)

### ✅ الإصدار الأول (v1.0.0)
- [x] بنية التطبيق الأساسية (Clean Architecture)
- [x] الصفحة الرئيسية المتجاوبة (Mobile/Tablet/Desktop/Watch)
- [x] مواقيت الصلاة بناءً على الموقع الجغرافي (GPS + يدوي)
- [x] التخزين المحلي (Caching) للموقع ومواقيت الصلاة
- [x] التاريخ الهجري والميلادي
- [x] نظام الإشعارات المحلية مع أصوات مخصصة (أذان عادي / فجر / إقامة)
- [x] تأخير إقامة قابل للتخصيص لكل صلاة
- [x] بوصلة القبلة الحية مع dialog المعايرة
- [x] الأذكار اليومية (JSON data source + Clean Architecture)
- [x] بحث فوري في الأذكار (مع تنظيف النص العربي)
- [x] المسبحة التفاعلية (haptic + pulse animation)
- [x] نظام ثيم مزدوج (فاتح كريمي / داكن AMOLED) مع persistence
- [x] `ThemeHelper` extension لألوان theme-aware في كل الشاشات
- [x] شريط تنقل سفلي مع gradient ذهبي
- [x] دعم Desktop (window manager, tray icon, auto-start)
- [x] أيقونات التطبيق + Splash screens

---

## 4. خطة الإصدار القادم (v1.1.0 TODO)

### 🔴 أولوية عالية (Critical)
- [ ] **حذف `testNotification()`** من `prayer_times_cubit.dart` أو إخفاؤه ورا `kDebugMode`
- [ ] **توحيد مجلدات الـ error** — حذف `core/error/` ونقل محتواه لـ `core/errors/` + إصلاح اسم `faluire.dart` → `failure.dart`
- [ ] **تقليل حجم ملفات الصوت** — `fajr_azan.mp3` (2.3MB) و `adhan.mp3` (2MB) لازم يتقصروا لـ 10-15 ثانية (< 1MB)
- [ ] **استبدال `withOpacity()` بـ `withValues()`** في كل الملفات (48 موقع) — deprecated في SDK الجديد

### 🟡 أولوية متوسطة (Important)
- [ ] **حفظ عداد المسبحة** — لما اليوزر يخرج ويرجع العداد يفضل زي ما هو (SharedPreferences أو Hive)
- [ ] **Singleton لـ `NotificationRepositoryImpl`** — حالياً بيتعمله instance مرتين في `app.dart`
- [ ] **إزالة `late SharedPreferences pref` global** — تحويلها لـ dependency injection
- [ ] **إضافة Error Handling UI** — شاشة خطأ موحدة (بدل SnackBar) مع retry button
- [ ] **Onboarding screen** — شاشة تعريفية لأول مرة (طلب permissions + شرح الميزات)
- [ ] **Widget Tests** — على الأقل للـ Cubits الأربعة

### 🟢 أولوية منخفضة (Nice to Have)
- [ ] **القرآن الكريم** — مصحف كامل (feature `quran/` موجود كـ placeholder)
- [ ] **تذكير بيومي** — تنبيه بأذكار الصباح والمساء
- [ ] **Islamic Calendar** — عرض الأيام البيض ومواسم الطاعات
- [ ] **Habit Tracker** — تتبع الصلاة في وقتها والورد اليومي
- [ ] **Multi-language** — إنجليزي + فرنسي + أوردو + تركي
- [ ] **Quran Audio Player** — تلاوات لأشهر القراء
- [ ] **حذف الـ quran feature placeholder** أو تطويره

---

## 5. الحزم المستخدمة (Dependencies)

| الحزمة | الغرض |
|---|---|
| `flutter_bloc` / `bloc` | إدارة الحالة |
| `adhan` | حساب مواقيت الصلاة |
| `geolocator` + `geocoding` | الموقع الجغرافي |
| `shared_preferences` | تخزين محلي |
| `flutter_local_notifications` + `timezone` | إشعارات مجدولة |
| `flutter_qiblah` | بوصلة القبلة |
| `google_nav_bar` | شريط تنقل |
| `google_fonts` | خطوط |
| `hijri` | التقويم الهجري |
| `lottie` | أنيميشن |
| `dartz` | Either type |
| `intl` | تنسيق التاريخ والوقت |
| `window_manager` + `tray_manager` + `launch_at_startup` | Desktop |
| `country_state_city_picker` | اختيار الموقع يدوياً |
| `wakelock_plus` | إبقاء الشاشة |
| `permission_handler` | إدارة الصلاحيات |
