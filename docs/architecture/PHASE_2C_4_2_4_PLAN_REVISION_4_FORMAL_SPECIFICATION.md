# Phase 2C.4.2.4 Implementation Plan (Revision 4)
## Formal Specification: Two-Phase Reconciliation, Payload-Bound Evidence, & Fail-Closed Safety

**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** Phase 2C.4.2.4  
**Gate:** STOP GATE 5 (Plan Revision 4 Submission)  
**Author:** AI Pair Programmer (DeepMind)  
**Reviewer:** User / Chief Architect  
**Status:** PROPOSED FOR FORMAL REVIEW  

---

## 1. Executive Summary & Resolution of Revision 3 Critiques

Following the Chief Architect's review of Revision 3, this **Revision 4 Plan** eliminates all speculative assumptions and ungrounded claims, establishing an airtight, mathematically rigorous reconciliation contract:

| # | Review Point | Mandated Architectural Solution in Revision 4 |
|---|---|---|
| **1 (Critical)** | Same-ID Replacement Characterization & Risk | Disclaimed atomic replacement claims. Documented distinct truth boundaries between fake unit tests and Android kernel behavior. Established fail-closed replacement failure strategy: opposing alert retained as redundant lifeboat, operation marked `failed`, day marked incomplete. |
| **2 (Critical)** | Scheduling Instance Identity & Binding | Bound the persistent fingerprint to the native pending notification via the native `request.payload` field. If `request.payload != fingerprint.payload`, binding is broken $\implies$ `cancelNotificationSafely` returns `unverifiable` (Fail-Closed imminent guard). |
| **3 (High)** | Per-Operation Completeness Invariants | Replaced broad invariant with per-operation mathematical definitions (`futureAlarm`, `futureNotification`, `off`, `pastDay0`, `auxiliary`). |
| **4 (High)** | Notification Cancellation with Invalid Fingerprint | In `cancelNotificationSafely`, any missing, unreadable, or unbound fingerprint emits `EventCancellationStatus.unverifiable`, strictly preventing cancellation of unverified alerts. |
| **5 (High)** | Test Matrix Count Discrepancy | Formally reconciled test inventory: 36 baseline tests (Tests 22 $\to$ 22a, 23 $\to$ 23a) + 16 new fault-injection tests (22b, 23b, 24d–24q) = **52 Total Tests** (Target: 52/52 PASS). |
| **6 (High)** | Orphan Fingerprint Non-Resurrection Test | Added Test 24q proving that orphaned fingerprints without FLN pending requests never resurrect notifications or prevent clean convergence. |

---

## 2. Evidence Boundaries & Cryptographic/Payload Instance Binding

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ Level 1: Platform Channel Dispatch (L1)                                      │
│ • Truth Claim: MethodChannel call returned without platform exception.      │
│ • Limitation: Does NOT prove storage in plugin registry or OS armed timer.  │
├─────────────────────────────────────────────────────────────────────────────┤
│ Level 2: Local Plugin Registry / Queue Query (L2)                           │
│ • Alarm Truth Claim: Alarm.getAlarm(id) returned matching record in SQLite. │
│ • Notification Tier 1 Claim: FLN pendingNotificationRequests() has ID &     │
│   native request.payload.                                                   │
│ • Notification Tier 2 Claim: SharedPreferences fingerprint matches native   │
│   request.payload.                                                          │
│ • Limitation: Application-side metadata only; does NOT inspect Android OS   │
│   AlarmManager / NotificationManager kernel system services (L4).           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Native Payload Instance Binding:
To prove that a SharedPreferences fingerprint belongs to the **exact active pending request** in the native Android queue without external session state:
1. **At Scheduling Time:**
   - The scheduler derives an immutable `schedulingInstanceId`:
     $$\text{instanceId} = \text{"inst\_" + eventId + "\_" + scheduledTime.millisecondsSinceEpoch}$$
   - The native notification payload is set to:
     $$\text{payload} = \text{"prayer\_" + prayerId + "#" + instanceId}$$
   - The fingerprint written to `SharedPreferences` at `notif_fingerprint_<id>` records:
     `{"id": id, "instanceId": instanceId, "payload": payload, "scheduledTimeIso": "...", "channelId": "...", "soundSource": "..."}`.
2. **At Verification & Cancellation Time:**
   - Query `flutterLocalNotificationsPlugin.pendingNotificationRequests()`.
   - Find request with matching `request.id`.
   - Compare: Does `request.payload == fingerprint.payload`?
     - **Match:** The fingerprint is cryptographically/deterministically bound to this active native request. The scheduled time in the fingerprint is verified application metadata.
     - **Mismatch / Missing:** The binding is broken. The pending request belongs to an untracked or prior scheduling attempt.
       - In `verifyNotification`: Returns `EventVerificationStatus.stale` (unverified metadata, requires in-place refresh).
       - In `cancelNotificationSafely`: Returns `EventCancellationStatus.unverifiable` (temporal status unknown $\implies$ cancel suppressed).

---

## 3. Same-ID Replacement: Characterization, Risk & Safety Strategy

### 3.1 Characterization of Plugin In-Place Replacement:
- **Unit / Fake Test Scope:** Proves application control flow, exception handling, and repo-level state mapping when an existing ID is re-scheduled. Does *not* simulate kernel-level process death during a native syscall.
- **Android OS Reality:**
  - `package:alarm`: Writes to SQLite first, then calls `AlarmManager.setExactAndAllowWhileIdle`. A failure at the platform level may leave SQLite and AlarmManager out of sync.
  - `flutter_local_notifications`: Uses `PendingIntent.FLAG_UPDATE_CURRENT`. A failure during `AlarmManager.setExact` could leave the previous PendingIntent in an undefined OS state.
- **Strict Architecture Position:** **We do NOT claim atomic replacement.** We acknowledge that in-place replacement carries native failure risks.

### 3.2 Redundant Lifeboat & Failure Strategy:
To protect against alert dropout without claiming impossible atomicity:
1. **No Pre-Cancellation:** The scheduler **never** calls `cancel` on a stale alert before dispatching the new one.
2. **Post-Dispatch Verification Gate:**
   - Immediately following dispatch, `verifyAlarm` or `verifyNotification` is executed.
   - If dispatch throws (`PlatformException` / `MissingPluginException`) OR post-verification returns `absent`, `stale`, or `unverifiable`:
     - The replacement is marked `failed`.
     - **The opposing alert (if present) is NOT decommissioned.**
     - The opposing alert remains active as a **redundant lifeboat**, ensuring the user still receives an adhan alert.
     - Day outcome is marked incomplete (`DaySchedulingOutcome.isComplete = false`).
     - Completion horizon advance is halted.
3. **Idempotent Retry:** On the subsequent scheduler run, the alert is detected as `stale` or `absent`, and replacement is re-attempted cleanly.

---

## 4. Per-Operation Completeness Invariant Specification

An operation satisfies daily completeness (`satisfiesDayCompleteness == true`) **if and only if** its specific contract is satisfied:

| Operation Type / Decision | Emitted Status | Criteria Required for `satisfiesDayCompleteness == true` | Non-Terminal Outcomes (`satisfiesDayCompleteness == false`) |
|---|---|---|---|
| **Future Prayer Alert (`alarm`)** | `scheduled`<br>`skippedMatching` | 1. Desired Alarm verified `EventVerificationStatus.matching`<br>2. Opposing Notification is `cancelled` or `alreadyAbsent` | `failed` (dispatch or verify error)<br>`opposingDecommissionDeferred` (notif imminent)<br>`opposingDecommissionFailed` (notif cancel failed/unverifiable) |
| **Future Prayer Alert (`notification`)** | `scheduled`<br>`skippedMatching` | 1. Desired Notification verified `EventVerificationStatus.matching`<br>2. Opposing Alarm is `cancelled` or `alreadyAbsent` | `failed` (dispatch or verify error)<br>`opposingDecommissionDeferred` (alarm imminent/ringing)<br>`opposingDecommissionFailed` (alarm cancel failed/unverifiable) |
| **Prayer Alert (`off` mode)** | `skippedOff` | Both Alarm AND Notification confirmed decommissioned (`cancelled` or `alreadyAbsent`) | `skippedImminent` (either alert imminent/ringing)<br>`failed` (either cancel failed/unverifiable) |
| **Past Prayer Alert (Day 0)** | `skippedPast` | Prayer time is in the past ($t_{\text{prayer}} < t_{\text{now}} - 15\text{s}$) on Day 0 | None (Terminal skip; past alert cannot be scheduled) |
| **Auxiliary Alert (Iqama/Azkar)** | `scheduled` | L1 dispatch returned without exception AND Tier 1 pending queue contains ID | `failed` (L1 exception or absent in Tier 1 queue) |

---

## 5. Cancellation Model & Actual-Time Temporal Guard

### 5.1 Typed Cancellation Status:
```dart
// lib/features/notifications/domain/entities/schedule_operation_result.dart

enum EventCancellationStatus {
  cancelled,        // Event was present in registry/queue and successfully cancelled
  alreadyAbsent,    // Event was verified absent prior to cancellation (idempotent clean)
  deferredImminent, // Cancellation suppressed: actual time within [-15s, +60s]
  deferredRinging,  // Cancellation suppressed: alarm is actively playing audio
  failed,           // PlatformException or MissingPluginException during cancellation
  unverifiable,     // Query threw exception or metadata unreadable/unbound (Fail-Closed)
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

### 5.3 Actual Scheduled Time Retrieval & Fail-Closed Guard:
- **Alarm:** `alarm.dateTime` from `Alarm.getAlarm(id)`.
- **Notification (`cancelNotificationSafely`):**
  1. Query `flutterLocalNotificationsPlugin.pendingNotificationRequests()`.
  2. If ID absent $\implies$ return `EventCancellationStatus.alreadyAbsent`.
  3. If ID present:
     - Read fingerprint `notif_fingerprint_<id>` from `SharedPreferences`.
     - Validate payload binding: `fingerprint.payload == request.payload`.
     - If fingerprint is missing, unreadable, or payload mismatches $\implies$ **return `EventCancellationStatus.unverifiable`** (suppressing cancellation).
     - If payload matches $\implies$ parse `fingerprint.scheduledTimeIso`.
     - If `isWithinImminentWindow(scheduledTime, DateTime.now())` $\implies$ return `EventCancellationStatus.deferredImminent`.
     - Otherwise, call `flutterLocalNotificationsPlugin.cancel(id)`, remove fingerprint, and return `EventCancellationStatus.cancelled`.

---

## 6. Precedence Rules in `off` Mode

$$\text{Failed / Unverifiable} > \text{Deferred} > \text{Clean}$$

```dart
final alarmResult = await notificationRepository.cancelAlarmSafely(alarmId);
final notifResult = await notificationRepository.cancelNotificationSafely(notifId);

if (alarmResult.isSuccessful && notifResult.isSuccessful) {
  operations.add(ScheduleOperationResult.skippedOff(
    eventId: null,
    eventType: ScheduleEventType.prayerAlert,
    scheduledTime: prayerTime,
  ));
} else if (alarmResult == EventCancellationStatus.failed ||
           alarmResult == EventCancellationStatus.unverifiable ||
           notifResult == EventCancellationStatus.failed ||
           notifResult == EventCancellationStatus.unverifiable) {
  // Infrastructure failure takes strict precedence over deferrals
  operations.add(ScheduleOperationResult.failed(
    eventId: !alarmResult.isSuccessful ? alarmId : notifId,
    eventType: ScheduleEventType.prayerAlert,
    scheduledTime: prayerTime,
    failureReason: 'Off decommission failed: alarm=$alarmResult, notif=$notifResult',
  ));
} else {
  // Deferred due to ringing or imminent guard
  operations.add(ScheduleOperationResult.skippedImminent(
    eventId: alarmResult.isDeferred ? alarmId : notifId,
    eventType: ScheduleEventType.prayerAlert,
    scheduledTime: prayerTime,
  ));
}
```

---

## 7. Orphan Fingerprint Cleanup & Non-Resurrection Contract

1. **Gatekeeper Rule:** `verifyNotification` enforces Tier 1 (`pendingNotificationRequests()`) as the absolute authority for existence. If Tier 1 is absent, `verifyNotification` returns `EventVerificationStatus.absent` immediately without checking SharedPreferences.
2. **Orphan Cleanup:** When `cancelNotificationSafely` is invoked:
   - If Tier 1 is absent, but SharedPreferences has `notif_fingerprint_<id>`, the method removes the orphan fingerprint and returns `EventCancellationStatus.alreadyAbsent`.
3. **Non-Resurrection Proof (Test 24q):** If an orphaned fingerprint exists in SharedPreferences with no pending request in FLN, a subsequent scheduler run detects the notification as absent, clears the orphan, and **never resurrects or schedules an unwanted notification**.

---

## 8. Domain vs. Infrastructure Exception Boundary

In accordance with Phase 2C.4.2.2:
- **Infrastructure Exceptions:** `PlatformException` and `MissingPluginException` are caught, logged, and mapped to `unverifiable` or `failed`.
- **Domain Exceptions:** `ArgumentError`, `RangeError`, `StateError`, `TypeError` are **never caught**. They bubble up unswallowed to fail tests and reveal contract violations.

---

## 9. Full 52-Test Inventory & Fault-Injection Matrix

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

### 9.2 Comprehensive Fault-Injection Matrix (21 Specific Cases):

| Test ID | Status | Scenario / Injected Fault | Expected Scheduler Behavior & Assertions |
|---|:---:|---|---|
| **Test 21** | Existing | Alarm L1 dispatch failure (`failL1AlarmScheduleForIds.add(alarmId)`) | Platform error caught; old notification preserved; operation failed. |
| **Test 22a** | Existing (was 22) | Alarm L2 post-check returns `absent` | Old notification strictly preserved; operation failed; horizon capped. |
| **Test 22b** | **NEW** | Alarm L2 post-check throws $\implies$ `unverifiable` | Old notification strictly preserved; operation failed; horizon capped. |
| **Test 23a** | Existing (was 23) | Notification L2 post-check returns `absent` | Old alarm strictly preserved; operation failed; horizon capped. |
| **Test 23b** | **NEW** | Notification L2 post-check throws $\implies$ `unverifiable` | Old alarm strictly preserved; operation failed; horizon capped. |
| **Test 24a** | Existing | Stale Alarm in-place refresh dispatches deterministic ID | Scheduler dispatches to deterministic ID `alarmId`. |
| **Test 24b** | Existing | Stale Alarm refresh failure (L1 error) | Old 4:30 alarm preserved intact; status remains `stale`; horizon capped. |
| **Test 24c** | Existing | Notification L2 Two-Tier verification | Validates FLN pending queue + persistent fingerprint ledger. |
| **Test 24d** | **NEW** | Desired Alarm verified matching, but opposing Notification cancel fails | Operation emits `opposingDecommissionFailed`; day incomplete; horizon capped. |
| **Test 24e** | **NEW** | Desired Alarm verified matching, but opposing Notification is imminent | Operation emits `opposingDecommissionDeferred`; day incomplete; horizon capped. |
| **Test 24f** | **NEW** | Pre-check `verifyAlarm` returns `unverifiable` | Fail-Closed: no dispatch call, no decommission call, day incomplete. |
| **Test 24g** | **NEW** | Desired Notification matching, but opposing Alarm cancel fails | Operation emits `opposingDecommissionFailed`; day incomplete; horizon capped. |
| **Test 24h** | **NEW** | Desired Notification matching, but opposing Alarm is imminent | Operation emits `opposingDecommissionDeferred`; day incomplete; horizon capped. |
| **Test 24i** | **NEW** | Post-check `verifyNotification` returns `unverifiable` | Operation emits `failed`; day incomplete; opposing alarm preserved. |
| **Test 24j** | **NEW** | Opposing Alarm cancellation deferred due to active ringing | Operation emits `opposingDecommissionDeferred`; ringing audio protected. |
| **Test 24k** | **NEW** | Notification present in FLN queue, but fingerprint missing / payload mismatched | Status evaluates to `stale`; refresh attempted. |
| **Test 24l** | **NEW** | Notification cancel succeeds, but fingerprint removal fails | Cancellation returns `failed`; day marked incomplete. |
| **Test 24m** | **NEW** | Off mode: Alarm failed + Notification deferred | Precedence enforced: operation emits `failed` (not `skippedImminent`). |
| **Test 24n** | **NEW** | Off mode: Notification failed + Alarm cancelled | Operation emits `failed`; day incomplete. |
| **Test 24o** | **NEW** | Same-ID FLN replacement failure | Operation `failed`; opposing alert preserved as lifeboat. |
| **Test 24p** | **NEW** | Same-ID Alarm replacement failure | Stale alarm preserved intact; operation `failed`; opposing preserved. |
| **Test 24q** | **NEW** | Orphan fingerprint non-resurrection on retry | Verifies orphan fingerprint does not reschedule notification or block cleanup. |

---

## 10. File-by-File Implementation Details

### 10.1 [`lib/features/notifications/domain/entities/schedule_operation_result.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/entities/schedule_operation_result.dart)
1. Add `EventVerificationStatus` enum (`absent`, `matching`, `stale`, `unverifiable`).
2. Add `EventCancellationStatus` enum (`cancelled`, `alreadyAbsent`, `deferredImminent`, `deferredRinging`, `failed`, `unverifiable`) with `isSuccessful` and `isDeferred`.
3. Add `ScheduleOperationStatus.opposingDecommissionDeferred` and `opposingDecommissionFailed`.
4. Add factory constructors `opposingDecommissionDeferred` and `opposingDecommissionFailed`.
5. Update `satisfiesDayCompleteness` and `isDeferred`.

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
  String? expectedTitle,
  String? expectedBody,
  String? expectedChannelId,
  String? expectedSoundSource,
  String? expectedPayload,
});
```

### 10.3 [`lib/features/notifications/data/repos/notification_repository_impl.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/data/repos/notification_repository_impl.dart)
- Implement `cancelAlarmSafely` returning `EventCancellationStatus` using `isWithinImminentWindow(alarm.dateTime, DateTime.now())`.
- Implement `cancelNotificationSafely` returning `EventCancellationStatus` using fingerprint scheduled time with fail-closed fallback to `unverifiable` when payload binding fails.
- Implement `verifyAlarm` and `verifyNotification` wrapping infrastructure errors into `unverifiable` and re-throwing domain errors.

### 10.4 [`lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart)
- Implement Two-Phase Atomic Reconciliation across `alarm`, `notification`, and `off` modes.
- Implement strict precedence in `off` mode ($\text{Failed} > \text{Deferred} > \text{Clean}$).
- Handle `unverifiable` fail-closed. Catch only `PlatformException` and `MissingPluginException`.

---

## 11. Acceptance Criteria & Pre-Execution Freeze

1. **Production Freeze:** Zero edits to `lib/` until this Revision 4 Plan receives formal architectural approval.
2. **Suite Targets:**
   - `scheduler_production_path_integration_test.dart`: **52 / 52 PASS (100% GREEN)**.
   - Core Regression Suite (5 files / 80 tests): **80 / 80 PASS (100% GREEN)**.
   - Static Analysis (`flutter analyze`): **0 Compilation Errors**.

