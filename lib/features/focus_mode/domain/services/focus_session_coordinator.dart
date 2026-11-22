import 'dart:async';
import '../entities/focus_enforcement_operation.dart';
import '../entities/focus_session_progress.dart';
import '../entities/focus_session_state.dart';
import '../entities/focus_session_status.dart';
import '../entities/focus_ward_type.dart';
import '../entities/quran_reading_goal.dart';
import '../entities/ward_completion_event.dart';
import '../ports/adhkar_completion_port.dart';
import '../ports/focus_enforcement_port.dart';
import '../ports/quran_reading_completion_port.dart';
import '../repositories/focus_session_repository.dart';
import 'focus_completion_evaluator.dart';

/// Coordinator for managing the domain lifecycle and state transitions of Focus sessions.
/// Listens to completion ports and controls enforcement via an abstract [FocusEnforcementPort]
/// with atomic persistence via [FocusSessionRepository].
class FocusSessionCoordinator {
  final AdhkarCompletionPort adhkarPort;
  final QuranReadingCompletionPort quranPort;
  final FocusEnforcementPort enforcementPort;
  final FocusSessionRepository? repository;
  final FocusCompletionEvaluator evaluator;

  FocusSessionState _state = FocusSessionState.initial();
  FocusSessionState get state => _state;

  final StreamController<FocusSessionState> _stateController =
      StreamController<FocusSessionState>.broadcast();
  Stream<FocusSessionState> get onStateChanged => _stateController.stream;

  StreamSubscription<AdhkarCompletionEvent>? _adhkarSub;
  StreamSubscription<QuranPageReadEvent>? _quranPageSub;
  StreamSubscription<QuranGoalCompletedEvent>? _quranGoalSub;

  // Set of distinct pages read (prevents counting the same page multiple times)
  final Set<int> _genuinePagesRead = {};
  Duration _accumulatedGenuineDuration = Duration.zero;

  // Track completed unique items
  final Set<String> _completedItemKeys = {};

  FocusSessionCoordinator({
    required this.adhkarPort,
    required this.quranPort,
    required this.enforcementPort,
    this.repository,
    this.evaluator = const FocusCompletionEvaluator(),
  });

  /// Starts a new Focus session for a specific [wardType] with transactional persistence.
  Future<void> startSession({
    required String sessionId,
    required FocusWardType wardType,
    QuranReadingGoal? quranGoal,
    bool startEnforcementImmediately = true,
  }) async {
    _cleanupSubscriptions();
    _genuinePagesRead.clear();
    _accumulatedGenuineDuration = Duration.zero;
    _completedItemKeys.clear();

    _state = FocusSessionState(
      sessionId: sessionId,
      wardType: wardType,
      status: FocusSessionStatus.active,
      startTime: DateTime.now(),
      quranGoal: quranGoal,
    );

    // 1. Transactional persistence of session + progress + pending start op
    FocusEnforcementOperation? startOp;
    if (repository != null) {
      final initialProgress = FocusSessionProgress.initial(
        sessionId: sessionId,
        quranGoal: quranGoal,
      );
      startOp = FocusEnforcementOperation(
        operationId: 'op_start_$sessionId',
        sessionId: sessionId,
        operationType: EnforcementOperationType.start,
        status: EnforcementOperationStatus.pending,
        createdAt: DateTime.now(),
      );

      await repository!.saveActiveSession(
        _state,
        progress: initialProgress,
        pendingOperation: startOp,
      );
    }

    _emitState();
    _subscribeToPorts();

    // 2. Dispatch start to native engine
    if (startEnforcementImmediately) {
      final ok = await enforcementPort.startEnforcement(
        sessionId: sessionId,
        wardTitle: wardType.displayName,
      );

      if (repository != null && startOp != null) {
        if (ok) {
          await repository!.deleteEnforcementOperation(startOp.operationId);
        } else {
          await repository!.updateEnforcementOperationStatus(
            operationId: startOp.operationId,
            status: EnforcementOperationStatus.failed,
            error: 'Native startEnforcement returned false',
          );
        }
      }
    }
  }

  /// Restores an existing active/snoozed session (e.g. from RecoveryManager on cold start).
  void restoreSession({
    required FocusSessionState session,
    FocusSessionProgress? progress,
  }) {
    _cleanupSubscriptions();
    _genuinePagesRead.clear();
    _accumulatedGenuineDuration = Duration.zero;
    _completedItemKeys.clear();

    _state = session;

    if (progress != null) {
      _genuinePagesRead.addAll(progress.readQuranPages);
      _accumulatedGenuineDuration = progress.accumulatedQuranDuration;
      _completedItemKeys.addAll(progress.completedItemKeys);
    }

    _emitState();
    _subscribeToPorts();
  }

  /// Snoozes the current session if allowed (max 2 times).
  Future<bool> snoozeSession() async {
    if (!_state.canSnooze) {
      return false;
    }

    _state = _state.copyWith(
      status: FocusSessionStatus.snoozed,
      snoozeCount: _state.snoozeCount + 1,
    );

    if (repository != null) {
      await repository!.saveActiveSession(_state);
    }

    _emitState();
    return true;
  }

  /// Resumes the session back to active from snooze.
  Future<void> resumeFromSnooze() async {
    if (_state.status == FocusSessionStatus.snoozed) {
      _state = _state.copyWith(status: FocusSessionStatus.active);
      if (repository != null) {
        await repository!.saveActiveSession(_state);
      }
      _emitState();
    }
  }

  /// Intentionally cancels the session from within Hafiz Al-Ahd.
  Future<void> cancelSession() async {
    if (_state.isTerminal) return;

    _state = _state.copyWith(
      status: FocusSessionStatus.cancelled,
      endTime: DateTime.now(),
    );
    _cleanupSubscriptions();
    _emitState();

    final stopOp = FocusEnforcementOperation(
      operationId: 'op_cancel_${_state.sessionId}',
      sessionId: _state.sessionId,
      operationType: EnforcementOperationType.stop,
      status: EnforcementOperationStatus.pending,
      createdAt: DateTime.now(),
    );

    if (repository != null) {
      await repository!.archiveSession(_state, pendingOperation: stopOp);
    }

    final stopped = await enforcementPort.stopEnforcement();
    if (stopped) {
      if (repository != null) {
        await repository!.deleteEnforcementOperation(stopOp.operationId);
      }
    } else {
      _state = _state.copyWith(enforcementStopFailed: true);
      _emitState();
      if (repository != null) {
        await repository!.updateEnforcementOperationStatus(
          operationId: stopOp.operationId,
          status: EnforcementOperationStatus.failed,
          error: 'Native stopEnforcement returned false',
        );
      }
    }
  }

  /// Manually or programmatically completes the active session (e.g. from UI completion triggers).
  Future<void> completeActiveSession() async {
    await _completeSession();
  }

  /// Marks the session as interrupted due to external anomalies.
  Future<void> interruptSession(String reason) async {
    if (_state.isTerminal) return;

    _state = _state.copyWith(
      status: FocusSessionStatus.interrupted,
      endTime: DateTime.now(),
      interruptionReason: reason,
    );
    _cleanupSubscriptions();
    _emitState();

    final stopOp = FocusEnforcementOperation(
      operationId: 'op_interrupt_${_state.sessionId}',
      sessionId: _state.sessionId,
      operationType: EnforcementOperationType.stop,
      status: EnforcementOperationStatus.pending,
      createdAt: DateTime.now(),
    );

    if (repository != null) {
      await repository!.archiveSession(_state, pendingOperation: stopOp);
    }

    final stopped = await enforcementPort.stopEnforcement();
    if (stopped) {
      if (repository != null) {
        await repository!.deleteEnforcementOperation(stopOp.operationId);
      }
    } else {
      _state = _state.copyWith(enforcementStopFailed: true);
      _emitState();
      if (repository != null) {
        await repository!.updateEnforcementOperationStatus(
          operationId: stopOp.operationId,
          status: EnforcementOperationStatus.failed,
          error: 'Native stopEnforcement returned false',
        );
      }
    }
  }

  void _subscribeToPorts() {
    // 1. Listen for Adhkar completion events
    _adhkarSub = adhkarPort.onAdhkarEvent.listen((event) async {
      if (_state.isTerminal) return;

      _completedItemKeys.addAll(event.completedItemKeys);

      // Persist progress snapshot
      if (repository != null) {
        await repository!.saveProgress(
          FocusSessionProgress(
            sessionId: _state.sessionId,
            requiredItemKeys: event.requiredItemKeys,
            completedItemKeys: _completedItemKeys,
            readQuranPages: _genuinePagesRead,
            accumulatedQuranDuration: _accumulatedGenuineDuration,
            quranGoalSnapshot: _state.quranGoal,
            updatedAt: DateTime.now(),
          ),
        );
      }

      final isCompleted = evaluator.evaluateAdhkarCompletion(
        session: _state,
        event: event,
      );

      if (isCompleted) {
        await _completeSession();
      }
    });

    // 2. Listen for Quran page reading events
    _quranPageSub = quranPort.onPageRead.listen((event) async {
      if (_state.isTerminal || _state.wardType != FocusWardType.quranReading) {
        return;
      }

      final goal = _state.quranGoal ?? QuranReadingGoal.pageCount(1);
      final isGenuine = evaluator.isPageDwellGenuine(
        goal: goal,
        event: event,
      );

      if (isGenuine) {
        final isNewPage = !_genuinePagesRead.contains(event.pageNumber);
        _genuinePagesRead.add(event.pageNumber);

        if (isNewPage) {
          _accumulatedGenuineDuration += event.timeSpent;
        }

        // Persist Quran progress
        if (repository != null) {
          await repository!.saveProgress(
            FocusSessionProgress(
              sessionId: _state.sessionId,
              readQuranPages: _genuinePagesRead,
              accumulatedQuranDuration: _accumulatedGenuineDuration,
              lastCompletedPage: event.pageNumber,
              quranGoalSnapshot: _state.quranGoal,
              updatedAt: DateTime.now(),
            ),
          );
        }

        final goalSatisfied = evaluator.evaluateQuranGoalCompletion(
          session: _state,
          uniquePagesCount: _genuinePagesRead.length,
          totalGenuineDuration: _accumulatedGenuineDuration,
        );

        if (goalSatisfied) {
          await _completeSession();
        }
      }
    });

    // 3. Listen for direct Quran goal completion events
    _quranGoalSub = quranPort.onGoalCompleted.listen((event) async {
      if (_state.isTerminal || _state.wardType != FocusWardType.quranReading) {
        return;
      }

      final goal = _state.quranGoal;
      final completedSurah = goal?.goalType == QuranGoalType.surah
          ? event.achievedTarget
          : null;

      final isCompleted = evaluator.evaluateQuranGoalCompletion(
        session: _state,
        uniquePagesCount: event.totalPagesRead,
        totalGenuineDuration: event.totalReadingDuration,
        completedSurahNumber: completedSurah,
        eventSessionId: event.sessionId,
      );

      if (isCompleted) {
        await _completeSession();
      }
    });
  }

  Future<void> _completeSession() async {
    if (_state.isTerminal) return;

    _state = _state.copyWith(
      status: FocusSessionStatus.completed,
      endTime: DateTime.now(),
    );
    _cleanupSubscriptions();
    _emitState();

    final stopOp = FocusEnforcementOperation(
      operationId: 'op_complete_${_state.sessionId}',
      sessionId: _state.sessionId,
      operationType: EnforcementOperationType.stop,
      status: EnforcementOperationStatus.pending,
      createdAt: DateTime.now(),
    );

    // Atomic archive in SQLite
    if (repository != null) {
      await repository!.archiveSession(_state, pendingOperation: stopOp);
    }

    final stopped = await enforcementPort.stopEnforcement();
    if (stopped) {
      if (repository != null) {
        await repository!.deleteEnforcementOperation(stopOp.operationId);
      }
    } else {
      _state = _state.copyWith(enforcementStopFailed: true);
      _emitState();
      if (repository != null) {
        await repository!.updateEnforcementOperationStatus(
          operationId: stopOp.operationId,
          status: EnforcementOperationStatus.failed,
          error: 'stopEnforcement returned false',
        );
      }
    }
  }

  void _cleanupSubscriptions() {
    _adhkarSub?.cancel();
    _adhkarSub = null;
    _quranPageSub?.cancel();
    _quranPageSub = null;
    _quranGoalSub?.cancel();
    _quranGoalSub = null;
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void dispose() {
    _cleanupSubscriptions();
    _stateController.close();
  }
}
