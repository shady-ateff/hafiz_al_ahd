import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_session_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_adhkar_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_quran_reading_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_session_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/quran_reading_goal.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/ports/focus_enforcement_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_coordinator.dart';
import 'package:hafiz_al_ahd/features/focus_mode/presentation/services/quran_focus_dwell_tracker.dart';

class StubEnforcementPort implements FocusEnforcementPort {
  bool isStopped = false;
  int stopCalls = 0;

  @override
  Future<bool> startEnforcement({
    required String sessionId,
    required String wardTitle,
  }) async =>
      true;

  @override
  Future<bool> stopEnforcement() async {
    stopCalls++;
    isStopped = true;
    return true;
  }

  @override
  Future<bool> isEnforcing() async => !isStopped;

  @override
  Future<FocusEnforcementStatus> getEnforcementStatus() async =>
      FocusEnforcementStatus.stopped();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryQuranReadingCompletionPort quranPort;
  late InMemoryAdhkarCompletionPort adhkarPort;
  late StubEnforcementPort enforcementPort;
  late FocusSessionRepositoryImpl sessionRepo;
  late FocusSessionCoordinator coordinator;

  setUp(() {
    quranPort = InMemoryQuranReadingCompletionPort();
    adhkarPort = InMemoryAdhkarCompletionPort();
    enforcementPort = StubEnforcementPort();
    sessionRepo = FocusSessionRepositoryImpl(
      localDataSource: FocusSessionLocalDataSourceImpl.inMemory(),
    );

    coordinator = FocusSessionCoordinator(
      adhkarPort: adhkarPort,
      quranPort: quranPort,
      enforcementPort: enforcementPort,
      repository: sessionRepo,
    );
  });

  tearDown(() {
    coordinator.dispose();
    quranPort.dispose();
    adhkarPort.dispose();
  });

  group('QuranFocusDwellTracker Tests', () {
    test('Dwell below 20 seconds is not recorded upon page turn', () async {
      final tracker = QuranFocusDwellTracker(
        port: quranPort,
        minimumDwellThreshold: const Duration(seconds: 20),
      );

      final receivedEvents = <int>[];
      final sub = quranPort.onPageRead.listen((event) {
        receivedEvents.add(event.pageNumber);
      });

      tracker.onPageBecameVisible(1);
      // Wait only 100 milliseconds
      await Future.delayed(const Duration(milliseconds: 100));

      // Turn page before 20s threshold
      tracker.onPageBecameVisible(2);

      expect(receivedEvents, isEmpty);
      await sub.cancel();
      tracker.dispose();
    });

    test('Dwell >= 20 seconds is recorded upon page turn or dispose', () async {
      // Use shorter threshold for testing speed
      final tracker = QuranFocusDwellTracker(
        port: quranPort,
        minimumDwellThreshold: const Duration(milliseconds: 50),
      );

      final receivedEvents = <int>[];
      final sub = quranPort.onPageRead.listen((event) {
        receivedEvents.add(event.pageNumber);
      });

      tracker.onPageBecameVisible(5);
      await Future.delayed(const Duration(milliseconds: 60));

      tracker.onPageBecameVisible(6);
      await Future.delayed(Duration.zero);
      expect(receivedEvents, contains(5));

      await Future.delayed(const Duration(milliseconds: 60));
      tracker.dispose();
      await Future.delayed(Duration.zero);
      expect(receivedEvents, contains(6));

      await sub.cancel();
    });

    test('Backgrounding halts accumulation and records only prior genuine dwell', () async {
      final tracker = QuranFocusDwellTracker(
        port: quranPort,
        minimumDwellThreshold: const Duration(milliseconds: 50),
      );

      final receivedEvents = <int>[];
      final sub = quranPort.onPageRead.listen((event) {
        receivedEvents.add(event.pageNumber);
      });

      tracker.onPageBecameVisible(10);
      await Future.delayed(const Duration(milliseconds: 60));

      // User leaves app to background
      tracker.onAppLifecycleChanged(AppLifecycleState.paused);
      await Future.delayed(Duration.zero);
      expect(receivedEvents, contains(10));

      // While in background, no accumulation should happen
      await Future.delayed(const Duration(milliseconds: 70));
      tracker.onPageBecameVisible(11); // Page turn while paused should not flush background time
      expect(receivedEvents.length, 1);

      await sub.cancel();
      tracker.dispose();
    });
  });

  group('End-to-End Quran Goal Completion Integration', () {
    test('Dwell events satisfy target page count and dismantle native shield', () async {
      // Start a Quran reading session with a 2-page goal
      await coordinator.startSession(
        sessionId: 'quran_e2e_session',
        wardType: FocusWardType.quranReading,
        quranGoal: QuranReadingGoal.pageCount(
          2,
          minDurationPerPage: Duration.zero, // In unit test, dwell is accepted
        ),
      );

      expect(coordinator.state.status, FocusSessionStatus.active);
      expect(coordinator.state.wardType, FocusWardType.quranReading);

      // Page 1 dwelled
      quranPort.recordPageDwell(
        pageNumber: 101,
        timeSpent: const Duration(seconds: 25),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(coordinator.state.status, FocusSessionStatus.active);

      // Page 2 dwelled (completes 2-page goal)
      quranPort.recordPageDwell(
        pageNumber: 102,
        timeSpent: const Duration(seconds: 30),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Verified goal completion
      expect(coordinator.state.status, FocusSessionStatus.completed);
      expect(enforcementPort.stopCalls, 1);
      expect(enforcementPort.isStopped, isTrue);

      // Verify SQLite state
      final activeFromDb = await sessionRepo.getActiveSession();
      expect(activeFromDb, isNull); // Cleared active session

      final history = await sessionRepo.getSessionHistory();
      expect(history.length, 1);
      expect(history.first.status, FocusSessionStatus.completed);
    });
  });
}
