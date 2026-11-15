import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_scheduling_decision.dart';

/// Contract providing deterministic 32-bit calendar-based IDs for all scheduled events.
///
/// Formula:
/// id = (year % 100) * 1000000 + month * 10000 + day * 100 + prayerIndex * 10 + typeOffset
class CalendarAlarmIdContract {
  static const int minYear = 2024;
  static const int maxYear = 2099;
  static const int minContractId = 24010100;
  static const int maxContractId = 99123149;

  static const int offsetPrayerAlarm = 0;
  static const int offsetPrayerNotification = 1;
  static const int offsetIqama = 2;
  static const int offsetPostPrayerAzkar = 3;
  static const int offsetMorningAzkar = 4;
  static const int offsetEveningAzkar = 5;

  static const int reservedTestAlarmId = 888;
  static const int reservedHomeWidgetId = 999;
  static const int reservedForegroundServiceId = 8888;

  static const Set<int> reservedIds = {
    reservedTestAlarmId,
    reservedHomeWidgetId,
    reservedForegroundServiceId,
  };

  /// Generates the deterministic ID for a prayer alert based on its decision.
  static int prayerAlertId({
    required DateTime date,
    required PrayerId prayer,
    required PrayerAlertDecision decision,
  }) {
    final offset = switch (decision) {
      PrayerAlertDecision.alarm => offsetPrayerAlarm,
      PrayerAlertDecision.notification => offsetPrayerNotification,
      PrayerAlertDecision.none => throw ArgumentError.value(
          decision,
          'decision',
          'PrayerAlertDecision.none does not produce a prayer alert ID',
        ),
    };
    return _computeId(date: date, prayerIdx: prayerIndex(prayer), typeOffset: offset);
  }

  /// Generates the deterministic ID for an Iqama notification.
  static int iqamaId({
    required DateTime date,
    required PrayerId prayer,
  }) {
    return _computeId(date: date, prayerIdx: prayerIndex(prayer), typeOffset: offsetIqama);
  }

  /// Returns true if [id] belongs to an Iqama scheduled event.
  static bool isIqamaId(int id) {
    if (id < minContractId || id > maxContractId) return false;
    return (id % 10) == offsetIqama;
  }

  /// Generates the deterministic ID for post-prayer Azkar.
  static int postPrayerAzkarId({
    required DateTime date,
    required PrayerId prayer,
  }) {
    return _computeId(date: date, prayerIdx: prayerIndex(prayer), typeOffset: offsetPostPrayerAzkar);
  }

  /// Generates the deterministic ID for Morning Azkar (linked to Fajr: index 0).
  static int morningAzkarId({
    required DateTime date,
  }) {
    return _computeId(date: date, prayerIdx: prayerIndex(PrayerId.fajr), typeOffset: offsetMorningAzkar);
  }

  /// Generates the deterministic ID for Evening Azkar (linked to Asr: index 2).
  static int eveningAzkarId({
    required DateTime date,
  }) {
    return _computeId(date: date, prayerIdx: prayerIndex(PrayerId.asr), typeOffset: offsetEveningAzkar);
  }

  /// Maps [PrayerId] to its canonical prayer index (0..4).
  static int prayerIndex(PrayerId prayer) {
    return switch (prayer) {
      PrayerId.fajr => 0,
      PrayerId.dhuhr => 1,
      PrayerId.asr => 2,
      PrayerId.maghrib => 3,
      PrayerId.isha => 4,
    };
  }

  static int _computeId({
    required DateTime date,
    required int prayerIdx,
    required int typeOffset,
  }) {
    if (date.isUtc) {
      throw ArgumentError.value(
        date,
        'date',
        'DateTime must be a local calendar date. UTC dates are rejected to prevent silent date drift.',
      );
    }
    if (date.year < minYear || date.year > maxYear) {
      throw RangeError.value(date.year, 'date.year', 'Supported years are $minYear..$maxYear');
    }
    if (date.month < 1 || date.month > 12) {
      throw RangeError.value(date.month, 'date.month', 'Month must be 1..12');
    }
    if (date.day < 1 || date.day > 31) {
      throw RangeError.value(date.day, 'date.day', 'Day must be 1..31');
    }
    if (prayerIdx < 0 || prayerIdx > 4) {
      throw RangeError.value(prayerIdx, 'prayerIdx', 'Prayer index must be 0..4');
    }
    if (typeOffset < 0 || typeOffset > 9) {
      throw RangeError.value(typeOffset, 'typeOffset', 'Type offset must be 0..9');
    }

    final id = (date.year % 100) * 1000000 +
        date.month * 10000 +
        date.day * 100 +
        prayerIdx * 10 +
        typeOffset;

    if (id < minContractId || id > maxContractId) {
      throw StateError('Calculated ID $id is outside valid contract space ($minContractId..$maxContractId)');
    }
    if (reservedIds.contains(id)) {
      throw StateError('Calculated ID $id collides with a reserved system ID');
    }

    return id;
  }
}

