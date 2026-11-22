import 'package:flutter_test/flutter_test.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/datasources/focus_session_local_data_source.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_adhkar_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/ports/in_memory_quran_reading_completion_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/data/repositories/focus_session_repository_impl.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_enforcement_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_session_status.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/focus_ward_type.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/entities/ward_completion_event.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/ports/focus_enforcement_port.dart';
import 'package:hafiz_al_ahd/features/focus_mode/domain/services/focus_session_coordinator.dart';

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

  group('End-to-End Adhkar Session Completion Integration', () {
    test('100% Adhkar category completion completes session, stops shield, and archives atomically', () async {
      // 1. Start Morning Azkar focus session
      await coordinator.startSession(
        sessionId: 'morning_azkar_e2e',
        wardType: FocusWardType.morningAzkar,
      );

      expect(coordinator.state.status, FocusSessionStatus.active);
      expect(coordinator.state.wardType, FocusWardType.morningAzkar);

      // Verify active in repository
      final activeFromDb = await sessionRepo.getActiveSession();
      expect(activeFromDb, isNotNull);
      expect(activeFromDb!.sessionId, 'morning_azkar_e2e');

      // 2. Dispatch 100% category completion event
      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.morningAzkar,
          categoryKey: FocusWardType.morningAzkar.categoryKey,
          totalCount: 15,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // 3. Coordinator transitioned to completed
      expect(coordinator.state.status, FocusSessionStatus.completed);
      expect(enforcementPort.stopCalls, 1);
      expect(enforcementPort.isStopped, isTrue);

      // 4. ACID storage checks: active is null, history has completed record
      final clearedActive = await sessionRepo.getActiveSession();
      expect(clearedActive, isNull);

      final history = await sessionRepo.getSessionHistory();
      expect(history.length, 1);
      expect(history.first.sessionId, 'morning_azkar_e2e');
      expect(history.first.status, FocusSessionStatus.completed);
    });

    test('Completion event of a different ward does not complete current active session', () async {
      await coordinator.startSession(
        sessionId: 'evening_session',
        wardType: FocusWardType.eveningAzkar,
      );

      // Dispatch morning azkar completion instead of evening
      adhkarPort.dispatchEvent(
        AdhkarCompletionEvent.completed(
          wardType: FocusWardType.morningAzkar,
          categoryKey: FocusWardType.morningAzkar.categoryKey,
          totalCount: 10,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      // Remains active because ward types do not match
      expect(coordinator.state.status, FocusSessionStatus.active);
      expect(enforcementPort.stopCalls, 0);
    });
  });
}
