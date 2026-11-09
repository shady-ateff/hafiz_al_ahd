# Phase 2C.4.2.4 Implementation Plan (Revision 9)
## Two-Phase Non-Atomic Reconciliation with Verified Plugin-Level Completion & Separated Metadata Cleanup

**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** Phase 2C.4.2.4  
**Gate:** STOP GATE 5 (Plan Revision 9 Submission)  
**Author:** AI Pair Programmer (DeepMind)  
**Reviewer:** User / Chief Architect  
**Status:** PROPOSED FOR FORMAL ARCHITECTURAL APPROVAL  

---

## 1. Executive Summary & Resolution of Revision 8 Blockers

This **Revision 9 Plan** directly resolves all 5 blockers (B1–B5) and 3 architectural notes (A–C) identified in the Chief Architect's review of Revision 8:

| # | Architecture Issue / Blocker | Resolution in Revision 9 |
|---|---|---|
| **B1** | **FLN Cancellation Post-Query Verification** | Added mandatory post-query `pendingNotificationRequests()` following `cancel(id)`. Confirms ID absence from queue before attempting fingerprint cleanup. If ID persists $\implies$ `failed`; if query throws $\implies$ `unverifiable`. Explicitly disclaims OS AlarmManager/NotificationManager kernel inspection (L4). |
| **B2** | **Post-Query Exception Mapping Distinction** | Formally decoupled cancellation call outcome from post-query outcome across both `cancelAlarmSafely` and `cancelNotificationSafely`: Cancellation call error $\implies$ `failed`; Post-query confirms record persists $\implies$ `failed`; Post-query itself throws $\implies$ `unverifiable`. |
| **B3** | **Infrastructure Exception Harmonization & Domain Error Preservation** | Standardized exception mapping: Domain validation errors (`ArgumentError`, `RangeError`, `StateError`, `AssertionError`) bubble up; all plugin, channel, SQLite, storage, and platform exceptions are mapped into typed cancellation/verification outcomes. No unclassified failure bypasses `ScheduleOperationResult.failed`. |
| **B4** | **Accurate Terminology for Canonical JSON & Truncated Digest** | Replaced "Injective SHA-256" with **"Canonical JSON + Truncated SHA-256 Fingerprint"** (64-bit truncated hex string). Formally specified as an application-level correlation fingerprint, not cryptographic identity or cryptographic authenticity. |
| **B5** | **Test 24q End-to-End Scheduler Retry Convergence** | Expanded Test 24q specification to execute the full scheduler use case end-to-end across two consecutive scheduling runs: Run 1 (injected cleanup failure) $\implies$ verifies zero dispatches, incomplete day, horizon halt, and ledger persistence; Run 2 (retry) $\implies$ verifies clean orphan cleanup, zero dispatches, day completion, and horizon advancement. |
| **Note A** | **Generation Semantics Clarification** | Documented that `int generation = 1` is a static application schema token, not monotonically increasing and not a proof of temporal recency. |
| **Note B** | **Separation of Alert Delivery vs Metadata Cleanup** | Formalized that native alert removal satisfies user-facing delivery safety (no duplicate firing); SharedPreferences removal failure is an infrastructure storage failure that blocks horizon advance under fail-closed integrity rules. |
| **Note C** | **Test Matrix Count Integrity** | Formally maintained exact inventory: **52 total suite tests** ($12 + 4 + 4 + 22 + 6 + 4 = 52$) with **22 specific fault-injection cases** in Group D. |

---

## 2. Evidence Boundaries & Plugin-Level Completion (L2)

### 2.1 The Two Verification & Cancellation Levels
1. **Level 1 (L1 — Platform Dispatch):**
   - Invocation of `Alarm.set()` or `flutterLocalNotificationsPlugin.zonedSchedule()`.
   - Proves platform channel call returned without throwing `PlatformException` or `MissingPluginException`.
2. **Level 2 (L2 — Local Plugin Registry & Queue Query):**
   - **Alarm:** SQLite-backed registry query via `Alarm.getAlarm(id)`.
   - **Notification Tier 1:** Native pending intent queue query via `flutterLocalNotificationsPlugin.pendingNotificationRequests()`.
   - **Notification Tier 2:** Application metadata consistency verification via `SharedPreferences` fingerprint ledger.
   - **Auxiliary Events (Iqama/Azkar):** Strictly **Pending Request ID-Only Presence** in `pendingNotificationRequests()`.
3. **Level 4 (L4 — Android OS Kernel & dumpsys):**
   - Formally **out of scope**. No claims are made regarding kernel-level `AlarmManager` or `NotificationManager` internals.

---

## 3. Canonical JSON & Truncated SHA-256 Fingerprint

### 3.1 Serialization & Correlation Contract:
- **Canonical JSON:** Strictly sorted keys (`bdy`, `chn`, `snd`, `ttl`) with standard RFC 8259 string escaping.
- **Truncated SHA-256 Fingerprint:** 16-hex-character (64-bit) prefix of SHA-256 digest over UTF-8 bytes.
- **Application Semantics:** Used strictly as an application-level correlation fingerprint to cross-check native request payloads against persistent ledger records. It does *not* claim cryptographic authenticity or collision resistance across arbitrary external inputs.
- **Generation Semantics:** `generation = 1` is an application schema version token, not a monotonic sequence or proof of recency.

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

  /// Computes a deterministic 64-bit truncated SHA-256 correlation fingerprint.
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

### 3.2 Mutual Request ID Binding & Consistency Assertion:
Before using `fingerprint.scheduledTime` in `cancelNotificationSafely(int id)`:
1. Find request where `request.id == id`.
2. Parse payload: `final parsed = NotificationPayloadContract.parsePayload(request.payload)`. If null $\implies$ return `EventCancellationStatus.unverifiable`.
3. Read fingerprint from `SharedPreferences`. If missing $\implies$ return `EventCancellationStatus.unverifiable`.
4. **Strict 4-Way Mutual Identity Binding Assertions:**
   - `request.id == id` (native request ID matches target ID)
   - `parsed.eventId == id` (payload embedded event ID matches target ID)
   - `parsed.eventId == request.id` (payload event ID matches native request ID)
   - `fingerprint.eventId == id` (ledger event ID matches target ID)
   - `parsed.scheduledTimeEpochMs == fingerprint.scheduledTime.millisecondsSinceEpoch`
   - `parsed.configDigest == fingerprint.configDigest`
   - `request.payload == fingerprint.payload`
5. If **any** condition fails $\implies$ metadata correlation is broken $\implies$ **return `EventCancellationStatus.unverifiable`** (fail-closed; cancellation suppressed).
6. If all pass $\implies$ fingerprint time is verified application metadata, evaluated against `isWithinImminentWindow(fingerprint.scheduledTime, DateTime.now())`.

---

## 4. Exception Layering & Cancellation Contracts

### 4.1 Domain vs Infrastructure Exception Separation:
```dart
bool _isDomainException(Object e) =>
    e is ArgumentError ||
    e is RangeError ||
    e is TypeError ||
    e is AssertionError ||
    e is StateError;
```
- **Domain Exceptions:** Never swallowed; allowed to rethrow immediately so programming bugs are uncovered during testing.
- **Infrastructure / Platform / Plugin / Storage Exceptions:** Safely captured and mapped to typed outcomes (`failed` or `unverifiable`).

### 4.2 Typed Cancellation Status:
```dart
enum EventCancellationStatus {
  cancelled,        // Active event successfully removed from plugin registry/queue and verified absent
  alreadyAbsent,    // Event confirmed absent prior to cancellation (idempotent clean)
  deferredImminent, // Cancellation suppressed: actual time within [-15s, +60s]
  deferredRinging,  // Cancellation suppressed: alarm is actively playing audio
  failed,           // Cancellation call threw, record persisted, or storage removal failed
  unverifiable,     // Pre- or post-cancellation query threw, or metadata correlation was broken
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

### 4.3 Exact Duration Boundary Math (Closed Interval):
```dart
static bool isWithinImminentWindow(DateTime actualScheduledTime, DateTime now) {
  final difference = actualScheduledTime.difference(now);
  return difference >= const Duration(seconds: -15) &&
         difference <= const Duration(seconds: 60);
}
```

### 4.4 `cancelAlarmSafely` with Triaged Post-Query:
```dart
Future<EventCancellationStatus> cancelAlarmSafely(int id) async {
  try {
    // 1. Ringing Audio Guard (Strictly Pre-Destructive)
    bool isRinging = false;
    try {
      isRinging = await Alarm.isRinging(id);
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.unverifiable;
    }
    if (isRinging) {
      return EventCancellationStatus.deferredRinging;
    }

    // 2. Pre-Query Registry
    AlarmSettings? alarm;
    try {
      alarm = await Alarm.getAlarm(id);
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.unverifiable;
    }
    if (alarm == null) {
      return EventCancellationStatus.alreadyAbsent;
    }

    // 3. Temporal Proximity Guard (Actual registered alarm.dateTime)
    if (isWithinImminentWindow(alarm.dateTime, DateTime.now())) {
      return EventCancellationStatus.deferredImminent;
    }

    // 4. Cancellation Execution Call
    try {
      await Alarm.stop(id);
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.failed; // Cancellation call failed
    }

    // 5. Post-Query Verification Call
    AlarmSettings? postCheck;
    try {
      postCheck = await Alarm.getAlarm(id);
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.unverifiable; // Inability to prove completion
    }

    // 6. Registry Absence Confirmation
    if (postCheck == null) {
      return EventCancellationStatus.cancelled; // Plugin-level removal verified
    } else {
      return EventCancellationStatus.failed; // Record persisted in SQLite despite stop call
    }
  } catch (e) {
    if (_isDomainException(e)) rethrow;
    return EventCancellationStatus.failed;
  }
}
```

### 4.5 `cancelNotificationSafely` with Verified Post-Query & Orphan Cleanup:
```dart
Future<EventCancellationStatus> cancelNotificationSafely(int id) async {
  try {
    // 1. Pre-Query FLN Pending Queue
    List<PendingNotificationRequest> pendingRequests;
    try {
      pendingRequests = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.unverifiable;
    }

    final request = pendingRequests.cast<PendingNotificationRequest?>().firstWhere(
      (r) => r?.id == id,
      orElse: () => null,
    );

    // Path A: Native request is absent from FLN queue
    if (request == null) {
      final hasFingerprint = prefs.containsKey('notif_fingerprint_$id');
      if (!hasFingerprint) {
        return EventCancellationStatus.alreadyAbsent; // Clean state
      }
      // Orphan fingerprint exists: clean up storage ledger
      try {
        final removed = await prefs.remove('notif_fingerprint_$id');
        if (removed) {
          return EventCancellationStatus.alreadyAbsent; // Orphan cleaned
        } else {
          return EventCancellationStatus.failed; // Storage failure
        }
      } catch (e) {
        if (_isDomainException(e)) rethrow;
        return EventCancellationStatus.failed;
      }
    }

    // Path B: Native request is present in FLN queue
    // Perform Strict 4-Way Mutual Binding Check
    final parsed = NotificationPayloadContract.parsePayload(request.payload);
    if (parsed == null || parsed.eventId != id || parsed.eventId != request.id) {
      return EventCancellationStatus.unverifiable;
    }

    final fpJson = prefs.getString('notif_fingerprint_$id');
    if (fpJson == null) {
      return EventCancellationStatus.unverifiable; // Missing ledger
    }

    NotificationFingerprint fp;
    try {
      fp = NotificationFingerprint.fromJson(jsonDecode(fpJson));
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.unverifiable;
    }

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

    // 2. Native Cancellation Execution Call
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.failed; // Cancellation call failed
    }

    // 3. Post-Query Verification Call: Confirm native request removal
    List<PendingNotificationRequest> postRequests;
    try {
      postRequests = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.unverifiable; // Inability to prove completion
    }

    final stillExists = postRequests.any((r) => r.id == id);
    if (stillExists) {
      return EventCancellationStatus.failed; // Record persisted in FLN queue despite cancel call
    }

    // 4. Ledger Removal (executed ONLY after confirmed native removal)
    try {
      final removed = await prefs.remove('notif_fingerprint_$id');
      if (!removed) {
        // Native request absent, but storage cleanup failed
        return EventCancellationStatus.failed;
      }
    } catch (e) {
      if (_isDomainException(e)) rethrow;
      return EventCancellationStatus.failed;
    }

    return EventCancellationStatus.cancelled; // Native removal + ledger removal confirmed
  } catch (e) {
    if (_isDomainException(e)) rethrow;
    return EventCancellationStatus.failed;
  }
}
```

---

## 5. Separation of Alert Delivery State & Metadata Cleanup

```text
Reconciliation Evaluation:
├── Prayer Alert Delivery State:
│     • Desired Alert: Verified matching at L2 (plugin registry/queue).
│     • Opposing Native Alert: Absent from native queue (FLN / package:alarm).
│     → Delivery state is SATISFIED (User will receive correct alert; zero duplicate alerts).
│
└── Metadata Cleanup State (SharedPreferences):
      • Clean: No orphan fingerprints remain.
      • Failed: SharedPreferences write/remove error occurred.
      → Impact: Storage infrastructure error marks operation non-terminal
        (opposingDecommissionFailed). Day remains incomplete. Horizon capped.
```

---

## 6. Two-Phase Non-Atomic Reconciliation State Machine

### 6.1 Mode: `alarm`
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

### 6.2 Mode: `notification`
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

### 6.3 Mode: `off`
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

## 7. Non-Atomic Replacement Characterization (Tests 24b & 24p)

1. **Non-Atomic Disclaimer:** We disclaim native OS atomic replacement across process boundaries.
2. **Safety Invariants Asserted in Tests 24b & 24p:**
   - Pre-cancellation was **not** performed before dispatch.
   - Deterministic ID was dispatched.
   - Platform error was caught and mapped to `ScheduleOperationResult.failed`.
   - Opposing alert decommissioning was **not** attempted.
   - Daily outcome evaluated to `isComplete == false`, and the horizon was capped.
   - The state of the same-ID alert post-failure is recorded as diagnostic characterization, rather than an unconditional acceptance requirement.

---

## 8. Auxiliary L2 Scope: ID-Only Presence

Auxiliary events (Iqama, Post-Prayer Azkar, Morning Azkar, Evening Azkar) are verified at **Level 1 (Platform Dispatch)** and **Level 2 (Tier 1 Pending Queue ID-Only Presence)**:
- If `pendingNotificationRequests()` contains the auxiliary ID $\implies$ verified.
- No payload, channel, sound, or trigger time verification is performed or claimed for auxiliary events.
- If the ID is absent or the query throws $\implies$ operation records `failed`, day is marked incomplete (`isComplete == false`), and horizon advance is halted.

---

## 9. End-to-End Scheduler Retry Convergence & Orphan Cleanup (Test 24q)

Test 24q exercises the complete production scheduler path end-to-end across two scheduling runs to prove retry convergence:

### 9.1 Scenario Setup:
- Prayer Mode: `alarm` (or `off`) where NO notification should exist.
- FLN Pending Queue: Empty (`pendingNotificationRequests() == []`).
- SharedPreferences: Contains orphaned fingerprint `notif_fingerprint_$notifId`.
- Injection: Configure fake SharedPreferences to fail on `remove('notif_fingerprint_$notifId')`.

### 9.2 Execution & 9 Required Assertions:

#### Run 1 (Injected Storage Failure):
Execute `scheduleWeeklyPrayers(settings)`:
1. `scheduler` reconciles Day 0 prayer.
2. Desired alarm is scheduled/verified; scheduler invokes `cancelNotificationSafely(notifId)`.
3. `cancelNotificationSafely` finds native queue empty $\to$ attempts orphan fingerprint removal $\to$ throws/fails.
4. Returns `EventCancellationStatus.failed`.
5. Scheduler records `ScheduleOperationStatus.opposingDecommissionFailed`.
6. **Assertion 1:** `isComplete == false` for Day 0.
7. **Assertion 2:** Horizon does **not** advance (`scheduledUntilDate == null`).
8. **Assertion 3:** Orphan fingerprint still exists in SharedPreferences (`containsKey == true`).
9. **Assertion 4:** Zero calls to `schedulePrayerNotification` (no phantom notification resurrected).

#### Run 2 (Storage Failure Cleared — Retry Convergence):
Clear fault injection and execute `scheduleWeeklyPrayers(settings)` again:
10. `scheduler` reconciles Day 0 prayer again.
11. **Assertion 5:** Still zero calls to `schedulePrayerNotification(notifId)`.
12. `cancelNotificationSafely(notifId)` finds native queue empty $\to$ removes orphan fingerprint successfully $\to$ returns `alreadyAbsent`.
13. **Assertion 6:** Cleanup succeeds and orphan fingerprint is removed from SharedPreferences (`containsKey == false`).
14. **Assertion 7:** Prayer alert delivery state is not misclassified as a matching notification.
15. **Assertion 8:** Day 0 outcome evaluates to `isComplete == true`.
16. **Assertion 9:** Horizon advances according to the contiguous-completeness rule (`scheduledUntilDate == targetDate`).

---

## 10. Comprehensive 52-Test Inventory & 22-Case Fault-Injection Matrix

### 10.1 Test Inventory Reconciliation:
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

### 10.2 Group D Comprehensive Fault-Injection Matrix (22 Specific Cases):

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

## 11. File-by-File Implementation Details

### 11.1 [`pubspec.yaml`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/pubspec.yaml)
- Add `crypto: ^3.0.7` to `dependencies` (already resolved in `pubspec.lock`).

### 11.2 [`lib/features/notifications/domain/entities/schedule_operation_result.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/entities/schedule_operation_result.dart)
1. Add `EventVerificationStatus` enum (`absent`, `matching`, `stale`, `unverifiable`).
2. Add `EventCancellationStatus` enum (`cancelled`, `alreadyAbsent`, `deferredImminent`, `deferredRinging`, `failed`, `unverifiable`) with `isSuccessful` and `isDeferred`.
3. Add `OffDecommissionDetails` class.
4. Add `ScheduleOperationStatus.opposingDecommissionDeferred` and `opposingDecommissionFailed`.
5. Add factory constructors `opposingDecommissionDeferred` and `opposingDecommissionFailed`.
6. Update `satisfiesDayCompleteness` and `isDeferred`.

### 11.3 [`lib/features/notifications/domain/repos/base_notification_repository.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/repos/base_notification_repository.dart)
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

### 11.4 [`lib/features/notifications/data/repos/notification_repository_impl.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/data/repos/notification_repository_impl.dart)
- Implement `NotificationPayloadContract` with Canonical JSON and truncated SHA-256 (`package:crypto/crypto.dart`).
- Implement `cancelAlarmSafely` with pre-destructive ringing guard, registry check, post-stop verification, and separate exception handling.
- Implement `cancelNotificationSafely` with pre-query, mutual ID binding check, post-cancel verification query, and ledger cleanup.
- Implement `verifyAlarm` and `verifyNotification` wrapping infrastructure errors into `unverifiable` and allowing domain errors to bubble up.

### 11.5 [`lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart)
- Implement Two-Phase Non-Atomic Reconciliation across `alarm`, `notification`, and `off` modes.
- Implement strict precedence in `off` mode ($\text{Failed} > \text{Deferred} > \text{Clean}$) using `OffDecommissionDetails`.
- Day 0 past check uses `prayerTime.isBefore(now)`.
- Re-throw domain exceptions; map plugin exceptions to `ScheduleOperationResult.failed`.

---

## 12. Acceptance Criteria & Pre-Execution Freeze

1. **Production Freeze:** Zero edits to `lib/` until this Revision 9 Plan receives formal architectural approval.
2. **Suite Targets:**
   - `scheduler_production_path_integration_test.dart`: **52 / 52 PASS (100% GREEN)**.
   - Core Regression Suite (5 files / 80 tests): **80 / 80 PASS (100% GREEN)**.
   - Static Analysis (`flutter analyze`): **0 Compilation Errors**.

