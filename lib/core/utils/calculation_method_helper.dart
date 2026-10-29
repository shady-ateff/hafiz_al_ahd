import 'package:adhan_dart/adhan_dart.dart';

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

  /// تحويل أي اسم دولة (سواء بالإنجليزية، العربية، أو كود) إلى كود ISO ثنائي موحد
  static String? normalizeToIsoCountryCode(String? country) {
    if (country == null || country.trim().isEmpty) return null;
    final clean = country
        .toUpperCase()
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '')
        .trim();

    if (clean == 'EG' || clean.contains('EGYPT') || clean.contains('مصر'))
      return 'EG';
    if (isMorocco(country)) return 'MA';
    if (clean == 'SA' || clean.contains('SAUDI') || clean.contains('السعودية'))
      return 'SA';
    if (clean == 'AE' ||
        clean.contains('EMIRATES') ||
        clean.contains('الإمارات'))
      return 'AE';
    if (clean == 'KW' || clean.contains('KUWAIT') || clean.contains('الكويت'))
      return 'KW';
    if (clean == 'QA' || clean.contains('QATAR') || clean.contains('قطر'))
      return 'QA';
    if (clean == 'BH' || clean.contains('BAHRAIN') || clean.contains('البحرين'))
      return 'BH';
    if (clean == 'OM' ||
        clean.contains('OMAN') ||
        clean.contains('عمان') ||
        clean.contains('عُمان'))
      return 'OM';
    if (clean == 'DZ' || clean.contains('ALGERIA') || clean.contains('الجزائر'))
      return 'DZ';
    if (clean == 'TN' || clean.contains('TUNISIA') || clean.contains('تونس'))
      return 'TN';
    if (clean == 'LY' || clean.contains('LIBYA') || clean.contains('ليبيا'))
      return 'LY';
    if (clean == 'JO' || clean.contains('JORDAN') || clean.contains('الأردن'))
      return 'JO';
    if (clean == 'PS' ||
        clean.contains('PALESTINE') ||
        clean.contains('فلسطين'))
      return 'PS';
    if (clean == 'IQ' || clean.contains('IRAQ') || clean.contains('العراق'))
      return 'IQ';
    if (clean == 'IR' || clean.contains('IRAN') || clean.contains('إيران'))
      return 'IR';
    if (clean == 'TR' ||
        clean.contains('TURKEY') ||
        clean.contains('تركيا') ||
        clean.contains('TÜRKIYE'))
      return 'TR';
    if (clean == 'YE' || clean.contains('YEMEN') || clean.contains('اليمن'))
      return 'YE';
    if (clean == 'SD' || clean.contains('SUDAN') || clean.contains('السودان'))
      return 'SD';
    if (clean == 'SY' || clean.contains('SYRIA') || clean.contains('سوريا'))
      return 'SY';
    if (clean == 'LB' || clean.contains('LEBANON') || clean.contains('لبنان'))
      return 'LB';
    if (clean == 'US' || clean.contains('UNITED STATES') || clean == 'USA')
      return 'US';
    if (clean == 'CA' || clean.contains('CANADA')) return 'CA';
    if (clean == 'GB' || clean.contains('UNITED KINGDOM') || clean == 'UK')
      return 'GB';
    if (clean == 'FR' || clean.contains('FRANCE') || clean.contains('فرنسا'))
      return 'FR';
    if (clean == 'DE' || clean.contains('GERMANY') || clean.contains('ألمانيا'))
      return 'DE';
    if (clean == 'IT' || clean.contains('ITALY') || clean.contains('إيطاليا'))
      return 'IT';
    if (clean == 'ES' || clean.contains('SPAIN') || clean.contains('إسبانيا'))
      return 'ES';
    if (clean == 'PK' ||
        clean.contains('PAKISTAN') ||
        clean.contains('باكستان'))
      return 'PK';
    if (clean == 'IN' || clean.contains('INDIA') || clean.contains('الهند'))
      return 'IN';
    if (clean == 'BD' ||
        clean.contains('BANGLADESH') ||
        clean.contains('بنغلاديش'))
      return 'BD';
    if (clean == 'AF' ||
        clean.contains('AFGHANISTAN') ||
        clean.contains('أفغانستان'))
      return 'AF';
    if (clean == 'MY' ||
        clean.contains('MALAYSIA') ||
        clean.contains('ماليزيا'))
      return 'MY';
    if (clean == 'SG' ||
        clean.contains('SINGAPORE') ||
        clean.contains('سنغافورة'))
      return 'SG';
    if (clean == 'ID' ||
        clean.contains('INDONESIA') ||
        clean.contains('إندونيسيا'))
      return 'ID';

    if (clean.length == 2) return clean;
    return country.trim();
  }

  /// تحديد كود الدولة (ISO) بناءً على الكود الممرر، أو استنتاجه بدقة من الإحداثيات الجغرافية
  /// هذا يمنع أي خلط في حال فشل الـ Geocoding عند تبديل الموقع في الإيميوليتور أو بدون إنترنت
  static String? resolveCountryCode(
    String? countryCode, [
    double? latitude,
    double? longitude,
  ]) {
    // 1. فحص كود/اسم الدولة المعطى وتطبيعه
    if (countryCode != null &&
        countryCode.trim().isNotEmpty &&
        countryCode != 'غير معروف') {
      final normalized = normalizeToIsoCountryCode(countryCode);
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }
    if (latitude == null || longitude == null) return null;

    // 2. Fallback احتياطي يعمل فقط لو Geocoding فشل (مثل الإيميوليتور أو عدم توفر إنترنت):
    // مصر
    if (latitude >= 21.5 &&
        latitude <= 32.5 &&
        longitude >= 24.0 &&
        longitude <= 37.0) {
      return 'EG';
    }

    // المغرب
    if (latitude >= 20.5 &&
        latitude <= 36.5 &&
        longitude >= -17.5 &&
        longitude <= -1.0) {
      return 'MA';
    }

    // الجزائر
    if (latitude >= 19.0 &&
        latitude <= 37.5 &&
        longitude >= -8.5 &&
        longitude <= 12.0) {
      return 'DZ';
    }

    // تونس
    if (latitude >= 30.0 &&
        latitude <= 37.5 &&
        longitude >= 7.5 &&
        longitude <= 11.5) {
      return 'TN';
    }

    // ليبيا
    if (latitude >= 19.0 &&
        latitude <= 33.0 &&
        longitude >= 9.5 &&
        longitude <= 25.0) {
      return 'LY';
    }

    // السعودية
    if (latitude >= 16.0 &&
        latitude <= 32.5 &&
        longitude >= 36.0 &&
        longitude <= 55.5) {
      return 'SA';
    }

    // الإمارات
    if (latitude >= 22.5 &&
        latitude <= 26.5 &&
        longitude >= 51.0 &&
        longitude <= 56.5) {
      return 'AE';
    }

    // الكويت
    if (latitude >= 28.5 &&
        latitude <= 30.5 &&
        longitude >= 46.5 &&
        longitude <= 48.5) {
      return 'KW';
    }

    // قطر
    if (latitude >= 24.5 &&
        latitude <= 26.5 &&
        longitude >= 50.5 &&
        longitude <= 51.8) {
      return 'QA';
    }

    // البحرين
    if (latitude >= 25.5 &&
        latitude <= 26.5 &&
        longitude >= 50.3 &&
        longitude <= 50.7) {
      return 'BH';
    }

    // عمان
    if (latitude >= 16.5 &&
        latitude <= 26.5 &&
        longitude >= 52.0 &&
        longitude <= 60.0) {
      return 'OM';
    }

    // الأردن وفلسطين
    if (latitude >= 29.0 &&
        latitude <= 33.5 &&
        longitude >= 34.5 &&
        longitude <= 39.5) {
      return 'JO';
    }

    // العراق
    if (latitude >= 29.0 &&
        latitude <= 37.5 &&
        longitude >= 38.5 &&
        longitude <= 48.5) {
      return 'IQ';
    }

    // تركيا
    if (latitude >= 35.5 &&
        latitude <= 42.5 &&
        longitude >= 25.5 &&
        longitude <= 45.0) {
      return 'TR';
    }

    return null;
  }

  /// بترجع طريقة الحساب المناسبة بناءً على كود أو اسم البلد مع فصل دول الخليج
  static String getMethodForCountry(String countryIdentifier) {
    if (countryIdentifier.isEmpty) return '3';

    final String normalized =
        normalizeToIsoCountryCode(countryIdentifier) ??
        countryIdentifier.toUpperCase().trim();

    // 14: المغرب
    if (normalized == 'MA') {
      return '14';
    }

    // 5: الهيئة المصرية العامة للمساحة
    if (normalized == 'EG') {
      return '5';
    }

    // 4: جامعة أم القرى، مكة المكرمة (السعودية)
    if (normalized == 'SA') {
      return '4';
    }

    // kuwait: دولة الكويت (فجر 18°، عشاء 17.5°)
    if (normalized == 'KW') {
      return 'kuwait';
    }

    // qatar: دولة قطر (فجر 18°، عشاء 90 دقيقة)
    if (normalized == 'QA') {
      return 'qatar';
    }

    // dubai: دبي / الإمارات العربية المتحدة (فجر 18.2°، عشاء 18.2°)
    if (normalized == 'AE') {
      return 'dubai';
    }

    // البحرين وعمان واليمن
    if (normalized == 'BH' || normalized == 'OM' || normalized == 'YE') {
      return 'dubai';
    }

    // 13: رئاسة الشؤون الدينية بتركيا (Diyanet)
    if (normalized == 'TR') {
      return 'turkey';
    }

    // 11: مجلس الشؤون الإسلامية بسنغافورة (MUIS) وماليزيا وإندونيسيا
    if (normalized == 'SG' || normalized == 'MY' || normalized == 'ID') {
      return 'singapore';
    }

    // tehran: معهد الجيوفيزياء بجامعة طهران
    if (normalized == 'IR') {
      return 'tehran';
    }

    // 1: جامعة العلوم الإسلامية بكراتشي (باكستان، الهند، بنغلاديش، أفغانستان)
    if (normalized == 'PK' ||
        normalized == 'IN' ||
        normalized == 'BD' ||
        normalized == 'AF') {
      return '1';
    }

    // 2: الجمعية الإسلامية لأمريكا الشمالية (ISNA)
    if (normalized == 'US' || normalized == 'CA') {
      return '2';
    }

    // 3: رابطة العالم الإسلامي (MWL) - أوروبا وغيرها
    if (normalized == 'GB' ||
        normalized == 'FR' ||
        normalized == 'DE' ||
        normalized == 'IT' ||
        normalized == 'ES') {
      return '3';
    }

    // الطريقة الافتراضية لو البلد مش في القائمة
    return '3';
  }

  /// إرجاع معايير الحساب الدقيقة لطريقة الحساب المحددة
  /// يدعم كل طرق مكتبة adhan_dart بالإضافة لوزارة الأوقاف المغربية والطريقة المخصصة
  static CalculationParameters getParametersFromMethodId(
    String methodId, {
    double? customFajrAngle,
    double? customIshaAngle,
  }) {
    if (methodId == 'custom') {
      final customParams = CalculationMethodParameters.other();
      customParams.fajrAngle = customFajrAngle ?? 18.0;
      customParams.ishaAngle = customIshaAngle ?? 17.0;
      return customParams;
    }

    switch (methodId) {
      case '5':
      case 'egyptian':
        return CalculationMethodParameters.egyptian();
      case '4':
      case 'umm_al_qura':
        return CalculationMethodParameters.ummAlQura();
      case '8':
      case 'dubai':
        return CalculationMethodParameters.dubai();
      case '9':
      case 'kuwait':
        return CalculationMethodParameters.kuwait();
      case '10':
      case 'qatar':
        return CalculationMethodParameters.qatar();
      case 'moon_sighting':
      case 'moon_sighting_committee':
        return CalculationMethodParameters.moonsightingCommittee();
      case 'singapore':
      case '11':
        return CalculationMethodParameters.singapore();
      case 'turkey':
      case '13':
        return CalculationMethodParameters.turkiye();
      case '14':
        var morocoPar = CalculationMethodParameters.morocco();
        morocoPar.adjustments = {
          Prayer.fajr: -1,
          Prayer.sunrise:-2,
          Prayer.asr: 1,
          Prayer.maghrib: 1,
          Prayer.isha: 0,
        };
        return morocoPar;
      case 'tehran':
      case '7':
        return CalculationMethodParameters.tehran();
      case '2':
      case 'north_america':
        return CalculationMethodParameters.northAmerica();
      case '1':
      case 'karachi':
        return CalculationMethodParameters.karachi();
      case '3':
      case 'muslim_world_league':
      default:
        return CalculationMethodParameters.muslimWorldLeague();
    }
  }

  /// خريطة ربط كود الدولة أو الطريقة بمعرف المنطقة الزمنية (IANA Timezone)
  /// تُستخدم لتحويل أوقات الصلاة (UTC) إلى التوقيت المحلي الصحيح لكل دولة
  static String? getTimezoneForCountry(String? countryCode) {
    if (countryCode == null || countryCode.trim().isEmpty) return null;

    if (isMorocco(countryCode)) {
      return 'Africa/Casablanca';
    }

    final String? normalized = normalizeToIsoCountryCode(countryCode);
    final String id = normalized ?? countryCode.toUpperCase().trim();

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
      'IR': 'Asia/Tehran',
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

  /// جميع طرق الحساب المتاحة في الباكدج مضافاً إليها وزارة الأوقاف المغربية والطريقة المخصصة
  static const Map<String, String> methodsMap = {
    'auto': 'تلقائي (حسب الدولة)',
    '14': 'وزارة الأوقاف والشؤون الإسلامية (المغرب)',
    '5': 'الهيئة المصرية العامة للمساحة',
    '4': 'جامعة أم القرى، مكة المكرمة (السعودية)',
    'dubai': 'دبي (الإمارات العربية المتحدة)',
    'kuwait': 'دولة الكويت',
    'qatar': 'دولة قطر',
    '3': 'رابطة العالم الإسلامي (MWL)',
    '1': 'جامعة العلوم الإسلامية بكراتشي',
    'singapore': 'مجلس الشؤون الإسلامية بسنغافورة (MUIS)',
    'turkey': 'رئاسة الشؤون الدينية بتركيا (Diyanet)',
    'tehran': 'معهد الجيوفيزياء بجامعة طهران',
    'moon_sighting': 'لجنة تحري الهلال (Moon Sighting Committee)',
    '2': 'الجمعية الإسلامية لأمريكا الشمالية (ISNA)',
    'custom': 'مخصص (زوايا الفجر والعشاء يدويًا)',
  };

  static const Map<String, String> madhabsMap = {
    'shafi': 'شافعي / مالكي / حنبلي',
    'hanafi': 'حنفي',
  };
}
