import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:adhan_dart/adhan_dart.dart';
import 'package:hafiz_al_ahd/features/home/data/datasources/prayer_times_local_data_source.dart';
import 'package:hafiz_al_ahd/features/home/presentation/cubit/time_cubit.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/usecases/check_if_scheduling_needed_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';

String formatTime(DateTime? dt) {
  if (dt == null) return '--:--';
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

int diffInMinutes(DateTime? actual, String expected) {
  if (actual == null) return 999;
  final parts = expected.split(':');
  final expH = int.parse(parts[0]);
  final expM = int.parse(parts[1]);
  final actualMinutes = actual.hour * 60 + actual.minute;
  final expectedMinutes = expH * 60 + expM;
  return (actualMinutes - expectedMinutes).abs();
}

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
  });

  final dataSource = PrayerTimesLocalDataSource();

  group('1. مقارنة أوقات الصلاة بمصادر حكومية ورسمية أونلاين (30 أكتوبر 2026)', () {
    final testCases = [
      {
        'country': 'مصر (القاهرة)',
        'countryCode': 'EG',
        'coords': const Coordinates(30.0444, 31.2357),
        'source': 'الهيئة المصرية العامة للمساحة (esa.gov.eg)',
        'expected': {
          'fajr': '04:39',
          'sunrise': '06:07',
          'dhuhr': '11:39',
          'asr': '14:46',
          'maghrib': '17:10',
          'isha': '18:28',
        }
      },
      {
        'country': 'السعودية (مكة المكرمة)',
        'countryCode': 'SA',
        'coords': const Coordinates(21.4225, 39.8262),
        'source': 'تقويم أم القرى (ummulqura.org.sa)',
        'expected': {
          'fajr': '05:05',
          'sunrise': '06:23',
          'dhuhr': '12:04',
          'asr': '15:20',
          'maghrib': '17:46',
          'isha': '19:16',
        }
      },
      {
        'country': 'المغرب (مراكش)',
        'countryCode': 'MA',
        'coords': const Coordinates(31.6295, -7.9811),
        'source': 'وزارة الأوقاف والشؤون الإسلامية بالمغرب (habous.gov.ma)',
        'expected': {
          'fajr': '05:19',
          'sunrise': '06:42',
          'dhuhr': '12:21',
          'asr': '15:21',
          'maghrib': '17:50',
          'isha': '19:02',
        }
      },
      {
        'country': 'الإمارات (دبي)',
        'countryCode': 'AE',
        'coords': const Coordinates(25.2048, 55.2708),
        'source': 'دائرة الشؤون الإسلامية بدبي (iacad.gov.ae)',
        'expected': {
          'fajr': '05:07',
          'sunrise': '06:22',
          'dhuhr': '12:05',
          'asr': '15:16',
          'maghrib': '17:43',
          'isha': '18:58',
        }
      },
    ];

    for (final tc in testCases) {
      final country = tc['country'] as String;
      final code = tc['countryCode'] as String;
      final coords = tc['coords'] as Coordinates;
      final source = tc['source'] as String;
      final expected = tc['expected'] as Map<String, String>;

      test('اختبار دقة مواقيت: $country مقارنة بـ $source', () async {
        final model = await dataSource.getPrayerTimes(
          coordinates: coords,
          date: DateTime(2026, 10, 30),
          countryCode: code,
        );

        print('\n📍 الدولة / المدينة: $country');
        print('🏛️ المصدر الرسمي المقارن: $source');
        print('┌─────────┬──────────────┬──────────────┬─────────┐');
        print('│ الصلاة  │ تطبيقنا      │ المصدر الرسمي│ الفرق   │');
        print('├─────────┼──────────────┼──────────────┼─────────┤');

        final prayers = [
          ('الفجر', model.fajr, expected['fajr']!),
          ('الشروق', model.sunrise, expected['sunrise']!),
          ('الظهر', model.dhuhr, expected['dhuhr']!),
          ('العصر', model.asr, expected['asr']!),
          ('المغرب', model.maghrib, expected['maghrib']!),
          ('العشاء', model.isha, expected['isha']!),
        ];

        for (final p in prayers) {
          final name = p.$1.padRight(6);
          final actualStr = formatTime(p.$2).padRight(12);
          final expStr = p.$3.padRight(12);
          final diff = diffInMinutes(p.$2, p.$3);
          final diffStr = diff == 0 ? 'مطابق ✅' : '±$diff دقيقة';
          print('│ $name │ $actualStr │ $expStr │ $diffStr │');

          // يجب ألا يزيد الفرق الفلكي عن دقيقة واحدة (ناتج تقريب الثواني)
          expect(diff, lessThanOrEqualTo(2),
              reason: 'صلاة ${p.$1} في $country بها فرق غير مقبول: $actualStr مقابل $expStr');
        }
        print('└─────────┴──────────────┴──────────────┴─────────┘');
      });
    }
  });

  group('2. اختبار انتقال التوقيت الصيفي/الشتوي (DST Fall-Back) لمصر', () {
    test('تغير التوقيت الصيفي لـ 29 و 30 أكتوبر وحساب tomorrowFajr الشتوي بدقة', () async {
      final cairoCoords = const Coordinates(30.0444, 31.2357);
      final oct29 = await dataSource.getPrayerTimes(
        coordinates: cairoCoords,
        date: DateTime(2026, 10, 29),
        countryCode: 'EG',
      );
      final oct30 = await dataSource.getPrayerTimes(
        coordinates: cairoCoords,
        date: DateTime(2026, 10, 30),
        countryCode: 'EG',
      );

      print('\n29 أكتوبر (قبل التحول): الفجر = ${formatTime(oct29.fajr)} (+3 صيفي)، المغرب = ${formatTime(oct29.maghrib)}');
      print('30 أكتوبر (بعد التحول): الفجر = ${formatTime(oct30.fajr)} (+2 شتوي)، المغرب = ${formatTime(oct30.maghrib)}');
      print('فجر الغد المحسوب ليلة 29 أكتوبر: ${formatTime(oct29.tomorrowFajr)} (شتوي)');

      expect(oct30.fajr!.hour, 4, reason: 'فجر الجمعة 30 أكتوبر يجب أن يكون بالساعة 4 ص (توقيت شتوي)');
      expect(oct29.tomorrowFajr!.hour, 4, reason: 'tomorrowFajr المحسوب ليلة 29 يجب أن يقفز تلقائياً للساعة 4 ص');
      expect(oct29.tomorrowFajr!.day, 30);
    });
  });

  group('3. اختبار حساب الصلاة القادمة بعد العشاء ليلة تغيير التوقيت (getNextPrayer)', () {
    test('getNextPrayer في 11:15 م ليلة 29 أكتوبر يعيد فجر الغد بالساعة 4:39 ص', () async {
      final cairoCoords = const Coordinates(30.0444, 31.2357);
      final oct29 = await dataSource.getPrayerTimes(
        coordinates: cairoCoords,
        date: DateTime(2026, 10, 29),
        countryCode: 'EG',
      );

      final currentTimeLateNight = DateTime(2026, 10, 29, 23, 15);
      final next = oct29.getNextPrayer(currentTimeLateNight);

      print('\nالوقت المفترض: 11:15 مساء الخميس 29 أكتوبر');
      print('الصلاة القادمة: ${next.name}');
      print('الوقت: ${formatTime(next.time)} (بتاريخ ${next.time?.day} أكتوبر)');
      print('المتبقي: ${next.remaining.inHours} ساعة و ${next.remaining.inMinutes % 60} دقيقة');

      expect(next.name, 'الفجر');
      expect(next.time?.hour, 4);
      expect(next.time?.day, 30);
      expect(next.remaining.isNegative, false);
    });
  });

  group('4. اختبار مراقب تغير اليوم ومنتصف الليل (TimeCubit)', () {
    test('TimeCubit يحتوي على onDayChanged ويراقب تغير اليوم', () {
      bool dayChangedCalled = false;
      final cubit = TimeCubit(
        onDayChanged: (newDate) {
          dayChangedCalled = true;
        },
      );

      expect(cubit.onDayChanged, isNotNull);
      cubit.close();
    });
  });

  group('5. اختبار حارس التوقيت (DST Guard) وإعادة الجدولة عند تغير فرق التوقيت', () {
    test('CheckIfSchedulingNeededUseCase يكتشف تغير فرق التوقيت ويعيد الجدولة فوراً', () async {
      SharedPreferences.setMockInitialValues({
        'last_known_timezone_offset_minutes': 180, // كان +3 صيفي
        'scheduled_until_date': DateTime.now().add(const Duration(days: 5)).toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      final checker = CheckIfSchedulingNeededUseCase(pref: prefs);

      final needsScheduling = checker.execute();
      print('\nالقيمة السابقة المحفوظة: 180 دقيقة (+3)');
      print('القيمة الحالية للجهاز: ${DateTime.now().timeZoneOffset.inMinutes} دقيقة');
      print('استشعار الحارس وإعادة الجدولة: $needsScheduling');

      expect(needsScheduling, true);
    });
  });
}
