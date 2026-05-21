# توثيق تحديثات نظام الأذان والصلاحيات (مايو 2026)

تم إعداد هذا المستند كمرجع شامل لكل المشاكل البرمجية التي واجهناها خلال الفترة الأخيرة، والتعديلات التي تمت على الكود لحلها بشكل جذري. يمكنك العودة إلى هذا الملف لفهم المنطق وراء كل قرار برمجي تم اتخاذه.

---

## 1. الإغلاق التلقائي لشاشة الأذان بطريقة ديناميكية
**الملف:** `lib/features/notifications/presentation/screens/adhan_screen.dart`

### المشكلة (The Problem):
باكيدج `alarm` تقوم بإيقاف تشغيل الصوت تلقائياً عند انتهاء الملف (بسبب `loopAudio: false`)، لكنها **لا تقوم بتغيير حالة المنبه** من النظام (يظل `isRinging` يساوي `true`).
بسبب ذلك، التايمر الخاص بـ `_checkExternalStopTimer` لم يكن يكتشف انتهاء الصوت، وكانت الشاشة تظل معلقة حتى ينتهي التايمر الاحتياطي الثابت (الذي كان محدداً بـ 6 دقائق).
الطرق القديمة لجلب مدة الصوت كانت إما تتسبب في تجميد الشاشة (Hanging) أو تعتمد على قيم ثابتة (Hardcoding).

### الحل والكود (The Solution & Code):
تمت كتابة دالة `_setupDynamicCloseTimer` جديدة تستخدم `AudioPlayer` لاستخراج المدة الزمنية الحقيقية للملف بشكل خفي:

```dart
// إزالة 'assets/' لأن audioplayers يفهمها ضمناً
if (relativePath.startsWith('assets/')) {
  relativePath = relativePath.substring(7); 
}
await player.setSource(AssetSource(relativePath));

// استخراج الطول مع وضع Timeout لحماية التطبيق من التجميد
Duration? duration = await player.getDuration();
if (duration == null) {
  try {
    duration = await player.onDurationChanged.first.timeout(const Duration(seconds: 2));
  } catch (_) {}
}

// تشغيل صامت للحظة لإجبار بعض أجهزة أندرويد على قراءة الطول
if (duration == null) {
  await player.setVolume(0.0);
  await player.play(AssetSource(relativePath));
  await Future.delayed(const Duration(milliseconds: 200));
  duration = await player.getDuration();
  await player.stop();
}

// ضبط التايمر مع إضافة 5 ثواني Margin
final closeDuration = duration + const Duration(seconds: 5);
_autoCloseTimer = Timer(closeDuration, () {
  if (mounted) _closeScreen();
});
```

> [!TIP]
> **السبب:** هذا الحل جذري وديناميكي 100%. حتى لو قمت لاحقاً بتغيير ملفات الأذان بملفات أطول أو أقصر، التطبيق سيقرأ مدتها تلقائياً ويقفل الشاشة في الوقت المناسب تماماً.

---

## 2. منع ظهور شريط مستوى الصوت (Volume Bar) إجبارياً
**الملف:** `lib/features/notifications/data/repos/notification_repository_impl.dart`

### المشكلة:
شاشة الأذان كانت تُبقي شريط مستوى الصوت الخاص بالنظام ظاهراً طوال فترة الأذان، مما يزعج المستخدم.

### الحل والكود:
```diff
- volumeEnforced: volume != null,
+ volumeEnforced: false, // 👈 لمنع شريط الصوت الإجباري
```

> [!NOTE]
> **السبب:** الخاصية `volumeEnforced` كانت تجعل باكيدج `alarm` تحجز متحكم الصوت (AudioManager) بالقوة وتراقب أي محاولة لخفض الصوت، مما يستدعي واجهة النظام (System UI) بشكل مستمر. إيقافها يضمن تشغيل الصوت بنجاح مرة واحدة دون تجميد شريط الصوت على الشاشة.

---

## 3. معالجة فتح شاشة الأذان مرتين فوق بعضها (Duplicate Pushes)
**الملف:** `lib/main.dart`

### المشكلة:
عند تشغيل الأذان والموبايل مغلق (Terminated State)، كانت باكيدج الأذان تنشئ Stream يبث حالة تشغيل الأذان.
في نفس الوقت، الكود في `main` كان يتفقد (بشكل يدوي) ما إذا كان هناك أذان يعمل. هذا أدى إلى استدعاء أمر `navigatorKey.currentState?.push` **مرتين في نفس الثانية**، مما ينتج عنه شاشتين متطابقتين.

### الحل والكود:
تم إضافة (Lock Flag) لمنع الاستدعاء المزدوج:

```dart
bool _isAdhanScreenActive = false; // 👈 علم لمنع فتح الشاشة مرتين

void _openAdhanScreen({required String payload, int? notificationId, String? prayerName}) {
  if (_isAdhanScreenActive) return; // الرفض المباشر لو الشاشة مفتوحة أصلاً
  _isAdhanScreenActive = true;
  
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => AdhanScreen(...)),
  ).then((_) {
    // إرجاع العلم لـ false عند قفل الشاشة للسماح بفتحها مرة أخرى للأذان القادم
    _isAdhanScreenActive = false; 
  });
}
```

> [!IMPORTANT]
> **السبب:** التنسيق بين المستمعات المتعددة (Listeners) في الـ Streams صعب لأنها تطلق أحداثها في أوقات متقاربة جداً (Race Condition). استخدام متغیر (Lock) يحل هذه المعضلة من الجذور.

---

## 4. نظام الصلاحيات الذكي للمستخدمين القدامى (Smart Onboarding)
**الملفات:** `onboarding_screen.dart` و `onboarding_cubit.dart`

### المشكلة:
تمت إضافة صلاحيات جديدة (استثناء البطارية والتشغيل التلقائي). المستخدمون القدامى كانت لديهم قيمة `isOnboardingComplete = true` في قواعد البيانات المحلية، وبالتالي لم يكونوا ليروا الشاشات الجديدة أبداً. وإذا قمنا بتغيير القيمة لـ `false`، سيضطرون لإعادة كل الخطوات (مثل الموقع والإشعارات).

### الحل والكود:
1. **في الـ Cubit:** تحويل الاستعلام ليتفقد حالة كل صلاحية على حدة بدلاً من التحقق من قيمة عامة واحدة.
```dart
static Future<bool> isOnboardingComplete() async {
  // تفقد كل صلاحية مطلوبة
  for (final type in requiredTypes) {
    if (!(prefs.getBool('onboarding_step_${type.name}') ?? false)) {
      return false; // يطالبه بفتح شاشة الـ Onboarding
    }
  }
  return true;
}
```

2. **في شاشة الـ Onboarding:** فلترة الصفحات لعرض الناقص منها فقط.
```dart
final List<_OnboardingPageData> pendingPages = [];
for (var page in basePages) {
  if (!(prefs.getBool('onboarding_step_${page.permissionType.name}') ?? false)) {
    pendingPages.add(page); // 👈 إضافة الشاشات الجديدة غير المكتملة فقط
  }
}
setState(() { _pages = pendingPages; });
```

> [!TIP]
> **السبب:** هذا التصميم الذكي يسمح للتطبيق بالترقية التلقائية. إذا أضفت خطوة صلاحيات سابعة غداً، سيتم عرض الشاشة السابعة فقط للمستخدمين الحاليين، ثم يعودون للشاشة الرئيسية مباشرة.

---

## 5. حفظ حالة الـ Tabs (State Preservation)
**الملف:** `lib/features/home/presentation/screens/home_screen.dart`

### المشكلة:
ظهور Warning يخبرك بأن دالة `build` في الـ `AutomaticKeepAliveClientMixin` لم تقم باستدعاء النسخة الأصلية `super.build(context)`. عدم استدعائها يتسبب في تدمير حالة الشاشة (البيانات، مؤشرات التمرير) عند الانتقال بين الـ Tabs.

### الحل والكود:
```diff
  @override
  Widget build(BuildContext context) {
+   super.build(context); // 👈 ضروري لضمان عمل KeepAlive
    return Scaffold(...);
  }
```

> [!NOTE]
> **السبب:** بناءً على دورة حياة Flutter (Lifecycle)، الـ Mixin يعتمد كلياً على أمر `super.build` لتسجيل هذه الصفحة كصفحة يجب الاحتفاظ بها في الذاكرة حتى لو لم تكن ظاهرة للمستخدم.
