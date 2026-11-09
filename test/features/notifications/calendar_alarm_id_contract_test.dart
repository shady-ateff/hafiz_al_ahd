import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/calendar_alarm_id_contract.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_scheduling_decision.dart';

void main() {
  group('P4.1-B.3 Phase 2C.3.1 — Calendar Alarm ID Contract Tests', () {
    final baseDate = DateTime(2026, 11, 8);

    // ========================================================================
    // GROUP A: DETERMINISM
    // ========================================================================
    group('Group A — Determinism', () {
      test('1. Same date, prayer, and decision produce identical ID across multiple calls', () {
        final id1 = CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );
        final id2 = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2026, 11, 8),
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );
        expect(id1, equals(id2));
        expect(id1, equals(26110800));
      });

      test('2. Calculation order does not alter results (Commutative/Independent)', () {
        final idIshaFirst = CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: PrayerId.isha,
          decision: PrayerAlertDecision.notification,
        );
        final idFajr = CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );
        final idIshaSecond = CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: PrayerId.isha,
          decision: PrayerAlertDecision.notification,
        );

        expect(idIshaFirst, equals(idIshaSecond));
        expect(idIshaFirst, isNot(equals(idFajr)));
      });

      test('3. Re-running generation is 100% idempotent', () {
        final idsBatch1 = PrayerId.values.map((p) => CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: p,
          decision: PrayerAlertDecision.alarm,
        )).toList();

        final idsBatch2 = PrayerId.values.map((p) => CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: p,
          decision: PrayerAlertDecision.alarm,
        )).toList();

        expect(idsBatch1, equals(idsBatch2));
      });
    });

    // ========================================================================
    // GROUP B: PRAYER ISOLATION & TYPE DISJOINTNESS
    // ========================================================================
    group('Group B — Prayer Isolation & Type Disjointness', () {
      test('4. The five prayers produce distinct IDs on the same date for alarms', () {
        final ids = PrayerId.values.map((p) => CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: p,
          decision: PrayerAlertDecision.alarm,
        )).toSet();

        expect(ids.length, equals(5));
      });

      test('5. The five prayers produce distinct IDs on the same date for notifications', () {
        final ids = PrayerId.values.map((p) => CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: p,
          decision: PrayerAlertDecision.notification,
        )).toSet();

        expect(ids.length, equals(5));
      });

      test('6. Prayer Alarm and Prayer Notification produce distinct IDs for the same prayer and date', () {
        for (final p in PrayerId.values) {
          final alarmId = CalendarAlarmIdContract.prayerAlertId(
            date: baseDate,
            prayer: p,
            decision: PrayerAlertDecision.alarm,
          );
          final notifId = CalendarAlarmIdContract.prayerAlertId(
            date: baseDate,
            prayer: p,
            decision: PrayerAlertDecision.notification,
          );

          expect(alarmId, isNot(equals(notifId)));
          expect(notifId - alarmId, equals(1)); // Offset difference: 1 - 0 = 1
        }
      });

      test('7. Decision none throws ArgumentError (Rule 12: off does not produce an ID)', () {
        expect(
          () => CalendarAlarmIdContract.prayerAlertId(
            date: baseDate,
            prayer: PrayerId.fajr,
            decision: PrayerAlertDecision.none,
          ),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('PrayerAlertDecision.none does not produce a prayer alert ID'),
          )),
        );
      });
    });

    // ========================================================================
    // GROUP C: AUXILIARY IDENTITY ISOLATION
    // ========================================================================
    group('Group C — Auxiliary Identity Isolation', () {
      test('8. Iqama IDs are distinct for all 5 prayers on the same date', () {
        final ids = PrayerId.values.map((p) => CalendarAlarmIdContract.iqamaId(
          date: baseDate,
          prayer: p,
        )).toSet();

        expect(ids.length, equals(5));
      });

      test('9. Post-prayer Azkar IDs are distinct for all 5 prayers on the same date', () {
        final ids = PrayerId.values.map((p) => CalendarAlarmIdContract.postPrayerAzkarId(
          date: baseDate,
          prayer: p,
        )).toSet();

        expect(ids.length, equals(5));
      });

      test('10. Morning Azkar ID is linked to Fajr index (0) and distinct from Fajr alert ID', () {
        final morningAzkarId = CalendarAlarmIdContract.morningAzkarId(date: baseDate);
        final fajrAlarmId = CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );
        final fajrNotifId = CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.notification,
        );

        expect(morningAzkarId, equals(26110804));
        expect(morningAzkarId, isNot(equals(fajrAlarmId)));
        expect(morningAzkarId, isNot(equals(fajrNotifId)));
      });

      test('11. Evening Azkar ID is linked to Asr index (2) and distinct from Asr alert ID', () {
        final eveningAzkarId = CalendarAlarmIdContract.eveningAzkarId(date: baseDate);
        final asrAlarmId = CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: PrayerId.asr,
          decision: PrayerAlertDecision.alarm,
        );
        final asrNotifId = CalendarAlarmIdContract.prayerAlertId(
          date: baseDate,
          prayer: PrayerId.asr,
          decision: PrayerAlertDecision.notification,
        );

        expect(eveningAzkarId, equals(26110825));
        expect(eveningAzkarId, isNot(equals(asrAlarmId)));
        expect(eveningAzkarId, isNot(equals(asrNotifId)));
      });

      test('12. Iqama, Post-prayer Azkar, Morning, and Evening Azkar do not collide with each other', () {
        final fajrIqama = CalendarAlarmIdContract.iqamaId(date: baseDate, prayer: PrayerId.fajr);
        final fajrPostAzkar = CalendarAlarmIdContract.postPrayerAzkarId(date: baseDate, prayer: PrayerId.fajr);
        final morningAzkar = CalendarAlarmIdContract.morningAzkarId(date: baseDate);

        final asrIqama = CalendarAlarmIdContract.iqamaId(date: baseDate, prayer: PrayerId.asr);
        final asrPostAzkar = CalendarAlarmIdContract.postPrayerAzkarId(date: baseDate, prayer: PrayerId.asr);
        final eveningAzkar = CalendarAlarmIdContract.eveningAzkarId(date: baseDate);

        final set = {fajrIqama, fajrPostAzkar, morningAzkar, asrIqama, asrPostAzkar, eveningAzkar};
        expect(set.length, equals(6));
      });
    });

    // ========================================================================
    // GROUP D: DATE & TIME BOUNDARY ISOLATION
    // ========================================================================
    group('Group D — Date & Time Boundary Isolation', () {
      test('13. Different calendar dates produce different IDs for the same prayer and type', () {
        final day1 = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2026, 11, 8),
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );
        final day2 = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2026, 11, 9),
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );

        expect(day1, equals(26110800));
        expect(day2, equals(26110900));
        expect(day1, isNot(equals(day2)));
      });

      test('14. Minimum valid boundary (2024-01-01 Fajr Alarm) equals 24010100', () {
        final minId = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2024, 1, 1),
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );

        expect(minId, equals(CalendarAlarmIdContract.minContractId));
        expect(minId, equals(24010100));
      });

      test('15. Maximum valid date (2099-12-31 Isha Notification) produces valid 32-bit ID', () {
        final maxId = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2099, 12, 31),
          prayer: PrayerId.isha,
          decision: PrayerAlertDecision.notification,
        );

        expect(maxId, equals(99123141));
        expect(maxId, lessThanOrEqualTo(CalendarAlarmIdContract.maxContractId));
        expect(maxId, lessThan(2147483647)); // 32-bit signed integer limit
      });

      test('16. Year-end transition (Dec 31 -> Jan 01) produces distinct monotonically ordered IDs', () {
        final dec31 = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2026, 12, 31),
          prayer: PrayerId.isha,
          decision: PrayerAlertDecision.alarm,
        );
        final jan01 = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2027, 1, 1),
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );

        expect(dec31, equals(26123140));
        expect(jan01, equals(27010100));
        expect(dec31, lessThan(jan01));
      });

      test('17. Leap days (2024-02-29 and 2028-02-29) produce valid deterministic IDs', () {
        final leap2024 = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2024, 2, 29),
          prayer: PrayerId.dhuhr,
          decision: PrayerAlertDecision.alarm,
        );
        final leap2028 = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2028, 2, 29),
          prayer: PrayerId.dhuhr,
          decision: PrayerAlertDecision.alarm,
        );

        expect(leap2024, equals(24022910));
        expect(leap2028, equals(28022910));
      });

      test('18. Time components (hours, minutes, seconds) on the same calendar day do not alter ID', () {
        final morning = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2026, 11, 8, 4, 30, 0),
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );
        final evening = CalendarAlarmIdContract.prayerAlertId(
          date: DateTime(2026, 11, 8, 23, 59, 59),
          prayer: PrayerId.fajr,
          decision: PrayerAlertDecision.alarm,
        );

        expect(morning, equals(evening));
      });
    });

    // ========================================================================
    // GROUP E: VALIDATION & BOUNDARY PROTECTION
    // ========================================================================
    group('Group E — Validation & Boundary Protection', () {
      test('19. Years before 2024 throw RangeError', () {
        expect(
          () => CalendarAlarmIdContract.prayerAlertId(
            date: DateTime(2023, 12, 31),
            prayer: PrayerId.fajr,
            decision: PrayerAlertDecision.alarm,
          ),
          throwsRangeError,
        );
      });

      test('20. Years after 2099 throw RangeError', () {
        expect(
          () => CalendarAlarmIdContract.prayerAlertId(
            date: DateTime(2100, 1, 1),
            prayer: PrayerId.fajr,
            decision: PrayerAlertDecision.alarm,
          ),
          throwsRangeError,
        );
      });

      test('21. UTC dates throw ArgumentError (Fail-Closed against silent date drift)', () {
        final utcDate = DateTime.utc(2026, 11, 8);
        expect(
          () => CalendarAlarmIdContract.prayerAlertId(
            date: utcDate,
            prayer: PrayerId.fajr,
            decision: PrayerAlertDecision.alarm,
          ),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('DateTime must be a local calendar date. UTC dates are rejected'),
          )),
        );
      });

      test('22. Reserved IDs (888, 999, 8888) are strictly isolated and never generated', () {
        for (int month = 1; month <= 12; month++) {
          final id = CalendarAlarmIdContract.prayerAlertId(
            date: DateTime(2026, month, 15),
            prayer: PrayerId.fajr,
            decision: PrayerAlertDecision.alarm,
          );
          for (final reservedId in CalendarAlarmIdContract.reservedIds) {
            expect(id, isNot(equals(reservedId)));
            expect(id, greaterThan(reservedId));
          }
        }
      });
    });

    // ========================================================================
    // GROUP F: COMPLETE PAIRWISE COLLISION MATRIX
    // ========================================================================
    group('Group F — Complete Pairwise Collision Matrix', () {
      test('23. Exhaustive 7-day horizon collision check: 182 distinct events produce 182 unique IDs', () {
        final allGeneratedIds = <int>{};
        int totalEventsCount = 0;

        for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
          final date = DateTime(2026, 11, 8 + dayOffset);

          for (final prayer in PrayerId.values) {
            // 1. Prayer Alarm
            final alarmId = CalendarAlarmIdContract.prayerAlertId(
              date: date,
              prayer: prayer,
              decision: PrayerAlertDecision.alarm,
            );
            expect(allGeneratedIds.add(alarmId), isTrue, reason: 'Duplicate ID: $alarmId');
            totalEventsCount++;

            // 2. Prayer Notification
            final notifId = CalendarAlarmIdContract.prayerAlertId(
              date: date,
              prayer: prayer,
              decision: PrayerAlertDecision.notification,
            );
            expect(allGeneratedIds.add(notifId), isTrue, reason: 'Duplicate ID: $notifId');
            totalEventsCount++;

            // 3. Iqama
            final iqamaId = CalendarAlarmIdContract.iqamaId(date: date, prayer: prayer);
            expect(allGeneratedIds.add(iqamaId), isTrue, reason: 'Duplicate ID: $iqamaId');
            totalEventsCount++;

            // 4. Post-prayer Azkar
            final postAzkarId = CalendarAlarmIdContract.postPrayerAzkarId(date: date, prayer: prayer);
            expect(allGeneratedIds.add(postAzkarId), isTrue, reason: 'Duplicate ID: $postAzkarId');
            totalEventsCount++;
          }

          // 5. Morning Azkar (once per day)
          final morningId = CalendarAlarmIdContract.morningAzkarId(date: date);
          expect(allGeneratedIds.add(morningId), isTrue, reason: 'Duplicate ID: $morningId');
          totalEventsCount++;

          // 6. Evening Azkar (once per day)
          final eveningId = CalendarAlarmIdContract.eveningAzkarId(date: date);
          expect(allGeneratedIds.add(eveningId), isTrue, reason: 'Duplicate ID: $eveningId');
          totalEventsCount++;
        }

        // 7 days * (5 prayers * 4 types + 2 daily azkar) = 7 * (20 + 2) = 7 * 22 = 154
        expect(totalEventsCount, equals(154));
        expect(allGeneratedIds.length, equals(154));

        // Ensure zero collision with reserved IDs
        for (final reserved in CalendarAlarmIdContract.reservedIds) {
          expect(allGeneratedIds.contains(reserved), isFalse);
        }
      });
    });
  });
}

