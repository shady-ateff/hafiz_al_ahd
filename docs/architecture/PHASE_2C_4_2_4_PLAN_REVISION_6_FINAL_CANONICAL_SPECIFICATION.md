# Phase 2C.4.2.4 Implementation Plan (Revision 6)
## Final Canonical Specification: Deterministic Verification, Multi-Phase State Machine, & Bounded Evidence Contracts

**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** Phase 2C.4.2.4  
**Gate:** STOP GATE 5 (Plan Revision 6 Submission)  
**Author:** AI Pair Programmer (DeepMind)  
**Reviewer:** User / Chief Architect  
**Status:** PROPOSED FOR FORMAL ARCHITECTURAL APPROVAL  

---

## 1. Executive Summary & Resolution of Revision 5 Critiques

This **Revision 6 Plan** addresses all ten architectural requirements from the Chief Architect's review, establishing an uncompromising, mathematically grounded reconciliation specification:

| # | Critique Requirement | Canonical Resolution in Revision 6 |
|---|---|---|
| **1 (Critical)** | Deterministic Payload Contract (No `Object.hash()`) | Implemented persistent canonical serialization with deterministic 64-bit FNV-1a hashing. Explicitly scoped as **Application-Level Correlation**, not cryptographic proof. |
| **2 (Critical)** | Notification Cancellation Timing Evidence | Acknowledged that FLN pending requests do not reveal scheduled time. Fingerprint time is strictly application-side metadata. Any unbound or missing fingerprint fails closed as `EventCancellationStatus.unverifiable`, suppressing cancellation. |
| **3 (Critical)** | Notification Cancellation Failure Window & Recovery | Formalized failure window semantics: if FLN cancel succeeds but fingerprint cleanup fails, operation returns `failed` and day remains incomplete. Retry cleans up orphan fingerprint without rescheduling. |
| **4 (Critical)** | Alarm Cancellation Truth Boundaries | Scoped `cancelAlarmSafely` to **Plugin-Level Cancellation** (does not claim L4 OS AlarmManager inspection). Active ringing check executes before any destructive action. |
| **5 (High)** | Explicit Reconciliation State Machine | Formulated complete, exhaustive decision trees for `alarm`, `notification`, and `off` modes covering `matching`, `absent`, `stale`, and `unverifiable`. |
| **6 (High)** | Remove Overclaiming from Tests 24b & 24p | Refactored Tests 24b and 24p to assert control flow (no pre-cancellation, dispatch attempted, opposing not cancelled, day incomplete, horizon capped), logging same-ID post-failure state as characterization rather than an unconditional acceptance requirement. |
| **7 (High)** | Auxiliary L2 Verification Scoped to ID-Only | Formally defined Auxiliary L2 as **Pending Request ID-Only Presence**. Explicitly disclaimed payload/config/time verification for auxiliary events. |
| **8 (High)** | Strengthen Test 24q Assertions | Test 24q verifies orphan cleanup, asserts zero dispatch calls, verifies empty pending queue, injects cleanup failure, and proves no phantom resurrection on retry. |
| **9 (High)** | Test 24l Reconciled with Orphan Recovery | Test 24l asserts `failed` outcome on cleanup failure, leaves day incomplete, and verifies retry completes orphan cleanup. |
| **10 (High)** | Reconcile Test Counts | Reconciled test suite: **52 total tests** ($12 + 4 + 4 + 22 + 6 + 4 = 52$), with Group D containing **22 specific fault-injection cases**. |

---

## 2. Deterministic Payload Contract & Application-Level Correlation

### 2.1 The Problem with `Object.hash()`:
Dart's `Object.hash()` uses process-randomized seeds across VM runs, making it non-deterministic across app restarts.

### 2.2 Canonical Serialization & Deterministic FNV-1a Digest:
To produce a 100% persistent, deterministic hash across sessions without external dependencies, we use canonical string concatenation and standard 64-bit FNV-1a:

```dart
class NotificationPayloadContract {
  static const int _fnvOffsetBasis = 0xcbf29ce484222325;
  static const int _fnvPrime = 0x100000001b3;

  /// Computes a deterministic 64-bit FNV-1a hex digest over canonical UTF-8 bytes.
  static String computeConfigDigest({
    required String channelId,
    required String soundSource,
    required String title,
    required String body,
  }) {
    // Canonical delimited string avoiding collision
    final canonical = 'chan:$channelId|snd:$soundSource|ttl:$title|bdy:$body';
    int hash = _fnvOffsetBasis;
    for (final unit in canonical.codeUnits) {
      hash ^= unit;
      hash = (hash * _fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Builds the payload string passed to FLN and stored in SharedPreferences.
  static String buildPayload({
    required int eventId,
    required DateTime scheduledTime,
    required String channelId,
    required String soundSource,
    required String title,
    required String body,
    int generation = 1,
  }) {
    final digest = computeConfigDigest(
      channelId: channelId,
      soundSource: soundSource,
      title: title,
      body: body,
    );
    final timeEpoch = scheduledTime.millisecondsSinceEpoch;
    return 'prayer_${eventId}_g${generation}_t${timeEpoch}_$digest';
  }
}
```

> [!IMPORTANT]
> **Strict Evidence Boundary:** This mechanism provides **Application-Level Metadata Correlation** between the FLN pending queue and local SharedPreferences. It does **NOT** claim cryptographic non-repudiation or independent OS kernel inspection.

---

## 3. Evidence Boundaries & Truth Claims

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Level 1: Platform Channel Dispatch (L1)                                      │
│ • Truth Claim: MethodChannel call returned without platform exception.      │
│ • Boundary: Does NOT prove storage in plugin registry or OS armed timer.    │
├─────────────────────────────────────────────────────────────────────────────┤
│ Level 2: Local Plugin Registry / Queue Query (L2)                           │
│ • Alarm Truth Claim: Alarm.getAlarm(id) returned matching record in SQLite. │
│ • Notification Tier 1 Claim: FLN pendingNotificationRequests() has ID.      │
│ • Notification Tier 2 Claim: SharedPreferences fingerprint matches native   │
│   request.payload.                                                          │
│ • Boundary: Application-side metadata only; does NOT inspect Android OS     │
│   AlarmManager / NotificationManager kernel system services (L4).           │
├─────────────────────────────────────────────────────────────────────────────┤
│ Auxiliary Alerts (Iqama / Azkar) L2 Boundary:                               │
│ • ID-Only Presence: Verifies request ID exists in FLN pending queue.        │
│ • Boundary: No payload, channel, sound, or trigger time verification.       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Cancellation Model & Actual-Time Temporal Guard

### 4.1 Typed Cancellation Outcome:
```dart
enum EventCancellationStatus {
  cancelled,        // Event was active in registry/queue and successfully cancelled
  alreadyAbsent,    // Event was verified absent prior to cancellation (idempotent clean)
  deferredImminent, // Cancellation suppressed: actual time within [-15s, +60s]
  deferredRinging,  // Cancellation suppressed: alarm is actively playing audio
  failed,           // PlatformException or MissingPluginException during cancellation
  unverifiable,     // Pre-cancellation query threw exception or metadata unbound (Fail-Closed)
}

extension EventCancellationStatusX on EventCancellationStatus {
  bool get isSuccessful =>
      this == EventCancellationStatus.cancelled ||
      this == EventCancellationStatus.alreadyAbsent;

  bool get isDeferred =>
      this == EventCancellationStatus.deferredImminent ||
      this == EventCancellationStatus.deferredRinging;
}
```

### 4.2 Exact Duration Boundary Math (Closed Interval):
```dart
static bool isWithinImminentWindow(DateTime actualScheduledTime, DateTime now) {
  final difference = actualScheduledTime.difference(now);
  return difference >= const Duration(seconds: -15) &&
         difference <= const Duration(seconds: 60);
}
```

### 4.3 Alarm Cancellation Protocol (`cancelAlarmSafely`):
1. **Ringing Audio Guard (Pre-Destructive Check):**
   - Query `Alarm.isRinging(id)`.
   - If `true` $\implies$ return `EventCancellationStatus.deferredRinging` immediately. **Zero destructive actions taken.**
2. **Registry Query:**
   - Query `Alarm.getAlarm(id)`.
   - If `null` $\implies$ return `EventCancellationStatus.alreadyAbsent`.
   - If throws `PlatformException` $\implies$ return `EventCancellationStatus.unverifiable`.
3. **Temporal Proximity Guard:**
   - If `isWithinImminentWindow(alarm.dateTime, DateTime.now())` $\implies$ return `EventCancellationStatus.deferredImminent`.
4. **Plugin Cancellation Execution:**
   - Call `Alarm.stop(id)`.
   - If returns `true` $\implies$ return `EventCancellationStatus.cancelled` (Plugin-Level Cancellation).
   - If throws $\implies$ return `EventCancellationStatus.failed`.

### 4.4 Notification Cancellation Protocol (`cancelNotificationSafely`):
1. Query `flutterLocalNotificationsPlugin.pendingNotificationRequests()`.
2. If request with `id` absent:
   - Attempt orphan fingerprint cleanup: `prefs.remove('notif_fingerprint_$id')`.
   - Return `EventCancellationStatus.alreadyAbsent`.
3. If request with `id` present:
   - Read fingerprint from `SharedPreferences`.
   - **Fail-Closed Imminent Guard:** If fingerprint is missing, unreadable, or `fingerprint.payload != request.payload` $\implies$ metadata correlation is broken $\implies$ **return `EventCancellationStatus.unverifiable`** (suppressing cancellation).
   - Parse `fingerprint.scheduledTimeIso`.
   - If `isWithinImminentWindow(scheduledTime, DateTime.now())` $\implies$ return `EventCancellationStatus.deferredImminent`.
   - Execute native cancellation: `flutterLocalNotificationsPlugin.cancel(id)`.
   - Attempt fingerprint removal:
     - If removal throws $\implies$ return `EventCancellationStatus.failed` (Failure Window observable).
     - If removal succeeds $\implies$ return `EventCancellationStatus.cancelled`.

---

## 5. Exhaustive Reconciliation State Machine

### 5.1 Mode: `alarm`
```text
verifyAlarm(alarmId)
│
├── unverifiable:
│     └── emit failed (FAIL-CLOSED: no dispatch, no decommission)
│
├── matching:
│     └── cancelNotificationSafely(notifId)
│           ├── cancelled / alreadyAbsent     → emit skippedMatching (COMPLETE)
│           ├── deferredImminent / Ringing    → emit opposingDecommissionDeferred (INCOMPLETE)
│           └── failed / unverifiable         → emit opposingDecommissionFailed (INCOMPLETE)
│
├── absent OR stale:
│     └── dispatch scheduleAdhanAlarm(alarmId)
│           ├── throws Platform/Plugin Exception:
│           │     └── emit failed (opposing alert preserved; INCOMPLETE)
│           └── dispatch succeeded:
│                 └── post-verifyAlarm(alarmId)
│                       ├── matching:
│                       │     └── cancelNotificationSafely(notifId)
│                       │           ├── cancelled / alreadyAbsent  → emit scheduled (COMPLETE)
│                       │           ├── deferred                   → emit opposingDecommissionDeferred (INCOMPLETE)
│                       │           └── failed / unverifiable      → emit opposingDecommissionFailed (INCOMPLETE)
│                       └── absent / stale / unverifiable:
│                             └── emit failed (opposing alert preserved; INCOMPLETE)
```

### 5.2 Mode: `notification`
```text
verifyNotification(notifId)
│
├── unverifiable:
│     └── emit failed (FAIL-CLOSED: no dispatch, no decommission)
│
├── matching:
│     └── cancelAlarmSafely(alarmId)
│           ├── cancelled / alreadyAbsent     → emit skippedMatching (COMPLETE)
│           ├── deferredImminent / Ringing    → emit opposingDecommissionDeferred (INCOMPLETE)
│           └── failed / unverifiable         → emit opposingDecommissionFailed (INCOMPLETE)
│
├── absent OR stale:
│     └── dispatch schedulePrayerNotification(notifId)
│           ├── throws Platform/Plugin Exception:
│           │     └── emit failed (opposing alert preserved; INCOMPLETE)
│           └── dispatch succeeded:
│                 └── post-verifyNotification(notifId)
│                       ├── matching:
│                       │     └── cancelAlarmSafely(alarmId)
│                       │           ├── cancelled / alreadyAbsent  → emit scheduled (COMPLETE)
│                       │           ├── deferred                   → emit opposingDecommissionDeferred (INCOMPLETE)
│                       │           └── failed / unverifiable      → emit opposingDecommissionFailed (INCOMPLETE)
│                       └── absent / stale / unverifiable:
│                             └── emit failed (opposing alert preserved; INCOMPLETE)
```

### 5.3 Mode: `off`
```dart
final details = OffDecommissionDetails(
  alarmId: alarmId,
  alarmStatus: await notificationRepository.cancelAlarmSafely(alarmId),
  notificationId: notifId,
  notificationStatus: await notificationRepository.cancelNotificationSafely(notifId),
);

if (details.isFullyClean) {
  operations.add(ScheduleOperationResult.skippedOff(
    eventId: null,
    eventType: ScheduleEventType.prayerAlert,
    scheduledTime: prayerTime,
    offDetails: details,
  ));
} else if (details.hasFailure) {
  // Infrastructure failure strictly takes precedence over deferral
  operations.add(ScheduleOperationResult.failed(
    eventId: null,
    eventType: ScheduleEventType.prayerAlert,
    scheduledTime: prayerTime,
    failureReason: 'Off decommission failed: alarm=${details.alarmStatus}, notif=${details.notificationStatus}',
    offDetails: details,
  ));
} else {
  // Deferred due to ringing or imminent protection
  operations.add(ScheduleOperationResult.skippedImminent(
    eventId: null,
    eventType: ScheduleEventType.prayerAlert,
    scheduledTime: prayerTime,
    offDetails: details,
  ));
}
```

---

## 6. Same-ID In-Place Replacement: Characterization & Non-Atomic Recovery

### 6.1 Truth Boundaries & Disclaimers:
- We explicitly **disclaim native atomic replacement** across OS process boundaries.
- We do **not claim guaranteed Adhan arrival** if native scheduling fails mid-syscall.
- We characterize in-place replacement as an **opposing alert preservation attempt**.

### 6.2 Application Safety Assertions in Tests 24b & 24p:
Tests 24b and 24p will assert the following verifiable application behaviors:
1. **No Pre-Cancellation:** The scheduler did not call `cancel` or `stop` before dispatching.
2. **Deterministic Dispatch:** The scheduler attempted dispatch with the expected deterministic ID.
3. **Exception Interception:** The injected platform error was caught without crashing the scheduler.
4. **Opposing Preservation:** Decommissioning of the opposing alert was suppressed.
5. **Completeness Blocked:** The operation recorded `failed`, daily outcome evaluated to `isComplete == false`, and the horizon did not advance.
6. **Characterization Logging:** The state of the same-ID alert in the repo map post-failure is recorded as diagnostic evidence.

---

## 7. Orphan Fingerprint Cleanup & Non-Resurrection Contract

1. **Gatekeeper:** `verifyNotification` queries Tier 1 (FLN queue) first. If absent, it immediately returns `EventVerificationStatus.absent` without checking SharedPreferences. An orphaned fingerprint never produces a false `matching` claim.
2. **Non-Resurrection Proof (Test 24q):**
   - Seed orphan fingerprint in `SharedPreferences` while FLN pending queue is empty.
   - Run scheduler.
   - Assert: `verifyNotification` returns `absent`.
   - Assert: Zero calls to `schedulePrayerNotification(notifId)`.
   - Assert: FLN pending queue remains empty.
   - Assert: Orphan fingerprint cleanup was attempted.
   - Inject SharedPreferences removal failure $\implies$ operation emits `failed` (observable).
   - Once removal failure is cleared, retry cleans up orphan fingerprint and converges to `alreadyAbsent`.

---

## 8. Domain vs. Infrastructure Exception Boundary

In accordance with Phase 2C.4.2.2:
- **Infrastructure Exceptions:** `PlatformException`, `MissingPluginException` are caught, logged, and mapped to `unverifiable` or `failed`.
- **Domain Exceptions:** `ArgumentError`, `RangeError`, `StateError`, `TypeError` are **never caught**. They bubble up unswallowed.

---

## 9. Comprehensive 52-Test Inventory & 22-Case Fault-Injection Matrix

### 9.1 Test Inventory Reconciliation:
- **Baseline Matrix (36 Tests):**
  - Group A: Transition Matrix Cases 1–12 (12 tests) — PASS.
  - Group B: Blanket Wipe Elimination Tests 13–16 (4 tests) — PASS.
  - Group C: Ringing & Temporal Guards Tests 17–20 (4 tests) — PASS.
  - Group D Baseline: Tests 21, 22a, 23a, 24a, 24b, 24c (6 tests) — (22a and 23a flip from RED to GREEN).
  - Group E: Auxiliary Isolation Tests 25–30 (6 tests) — PASS.
  - Group F: Horizon Advancement & Concurrency Tests 31–34 (4 tests) — PASS.
- **New Group D Fault-Injection Tests (16 Tests):**
  - Tests 22b, 23b, 24d through 24q.
- **Total Test Suite Count:** $36 + 16 = \mathbf{52\text{ Tests}}$.

### 9.2 Group D Comprehensive Fault-Injection Matrix (22 Specific Cases):

| Test ID | Status | Injected Condition / Scenario | Expected Scheduler Behavior & Assertions |
|---|---|---|---|
| **Test 21** | Existing | Alarm L1 dispatch failure (`failL1AlarmScheduleForIds.add(alarmId)`) | Platform error caught; old notification preserved; operation failed. |
| **Test 22a** | Existing (was 22) | Alarm L2 post-check returns `absent` | Old notification strictly preserved; operation failed; horizon capped. |
| **Test 22b** | **NEW** | Alarm L2 post-check throws $\implies$ `unverifiable` | Old notification strictly preserved; operation failed; horizon capped. |
| **Test 23a** | Existing (was 23) | Notification L2 post-check returns `absent` | Old alarm strictly preserved; operation failed; horizon capped. |
| **Test 23b** | **NEW** | Notification L2 post-check throws $\implies$ `unverifiable` | Old alarm strictly preserved; operation failed; horizon capped. |
| **Test 24a** | Existing | Stale Alarm in-place refresh dispatches deterministic ID | Scheduler dispatches to deterministic ID `alarmId`. |
| **Test 24b** | Existing | Stale Alarm refresh failure characterization | Proves no pre-cancellation; opposing preserved; status `failed`; horizon capped. |
| **Test 24c** | Existing | Notification L2 Two-Tier verification | Validates FLN pending queue + persistent fingerprint ledger. |
| **Test 24d** | **NEW** | Desired Alarm verified matching, opposing Notification cancel fails | Operation emits `opposingDecommissionFailed`; day incomplete; horizon capped. |
| **Test 24e** | **NEW** | Desired Alarm verified matching, opposing Notification is imminent | Operation emits `opposingDecommissionDeferred`; day incomplete; horizon capped. |
| **Test 24f** | **NEW** | Pre-check `verifyAlarm` returns `unverifiable` | Fail-Closed: no dispatch call, no decommission call, day incomplete. |
| **Test 24g** | **NEW** | Desired Notification matching, opposing Alarm cancel fails | Operation emits `opposingDecommissionFailed`; day incomplete; horizon capped. |
| **Test 24h** | **NEW** | Desired Notification matching, opposing Alarm is imminent | Operation emits `opposingDecommissionDeferred`; day incomplete; horizon capped. |
| **Test 24i** | **NEW** | Post-check `verifyNotification` returns `unverifiable` | Operation emits `failed`; day incomplete; opposing alarm preserved. |
| **Test 24j** | **NEW** | Opposing Alarm cancellation deferred due to active ringing | Operation emits `opposingDecommissionDeferred`; ringing audio protected. |
| **Test 24k** | **NEW** | Notification in FLN queue, but fingerprint missing / payload mismatched | Status evaluates to `stale`; refresh attempted. |
| **Test 24l** | **NEW** | Notification cancel succeeds, but fingerprint removal fails | Cancellation returns `failed`; day marked incomplete; retry cleans orphan. |
| **Test 24m** | **NEW** | Off mode: Alarm failed + Notification deferred | Precedence enforced: operation emits `failed` (not `skippedImminent`). |
| **Test 24n** | **NEW** | Off mode: Notification failed + Alarm cancelled | Operation emits `failed`; day incomplete. |
| **Test 24o** | **NEW** | Same-ID FLN replacement failure characterization | Proves no pre-cancellation; opposing preserved; operation `failed`. |
| **Test 24p** | **NEW** | Same-ID Alarm replacement failure characterization | Proves no pre-cancellation; opposing preserved; operation `failed`. |
| **Test 24q** | **NEW** | Orphan fingerprint non-resurrection & retry cleanup | Asserts no dispatch calls; queue stays empty; retry cleans orphan. |

---

## 10. File-by-File Implementation Details

### 10.1 [`lib/features/notifications/domain/entities/schedule_operation_result.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/entities/schedule_operation_result.dart)
1. Add `EventVerificationStatus` enum (`absent`, `matching`, `stale`, `unverifiable`).
2. Add `EventCancellationStatus` enum (`cancelled`, `alreadyAbsent`, `deferredImminent`, `deferredRinging`, `failed`, `unverifiable`) with `isSuccessful` and `isDeferred`.
3. Add `OffDecommissionDetails` class.
4. Add `ScheduleOperationStatus.opposingDecommissionDeferred` and `opposingDecommissionFailed`.
5. Add factory constructors `opposingDecommissionDeferred` and `opposingDecommissionFailed`.
6. Update `satisfiesDayCompleteness` and `isDeferred`.

### 10.2 [`lib/features/notifications/domain/repos/base_notification_repository.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/repos/base_notification_repository.dart)
```dart
Future<EventCancellationStatus> cancelAlarmSafely(int id);
Future<EventCancellationStatus> cancelNotificationSafely(int id);

Future<EventVerificationStatus> verifyAlarm({
  required int id,
  required DateTime expectedScheduledTime,
  String? expectedAssetAudioPath,
  double? expectedVolume,
  bool? expectedEnableVibration,
});

Future<EventVerificationStatus> verifyNotification({
  required int id,
  required DateTime expectedScheduledTime,
  required String expectedPayload,
  String? expectedTitle,
  String? expectedBody,
  String? expectedChannelId,
  String? expectedSoundSource,
});
```

### 10.3 [`lib/features/notifications/data/repos/notification_repository_impl.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/data/repos/notification_repository_impl.dart)
- Implement `cancelAlarmSafely` returning `EventCancellationStatus` using `isWithinImminentWindow(alarm.dateTime, DateTime.now())`.
- Implement `cancelNotificationSafely` returning `EventCancellationStatus` using fingerprint scheduled time with fail-closed fallback to `unverifiable` when payload binding fails.
- Implement `verifyAlarm` and `verifyNotification` wrapping infrastructure errors into `unverifiable` and re-throwing domain errors.

### 10.4 [`lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart)
- Implement Two-Phase Atomic Reconciliation across `alarm`, `notification`, and `off` modes.
- Implement strict precedence in `off` mode ($\text{Failed} > \text{Deferred} > \text{Clean}$) using `OffDecommissionDetails`.
- Past Day 0 strictly checks `prayerTime.isBefore(now)` for `skippedPast`.
- Handle `unverifiable` fail-closed. Catch only `PlatformException` and `MissingPluginException`.

---

## 11. Acceptance Criteria & Pre-Execution Freeze

1. **Production Freeze:** Zero edits to `lib/` until this Revision 6 Plan receives formal architectural approval.
2. **Suite Targets:**
   - `scheduler_production_path_integration_test.dart`: **52 / 52 PASS (100% GREEN)**.
   - Core Regression Suite (5 files / 80 tests): **80 / 80 PASS (100% GREEN)**.
   - Static Analysis (`flutter analyze`): **0 Compilation Errors**.

