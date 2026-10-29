# Hafiz Al-Ahd - Release Notes

## Version 3.1.1 (Advanced Prayer Calculations & Customization Update)

يقدم هذا التحديث تحكماً شاملاً ومرونة غير مسبوقة في ضبط وحساب مواقيت الصلاة بدقة فائقة لتلائم أي منطقة في العالم، مع ترقية شاملة لمحرك الحساب الفلكي.

### ⚙️ إعدادات فلكية ومواقيت متقدمة (Advanced Prayer Settings)
* **تعديل دقائق الصلوات (الإزاحة)**: إمكانية زيادة أو إنقاص الوقت (-30 إلى +30 دقيقة) لكل صلاة بشكل مستقل لضبط التوقيت بدقة تامة مع المسجد المحلي.
* **زوايا الفجر والعشاء المخصصة**: خيار جديد لإدخال زوايا فلكية مخصصة لحساب الفجر والعشاء يدوياً بدلاً من الاعتماد على طرق الحساب المسبقة.
* **إرشادات وتنبيهات السفر**: إضافة تنبيهات إرشادية واضحة لتذكير المستخدم بتحديث الإعدادات المخصصة أو الرجوع للوضع التلقائي عند الانتقال لمدينة أو دولة أخرى.

### 📍 تحديد موقع الإقامة يدويًا (Manual Location)
* إمكانية اختيار الدولة والمدينة يدوياً في أي وقت من شاشة الإعدادات دون الحاجة لتشغيل الـ GPS، مع سهولة الرجوع لزر "التحديد التلقائي بالـ GPS" بضغطة واحدة.

### 🕋 فصل شامل لطرق الحساب ودول الخليج
* فصل طرق الحساب الخاصة بدول الخليج لاتباع روزنامة كل دولة بدقة:
  * **السعودية**: تقويم أم القرى (مكة المكرمة).
  * **الكويت**: وزارة الأوقاف والشؤون الإسلامية الكويتية.
  * **قطر**: التقويم القطري المعتمد.
  * **الإمارات / عمان / البحرين**: تقويم دبي.
* دعم طرق الحساب الدولية الإضافية:
  * رئاسة الشؤون الدينية بتركيا (Diyanet).
  * مجلس الشؤون الإسلامية بسنغافورة وماليزيا (MUIS).
  * لجنة تحري الهلال (Moon Sighting Committee).
  * معهد الجيوفيزياء بجامعة طهران.
* **إظهار الطريقة التلقائية المكتشفة**: عرض اسم الهيئة أو الطريقة المعتمدة بين قوسين في واجهة الإعدادات لتسهيل المتابعة والتحقق من الطريقة المتبعة.

### 🇲🇦 دعم رسمي دقيق لمواقيت المملكة المغربية
* تطبيق دقائق الاحتياط الشرعية والتضاريسية المعتمدة رسمياً لدى وزارة الأوقاف والشؤون الإسلامية بالمغرب مباشرة من المنبع الفلكي، ليتطابق الأذان في التطبيق بنسبة 100% مع الروزنامة الرسمية للوزارة.
* ضبط التعامل الذكي مع التوقيت الصيفي وتوقيت غرينتش (GMT) الخاص بالمغرب.

### ⚡ تحديث فوري وشامل (Instant Synchronization)
* تطبيق أي تعديل في المواقيت أو الموقع فورياً وبشكل تلقائي على:
  * واجهة الشاشة الرئيسية وعداد الصلاة القادمة.
  * الإشعار الثابت (Sticky Notification).
  * ويدجات الشاشة الخارجية (Home Screen Widgets).
  * منبهات وإشعارات الأذان المجدولة للأسبوع كاملاً في الخلفية دون الحاجة لإعادة فتح التطبيق.

### 🛠️ ترقية البنية التحتية البرمجية (Under the Hood)
* الانتقال الكامل إلى مكتبة الحساب الفلكي الحديثة **`adhan_dart`**، مما يعزز دقة وسرعة الحسابات الفلكية ويوفر توافقاً طويل الأمد.
* تحسينات في الأداء العام وثبات واستقرار منبهات الأذان.

---

## Version 3.0.0 (Major Quran & Stability Update)

يعد هذا التحديث هو الأضخم في تاريخ التطبيق حتى الآن (Build 8)، حيث يقدم "المصحف الذكي"، وتجديد شامل لنظام الإشعارات، ونظام تتبع ذكي جديد للأذكار.

### 📖 القرآن الكريم (Smart Mushaf)
* **المطابقة التامة**: تجربة قراءة مطابقة 100% لمصحف المدينة المنورة الورقي (15 سطراً في كل صفحة).
* **الذكاء البصري (QCFv2)**: استخدام خطوط QCFv2 لرسم الآيات والزخارف، والبسملة، وترويسات السور بدقة متناهية، دون أي تشوه عند التكبير.
* **التحميل الذكي**: تقليل مساحة التطبيق الأولية عن طريق سحب وتحميل الخطوط والملحقات ديناميكياً عند الطلب في الخلفية.
* **الوضع الليلي المخصص**: ثيم ليلي خاص (Dedicated Dark Mode) لشاشة القرآن، يحول الزخارف والآيات لألوان تريح العين في الظلام وتبرز جماليات المصحف.

### 📿 الأذكار والمسبحة (Azkar & Misbaha)
* **التتبع الذكي**: نظام تتبع يربط بين قائمة الأذكار والمسبحة، مع إعادة ضبط يومية تلقائية لأذكار الصباح والمساء.
* **جدولة الأذكار**: جدولة تنبيهات لأذكار الصباح (بعد الفجر) وأذكار المساء (بعد العصر).
* **نافذة الاحتفال (Celebration Dialog)**: نافذة تفاعلية تظهر عند إتمام وردك اليومي من الأذكار بنجاح.

### ⚙️ الإشعارات والأذان (Notifications Engine)
* **نظام الجدولة الجديد (Throttling)**: إعادة هندسة محرك الجدولة ليعمل بسلاسة تامة، مما يمنع تجمد التطبيق (UI Lag) أثناء حساب وجدولة المواقيت للأيام القادمة.
* **منع التراكم (Stacked Adhans)**: نظام حماية ثلاثي الأبعاد لمنع تشغيل الأذانات المتراكمة إذا كان الهاتف مغلقاً لفترة طويلة.
* **إصلاحات التوجيه (Routing Fixes)**: إصلاح مشاكل فتح التطبيق من الإشعارات المستمرة (Sticky Notifications) وإشعارات الأذكار ليوجهك مباشرة للصفحة المطلوبة.

### 🎨 واجهة المستخدم (UI & Settings)
* **إعدادات جديدة كلياً**: إعادة تصميم صفحة الإعدادات لتكون مقسمة بشكل منطقي وسهل الاستخدام.
* **عن التطبيق (About App)**: صفحة تعريفية جديدة تحتوي على معلومات الإصدار، وروابط التواصل المباشر مع المطور ومشاركة التطبيق.
* **التنبيهات الفخمة (Luxurious Snackbars)**: استبدال التنبيهات السفلية برسائل عائمة أنيقة، متدرجة الألوان، وبإطار مذهب.

---

## Version 1.1.1 (Enhancement Update)

This update introduces a much-requested feature to maintain accurate prayer times in regions with complex or inconsistent Daylight Saving Time (DST) changes.

### 🎉 New Features

* **Manual DST Toggle**: Added a "التوقيت الصيفي" (Daylight Saving Time) option in settings. You can now manually apply a +60 minute offset if your device's operating system hasn't updated to the summer time automatically.
* **Safety Warning System**: To prevent "Double DST" bugs, the app warns users before enabling the manual toggle, reminding them to only activate it if the device natively failed to update its timezone.
* **Architecture Enhancements**: Rewrote the Time Calculation flow to use a "Single Point of Truth" architecture. When the DST offset is applied, it globally and instantly synchronizes across:
  * Application UI displays
  * Background Push Notifications
  * Persistent Sticky Countdown Notifications
  * Offline Native Android Alarm Scheduling
  * Android Home Screen Widgets

---

## Version 1.1.0 (Major Update & Enhancements)

In this update, the app has been completely overhauled to deliver a faster and more stable experience:

**New Adhan Experience:** A beautifully redesigned, interactive Adhan screen featuring a smooth swipe-to-stop gesture.

**Optimized Performance:** Significant improvements in overall speed along with noticeably reduced battery consumption.

**Smart Notifications:** Resolved overlapping notification issues using an intelligent background scheduling system.

⏱️ **Auto-Close Timer:** Introduced a smart auto-close feature for the Adhan screen to conserve battery and screen life.

---

## Version 1.0.0 (Initial Beta Release)

Welcome to the beta release of **Hafiz Al-Ahd**! This update brings essential features for prayer times, notifications, Azkar, and cross-platform usability. 

### 🎉 New Features

* **Prayer Times & Qibla Direction**: Get accurate, real-time prayer calculations worldwide. Integrates Qibla direction capabilities directly into the app.
* **Smart Prayer Notifications**: 
  * Full support for Adhan and Iqama alerts across devices.
  * Custom Fajr prayer sounds enabled for Android devices to distinguish the early morning call.
* **Azkar & Supplications Library**: Read daily morning, evening, and various other authentic Azkar easily with a streamlined reading tracker.
* **Offline Caching**: Most functionalities, including Azkar and previously loaded prayer times, remain accessible without an active internet connection.
* **Manual Location Selection**: Users can now manually search and pick their preferred location for prayer calculations when automatic GPS localization is unavailable or undesired.
* **Multi-Platform Support**: Enjoy a synchronized experience across Android, iOS, and Windows.
  * *Windows-Specific Additions*: System tray support, auto-launch at startup, and window state management.

### 🛠 Improvements & Fixes

* Resolved invalid constant value errors in the core `azkar_data` definitions.
* Refactored `PrayerTimesCubit` to optimize performance and prevent duplicate/stuck background notifications.
* Redesigned user interface utilizing elegant Arabic typography (Thuluth and Kufi fonts). 
* Implemented proper permission handling (Location, Notifications, Wake Lock) avoiding runtime crashes on newer Android/iOS versions.

---

### Known Issues & Upcoming Features
* The team is actively looking into expanding translation support and more audio recitations for Azkar.
* Continuous optimizations to background alarm handling on highly-restricted Android skins.

Thank you for choosing Hafiz Al-Ahd. We welcome your feedback!
