# Phase 2C.4.2.4 Implementation Plan (Revision 8)
## Two-Phase Non-Atomic Reconciliation with Verified Plugin-Level Completion & Separated Metadata Cleanup

**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** Phase 2C.4.2.4  
**Gate:** STOP GATE 5 (Plan Revision 8 Submission)  
**Author:** AI Pair Programmer (DeepMind)  
**Reviewer:** User / Chief Architect  
**Status:** PROPOSED FOR FORMAL ARCHITECTURAL APPROVAL  

---

## 1. Executive Summary & Resolution of Revision 7 Critiques

This **Revision 8 Plan** provides the final, complete architectural specification for Phase 2C.4.2.4, addressing all items from the Chief Architect's review:

| # | Architecture Issue | Resolution in Revision 8 |
|---|---|---|
| **1 (Critical)** | Missing Request ID Binding | Added mutual identity assertions: `request.id == id`, `parsed.eventId == id`, `parsed.eventId == request.id`, and `fingerprint.eventId == id`. Payload correlation is strictly bound to the requested target ID. |
| **2 (Critical)** | Notification Orphan Cleanup Return Semantics | Defined unambiguous return contracts when pending request is absent: if fingerprint is absent $\implies$ `alreadyAbsent`; if fingerprint cleanup succeeds $\implies$ `alreadyAbsent`; if fingerprint cleanup fails $\implies$ `failed`. |
| **3 (Critical)** | `Alarm.stop(id)` Post-Query Verification | Following `Alarm.stop(id)`, a mandatory post-query `Alarm.getAlarm(id)` verifies registry removal. Returns `cancelled` only if `postCheck == null`. If record persists $\implies$ `failed`. |
| **4 (High)** | Separation of Alert Delivery & Metadata Cleanup | Formally separated `PrayerAlertDeliveryState` from `MetadataCleanupOutcome`. Defined that storage cleanup failure blocks horizon advance due to storage infrastructure unreliability, without falsely claiming the alert exists. |
| **5 (High)** | Test 24q Assertions & Cleanup Recovery | Test 24q explicitly verifies zero calls to `schedulePrayerNotification`, asserts clean convergence on cleanup success, and verifies observable failure and horizon halt upon injected cleanup failure. |
| **6 (High)** | Non-Atomic Reconciliation Terminology | Maintained canonical terminology: **Two-Phase Non-Atomic Reconciliation with Verified Plugin-Level Completion**. |
| **7 (High)** | Test Inventory & Fault Matrix | Preserved **52 total suite tests** ($12 + 4 + 4 + 22 + 6 + 4 = 52$) with **22 specific fault-injection cases** in Group D. |

---

## 2. Mutual Request ID Binding & Injective Canonical JSON SHA-256

### 2.1 Complete Injective Canonical Serialization:
```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

class NotificationPayloadContract {
  /// Serializes configuration into an injective, escaped Canonical JSON string.
  static String canonicalSerializeConfig({
    required String channelId,
    required String soundSource,
    required String title,
    required String body,
  }) {
    final map = <String, String>{
      'bdy': body,
      'chn': channelId,
      'snd': soundSource,
      'ttl': title,
    };
    return jsonEncode(map);
  }

  /// Computes a deterministic SHA-256 hex digest over canonical UTF-8 bytes.
  static String computeConfigDigest({
    required String channelId,
    required String soundSource,
    required String title,
    required String body,
  }) {
    final canonicalJson = canonicalSerializeConfig(
      channelId: channelId,
      soundSource: soundSource,
      title: title,
      body: body,
    );
    final bytes = utf8.encode(canonicalJson);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Builds the composite payload string passed to FLN and stored in SharedPreferences.
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

  /// Parses and validates the structured payload components.
  static ParsedPayload? parsePayload(String? payload) {
    if (payload == null) return null;
    final regex = RegExp(r'^prayer_(\d+)_g(\d+)_t(\d+)_([0-9a-fA-F]{16})$');
    final match = regex.firstMatch(payload);
    if (match == null) return null;

    return ParsedPayload(
      eventId: int.parse(match.group(1)!),
      generation: int.parse(match.group(2)!),
      scheduledTimeEpochMs: int.parse(match.group(3)!),
      configDigest: match.group(4)!,
    );
  }
}

class ParsedPayload {
  final int eventId;
  final int generation;
  final int scheduledTimeEpochMs;
  final String configDigest;

  const ParsedPayload({
    required this.eventId,
    required this.generation,
    required this.scheduledTimeEpochMs,
    required this.configDigest,
  });
}
```

### 2.2 Mutual Request ID Binding & Consistency Assertion:
Before using `fingerprint.scheduledTime` in `cancelNotificationSafely(int id)`:
1. Find request where `request.id == id`.
2. Parse payload: `final parsed = NotificationPayloadContract.parsePayload(request.payload)`. If null $\implies$ return `EventCancellationStatus.unverifiable`.
3. Read fingerprint from `SharedPreferences`. If missing $\implies$ return `EventCancellationStatus.unverifiable`.
4. **Mutual ID Binding Assertions:**
   - `request.id == id` (native request ID matches target ID)
   - `parsed.eventId == id` (payload embedded event ID matches target ID)
   - `parsed.eventId == request.id` (payload event ID matches native request ID)
   - `fingerprint.eventId == id` (ledger event ID matches target ID)
   - `parsed.scheduledTimeEpochMs == fingerprint.scheduledTime.millisecondsSinceEpoch`
   - `parsed.configDigest == fingerprint.configDigest`
   - `request.payload == fingerprint.payload`
5. If **any** condition fails $\implies$ metadata correlation is broken $\implies$ **return `EventCancellationStatus.unverifiable`** (cancellation suppressed; fail-closed).
6. If all pass $\implies$ fingerprint time is verified application metadata, evaluated against `isWithinImminentWindow(fingerprint.scheduledTime, DateTime.now())`.

---

## 3. Cancellation Model & Post-Query Verification Contracts

### 3.1 Typed Cancellation Outcomes:
```dart
enum EventCancellationStatus {
  cancelled,        // Event was active in registry/queue and successfully cancelled at plugin level
  alreadyAbsent,    // Event was confirmed absent prior to cancellation (idempotent clean)
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

### 3.2 Exact Duration Boundary Math (Closed Interval):
```dart
static bool isWithinImminentWindow(DateTime actualScheduledTime, DateTime now) {
  final difference = actualScheduledTime.difference(now);
  return difference >= const Duration(seconds: -15) &&
         difference <= const Duration(seconds: 60);
}
```

### 3.3 `cancelAlarmSafely` with Post-Query Verification:
```dart
Future<EventCancellationStatus> cancelAlarmSafely(int id) async {
  try {
    // 1. Ringing Audio Guard (Strictly Pre-Destructive)
    final isRinging = await Alarm.isRinging(id);
    if (isRinging) {
      return EventCancellationStatus.deferredRinging;
    }

    // 2. Pre-Query Registry
    final alarm = await Alarm.getAlarm(id);
    if (alarm == null) {
      return EventCancellationStatus.alreadyAbsent;
    }

    // 3. Temporal Proximity Guard (Actual registered alarm.dateTime)
    if (isWithinImminentWindow(alarm.dateTime, DateTime.now())) {
      return EventCancellationStatus.deferredImminent;
    }

    // 4. Plugin Cancellation Execution
    await Alarm.stop(id);

    // 5. Post-Query Verification: Confirm registry removal
    final postCheck = await Alarm.getAlarm(id);
    if (postCheck == null) {
      return EventCancellationStatus.cancelled; // Registry absence confirmed
    } else {
      return EventCancellationStatus.failed; // Record persisted despite stop call
    }
  } on PlatformException catch (_) {
    return EventCancellationStatus.failed;
  } on MissingPluginException catch (_) {
    return EventCancellationStatus.failed;
  }
}
```
> [!NOTE]
> `EventCancellationStatus.cancelled` proves **Plugin-Level Cancellation** (registry record confirmed `null`). It explicitly does *not* claim independent OS kernel `dumpsys` verification (L4).

### 3.4 `cancelNotificationSafely` with Unambiguous Orphan Recovery:
```dart
Future<EventCancellationStatus> cancelNotificationSafely(int id) async {
  try {
    final pendingRequests = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    final request = pendingRequests.cast<PendingNotificationRequest?>().firstWhere(
      (r) => r?.id == id,
      orElse: () => null,
    );

    // Path A: Native request is absent
    if (request == null) {
      final hasFingerprint = prefs.containsKey('notif_fingerprint_$id');
      if (!hasFingerprint) {
        return EventCancellationStatus.alreadyAbsent; // Clean state
      }
      // Orphan fingerprint exists: attempt cleanup
      try {
        final removed = await prefs.remove('notif_fingerprint_$id');
        if (removed) {
          return EventCancellationStatus.alreadyAbsent; // Orphan cleaned
        } else {
          return EventCancellationStatus.failed; // Storage removal failed
        }
      } catch (_) {
        return EventCancellationStatus.failed;
      }
    }

    // Path B: Native request is present
    // Perform Section 2.2 Mutual Binding Check
    final parsed = NotificationPayloadContract.parsePayload(request.payload);
    if (parsed == null || parsed.eventId != id || parsed.eventId != request.id) {
      return EventCancellationStatus.unverifiable;
    }

    final fpJson = prefs.getString('notif_fingerprint_$id');
    if (fpJson == null) {
      return EventCancellationStatus.unverifiable; // Missing ledger
    }

    final fp = NotificationFingerprint.fromJson(jsonDecode(fpJson));
    if (fp.eventId != id ||
        fp.payload != request.payload ||
        parsed.scheduledTimeEpochMs != fp.scheduledTime.millisecondsSinceEpoch ||
        parsed.configDigest != fp.configDigest) {
      return EventCancellationStatus.unverifiable; // Mismatched ledger
    }

    // Temporal Proximity Guard
    if (isWithinImminentWindow(fp.scheduledTime, DateTime.now())) {
      return EventCancellationStatus.deferredImminent;
    }

    // Native Cancellation
    await flutterLocalNotificationsPlugin.cancel(id);

    // Ledger Removal
    try {
      final removed = await prefs.remove('notif_fingerprint_$id');
      if (!removed) return EventCancellationStatus.failed;
    } catch (_) {
      return EventCancellationStatus.failed;
    }

    return EventCancellationStatus.cancelled;
  } on PlatformException catch (_) {
    return EventCancellationStatus.failed;
  } on MissingPluginException catch (_) {
    return EventCancellationStatus.failed;
  }
}
```

---

## 4. Separation of Alert Delivery State & Metadata Cleanup

```text
Reconciliation Evaluation:
├── Prayer Alert Delivery State:
│     • Desired Alert: Verified matching at L2 (plugin registry/queue).
│     • Opposing Native Alert: Absent in native queue (FLN / package:alarm).
│     → Delivery state is SATISFIED (User will receive correct alert; zero duplicate alerts).
│
└── Metadata Cleanup State (SharedPreferences):
      • Clean: No orphan fingerprints remain.
      • Failed: SharedPreferences write/remove error occurred.
      → Impact: Storage infrastructure error marks operation non-terminal
        (opposingDecommissionFailed). Day remains incomplete. Horizon capped.
```

---

## 5. Two-Phase Non-Atomic Reconciliation State Machine

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

## 6. Non-Atomic Replacement Characterization (Tests 24b & 24p)

1. **Non-Atomic Disclaimer:** We disclaim native OS atomic replacement across process boundaries.
2. **Safety Invariants Asserted in Tests 24b & 24p:**
   - Pre-cancellation was **not** performed before dispatch.
   - Deterministic ID was dispatched.
   - Platform error was caught and mapped to `ScheduleOperationResult.failed`.
   - Opposing alert decommissioning was **not** attempted.
   - Daily outcome evaluated to `isComplete == false`, and the horizon was capped.
   - The state of the same-ID alert post-failure is recorded as diagnostic characterization, rather than an unconditional acceptance requirement.

---

## 7. Auxiliary L2 Scope: ID-Only Presence

Auxiliary events (Iqama, Post-Prayer Azkar, Morning Azkar, Evening Azkar) are verified at **Level 1 (Platform Dispatch)** and **Level 2 (Tier 1 Pending Queue ID-Only Presence)**:
- If `pendingNotificationRequests()` contains the auxiliary ID $\implies$ verified.
- No payload, channel, sound, or trigger time verification is performed or claimed for auxiliary events.
- If the ID is absent or the query throws $\implies$ operation records `failed`, day is marked incomplete (`isComplete == false`), and horizon advance is halted.

---

## 8. Orphan Fingerprint Cleanup & Non-Resurrection (Test 24q)

### 8.1 Functional Separation:
- **Desired Notification Path:** If prayer config is `notification` and pending request is absent, scheduler legitimately dispatches `schedulePrayerNotification` (orphan fingerprint does not suppress legitimate scheduling).
- **Orphan Cleanup Path (Test 24q):** If prayer config is `alarm` or `off` (where NO notification should exist):
  - Pending FLN queue is empty.
  - SharedPreferences contains an orphaned fingerprint.
  - Scheduler invokes `cancelNotificationSafely(notifId)`.
  - Cleans up the orphaned fingerprint.
  - Returns `alreadyAbsent`.
  - **Asserts zero calls to `schedulePrayerNotification(notifId)`** (no phantom notification resurrected).
  - Injecting SharedPreferences removal failure $\implies$ operation emits `opposingDecommissionFailed` or `failed` (observable failure).
  - On retry, cleans up orphan and converges to `alreadyAbsent`.

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

### 10.1 [`pubspec.yaml`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/pubspec.yaml)
- Add `crypto: ^3.0.7` to `dependencies` (already resolved in `pubspec.lock`).

### 10.2 [`lib/features/notifications/domain/entities/schedule_operation_result.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/entities/schedule_operation_result.dart)
1. Add `EventVerificationStatus` enum (`absent`, `matching`, `stale`, `unverifiable`).
2. Add `EventCancellationStatus` enum (`cancelled`, `alreadyAbsent`, `deferredImminent`, `deferredRinging`, `failed`, `unverifiable`) with `isSuccessful` and `isDeferred`.
3. Add `OffDecommissionDetails` class.
4. Add `ScheduleOperationStatus.opposingDecommissionDeferred` and `opposingDecommissionFailed`.
5. Add factory constructors `opposingDecommissionDeferred` and `opposingDecommissionFailed`.
6. Update `satisfiesDayCompleteness` and `isDeferred`.

### 10.3 [`lib/features/notifications/domain/repos/base_notification_repository.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/repos/base_notification_repository.dart)
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

### 10.4 [`lib/features/notifications/data/repos/notification_repository_impl.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/data/repos/notification_repository_impl.dart)
- Implement `NotificationPayloadContract` with Canonical JSON and SHA-256 (`package:crypto/crypto.dart`).
- Implement `cancelAlarmSafely` with pre-destructive ringing guard, registry check, and post-stop verification.
- Implement `cancelNotificationSafely` with mutual ID binding check and unambiguous orphan cleanup semantics.
- Implement `verifyAlarm` and `verifyNotification` wrapping infrastructure errors into `unverifiable` and allowing domain errors to bubble up.

### 10.5 [`lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart)
- Implement Two-Phase Non-Atomic Reconciliation across `alarm`, `notification`, and `off` modes.
- Implement strict precedence in `off` mode ($\text{Failed} > \text{Deferred} > \text{Clean}$) using `OffDecommissionDetails`.
- Day 0 past check uses `prayerTime.isBefore(now)`.
- Catch only `PlatformException` and `MissingPluginException`.

---

## 11. Acceptance Criteria & Pre-Execution Freeze

1. **Production Freeze:** Zero edits to `lib/` until this Revision 8 Plan receives formal architectural approval.
2. **Suite Targets:**
   - `scheduler_production_path_integration_test.dart`: **52 / 52 PASS (100% GREEN)**.
   - Core Regression Suite (5 files / 80 tests): **80 / 80 PASS (100% GREEN)**.
   - Static Analysis (`flutter analyze`): **0 Compilation Errors**.

