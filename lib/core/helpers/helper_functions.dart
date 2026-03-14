// 👈 1. الدالة السحرية لتنظيف النص العربي من التشكيل وتوحيد الحروف
  String normalizeArabicText(String text) {
    if (text.isEmpty) return text;
    return text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '') // مسح التشكيل كله
        .replaceAll(RegExp(r'[أإآ]'), 'ا') // توحيد الألف
        .replaceAll(RegExp(r'ة'), 'ه') // توحيد التاء المربوطة
        .replaceAll(RegExp(r'ى'), 'ي'); // توحيد الألف المقصورة
  }

