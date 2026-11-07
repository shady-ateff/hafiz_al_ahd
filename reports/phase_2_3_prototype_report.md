# تقرير الإنجاز الهندسي — المرحلة 2.3 (Phase 2.3 Report)
## النموذج الأولي التفاعلي لسطر واحد والتحقق البصري (Single-Line Interactive Quran Prototype)

---

### 📌 الفهرس
1. [الهدف ونطاق التجربة](#1-الهدف-ونطاق-التجربة)
2. [توصيف إعدادات الرندرة الأصلية بدقة](#2-توصيف-إعدادات-الرندرة-الأصلية-بدقة)
3. [بنية وتصميم النموذج الأولي (Prototype Architecture)](#3-بنية-وتصميم-النموذج-الأولي-prototype-architecture)
4. [أدلة المقارنة البصرية وتطابق البايتات (Visual Fidelity & Byte-for-Byte Match)](#4-أدلة-المقارنة-البصرية-وتطابق-البايتات-visual-fidelity--byte-for-byte-match)
5. [نتائج اختبارات حلبة الإيماءات ودورة حياة التعرف (Gesture Behavior & Lifecycle)](#5-نتائج-اختبارات-حلبة-الإيماءات-ودورة-حياة-التعرف-gesture-behavior--lifecycle)
6. [الملفات التي تم إنشاؤها وفحصها](#6-الملفات-التي-تم-إنشاؤها-وفحصها)
7. [القيود والتوصية الهندسية النهائية للمرحلة 2.4](#7-القيود-والتوصية-الهندسية-النهائية-للمرحلة-24)

---

## 1. الهدف ونطاق التجربة

الهدف الجوهري من المرحلة 2.3 هو **إثبات إمكانية استبدال ويدجت `Text` بويدجت `RichText` و `TextSpan` التفاعلية على مستوى الكلمة دون أدنى تغيير في المظهر البصري لمصحف المدينة النبوية (QCFv2)**.

تم حصر التجربة في سطر فيزيائي واحد مستقل (Isolated Prototype)، دون المساس بأي من شاشات التطبيق أو محرك العرض الرئيسي، لاختبار:
* Arabic shaping و Ligatures.
* المسافات بين الكلمات (`wordSpacing`).
* المسافات بين الحروف (`letterSpacing`).
* رموز نهايات الآيات المركبة داخل نفس الكلمة (مثل `ﱄ ﱅ`).
* أبعاد السطر والمطابقة بالبيكسل وبالبايت (Byte-for-byte parity).

---

## 2. توصيف إعدادات الرندرة الأصلية بدقة

تم فحص كود [`QuranPageWidget`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/presentation/widgets/quran_page_widget.dart) وتوثيق كافة المعاملات الطبوغرافية التي تتحكم في مظهر السطر الأصلي:

| المعامل | القيمة الحالية المعتمدة | التأثير الهندسي |
| :--- | :---: | :--- |
| **Font Family** | `fontFamily` (e.g. `QCF2001`, `QCF2604`) | خط الصفحة المخصص من مجمع الملك فهد |
| **Font Size** | `40.0` | الحجم الأساسي لرموز الخط في شبكة الـ 700 بكسل |
| **Font Weight** | `FontWeight.normal` | الوزن القياسي لخط المصحف |
| **Text Direction** | `TextDirection.rtl` | الكتابة من اليمين إلى اليسار |
| **Text Align** | `TextAlign.center` | توسيط السطر القرآني في الصفحة |
| **Word Spacing** | `-3.5` | تقليص المسافة بين الكلمات لضبط سطر المصحف الموزون |
| **Letter Spacing** | `-0.5` | تقارب الحروف المنسجمة في خط النسخ |
| **Line Height** | `dynamicHeight` (1.45 to 3.0) | التباعد الرأسي المتكيف مع شاشات الهواتف |
| **Layout Scaling** | `FittedBox(fit: BoxFit.scaleDown)` | تصغير السطر فقط إذا تجاوز 700 بكسل، دون تكبيره |
| **Container Width** | `SizedBox(width: 700)` | العرض المعياري لصفحة المصحف قبل التحجيم الكلي |

---

## 3. بنية وتصميم النموذج الأولي (Prototype Architecture)

تم بناء الويدجت المعزولة [`QuranInteractiveLinePrototype`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/presentation/widgets/quran_interactive_line_prototype.dart) كـ `StatefulWidget`:

```dart
class QuranInteractiveLinePrototype extends StatefulWidget {
  final QuranLineMapping line;
  final String fontFamily;
  final double dynamicHeight;
  final Color textColor;
  final ValueChanged<QuranWord>? onWordTapped;
  ...
}
```

### آلية البناء الداخلي:
1. استقبال كائن `QuranLineMapping` الحقيقي من المستودع.
2. لكل كلمة في `line.words`:
   - يتم إنشاء `TextSpan` يحتوي على `word.qcfText` ومربوط بـ `TapGestureRecognizer` مخصص للكلمة.
   - بين كل كلمتين، يتم إدراج `const TextSpan(text: ' ')` بمسافة فارغة **بدون أي Recognizer** (لتجاهل النقر على الفراغات).
3. تغليف المقاطع في `RichText` بنفس معاملات الـ `TextStyle` الأصلي (`fontSize: 40`, `wordSpacing: -3.5`, `letterSpacing: -0.5`, `height: dynamicHeight`).
4. وضع الـ `RichText` داخل نفس الـ `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.center)`.

---

## 4. أدلة المقارنة البصرية وتطابق البايتات (Visual Fidelity & Byte-for-Byte Match)

أجري اختبار مقارنة رندرة دقيق عبر محرك اختبارات فلاتر الرسومي بتوليد صورتي PNG متطابقتين تحت نفس الشروط المعيارية:
* **الصورة الأولى (قبل):** السطر النصي التقليدي `ExistingQuranLineRenderer` عبر `Text(line.text)`.
* **الصورة الثانية (بعد):** سطر النموذج الأولي `QuranInteractiveLinePrototype` عبر `RichText` و `TextSpan`.

### الصور المولدة في مجلد `reports/screenshots/`:
* الصورة قبل: [`reports/screenshots/prototype_line_before.png`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/reports/screenshots/prototype_line_before.png)
* الصورة بعد: [`reports/screenshots/prototype_line_after.png`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/reports/screenshots/prototype_line_after.png)

### نتيجة الفحص الميداني:
```text
Before bytes: 1293 | After bytes: 1293
Byte-for-byte identical: true
Rendered Size Deviation: 0.000 pixels (Width and Height)
```

> [!IMPORTANT]
> **التطابق تام بنسبة 100% على مستوى البايت الواحد (Byte-for-byte identical):**
> حجم كلا الملفين **1,293 بايت** ومحتواهما متطابق بصرياً وثنائياً.
> لا يوجد أي انحراف في تشكيل الحروف العربية، ولا أي تغير في محاذاة الخط، ولا كسر للمسافات، ولا أي اهتزاز بكسل واحد (Zero Layout Shift).

---

## 5. نتائج اختبارات حلبة الإيماءات ودورة حياة التعرف (Gesture Behavior & Lifecycle)

تم إخضاع النموذج الأولي لاختبارات صارمة في ملف [`test/quran_interactive_line_prototype_test.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test/quran_interactive_line_prototype_test.dart):

```text
flutter test test/quran_interactive_line_prototype_test.dart
00:03 +5: All tests passed!
```

### 1. تحديد الكلمات المنفردة بدقة (Word-level Tap):
* النقر على كلمة `"قُلْ"` (الموضع `112:1:1`) أعاد كائن الكلمة الصحيح.
* النقر على كلمة `"أَحَدٌ"` (الموضع `112:1:4`) أعاد الكلمة مع رمز نهاية الآية الملحق بها (`ﱄ ﱅ`).
* النقر على كلمات الآية الثانية على نفس السطر (`112:2:1`) أعاد الكلمة المناسبة دون أي خلط.

### 2. سلوك الفراغات (Whitespace Taps):
* النقر على المسافات الفاصلة بين الكلمات لا يطلق أي استدعاء لكولباك الكلمة.

### 3. سلوك حلبة الإيماءات مع ملء الشاشة (Gesture Arena Resolution):
* تم تغليف السطر بـ `GestureDetector` خارجي يحاكي تبديل وضع ملء الشاشة:
  - عند النقر على كلمة قرآنية: يفوز الـ `TapGestureRecognizer` الداخلي للكلمة ويتم استدعاء `onWordTapped`، **ولا يتم تفعيل كولباك الـ Parent**.
  - عند النقر في المساحات الفارغة حول السطر أو في الهامش: يفوز الـ `GestureDetector` الخارجي ويتم تفعيل تبديل ملء الشاشة.

### 4. دورة حياة الـ Recognizers ومنع تسريب الذاكرة (Leak Prevention):
* يتم تهيئة الـ Recognizers في `initState`.
* في دالة `didUpdateWidget`: لا يتم إعادة بناء الـ Recognizers إذا لم تتغير قائمة الكلمات (مثلاً عند تغير اللون أو الثيم فقط).
* في دالة `dispose`: يتم استدعاء `recognizer.dispose()` لكل كائن في القائمة وتفريغها، مما يمنع أي تسريب في الذاكرة أثناء تقليب الصفحات.

---

## 6. الملفات التي تم إنشاؤها وفحصها

* **الملفات التي تم إنشاؤها:**
  1. [`lib/features/quran/presentation/widgets/quran_interactive_line_prototype.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/presentation/widgets/quran_interactive_line_prototype.dart)
  2. [`test/quran_interactive_line_prototype_test.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test/quran_interactive_line_prototype_test.dart)
  3. [`reports/screenshots/prototype_line_before.png`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/reports/screenshots/prototype_line_before.png)
  4. [`reports/screenshots/prototype_line_after.png`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/reports/screenshots/prototype_line_after.png)
  5. [`reports/phase_2_3_prototype_report.md`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/reports/phase_2_3_prototype_report.md)
* **الملفات المعدلة:** **صفر** (لم يُعدل أي ملف في `QuranPageWidget` أو `QuranScreen` أو `QuranCubit`).

---

## 7. القيود والتوصية الهندسية النهائية للمرحلة 2.4

### القيود الحالية (Known Limitations):
* هذا النموذج الأولي اختبر الرندرة التفاعلية لسطر واحد معزول مع رصد نقر الكلمات، ولم يقم بتطبيق تظليل الآية الكاملة أو ربطها بالـ `QuranCubit`.
* التظليل الكامل للآيات وربط شريط الأدوات مؤجل للمرحلتين 2.4 و 2.5.

### التوصية الهندسية الصريحة (Definitive Recommendation):
> [!TIP]
> **التوصية: الاعتماد الفوري لـ `RichText` والانتقال للمرحلة 2.4.**
> أثبتت التجربة العملية القاطعة بالأدلة والصور الرقمية أن استخدام `RichText` مع `TextSpan` المنفصل للكلمات ينتج **تطابقاً ثنائياً وبصرياً تاماً (Byte-for-byte identical)** مع محرك الرندرة الأصلي، ويقدم دعماً سلساً ومحكماً للتفاعل وإدارة الذاكرة.

---

> [!IMPORTANT]
> **بوابة التوقف والاعتماد (STOPPING GATE):**
> تماشياً مع التعليمات الصارمة: **توقفنا تماماً عند نهاية المرحلة 2.3**.
> لم يتم تعميم الويدجت على الصفحة كاملة أو ربطها بالشاشة الرئيسية.
> ننتظر اعتمادكم وموافقة المهندس الاستشاري على نتائج النموذج الأولي والانتقال إلى:
> **المرحلة 2.4: تعميم الرندرة التفاعلية على الصفحة بالكامل (Full Page Interactive Rendering)**.

