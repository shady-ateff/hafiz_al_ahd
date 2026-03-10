class CalculationMethodHelper {
  /// بترجع رقم الطريقة المناسبة بناءً على كود أو اسم البلد
  /// الأرقام دي متوافقة مع أشهر APIs (زي Aladhan API)
  /// وممكن تعدلها لو بتستخدم باكدج مختلفة زي (adhan dart)
  static String getMethodForCountry(String countryIdentifier) {
    if (countryIdentifier.isEmpty) return '3';

    String id = countryIdentifier.toUpperCase();

    // 5: الهيئة المصرية العامة للمساحة
    if (id == 'EG' || id == 'EGYPT') {
      return '5';
    }

    // 4: جامعة أم القرى، مكة المكرمة
    if (id == 'SA' || id == 'SAUDI ARABIA') {
      return '4';
    }

    // 8: منطقة الخليج
    if (id == 'AE' ||
        id == 'UNITED ARAB EMIRATES' ||
        id == 'BH' ||
        id == 'BAHRAIN' ||
        id == 'QA' ||
        id == 'QATAR' ||
        id == 'KW' ||
        id == 'KUWAIT' ||
        id == 'OM' ||
        id == 'OMAN' ||
        id == 'YE' ||
        id == 'YEMEN') {
      return '8';
    }

    // 2: الجمعية الإسلامية لأمريكا الشمالية (ISNA)
    if (id == 'US' ||
        id == 'UNITED STATES' ||
        id == 'USA' ||
        id == 'CA' ||
        id == 'CANADA') {
      return '2';
    }

    // 3: رابطة العالم الإسلامي (MWL) - أوروبا وغيرها
    if (id == 'GB' ||
        id == 'UNITED KINGDOM' ||
        id == 'UK' ||
        id == 'FR' ||
        id == 'FRANCE' ||
        id == 'DE' ||
        id == 'GERMANY' ||
        id == 'IT' ||
        id == 'ITALY' ||
        id == 'ES' ||
        id == 'SPAIN') {
      return '3';
    }

    // 1: جامعة العلوم الإسلامية بكراتشي
    if (id == 'PK' ||
        id == 'PAKISTAN' ||
        id == 'IN' ||
        id == 'INDIA' ||
        id == 'BD' ||
        id == 'BANGLADESH' ||
        id == 'AF' ||
        id == 'AFGHANISTAN') {
      return '1';
    }

    // 11: مجلس الشؤون الإسلامية (MUIS)
    if (id == 'MY' ||
        id == 'MALAYSIA' ||
        id == 'SG' ||
        id == 'SINGAPORE' ||
        id == 'ID' ||
        id == 'INDONESIA') {
      return '11';
    }

    // 13: رئاسة الشؤون الدينية بتركيا (Diyanet)
    if (id == 'TR' || id == 'TURKEY' || id == 'TÜRKIYE') {
      return '13';
    }

    // الطريقة الافتراضية لو البلد مش في القائمة (رابطة العالم الإسلامي هي الأعم)
    return '3';
  }
}
