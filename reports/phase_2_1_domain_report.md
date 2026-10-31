# تقرير الإنجاز الهندسي — المرحلة 2.1 (Phase 2.1 Report)
## تأسيس طبقة النطاق وعقد المستودع لتفاعل المصحف (Domain Entities & Repository Contract)

---

### 📌 الفهرس
1. [نطاق المرحلة 2.1 والالتزام بالقواعد الجوهرية](#1-نطاق-المرحلة-21-والالتزام-بالقواعد-الجوهرية)
2. [الملفات التي تم فحصها وإنشاؤها](#2-الملفات-التي-تم-فحصها-وإنشاؤها)
3. [القرارات المعمارية لكيانات النطاق (Entity Design Decisions)](#3-القرارات-المعمارية-لكيانات-النطاق-entity-design-decisions)
4. [عقد المستودع (Repository Contract)](#4-عقد-المستودع-repository-contract)
5. [نتائج اختبارات الوحدة (Unit Test Execution)](#5-نتائج-اختبارات-الوحدة-unit-test-execution)
6. [الاعتبارات المتبقية والانتقال للمرحلة 2.2](#6-الاعتبارات-المتبقية-والانتقال-للمرحلة-22)

---

## 1. نطاق المرحلة 2.1 والالتزام بالقواعد الجوهرية

وفقاً للتوجيهات والقرارات المعمارية المعتمدة بعد مراجعة Phase 2.0:
* تم الاقتصار في هذه المرحلة حصراً على **بناء كيانات النطاق (Domain Entities) وعقد المستودع (Repository Contract)**.
* لم يتم لمس أو تعديل أي سطر في:
  - محرك العرض الحالي (`QuranPageWidget`).
  - شاشة المصحف (`QuranScreen`).
  - إدارة الحالة (`QuranCubit` و `QuranState`).
  - خطوط QCFv2 وآلية تحميلها وتخطيطها.
  - بيانات المصحف وقواعد البيانات.
* لم يتم إدخال أي حزم خارجية غير ضرورية (الاعتماد فقط على `equatable` و `dartz` الموجودين سلفاً في المشروع).

---

## 2. الملفات التي تم فحصها وإنشاؤها

### أ. الملفات التي تم فحصها (Files Inspected):
1. `lib/features/quran/domain/entities/quran_page.dart` (فحص نموذج الصفحة والسطر الحالي).
2. `lib/features/quran/domain/repositories/base_quran_repository.dart` (فحص أسلوب Clean Architecture وتسمية العقود).
3. `lib/core/errors/failure.dart` (فحص فئات الأخطاء المدعومة: `Failure`, `CacheFailure`, إلخ).
4. `pubspec.yaml` (التحقق من توفر `equatable` و `dartz`).
5. `assets/quran/mushaf/ayah_mapping.json` (التحقق من مطابقة الحقول ومقاطع الآيات).

### ب. الملفات التي تم إنشاؤها (Files Created):
1. [`lib/features/quran/domain/entities/ayah_id.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/domain/entities/ayah_id.dart)
2. [`lib/features/quran/domain/entities/word_location.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/domain/entities/word_location.dart)
3. [`lib/features/quran/domain/entities/quran_word.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/domain/entities/quran_word.dart)
4. [`lib/features/quran/domain/entities/ayah_segment.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/domain/entities/ayah_segment.dart)
5. [`lib/features/quran/domain/entities/quran_line_mapping.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/domain/entities/quran_line_mapping.dart)
6. [`lib/features/quran/domain/entities/quran_ayah.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/domain/entities/quran_ayah.dart)
7. [`lib/features/quran/domain/entities/quran_mapping_entities.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/domain/entities/quran_mapping_entities.dart) (Barrel Export)
8. [`lib/features/quran/domain/repositories/base_quran_mapping_repository.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/domain/repositories/base_quran_mapping_repository.dart)
9. [`test/quran_mapping_domain_test.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test/quran_mapping_domain_test.dart)

### ج. الملفات المعدلة (Files Modified):
**لا يوجد أي ملف معدل** (Zero modifications).

---

## 3. القرارات المعمارية لكيانات النطاق (Entity Design Decisions)

بناءً على ملاحظات المهندس الاستشاري لتفادي تكرار الحقول وحفظ وحدة الهوية:

### 1. `AyahId`:
* كائن قيمة غير قابل للتعديل (Immutable Value Object).
* الحقول: `surahNumber` و `ayahNumber`.
* التحقق الصارم (Assertions): `1 <= surahNumber <= 114` و `ayahNumber >= 1`.
* يدعم المقارنة بالقيمة عبر `Equatable`.
* يدعم التحويل من وإلى النص المعياري: `AyahId.fromString("2:255")` و `formatted => "2:255"`.

### 2. `WordLocation`:
* يحدد موقع الكلمة داخل المصحف بدقة.
* الحقول: `surahNumber`, `ayahNumber`, `wordIndex`.
* يحتوي على Getter لحظي `ayahId` يعيد `AyahId(surahNumber: surahNumber, ayahNumber: ayahNumber)` دون تخزين حقل مكرر.
* يدعم التحويل من وإلى النص: `WordLocation.fromString("1:1:3")` و `formatted => "1:1:3"`.

### 3. `QuranWord`:
* يمثل الكلمة المعروضة في سياق المصحف.
* الحقول: `location` (من نوع `WordLocation`), `uthmaniText` (النص العثماني الإملائي), `qcfText` (جليف أو جليفات QCF المقابلة بما فيها علامة نهاية الآية إن وجدت).
* التحقق: عدم قبول نصوص فارغة.
* توفير Getters مريحة وسريعة: `ayahId`, `surahNumber`, `ayahNumber`, `wordIndex`.

### 4. `AyahSegment`:
* يمثل المقطع الفيزيائي التابع للآية على سطر معين من صفحة معينة.
* الحقول: `ayahId`, `pageNumber`, `lineNumber`, `wordStart`, `wordEnd`, `qcfText`.
* التحقق: `wordEnd >= wordStart`، `1 <= pageNumber <= 604`، `1 <= lineNumber <= 15`.
* خاصية محسوبة: `wordCount => wordEnd - wordStart + 1`.

### 5. `QuranLineMapping`:
* يمثل التخطيط التفاعلي الكامل لسطر فيزيائي واحد.
* الحقول: `pageNumber`, `lineNumber`, `List<QuranWord> words`.
* **الحماية وعدم القابلية للتعديل (Immutability):** يتم تغليف قائمة الكلمات بـ `List.unmodifiable(words)` لمنع أي تعديل خارجي.
* خصائص مساعدة ذكية:
  - `ayahIds`: مجموعة الـ `AyahId`s الفريدة الموجودة في هذا السطر.
  - `containsAyah(AyahId)`: فحص سريع إن كان السطر يحتوي على جزء من الآية المحددة (مهم جداً لعزل الـ Rebuilds في مرحلة العرض).
  - `reconstructedQcfText`: إعادة تركيب نص السطر بالكامل من كلماته.

### 6. `QuranAyah`:
* يمثل الآية الكاملة مع حدودها ونصوصها ومقاطعها.
* الحقول: `id` (من نوع `AyahId`), `pageNumber`, `endPageNumber`, `uthmaniText`, `wordsCount`, `List<AyahSegment> segments`.
* قائمة المقاطع مغلفة بـ `List.unmodifiable`.
* خصائص: `isMultiLine => segments.length > 1` و `isMultiPage => pageNumber != endPageNumber`.

---

## 4. عقد المستودع (Repository Contract)

تم تعريف العقد في [`base_quran_mapping_repository.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/quran/domain/repositories/base_quran_mapping_repository.dart):

```dart
abstract class BaseQuranMappingRepository {
  /// Initializes and caches the mapping dataset in memory once.
  Future<Either<Failure, void>> init();

  /// Retrieves the line-by-line interactive mappings for a specific physical page (1..604).
  Future<Either<Failure, List<QuranLineMapping>>> getPageMapping(int pageNumber);

  /// Retrieves the full Ayah information by its [AyahId].
  Future<Either<Failure, QuranAyah>> getAyah(AyahId ayahId);

  /// Retrieves the ordered line segments for a specific Ayah across its physical lines.
  Future<Either<Failure, List<AyahSegment>>> getAyahSegments(AyahId ayahId);

  /// Resolves an individual word by its precise location.
  Future<Either<Failure, QuranWord>> getWord(WordLocation location);
}
```

* **الالتزام بمبدأ العزل:** العقد يعتمد فقط على كيانات الـ Domain ومغلف بنمط `Either<Failure, T>`، دون أي تسريب لبيانات JSON الخام أو بنيات التخزين إلى طبقة العرض.

---

## 5. نتائج اختبارات الوحدة (Unit Test Execution)

تم إنشاء وتشغيل حزمة الاختبارات [`test/quran_mapping_domain_test.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test/quran_mapping_domain_test.dart) التي غطت 17 سيناريو اختبار شامل:

```text
flutter test test/quran_mapping_domain_test.dart
00:05 +17: All tests passed!
```

### تفصيل الاختبارات الـ 17 المنجزة:
1. `AyahId`: اختبار تطابق القيمة و `hashCode`.
2. `AyahId`: اختبار التنسيق النصي `formatted` والتحويل العكسي `fromString`.
3. `AyahId`: اختبار إطلاق استثناءات عند أرقام سور وآيات غير صالحة.
4. `AyahId`: اختبار إطلاق `ArgumentError` عند نصوص تالفة.
5. `WordLocation`: اختبار تطابق القيمة و `hashCode`.
6. `WordLocation`: اختبار الـ Factory constructors و Getter الآية الأم.
7. `WordLocation`: اختبار الرفض الصارم للقيم والنصوص غير الصالحة.
8. `QuranWord`: اختبار خصائص الموقع وتطابق الكلمات.
9. `QuranWord`: اختبار رفض النصوص العثمانية أو نصوص QCF الفارغة.
10. `AyahSegment`: اختبار حساب عدد الكلمات `wordCount` وتطابق المقاطع.
11. `AyahSegment`: اختبار حدود المقاطع ورفض `wordEnd < wordStart` والأرقام غير الصالحة.
12. `QuranLineMapping`: اختبار ترتيب الكلمات وإعادة بناء نص السطر واستخراج الآيات `ayahIds`.
13. `QuranLineMapping`: اختبار منع التعديل على القائمة `List.unmodifiable`.
14. `QuranLineMapping`: اختبار رفض القوائم الفارغة أو السطور خارج النطاق 1..15.
15. `QuranAyah`: اختبار الآية ذات السطر الواحد `isMultiLine == false`.
16. `QuranAyah`: اختبار الآية متعددة الأسطر `isMultiLine == true`.
17. `QuranAyah`: اختبار عدم قابلية المقاطع للتعديل والتأكد من صحة نطاق الصفحات.

**النتيجة: نجاح 17 من 17 اختباراً بنسبة 100%.**

---

## 6. الاعتبارات المتبقية والانتقال للمرحلة 2.2

### خطة المرحلة القادمة (Phase 2.2 — JSON Data Source & Repository Implementation):
1. بناء `QuranMappingLocalDataSource` لقراءة `assets/quran/mushaf/ayah_mapping.json`.
2. فك تشفير وتخزين البيانات في الذاكرة **مرة واحدة فقط (In-Memory Singleton)** عند استدعاء `init()`.
3. تطبيق `QuranMappingRepositoryImpl` لتوفير وصول $O(1)$ لكافة استعلامات الصفحات والآيات والكلمات دون تكرار فك تشفير الـ JSON أثناء تقليب الصفحات.
4. كتابة اختبارات تكامل لطبقة البيانات للتأكد من استرجاع البيانات الحقيقية ومطابقتها لمصحف المدينة.

> [!IMPORTANT]
> **بوابة التوقف والاعتماد (STOPPING GATE):**
> تماشياً مع الالتزام الصارم بالخطة المقسمة: **تم التوقف هنا عند نهاية المرحلة 2.1**.
> ننتظر اعتمادكم لهذا التقرير للموافقة على الانتقال إلى المرحلة 2.2.

