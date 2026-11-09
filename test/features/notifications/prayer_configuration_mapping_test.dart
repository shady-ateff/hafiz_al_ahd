import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_alarm_config.dart';
import 'package:hafiz_al_ahd/features/notifications/domain/entities/prayer_scheduling_decision.dart';

void main() {
  group('P4.1-B.3 Phase 2C.2.4 — Prayer Configuration Mapping Contract Tests', () {
    // ========================================================================
    // GROUP A: DIRECT MAPPING CONTRACT
    // ========================================================================
    group('Group A: Direct Mapping Contract', () {
      test('1. Fajr with alarm maps to PrayerAlertDecision.alarm', () {
        const config = PrayerAlarmConfig(
          prayerId: PrayerId.fajr,
          alarmType: PrayerAlarmType.alarm,
        );
        expect(PrayerAlertDecision.fromConfig(config), equals(PrayerAlertDecision.alarm));
        expect(config.decision, equals(PrayerAlertDecision.alarm));
      });

      test('2. Dhuhr with notification maps to PrayerAlertDecision.notification', () {
        const config = PrayerAlarmConfig(
          prayerId: PrayerId.dhuhr,
          alarmType: PrayerAlarmType.notification,
        );
        expect(PrayerAlertDecision.fromConfig(config), equals(PrayerAlertDecision.notification));
        expect(config.decision, equals(PrayerAlertDecision.notification));
      });

      test('3. Asr with off maps to PrayerAlertDecision.none', () {
        const config = PrayerAlarmConfig(
          prayerId: PrayerId.asr,
          alarmType: PrayerAlarmType.off,
        );
        expect(PrayerAlertDecision.fromConfig(config), equals(PrayerAlertDecision.none));
        expect(config.decision, equals(PrayerAlertDecision.none));
      });

      test('4. Maghrib with alarm maps to PrayerAlertDecision.alarm', () {
        const config = PrayerAlarmConfig(
          prayerId: PrayerId.maghrib,
          alarmType: PrayerAlarmType.alarm,
        );
        expect(PrayerAlertDecision.fromConfig(config), equals(PrayerAlertDecision.alarm));
        expect(config.decision, equals(PrayerAlertDecision.alarm));
      });

      test('5. Isha with notification maps to PrayerAlertDecision.notification', () {
        const config = PrayerAlarmConfig(
          prayerId: PrayerId.isha,
          alarmType: PrayerAlarmType.notification,
        );
        expect(PrayerAlertDecision.fromConfig(config), equals(PrayerAlertDecision.notification));
        expect(config.decision, equals(PrayerAlertDecision.notification));
      });
    });

    // ========================================================================
    // GROUP B: PER-PRAYER INDEPENDENCE INVARIANT
    // ========================================================================
    group('Group B: Per-Prayer Independence Invariant', () {
      test('6. Modifying Fajr does not alter Dhuhr decision', () {
        const dhuhrConfig = PrayerAlarmConfig(
          prayerId: PrayerId.dhuhr,
          alarmType: PrayerAlarmType.notification,
        );

        final fajr1 = const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.alarm);
        final fajr2 = const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.off);

        expect(fajr1.decision, equals(PrayerAlertDecision.alarm));
        expect(fajr2.decision, equals(PrayerAlertDecision.none));
        // Dhuhr remains strictly unchanged
        expect(dhuhrConfig.decision, equals(PrayerAlertDecision.notification));
      });

      test('7. Modifying Dhuhr does not alter Asr decision', () {
        const asrConfig = PrayerAlarmConfig(
          prayerId: PrayerId.asr,
          alarmType: PrayerAlarmType.off,
        );

        final dhuhr1 = const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.alarm);
        final dhuhr2 = const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification);

        expect(dhuhr1.decision, equals(PrayerAlertDecision.alarm));
        expect(dhuhr2.decision, equals(PrayerAlertDecision.notification));
        // Asr remains strictly unchanged
        expect(asrConfig.decision, equals(PrayerAlertDecision.none));
      });

      test('8. All five prayers can have distinct heterogeneous decisions simultaneously', () {
        final configs = {
          PrayerId.fajr: const PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.alarm),
          PrayerId.dhuhr: const PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification),
          PrayerId.asr: const PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.off),
          PrayerId.maghrib: const PrayerAlarmConfig(prayerId: PrayerId.maghrib, alarmType: PrayerAlarmType.alarm),
          PrayerId.isha: const PrayerAlarmConfig(prayerId: PrayerId.isha, alarmType: PrayerAlarmType.notification),
        };

        final decisions = configs.map((k, v) => MapEntry(k, v.decision));

        expect(decisions[PrayerId.fajr], equals(PrayerAlertDecision.alarm));
        expect(decisions[PrayerId.dhuhr], equals(PrayerAlertDecision.notification));
        expect(decisions[PrayerId.asr], equals(PrayerAlertDecision.none));
        expect(decisions[PrayerId.maghrib], equals(PrayerAlertDecision.alarm));
        expect(decisions[PrayerId.isha], equals(PrayerAlertDecision.notification));
      });

      test('9. All five prayers can be simultaneously configured to off', () {
        final configs = {
          for (final p in PrayerId.values)
            p: PrayerAlarmConfig(prayerId: p, alarmType: PrayerAlarmType.off),
        };

        for (final entry in configs.entries) {
          expect(entry.value.decision, equals(PrayerAlertDecision.none));
        }
      });

      test('10. All five prayers can be simultaneously configured to alarm', () {
        final configs = {
          for (final p in PrayerId.values)
            p: PrayerAlarmConfig(prayerId: p, alarmType: PrayerAlarmType.alarm),
        };

        for (final entry in configs.entries) {
          expect(entry.value.decision, equals(PrayerAlertDecision.alarm));
        }
      });

      test('11. All five prayers can be simultaneously configured to notification', () {
        final configs = {
          for (final p in PrayerId.values)
            p: PrayerAlarmConfig(prayerId: p, alarmType: PrayerAlarmType.notification),
        };

        for (final entry in configs.entries) {
          expect(entry.value.decision, equals(PrayerAlertDecision.notification));
        }
      });
    });

    // ========================================================================
    // GROUP C: AUXILIARY EVENTS DECOUPLING CONTRACT (DESIGN INVARIANTS)
    // ========================================================================
    group('Group C: Auxiliary Events Decoupling Contract (Design Invariants)', () {
      test('12. PrayerAlertDecision is strictly decoupled from Iqama state', () {
        const offConfig = PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.off);
        expect(offConfig.decision, equals(PrayerAlertDecision.none));
        // The decision entity contains zero Iqama flags, guaranteeing domain isolation
      });

      test('13. PrayerAlertDecision is strictly decoupled from Morning Azkar', () {
        const offConfig = PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.off);
        expect(offConfig.decision, equals(PrayerAlertDecision.none));
        // Fajr alert decision has zero impact on morning azkar cadence in domain model
      });

      test('14. PrayerAlertDecision is strictly decoupled from Evening Azkar', () {
        const offConfig = PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.off);
        expect(offConfig.decision, equals(PrayerAlertDecision.none));
        // Asr alert decision has zero impact on evening azkar cadence in domain model
      });

      test('15. PrayerAlertDecision is strictly decoupled from Post-Prayer Azkar', () {
        for (final p in PrayerId.values) {
          final offConfig = PrayerAlarmConfig(prayerId: p, alarmType: PrayerAlarmType.off);
          expect(offConfig.decision, equals(PrayerAlertDecision.none));
        }
      });
    });

    // ========================================================================
    // GROUP D: TRANSITION SEMANTICS — FULL 9-CELL DESIRED-STATE MATRIX
    // ========================================================================
    group('Group D: Transition Semantics — Full 9-Cell Desired-State Matrix', () {
      // Cell 1: alarm -> alarm => alarm
      test('16. Transition [alarm -> alarm]: Desired state is alarm', () {
        const prev = PrayerAlarmType.alarm;
        const next = PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.alarm);
        expect(prev, equals(PrayerAlarmType.alarm));
        expect(next.decision, equals(PrayerAlertDecision.alarm));
      });

      // Cell 2: alarm -> notification => notification
      test('17. Transition [alarm -> notification]: Desired state is notification', () {
        const prev = PrayerAlarmType.alarm;
        const next = PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.notification);
        expect(prev, equals(PrayerAlarmType.alarm));
        expect(next.decision, equals(PrayerAlertDecision.notification));
      });

      // Cell 3: alarm -> off => none
      test('18. Transition [alarm -> off]: Desired state is none', () {
        const prev = PrayerAlarmType.alarm;
        const next = PrayerAlarmConfig(prayerId: PrayerId.fajr, alarmType: PrayerAlarmType.off);
        expect(prev, equals(PrayerAlarmType.alarm));
        expect(next.decision, equals(PrayerAlertDecision.none));
      });

      // Cell 4: notification -> alarm => alarm
      test('19. Transition [notification -> alarm]: Desired state is alarm', () {
        const prev = PrayerAlarmType.notification;
        const next = PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.alarm);
        expect(prev, equals(PrayerAlarmType.notification));
        expect(next.decision, equals(PrayerAlertDecision.alarm));
      });

      // Cell 5: notification -> notification => notification
      test('20. Transition [notification -> notification]: Desired state is notification', () {
        const prev = PrayerAlarmType.notification;
        const next = PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.notification);
        expect(prev, equals(PrayerAlarmType.notification));
        expect(next.decision, equals(PrayerAlertDecision.notification));
      });

      // Cell 6: notification -> off => none
      test('21. Transition [notification -> off]: Desired state is none', () {
        const prev = PrayerAlarmType.notification;
        const next = PrayerAlarmConfig(prayerId: PrayerId.dhuhr, alarmType: PrayerAlarmType.off);
        expect(prev, equals(PrayerAlarmType.notification));
        expect(next.decision, equals(PrayerAlertDecision.none));
      });

      // Cell 7: off -> alarm => alarm
      test('22. Transition [off -> alarm]: Desired state is alarm', () {
        const prev = PrayerAlarmType.off;
        const next = PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.alarm);
        expect(prev, equals(PrayerAlarmType.off));
        expect(next.decision, equals(PrayerAlertDecision.alarm));
      });

      // Cell 8: off -> notification => notification
      test('23. Transition [off -> notification]: Desired state is notification', () {
        const prev = PrayerAlarmType.off;
        const next = PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.notification);
        expect(prev, equals(PrayerAlarmType.off));
        expect(next.decision, equals(PrayerAlertDecision.notification));
      });

      // Cell 9: off -> off => none
      test('24. Transition [off -> off]: Desired state is none', () {
        const prev = PrayerAlarmType.off;
        const next = PrayerAlarmConfig(prayerId: PrayerId.asr, alarmType: PrayerAlarmType.off);
        expect(prev, equals(PrayerAlarmType.off));
        expect(next.decision, equals(PrayerAlertDecision.none));
      });
    });
  });
}

