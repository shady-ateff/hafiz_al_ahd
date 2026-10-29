import 'package:adhan/adhan.dart';

class CalculationMethodHelper {
  /// التحقق مما إذا كان المعرف يمثل المملكة المغربية
  static bool isMorocco(String? identifier) {
    if (identifier == null || identifier.trim().isEmpty) return false;
    final clean = identifier.toUpperCase().trim();
    return clean == 'MA' ||
        clean == 'MOROCCO' ||
        clean == 'MAROC' ||
        clean == 'المغرب' ||
        clean.contains('MOROCCO') ||
        clean.contains('MAROC') ||
        clean.contains('المغرب');
  }

  /// تحديد كود الدولة (ISO) بناءً على الكود الممرر، أو استنتاجه بدقة من الإحداثيات الجغرافية
  /// هذا يمنع أي خلط في حال فشل الـ Geocoding عند تبديل الموقع في الإيميوليتور أو بدون إنترنت
  static String? resolveCountryCode(String? countryCode, [double? latitude, double? longitude]) {
    // 1. إذا كان الكود متاحاً ومستخرجاً بنجاح من الـ GPS/Geocoding، نرجعه مباشرة لأي دولة في العالم
    if (countryCode != null &&
        countryCode.trim().isNotEmpty &&
        countryCode != 'غير معروف') {
      return countryCode.trim();
    }
    if (latitude == null || longitude == null) return null;

    // 2. Fallback احتياطي يعمل فقط لو Geocoding فشل (مثل الإيميوليتور أو عدم توفر إنترنت):
    // مصر
    if (latitude >= 21.5 && latitude <= 32.5 && longitude >= 24.0 && longitude <= 37.0) {
      return 'EG';
    }

    // المغرب
    if (latitude >= 20.5 && latitude <= 36.5 && longitude >= -17.5 && longitude <= -1.0) {
      return 'MA';
    }

    // الجزائر
    if (latitude >= 19.0 && latitude <= 37.5 && longitude >= -8.5 && longitude <= 12.0) {
      return 'DZ';
    }

    // تونس
    if (latitude >= 30.0 && latitude <= 37.5 && longitude >= 7.5 && longitude <= 11.5) {
      return 'TN';
    }

    // ليبيا
    if (latitude >= 19.0 && latitude <= 33.0 && longitude >= 9.5 && longitude <= 25.0) {
      return 'LY';
    }

    // السعودية
    if (latitude >= 16.0 && latitude <= 32.5 && longitude >= 36.0 && longitude <= 55.5) {
      return 'SA';
    }

    // الإمارات
    if (latitude >= 22.5 && latitude <= 26.5 && longitude >= 51.0 && longitude <= 56.5) {
      return 'AE';
    }

    // الكويت
    if (latitude >= 28.5 && latitude <= 30.5 && longitude >= 46.5 && longitude <= 48.5) {
      return 'KW';
    }

    // قطر
    if (latitude >= 24.5 && latitude <= 26.5 && longitude >= 50.5 && longitude <= 51.8) {
      return 'QA';
    }

    // البحرين
    if (latitude >= 25.5 && latitude <= 26.5 && longitude >= 50.3 && longitude <= 50.7) {
      return 'BH';
    }

    // عمان
    if (latitude >= 16.5 && latitude <= 26.5 && longitude >= 52.0 && longitude <= 60.0) {
      return 'OM';
    }

    // الأردن وفلسطين
    if (latitude >= 29.0 && latitude <= 33.5 && longitude >= 34.5 && longitude <= 39.5) {
      return 'JO';
    }

    // العراق
    if (latitude >= 29.0 && latitude <= 37.5 && longitude >= 38.5 && longitude <= 48.5) {
      return 'IQ';
    }

    // تركيا
    if (latitude >= 35.5 && latitude <= 42.5 && longitude >= 25.5 && longitude <= 45.0) {
      return 'TR';
    }

    return null;
  }

  /// بترجع رقم الطريقة المناسبة بناءً على كود أو اسم البلد
  /// الأرقام دي متوافقة مع أشهر APIs (زي Aladhan API)
  /// وممكن تعدلها لو بتستخدم باكدج مختلفة زي (adhan dart)
  static String getMethodForCountry(String countryIdentifier) {
    if (countryIdentifier.isEmpty) return '3';

    if (isMorocco(countryIdentifier)) {
      return '14';
    }

    String id = countryIdentifier.toUpperCase().trim();

    // 5: الهيئة المصرية العامة للمساحة
    if (id == 'EG' || id == 'EGYPT' || id.contains('EGYPT') || id == 'مصر') {
      return '5';
    }

    // 4: جامعة أم القرى، مكة المكرمة
    if (id == 'SA' ||
        id == 'SAUDI ARABIA' ||
        id.contains('SAUDI') ||
        id == 'السعودية') {
      return '4';
    }

    // 8: منطقة الخليج
    if (id == 'AE' ||
        id.contains('EMIRATES') ||
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

  /// إرجاع معايير الحساب الدقيقة لطريقة الحساب المحددة
  /// طريقة 14 مخصصة لوزارة الأوقاف المغربية (زاوية الفجر 19 والعشاء 17 والمذهب الشافعي/المالكي)
  static CalculationParameters getParametersFromMethodId(String methodId) {
    if (methodId == '14') {
      final moroccoParams = CalculationMethod.other.getParameters();
      moroccoParams.fajrAngle = 19.0;
      moroccoParams.ishaAngle = 17.0;
      moroccoParams.madhab =
          Madhab.shafi; // يتوافق مع المذهب المالكي المتبع في المغرب لحساب العصر
      return moroccoParams;
    }

    switch (methodId) {
      case '5':
        return CalculationMethod.egyptian.getParameters();
      case '4':
        return CalculationMethod.umm_al_qura.getParameters();
      case '8':
        return CalculationMethod.dubai.getParameters();
      case '2':
        return CalculationMethod.north_america.getParameters();
      case '1':
        return CalculationMethod.karachi.getParameters();
      case '11':
        return CalculationMethod.singapore.getParameters();
      case '13':
        return CalculationMethod.turkey.getParameters();
      case '3':
      default:
        return CalculationMethod.muslim_world_league.getParameters();
    }
  }

  /// خريطة ربط كود الدولة أو الطريقة بمعرف المنطقة الزمنية (IANA Timezone)
  /// تُستخدم لتحويل أوقات الصلاة (UTC) إلى التوقيت المحلي الصحيح لكل دولة
  static String? getTimezoneForCountry(String? countryCode) {
    if (countryCode == null || countryCode.trim().isEmpty) return null;

    if (isMorocco(countryCode)) {
      return 'Africa/Casablanca';
    }

    final String id = countryCode.toUpperCase().trim();

    final Map<String, String> countryTimezones = {
      'MA': 'Africa/Casablanca',
      'EG': 'Africa/Cairo',
      'SA': 'Asia/Riyadh',
      'AE': 'Asia/Dubai',
      'BH': 'Asia/Bahrain',
      'QA': 'Asia/Qatar',
      'KW': 'Asia/Kuwait',
      'OM': 'Asia/Muscat',
      'YE': 'Asia/Aden',
      'DZ': 'Africa/Algiers',
      'TN': 'Africa/Tunis',
      'LY': 'Africa/Tripoli',
      'SD': 'Africa/Khartoum',
      'JO': 'Asia/Amman',
      'PS': 'Asia/Gaza',
      'IQ': 'Asia/Baghdad',
      'LB': 'Asia/Beirut',
      'SY': 'Asia/Damascus',
      'US': 'America/New_York',
      'CA': 'America/Toronto',
      'GB': 'Europe/London',
      'FR': 'Europe/Paris',
      'DE': 'Europe/Berlin',
      'IT': 'Europe/Rome',
      'ES': 'Europe/Madrid',
      'PK': 'Asia/Karachi',
      'IN': 'Asia/Kolkata',
      'BD': 'Asia/Dhaka',
      'AF': 'Asia/Kabul',
      'MY': 'Asia/Kuala_Lumpur',
      'SG': 'Asia/Singapore',
      'ID': 'Asia/Jakarta',
      'TR': 'Europe/Istanbul',
    };

    return countryTimezones[id];
  }

  static const Map<String, String> methodsMap = {
    'auto': 'تلقائي (حسب الدولة)',
    '14': 'وزارة الأوقاف والشؤون الإسلامية (المغرب)',
    '5': 'الهيئة المصرية العامة للمساحة',
    '4': 'جامعة أم القرى، مكة المكرمة',
    '3': 'رابطة العالم الإسلامي (MWL)',
    '2': 'الجمعية الإسلامية لأمريكا الشمالية (ISNA)',
    '1': 'جامعة العلوم الإسلامية بكراتشي',
    '8': 'منطقة الخليج (دبي)',
    '11': 'مجلس الشؤون الإسلامية بسنغافورة',
    '13': 'رئاسة الشؤون الدينية بتركيا',
  };

  static const Map<String, String> madhabsMap = {
    'shafi': 'شافعي / مالكي / حنبلي',
    'hanafi': 'حنفي',
  };
}
