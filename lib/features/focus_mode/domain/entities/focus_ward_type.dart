/// Represents the type of religious ward or devotion tracked by Focus Mode.
enum FocusWardType {
  morningAzkar,
  eveningAzkar,
  postPrayerAzkar,
  quranReading,
  custom,
}

extension FocusWardTypeExtension on FocusWardType {
  String get displayName {
    switch (this) {
      case FocusWardType.morningAzkar:
        return 'أذكار الصباح';
      case FocusWardType.eveningAzkar:
        return 'أذكار المساء';
      case FocusWardType.postPrayerAzkar:
        return 'أذكار بعد الصلاة';
      case FocusWardType.quranReading:
        return 'ورد القرآن الكريم';
      case FocusWardType.custom:
        return 'ورد مخصص';
    }
  }

  String get categoryKey {
    switch (this) {
      case FocusWardType.morningAzkar:
        return 'morning';
      case FocusWardType.eveningAzkar:
        return 'evening';
      case FocusWardType.postPrayerAzkar:
        return 'post_prayer';
      case FocusWardType.quranReading:
        return 'quran';
      case FocusWardType.custom:
        return 'custom';
    }
  }
}
