# Phase 2C.4.2.4 Implementation Plan (Revision 5)
## Definitive Architectural Specification: Two-Phase Reconciliation, Payload-Bound Metadata, & Non-Atomic Recovery

**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** Phase 2C.4.2.4  
**Gate:** STOP GATE 5 (Plan Revision 5 Submission)  
**Author:** AI Pair Programmer (DeepMind)  
**Reviewer:** User / Chief Architect  
**Status:** PROPOSED FOR FORMAL REVIEW  

---

## 1. Executive Summary & Resolution of Revision 4 Critiques

Following the Chief Architect's review of Revision 4, this **Revision 5 Plan** incorporates the final five architectural refinements:

| # | Architecture Item | Definitive Resolution in Revision 5 |
|---|---|---|
| **1 (Critical)** | Payload Generation & Config Identity | Replaced simplistic time-only instance with a complete **Payload-Bound Application Metadata** contract encoding `{eventId, scheduledTime, channelId, soundSource, title, body}`. Prevents stale fingerprints matching changed configurations. Terminology corrected to application-level correlation (not cryptographic). |
| **2 (Critical)** | Same-ID Replacement Reality & Non-Atomicity | Explicitly disclaimed native atomic replacement and guaranteed Adhan arrival. Defined neutral "opposing alert preservation attempt". Converted Tests 24b and 24p into characterization of application control flow, non-destructive safety, and failure recovery. |
| **3 (High)** | Off-Mode Aggregate Diagnostics | Refactored `off` mode outcomes into an aggregate diagnostic model storing both `alarmCancellation` and `notificationCancellation` statuses independently. Eliminates event ID ambiguity and preserves full diagnostic fidelity. |
| **4 (High)** | Decoupling Past Day 0 from Imminent Guard | Restored the canonical Phase 2C.4.2.0 policy: past classification is strictly $t_{\text{prayer}} < t_{\text{now}}$ (`skippedPast`). Decoupled completely from the cancellation imminent window $[-15\text{s}, +60\text{s}]$. |
| **5 (High)** | Test Inventory & Test 24q Assertions | Formally aligned all counts: **52 total suite tests** with **22 specific fault-injection cases** in Group D. Test 24q explicitly asserts orphan cleanup AND zero phantom resurrection on retry. |

---

## 2. Evidence Boundaries & Payload-Bound Application Metadata

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Level 1: Platform Channel Dispatch (L1)                                      │
│ • Truth Claim: MethodChannel call returned without platform exception.      │
│ • Limitation: Does NOT prove storage in plugin registry or OS armed timer.  │
├─────────────────────────────────────────────────────────────────────────────┤
│ Level 2: Local Plugin Registry / Queue Query (L2)                           │
│ • Alarm Truth Claim: Alarm.getAlarm(id) returned matching record in SQLite. │
│ • Notification Tier 1 Claim: FLN pendingNotificationRequests() contains     │
│   matching ID and native request.payload.                                   │
│ • Notification Tier 2 Claim: SharedPreferences fingerprint matches native   │
│   request.payload and expected configuration.                               │
│ • Limitation: Application-level metadata correlation only; does NOT inspect │
│   Android OS AlarmManager / NotificationManager kernel services (L4).       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Complete Configuration-Bound Payload Contract:
To prevent a fingerprint from falsely correlating with an alert whose audio, channel, or title has changed:
```dart
class NotificationPayloadContract {
  /// Computes a deterministic application-level payload uniquely identifying
  /// the event, its scheduled trigger time, and its full visual/auditory configuration.
  static String computePayload({
    required int eventId,
    required DateTime scheduledTime,
    required String channelId,
    required String soundSource,
    required String title,
    required String body,
  }) {
    final timeMs = scheduledTime.millisecondsSinceEpoch;
    final configHash = Object.hash(channelId, soundSource, title, body).toRadixString(16);
    return 'prayer_${eventId}_${timeMs}_$configHash';
  }
}
```

### 2.2 Verification & Imminent Cancellation Protocol:
1. **In `verifyNotification`:**
   - Query `flutterLocalNotificationsPlugin.pendingNotificationRequests()`.
   - Find request matching `request.id == id`.
   - If absent $\implies$ return `EventVerificationStatus.absent` (fingerprint is ignored).
   - If present:
     - Compare `request.payload == expectedPayload`. If mismatch $\implies$ return `EventVerificationStatus.stale` (pending request exists but carries outdated configuration).
     - Read fingerprint `notif_fingerprint_<id>` from `SharedPreferences`.
     - If fingerprint is missing, unreadable, or `fingerprint.payload != request.payload` $\implies$ return `EventVerificationStatus.stale`.
     - Verify time drift: $|t_{\text{fingerprint}} - t_{\text{expected}}| \le 2\text{s}$. If $> 2\text{s} \implies$ `stale`.
     - If all pass $\implies$ return `EventVerificationStatus.matching`.
2. **In `cancelNotificationSafely`:**
   - Query `pendingNotificationRequests()`.
   - If absent $\implies$ clean any orphan fingerprint in `SharedPreferences` and return `EventCancellationStatus.alreadyAbsent`.
   - If present:
     - Read fingerprint from `SharedPreferences`.
     - Compare `fingerprint.payload == request.payload`.
     - **Fail-Closed Imminent Guard:** If fingerprint is missing, unreadable, or payload mismatches, the application **cannot reliably determine the actual scheduled time** $\implies$ return `EventCancellationStatus.unverifiable` (suppressing cancellation to protect potential imminent alerts).
     - If payload matches $\implies$ evaluate `isWithinImminentWindow(fingerprint.scheduledTime, DateTime.now())`.
     - If imminent $\implies$ return `EventCancellationStatus.deferredImminent`.
     - If not imminent $\implies$ call `flutterLocalNotificationsPlugin.cancel(id)`, remove fingerprint, and return `EventCancellationStatus.cancelled`.

---

## 3. Same-ID Replacement: Characterization, Risk & Non-Atomic Recovery

### 3.1 Characterization of Plugin In-Place Replacement:
- **Unit / Fake Test Scope:** Proves application control flow, exception interception, and repository-level state mapping when an existing ID is re-dispatched. Does *not* simulate kernel-level process death or low-memory killer during a native syscall.
- **Android OS Reality:**
  - `package:alarm`: Updates SQLite first, then calls Android `AlarmManager`. A platform error may leave SQLite and AlarmManager out of sync.
  - `flutter_local_notifications`: Uses `PendingIntent.FLAG_UPDATE_CURRENT`. A failure during `AlarmManager.setExact` could leave the native intent in an undefined state.
- **Architecture Disclaimer:** We explicitly **disclaim native atomic replacement** and **do not claim guaranteed Adhan arrival**.

### 3.2 Opposing Alert Preservation Attempt & Recovery Policy:
1. **Zero Pre-Cancellation:** The scheduler **never** cancels a stale alert prior to dispatching the replacement.
2. **Post-Dispatch Verification Gate:**
   - Immediately following dispatch, `verifyAlarm` or `verifyNotification` is executed.
   - If dispatch throws (`PlatformException` / `MissingPluginException`) OR post-verification returns `absent`, `stale`, or `unverifiable`:
     - The replacement is marked `failed`.
     - **Opposing Alert Preservation Attempt:** The opposing alert (if present) is **NOT decommissioned**. The scheduler leaves any existing redundant alert intact.
     - Day outcome is marked incomplete (`DaySchedulingOutcome.isComplete = false`).
     - Completion horizon advance is halted.
3. **Recovery Policy on Retry:**
   - On the subsequent scheduler run, the alert state is queried anew:
     - If `absent` $\implies$ scheduler treats it as an absent alert and attempts fresh dispatch.
     - If `stale` $\implies$ scheduler re-attempts in-place replacement.
     - Day completeness remains blocked until verification confirms `matching`.

---

## 4. Per-Operation Completeness Invariants

Completeness (`satisfiesDayCompleteness == true`) is formally partitioned per operation type:

| Operation Type / Decision | Emitted Status | Criteria Required for `satisfiesDayCompleteness == true` | Non-Terminal Outcomes (`satisfiesDayCompleteness == false`) |
|---|---|---|---|
| **Future Prayer Alert (`alarm`)** | `scheduled`<br>`skippedMatching` | 1. Desired Alarm verified `EventVerificationStatus.matching`<br>2. Opposing Notification is `cancelled` or `alreadyAbsent` | `failed` (dispatch or verify error)<br>`opposingDecommissionDeferred` (notif imminent)<br>`opposingDecommissionFailed` (notif cancel failed/unverifiable) |
| **Future Prayer Alert (`notification`)** | `scheduled`<br>`skippedMatching` | 1. Desired Notification verified `EventVerificationStatus.matching`<br>2. Opposing Alarm is `cancelled` or `alreadyAbsent` | `failed` (dispatch or verify error)<br>`opposingDecommissionDeferred` (alarm imminent/ringing)<br>`opposingDecommissionFailed` (alarm cancel failed/unverifiable) |
| **Prayer Alert (`off` mode)** | `skippedOff` | Both Alarm AND Notification confirmed decommissioned (`cancelled` or `alreadyAbsent`) | `skippedImminent` (either alert imminent/ringing)<br>`failed` (either cancel failed/unverifiable) |
| **Past Prayer Alert (Day 0)** | `skippedPast` | Canonical policy: prayer time is in the past ($t_{\text{prayer}} < t_{\text{now}}$) on Day 0 | None (Terminal skip; past alert cannot be scheduled) |
| **Auxiliary Alert (Iqama/Azkar)** | `scheduled` | L1 dispatch returned without exception AND Tier 1 pending queue contains ID | `failed` (L1 exception or absent in Tier 1 queue) |

---

## 5. Cancellation Model & Actual-Time Temporal Guard

### 5.1 Typed Cancellation Status:
```dart
// lib/features/notifications/domain/entities/schedule_operation_result.dart

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

### 5.2 Exact Duration Boundary Math (Closed Interval):
```dart
static bool isWithinImminentWindow(DateTime actualScheduledTime, DateTime now) {
  final difference = actualScheduledTime.difference(now);
  return difference >= const Duration(seconds: -15) &&
         difference <= const Duration(seconds: 60);
}
```

---

## 6. Precedence Rules & Independent Diagnostics in `off` Mode

### 6.1 Aggregate Diagnostic Structure:
```dart
class OffDecommissionDetails {
  final int alarmId;
  final EventCancellationStatus alarmStatus;
  final int notificationId;
  final EventCancellationStatus notificationStatus;

  const OffDecommissionDetails({
    required this.alarmId,
    required this.alarmStatus,
    required this.notificationId,
    required this.notificationStatus,
  });

  bool get isFullyClean => alarmStatus.isSuccessful && notificationStatus.isSuccessful;
  bool get hasFailure =>
      alarmStatus == EventCancellationStatus.failed ||
      alarmStatus == EventCancellationStatus.unverifiable ||
      notificationStatus == EventCancellationStatus.failed ||
      notificationStatus == EventCancellationStatus.unverifiable;
  bool get hasDeferred => alarmStatus.isDeferred || notificationStatus.isDeferred;
}
```

### 6.2 Strict Precedence Logic:
$$\text{Failed / Unverifiable} > \text{Deferred} > \text{Clean}$$

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
  // Infrastructure failure strictly takes precedence over deferral!
  operations.add(ScheduleOperationResult.failed(
    eventId: null,
    eventType: ScheduleEventType.prayerAlert,
    scheduledTime: prayerTime,
    failureReason: 'Off decommission failed: alarm=${details.alarmStatus}, notification=${details.notificationStatus}',
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

## 7. Orphan Fingerprint Cleanup & Non-Resurrection Contract

1. **Gatekeeper Rule:** `verifyNotification` enforces Tier 1 (`pendingNotificationRequests()`) as the absolute authority for existence. If Tier 1 is absent, `verifyNotification` returns `EventVerificationStatus.absent` immediately without reading SharedPreferences.
2. **Orphan Cleanup:** When `cancelNotificationSafely` is invoked:
   - If Tier 1 is absent, but SharedPreferences has `notif_fingerprint_<id>`, the method removes the orphan fingerprint and returns `EventCancellationStatus.alreadyAbsent`.
3. **Non-Resurrection Proof (Test 24q):** If an orphaned fingerprint exists in SharedPreferences with no pending request in FLN:
   - A subsequent scheduler run detects the notification as absent.
   - Cleans up the orphan fingerprint.
   - Does **NOT** schedule any notification for this prayer.
   - On retry, state remains clean (`alreadyAbsent`) with zero notifications scheduled.

---

## 8. Domain vs. Infrastructure Exception Boundary

In accordance with Phase 2C.4.2.2:
- **Infrastructure Exceptions:** `PlatformException` and `MissingPluginException` are caught, logged, and mapped to `unverifiable` or `failed`.
- **Domain Exceptions:** `ArgumentError`, `RangeError`, `StateError`, `TypeError` are **never caught**. They bubble up unswallowed to fail tests and reveal contract violations.

---

## 9. Comprehensive 52-Test Inventory & 22-Case Fault-Injection Matrix

### 9.1 Test Inventory Reconciliation:
- **Baseline Matrix (36 Tests):**
  - Group A: Transition Matrix Cases 1–12 (12 tests) — ALL GREEN.
  - Group B: Blanket Wipe Elimination Tests 13–16 (4 tests) — ALL GREEN.
  - Group C: Ringing & Temporal Guards Tests 17–20 (4 tests) — ALL GREEN.
  - Group D Baseline: Tests 21, 22a, 23a, 24a, 24b, 24c (6 tests) — (22a and 23a flip from RED to GREEN).
  - Group E: Auxiliary Isolation Tests 25–30 (6 tests) — ALL GREEN.
  - Group F: Horizon Advancement & Concurrency Tests 31–34 (4 tests) — ALL GREEN.
- **New Group D Fault-Injection Tests (16 Tests):**
  - Tests 22b, 23b, 24d through 24q.
- **Total Test Suite Count:** $36 + 16 = \mathbf{52\text{ Tests}}$.

### 9.2 Comprehensive Fault-Injection Matrix (22 Specific Cases):

| Test ID | Status | Scenario / Injected Fault | Expected Scheduler Behavior & Assertions |
|---|---|---|---|
| **Test 21** | Existing | Alarm L1 dispatch failure (`failL1AlarmScheduleForIds.add(alarmId)`) | Platform error caught; old notification preserved; operation failed. |
| **Test 22a** | Existing (was 22) | Alarm L2 post-check returns `absent` | Old notification strictly preserved; operation failed; horizon capped. |
| **Test 22b** | **NEW** | Alarm L2 post-check throws $\implies$ `unverifiable` | Old notification strictly preserved; operation failed; horizon capped. |
| **Test 23a** | Existing (was 23) | Notification L2 post-check returns `absent` | Old alarm strictly preserved; operation failed; horizon capped. |
| **Test 23b** | **NEW** | Notification L2 post-check throws $\implies$ `unverifiable` | Old alarm strictly preserved; operation failed; horizon capped. |
| **Test 24a** | Existing | Stale Alarm in-place refresh dispatches deterministic ID | Scheduler dispatches to deterministic ID `alarmId`. |
| **Test 24b** | Existing | Stale Alarm refresh failure characterization | Old 4:30 alarm preserved intact in fake map; status remains `stale`; horizon capped. |
| **Test 24c** | Existing | Notification L2 Two-Tier verification | Validates FLN pending queue + persistent fingerprint ledger. |
| **Test 24d** | **NEW** | Desired Alarm verified matching, but opposing Notification cancel fails | Operation emits `opposingDecommissionFailed`; day incomplete; horizon capped. |
| **Test 24e** | **NEW** | Desired Alarm verified matching, but opposing Notification is imminent | Operation emits `opposingDecommissionDeferred`; day incomplete; horizon capped. |
| **Test 24f** | **NEW** | Pre-check `verifyAlarm` returns `unverifiable` | Fail-Closed: no dispatch call, no decommission call, day incomplete. |
| **Test 24g** | **NEW** | Desired Notification matching, but opposing Alarm cancel fails | Operation emits `opposingDecommissionFailed`; day incomplete; horizon capped. |
| **Test 24h** | **NEW** | Desired Notification matching, but opposing Alarm is imminent | Operation emits `opposingDecommissionDeferred`; day incomplete; horizon capped. |
| **Test 24i** | **NEW** | Post-check `verifyNotification` returns `unverifiable` | Operation emits `failed`; day incomplete; opposing alarm preserved. |
| **Test 24j** | **NEW** | Opposing Alarm cancellation deferred due to active ringing | Operation emits `opposingDecommissionDeferred`; ringing audio protected. |
| **Test 24k** | **NEW** | Notification in FLN queue, but fingerprint missing / payload mismatched | Status evaluates to `stale`; refresh attempted. |
| **Test 24l** | **NEW** | Notification cancel succeeds, but fingerprint removal fails | Cancellation returns `failed`; day marked incomplete. |
| **Test 24m** | **NEW** | Off mode: Alarm failed + Notification deferred | Precedence enforced: operation emits `failed` (not `skippedImminent`); `offDetails` contains both. |
| **Test 24n** | **NEW** | Off mode: Notification failed + Alarm cancelled | Operation emits `failed`; day incomplete; `offDetails` contains both. |
| **Test 24o** | **NEW** | Same-ID FLN replacement failure characterization | Operation `failed`; opposing alert preserved as safety attempt. |
| **Test 24p** | **NEW** | Same-ID Alarm replacement failure characterization | Operation `failed`; opposing alert preserved as safety attempt. |
| **Test 24q** | **NEW** | Orphan fingerprint non-resurrection on retry | Verifies orphan fingerprint does NOT reschedule notification or prevent clean convergence. |

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

1. **Production Freeze:** Zero edits to `lib/` until this Revision 5 Plan receives formal architectural approval.
2. **Suite Targets:**
   - `scheduler_production_path_integration_test.dart`: **52 / 52 PASS (100% GREEN)**.
   - Core Regression Suite (5 files / 80 tests): **80 / 80 PASS (100% GREEN)**.
   - Static Analysis (`flutter analyze`): **0 Compilation Errors**.

