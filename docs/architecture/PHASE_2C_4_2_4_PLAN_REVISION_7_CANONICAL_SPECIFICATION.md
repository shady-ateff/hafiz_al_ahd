# Phase 2C.4.2.4 Implementation Plan (Revision 7)
## Two-Phase Non-Atomic Reconciliation with Verified Plugin-Level Completion

**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** Phase 2C.4.2.4  
**Gate:** STOP GATE 5 (Plan Revision 7 Submission)  
**Author:** AI Pair Programmer (DeepMind)  
**Reviewer:** User / Chief Architect  
**Status:** PROPOSED FOR FORMAL ARCHITECTURAL APPROVAL  

---

## 1. Executive Summary & Resolution of Revision 6 Critiques

This **Revision 7 Plan** establishes the complete, production-grade architectural specification for Phase 2C.4.2.4, addressing all feedback from the Chief Architect's review:

| # | Architecture Issue | Canonical Resolution in Revision 7 |
|---|---|---|
| **1 (Critical)** | UTF-8 Byte Handling & Deterministic Hash | Adopted `crypto` package (`sha256` from `package:crypto/crypto.dart`, already resolved in `pubspec.lock`). Guarantees 100% deterministic, cross-platform SHA-256 over UTF-8 bytes for English and Arabic text. |
| **2 (Critical)** | Injective Canonical Serialization | Replaced delimiter concatenation with **Canonical JSON Serialization** (`jsonEncode` with strictly sorted keys). Injective, standard-compliant, zero delimiter collisions. |
| **3 (High)** | Fingerprint Internal Consistency Validation | Mandatory consistency check before using fingerprint time: parses payload, extracts `{eventId, generation, scheduledTime, configDigest}`, and verifies exact equality with fingerprint fields. Any discrepancy fails closed as `unverifiable`. |
| **4 (Critical)** | Separation of Desired Scheduling & Orphan Cleanup in Test 24q | Resolved the functional contradiction: In `notification` mode, absent pending request triggers legitimate scheduling. Test 24q uses `alarm` or `off` mode to prove orphan cleanup does NOT resurrect notifications, asserts zero dispatch calls, and tests failure recovery. |
| **5 (High)** | `Alarm.stop(id)` Return Semantics | Defined explicit return contracts: `stop == true` $\implies$ plugin cancellation accepted; `stop == false` $\implies$ post-query determines if `alreadyAbsent` or `failed`. Scoped strictly to **Plugin-Level Cancellation**. |
| **6 (High)** | Accurate Reconciliation Terminology | Renamed all occurrences to **Two-Phase Non-Atomic Reconciliation with Verified Plugin-Level Completion**. |
| **7 (High)** | Same-ID Test Assertions (24b & 24p) | Characterizes post-failure state rather than requiring preservation. Asserts no pre-cancellation, dispatch attempted, opposing not cancelled, day incomplete, horizon capped. |
| **8 (High)** | Auxiliary L2 Verification Scope | Formally restricted to **Pending Request ID-Only Presence** in FLN queue. |
| **9 (High)** | Test Matrix Alignment | Reconciled test suite: **52 total tests** ($12 + 4 + 4 + 22 + 6 + 4 = 52$), with Group D containing **22 specific fault-injection cases**. |

---

## 2. Injective Canonical Serialization & SHA-256 Payload Contract

### 2.1 Injective Canonical JSON Serialization:
To guarantee that two distinct configurations never map to the same representation, fields are serialized as Canonical JSON with sorted keys:
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
    // 16-character hex prefix provides 64 bits of entropy against collision
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

### 2.3 Strict Evidence Boundary:
> [!IMPORTANT]
> This payload mechanism establishes **Application-Level Metadata Correlation** between the FLN pending queue and SharedPreferences. It does **NOT** claim cryptographic proof of native Android AlarmManager / NotificationManager kernel state.

---

## 3. Fingerprint Internal Consistency Validation

Before using `fingerprint.scheduledTime` for imminent temporal protection in `cancelNotificationSafely`:
1. Parse `request.payload` using `NotificationPayloadContract.parsePayload(request.payload)`.
2. If parse fails $\implies$ return `EventCancellationStatus.unverifiable`.
3. Read `fingerprint` from `SharedPreferences`.
4. Validate internal consistency:
   - `parsed.eventId == fingerprint.eventId`
   - `parsed.generation == fingerprint.generation`
   - `parsed.scheduledTimeEpochMs == fingerprint.scheduledTime.millisecondsSinceEpoch`
   - `parsed.configDigest == fingerprint.configDigest`
   - `request.payload == fingerprint.payload`
5. If **any** condition fails $\implies$ metadata is inconsistent or unbound $\implies$ **return `EventCancellationStatus.unverifiable`** (cancellation suppressed; fail-closed).
6. If all conditions pass $\implies$ the fingerprint time is verified application metadata, and is evaluated against `isWithinImminentWindow(fingerprint.scheduledTime, DateTime.now())`.

---

## 4. Cancellation Model & Explicit Return Semantics

### 4.1 Typed Cancellation Outcomes:
```dart
enum EventCancellationStatus {
  cancelled,        // Event active in registry/queue was successfully cancelled at plugin level
  alreadyAbsent,    // Event confirmed absent prior to cancellation (idempotent clean)
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

### 4.3 `cancelAlarmSafely` Protocol & Return Semantics:
```dart
Future<EventCancellationStatus> cancelAlarmSafely(int id) async {
  try {
    // 1. Ringing Audio Guard (Strictly Pre-Destructive)
    final isRinging = await Alarm.isRinging(id);
    if (isRinging) {
      return EventCancellationStatus.deferredRinging;
    }

    // 2. Registry Query
    final alarm = await Alarm.getAlarm(id);
    if (alarm == null) {
      return EventCancellationStatus.alreadyAbsent;
    }

    // 3. Temporal Proximity Guard (Actual registered alarm.dateTime)
    if (isWithinImminentWindow(alarm.dateTime, DateTime.now())) {
      return EventCancellationStatus.deferredImminent;
    }

    // 4. Plugin Cancellation Execution
    final stopped = await Alarm.stop(id);
    if (stopped) {
      return EventCancellationStatus.cancelled; // Plugin-level cancellation accepted
    } else {
      // Alarm.stop returned false: verify whether record remains in registry
      final postCheck = await Alarm.getAlarm(id);
      if (postCheck == null) {
        return EventCancellationStatus.alreadyAbsent;
      } else {
        return EventCancellationStatus.failed;
      }
    }
  } on PlatformException catch (_) {
    return EventCancellationStatus.failed;
  } on MissingPluginException catch (_) {
    return EventCancellationStatus.failed;
  }
}
```
> [!NOTE]
> `EventCancellationStatus.cancelled` proves **Plugin-Level Cancellation**: `Alarm.stop(id)` returned `true` and the record was cleared from the plugin's local store. It does *not* claim independent OS kernel `dumpsys` verification (L4).

### 4.4 `cancelNotificationSafely` Protocol:
1. Query `flutterLocalNotificationsPlugin.pendingNotificationRequests()`.
2. If request with `id` absent:
   - Attempt orphan fingerprint cleanup: `prefs.remove('notif_fingerprint_$id')`.
   - Return `EventCancellationStatus.alreadyAbsent`.
3. If request with `id` present:
   - Perform Section 3 internal consistency check.
   - If inconsistent $\implies$ return `EventCancellationStatus.unverifiable`.
   - If `isWithinImminentWindow(fingerprint.scheduledTime, DateTime.now())` $\implies$ return `EventCancellationStatus.deferredImminent`.
   - Call `flutterLocalNotificationsPlugin.cancel(id)`.
   - Attempt fingerprint removal:
     - If removal throws $\implies$ return `EventCancellationStatus.failed` (Failure Window observable).
     - If removal succeeds $\implies$ return `EventCancellationStatus.cancelled`.

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
- Add `crypto: ^3.0.7` to `dependencies` (already in `pubspec.lock`).

### 10.2 [`lib/features/notifications/domain/entities/schedule_operation_result.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/entities/schedule_operation_result.dart)
- Add `EventVerificationStatus` enum (`absent`, `matching`, `stale`, `unverifiable`).
- Add `EventCancellationStatus` enum (`cancelled`, `alreadyAbsent`, `deferredImminent`, `deferredRinging`, `failed`, `unverifiable`) with `isSuccessful` and `isDeferred`.
- Add `OffDecommissionDetails` class.
- Add `ScheduleOperationStatus.opposingDecommissionDeferred` and `opposingDecommissionFailed`.
- Add factory constructors `opposingDecommissionDeferred` and `opposingDecommissionFailed`.
- Update `satisfiesDayCompleteness` and `isDeferred`.

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
- Implement `NotificationPayloadContract` with Canonical JSON and SHA-256.
- Implement `cancelAlarmSafely` with pre-destructive ringing guard, registry check, and return semantics.
- Implement `cancelNotificationSafely` with internal consistency check and orphan cleanup.
- Implement `verifyAlarm` and `verifyNotification` wrapping infrastructure errors into `unverifiable` and allowing domain errors to bubble up.

### 10.5 [`lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart)
- Implement Two-Phase Non-Atomic Reconciliation across `alarm`, `notification`, and `off` modes.
- Implement strict precedence in `off` mode ($\text{Failed} > \text{Deferred} > \text{Clean}$) using `OffDecommissionDetails`.
- Day 0 past check uses `prayerTime.isBefore(now)`.
- Catch only `PlatformException` and `MissingPluginException`.

---

## 11. Acceptance Criteria & Pre-Execution Freeze

1. **Production Freeze:** Zero edits to `lib/` until this Revision 7 Plan receives formal architectural approval.
2. **Suite Targets:**
   - `scheduler_production_path_integration_test.dart`: **52 / 52 PASS (100% GREEN)**.
   - Core Regression Suite (5 files / 80 tests): **80 / 80 PASS (100% GREEN)**.
   - Static Analysis (`flutter analyze`): **0 Compilation Errors**.

