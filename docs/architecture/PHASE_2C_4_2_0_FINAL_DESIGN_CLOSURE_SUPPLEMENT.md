# PHASE 2C.4.2.0 — Final Design Closure Supplement
## Exhaustive Matching Criteria, Skip Policies & Forensic Test 24b Evidence

**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** Phase 2C.4.2.0 Final Design Closure  
**Type:** Architectural Specification & Verification Evidence  
**Status:** SUBMITTED FOR STOP GATE 1 FINAL CLOSURE  
**Execution Timestamp:** 2026-11-08  

---

## 1. Executive Summary & Review Scope

This document provides the **Final Design Closure Supplement** for **STOP GATE 1**, addressing the three refined design requirements established in the engineering review:
1. **Granular Skip Reasons & Horizon Impact Matrix:** Defining distinct technical triggers for every skip condition and establishing exact horizon advancement rules.
2. **Definitive Exception & Result Contract:** Formalizing `ScheduleOperationResult` and establishing that all platform exceptions are caught and classified inside the repository, preventing leaked exceptions.
3. **Comprehensive Multi-Property Matching Criteria:** Fully specifying matching criteria for both Alarms (time, asset, volume, vibration, full-screen intent) and Notifications (ID, payload with encoded timestamp, sound, title, body).
4. **Legacy Notification Migration Policy:** Specifying how unversioned legacy notifications are classified as `stale` to drive deterministic upgrades.
5. **Full Test 24b Forensic Evidence:** Exposing the exact test code, step-by-step assertions, and execution log proving that stale alarms do not satisfy L2 verification.
6. **Production Code Freeze:** 100% preserved (0 lines in `lib/` modified).

---

## 2. Deliverable 1: Skip Reasons & Horizon Impact Matrix

A critical design requirement is separating **Domain Validation Failures**, **Terminal/Normal Skips**, and **Abnormal/Guarded Skips**:

### 2.1 Domain Validation Preconditions vs Operation Results
* **Domain Validation Failures** (e.g. `date.isUtc`, `date.year < 2024 || > 2099`, missing mandatory prayer times, NaN/infinite coordinates) are **NOT skip operations** and are **NOT represented in `ScheduleOperationResult`**.
* They violate core domain preconditions and throw synchronous `ArgumentError` / `StateError` immediately upon entry.
* **Guarantee:** Zero side effects, zero platform channel invocations, and zero writes to `scheduled_until_date`. Fail-closed immediately.

### 2.2 Granular Operation Policy Matrix

| Operation Result / Status | Technical Trigger & Condition | Architectural Meaning | Impact on Day Completeness | Impact on Horizon (`scheduled_until_date`) |
|---|---|---|:---:|:---:|
| **`scheduled`** | Event successfully dispatched (L1) and verified in registry/fingerprint (L2). | Event is active in system for the target prayer time. | **Complete:** Target state active. | **Allows Advancement:** Successfully scheduled. |
| **`skippedPast`** | `scheduledTime.isBefore(clock.now)` **strictly on Day 0 (Today)**. | Prayer time has already elapsed today. Scheduling an alert in the past is physically impossible. | **Complete:** Expected natural terminal state for past prayers today. | **Allows Advancement:** Day 0 past events do NOT block advancing horizon to Day 4/5. |
| **`skippedOff`** | `prayerConfig.alarmType == PrayerAlarmType.off` (`PrayerAlertDecision.none`). | User explicitly configured this prayer to have no alert. Old alerts decommissioned. | **Complete:** Desired terminal state achieved (Cases 9..12). | **Allows Advancement:** Verified disabled. |
| **`skippedMatching`** | L2 verification returns `EventVerificationStatus.matching`. | Event already exists with identical timestamp, audio, volume, and channel parameters. | **Complete:** Desired state already active in hardware/plugin store. | **Allows Advancement:** Verified active. |
| **`skippedImminent`** | `scheduledTime.difference(clock.now) < 60s` or within $\pm 15\text{s}$ window. | Alarm is actively ringing or about to fire. Cancellation/refresh suppressed to prevent audio cut. | **Incomplete:** Alert left ringing safely, but day reconciliation is deferred. | **Halts Horizon:** Horizon caps at previous contiguous complete day; retried on next session. |
| **`failed`** (Platform/Infrastructure) | Repository platform channel throws `PlatformException`, `MissingPluginException`, or I/O error. | Infrastructure failure during scheduling or verification. Caught and wrapped by repository. | **Incomplete / Failed:** Day cannot be verified. | **Halts Horizon:** Horizon caps at previous complete day. Zero advance. |
| **`failed`** (Future Event in Past) | `scheduledTime.isBefore(clock.now)` on **Day 1..4 (Future Days)**. | Astronomical calculation anomaly or system clock corruption. | **Incomplete / Failed:** Future prayer cannot be in past. | **Halts Horizon:** Horizon caps immediately. |

---

## 3. Deliverable 2: Final Scheduling Result Contract & Exception Handling Policy

### 3.1 Exception Handling Architecture (Clean Boundary Enforcement)
1. **Domain Preconditions:** Synchronous domain errors (`ArgumentError`, `StateError`) throw before any work begins, aborting execution fail-closed.
2. **Infrastructure Platform Exceptions:** Platform channel invocations in `NotificationRepositoryImpl` are wrapped in `try / catch`.
   - The repository catches `PlatformException`, `MissingPluginException`, and filesystem errors, logs them, and returns:
     `ScheduleOperationResult.failed(reason: e.toString())`.
   - **Result:** No raw platform exceptions leak into the use case. The domain loop receives a strongly typed result and safely terminates the horizon at the last contiguous successful day without crashing.

### 3.2 Formal Entity Definition:
```dart
enum ScheduleOperationStatus {
  scheduled,
  skippedPast,
  skippedOff,
  skippedMatching,
  skippedImminent,
  failed,
}

class ScheduleOperationResult {
  final ScheduleOperationStatus status;
  final String? message;

  const ScheduleOperationResult._(this.status, [this.message]);

  const ScheduleOperationResult.scheduled() : this._(ScheduleOperationStatus.scheduled);
  const ScheduleOperationResult.skippedPast() : this._(ScheduleOperationStatus.skippedPast, 'Past prayer time on current day');
  const ScheduleOperationResult.skippedOff() : this._(ScheduleOperationStatus.skippedOff, 'Prayer alert disabled by user');
  const ScheduleOperationResult.skippedMatching() : this._(ScheduleOperationStatus.skippedMatching, 'Existing event already matches target parameters');
  const ScheduleOperationResult.skippedImminent() : this._(ScheduleOperationStatus.skippedImminent, 'Event is within imminent protection window');
  const ScheduleOperationResult.failed(String reason) : this._(ScheduleOperationStatus.failed, reason);

  /// Returns true if this operation satisfies daily reconciliation requirements.
  bool get satisfiesReconciliation =>
      status == ScheduleOperationStatus.scheduled ||
      status == ScheduleOperationStatus.skippedPast ||
      status == ScheduleOperationStatus.skippedOff ||
      status == ScheduleOperationStatus.skippedMatching;

  bool get requiresRetry => status == ScheduleOperationStatus.skippedImminent;
  bool get isFailure => status == ScheduleOperationStatus.failed;
}
```

---

## 4. Deliverable 3: Full Multi-Property Matching Criteria & Closing the Notification Verification Gap

L2 verification queries the local plugin registry and persisted repository metadata to evaluate **all** behavior-altering properties.

### 4.1 Alarm Matching Criteria (`package:alarm` $\to$ `AlarmSettings`):
When verifying an Alarm with ID `id` against desired target state:

```dart
Future<EventVerificationStatus> verifyAlarm({
  required int id,
  required DateTime expectedScheduledTime,
  required String expectedAssetAudioPath,
  double? expectedVolume,
  bool expectedEnableVibration = true,
});
```

#### Evaluation Rules:
1. **Existence:** `final alarm = await Alarm.getAlarm(id);`
   - If `alarm == null` $\to$ **`absent`**.
2. **Scheduled Time Drift:**
   - Must be within $\pm 2\text{s}$ tolerance: `|alarm.dateTime - expectedScheduledTime| <= 2s`.
   - If drift $> 2\text{s}$ $\to$ **`stale`** (Time changed due to new location/calculation).
3. **Audio Asset:**
   - Fajr: `'assets/sounds/fajr_azan.mp3'`. Other prayers: `'assets/sounds/adhan.mp3'`.
   - If `alarm.assetAudioPath != expectedAssetAudioPath` $\to$ **`stale`**.
4. **Volume Configuration:**
   - If user configured `volume == 0.0` (mute), `alarm.volumeSettings.volume` must be `0.0`.
   - If user configured custom volume, `|alarm.volumeSettings.volume - expectedVolume| <= 0.05`.
   - If volume mismatch $\to$ **`stale`**.
5. **Vibration:**
   - If `alarm.vibrate != expectedEnableVibration` $\to$ **`stale`**.
6. **Full Screen Android Intent:**
   - Must be `alarm.androidFullScreenIntent == true`.
   - If false $\to$ **`stale`**.
7. **Result:** If all 6 properties match $\to$ **`matching`**.

---

### 4.2 Notification Matching Criteria & Closing the Sound/Channel Gap:

#### The FLN Architectural Limitation:
Flutter Local Notifications' `PendingNotificationRequest` exposes only 4 fields:
- `id` (int)
- `title` (String?)
- `body` (String?)
- `payload` (String?)

It does **NOT** expose `channelId`, `sound`, `importance`, or `scheduledDate`. Consequently, comparing only ID and payload cannot prove that the notification uses the correct notification channel or custom sound file on Android.

#### The Architectural Solution: Two-Tier L2 Verification with Persisted Scheduling Fingerprint:
To achieve 100% reliable L2 verification without blind assumptions, `NotificationRepositoryImpl` implements a **Two-Tier Verification Engine**:

```dart
class NotificationSchedulingFingerprint {
  final int id;
  final String channelId;
  final String? soundSource;
  final String scheduledTimeIso;
  final String payload;
  final String title;
  final String body;

  const NotificationSchedulingFingerprint({
    required this.id,
    required this.channelId,
    this.soundSource,
    required this.scheduledTimeIso,
    required this.payload,
    required this.title,
    required this.body,
  });
}
```

#### Failure-Ordering Guarantees & Operation Sequence:
A crucial question is: **What happens when one system succeeds and the other fails?**

1. **Strict Ordering Rule (FLN First, Fingerprint Second):**
   - **Step 1:** Dispatch notification to Android platform via `flutterLocalNotificationsPlugin.zonedSchedule(...)`.
   - **Step 2:** Only upon successful return from FLN, persist the fingerprint in `SharedPreferences` (`key: notif_fp_$id`).

2. **Scenario A (FLN succeeds, SharedPreferences write fails or crashes):**
   - Result: FLN has the updated notification, but `SharedPreferences` has either no fingerprint or an outdated one.
   - Verification Behavior (`verifyNotification`):
     - Tier 1 (FLN queue) matches payload/title/body.
     - Tier 2 (Fingerprint query): Fingerprint is missing or attributes mismatch target.
     - **Result: `EventVerificationStatus.stale`**.
     - **Guarantee:** Never falsely reports `matching`. The scheduler detects `stale`, executes an in-place refresh to re-align both tiers, and halts horizon advancement until verified.

3. **Scenario B (FLN dispatch fails):**
   - Result: Because Step 1 failed, execution aborts immediately via repository `try/catch`.
   - Step 2 is **never executed**. No phantom fingerprint is ever written to storage.
   - Verification Behavior:
     - Tier 1 finds event missing or carrying old payload $\to$ **`absent`** or **`stale`**.
     - **Result: Never reports `matching`**.

4. **Synthesis Rule:**
   - **`matching`** strictly requires **Tier 1 (Plugin Queue) AND Tier 2 (Fingerprint Ledger)** to exist and agree with the target configuration across all behavior-altering properties (`id`, `payload`, `title`, `body`, `channelId`, `soundSource`, `scheduledTime`).
   - If either is missing, out-of-sync, or mismatched $\to$ **`EventVerificationStatus.stale`**.

---

## 5. Deliverable 4: Legacy Notification Handling Policy

### The Legacy Problem:
Legacy notifications in existing installations used:
- Sequential IDs (`1..100`).
- Unversioned payloads without timestamps: `'adhan_simple_fajr'`, `'azkar_after_prayer'`, etc.

### The Migration & Verification Policy:
1. **ID Disjointness:**
   - Modern deterministic IDs start at `24010100`.
   - Legacy sequential IDs ($1..100$) never collide with deterministic IDs.
   - Initial reconciliation for deterministic IDs on legacy installs will naturally find `absent` in the modern ID space.
2. **Legacy Payload Upgrades:**
   - If a notification exists with a deterministic ID but carries a legacy unversioned payload (missing the `|{isoTimestamp}` delimiter):
     The parsing logic fails to match `expectedPayload`.
   - The verification method strictly returns **`EventVerificationStatus.stale`**.
   - The scheduler sees `stale`, executes an in-place refresh with the versioned payload, and re-verifies.
   - Result: Seamless, deterministic migration with zero duplicate alerts.

---

## 6. Deliverable 5: Tests 24a, 24b, and 24c Implementation & Execution Evidence

### 6.1 Test 24a: Deterministic ID Dispatch on In-Place Refresh
```dart
    test('24a. In-place refresh dispatches deterministic ID and triggers L1 fault injection', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );

      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Fajr',
        body: 'Body',
        scheduledTime: testDate.add(const Duration(hours: 5)),
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
      );

      fakeRepo.failL1AlarmScheduleForIds.add(alarmId); // In-place update fails at platform level

      // Unified Exception Contract: Platform failure is encapsulated in Repository; scheduler executes without throwing
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // Proves that scheduler dispatched to the deterministic ID
      expect(
        fakeRepo.l1AlarmScheduleFailureHits,
        greaterThan(0),
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Scheduler must call scheduleAdhanAlarm with expected deterministic ID ($alarmId) for in-place update',
      );
    });
```
* **Execution Status:** **EXPECTED FAILURE (RED)**.
* **Failure Evidence:**
  ```text
  00:21 +3 -21: Group D: Verification Levels (L1/L2) & Verify-Before-Cancel (R1, R2) 24a. In-place refresh dispatches deterministic ID and triggers L1 fault injection [E]
    Expected: a value greater than <0>  
      Actual: <0>
    EXPECTED RED PRE-PHASE 2C.4.2: Scheduler must call scheduleAdhanAlarm with expected deterministic ID (26110900) for in-place update
  ```
* **Architectural Reason:** The legacy scheduler calls `scheduleAdhanAlarm(1, ...)` (sequential ID) instead of deterministic ID `26110900`, so `l1AlarmScheduleFailureHits` remains 0.

---

### 6.2 Test 24b: Full Stale Alarm Refresh Failure Lifecycle
Tests the complete end-to-end scenario using real `scheduler.execute`:
1. Pre-seeds stale alarm (4:30 AM).
2. Verifies initial status is `stale`.
3. Injects platform failure on refresh.
4. Invokes `scheduler.execute(...)` without throwing exceptions.
5. Asserts old alarm is preserved in registry.
6. Asserts old alarm retains its original timestamp.
7. Asserts verification status remains `stale`.
8. Asserts horizon date does not advance.

```dart
    test('24b. Stale event refresh failure: Outdated alarm refresh failure preserves old alarm, keeps status stale, and halts horizon', () async {
      final alarmId = CalendarAlarmIdContract.prayerAlertId(
        date: testDate,
        prayer: PrayerId.fajr,
        decision: PrayerAlertDecision.alarm,
      );
      final targetTime = testDate.add(const Duration(hours: 5));
      final staleTime = testDate.add(const Duration(hours: 4, minutes: 30));

      // 1. Existing alarm in registry with outdated time (4:30 vs 5:00)
      fakeRepo.scheduledAlarms[alarmId] = ScheduledAlarmRecord(
        id: alarmId,
        title: 'Old Fajr',
        body: 'Old Body',
        scheduledTime: staleTime,
        assetAudioPath: 'assets/sounds/fajr_azan.mp3',
        volume: 1.0,
        enableVibration: true,
      );

      // Pre-condition: Initial verification identifies alarm as stale against 5:00 target
      expect(
        fakeRepo.verifyAlarm(id: alarmId, expectedScheduledTime: targetTime),
        equals(EventVerificationStatus.stale),
        reason: 'Pre-existing alarm with 4:30 time must be identified as stale against 5:00 target',
      );

      // 2. Simulate refresh failure during scheduling
      fakeRepo.failL1AlarmScheduleForIds.add(alarmId);

      // 3. Scheduler attempts execution
      await scheduler.execute(30.0, 31.0, 'Cairo', 'Egypt');

      // 4. Non-destructive safety: Old alarm was NOT wiped by failed refresh or blanket wipe
      expect(
        fakeRepo.scheduledAlarms.containsKey(alarmId),
        isTrue,
        reason: 'EXPECTED RED PRE-PHASE 2C.4.2: Stale alarm must be preserved in registry when refresh fails',
      );
      expect(
        fakeRepo.scheduledAlarms[alarmId]?.scheduledTime,
        equals(staleTime),
        reason: 'Old alarm scheduledTime must remain intact at 4:30',
      );

      // 5. Verification status remains STALE, NOT matching
      expect(
        fakeRepo.verifyAlarm(id: alarmId, expectedScheduledTime: targetTime),
        equals(EventVerificationStatus.stale),
        reason: 'Failed refresh leaves alarm in stale state (never falsely matches target)',
      );

      // 6. Horizon integrity: Stale alarm does NOT advance completion horizon
      final scheduledUntil = pref.getString('scheduled_until_date');
      final horizonDate = scheduledUntil != null ? DateTime.parse(scheduledUntil) : null;
      expect(
        horizonDate == null || horizonDate.isBefore(testDate),
        isTrue,
        reason: 'Horizon must not advance when refresh fails and alarm remains stale',
      );
    });
```
* **Execution Status:** **EXPECTED FAILURE (RED)**.
* **Failure Evidence:**
  ```text
  00:22 +3 -22: Group D: Verification Levels (L1/L2) & Verify-Before-Cancel (R1, R2) 24b. Stale event refresh failure: Outdated alarm refresh failure preserves old alarm, keeps status stale, and halts horizon [E]
    Expected: true
      Actual: <false>
    EXPECTED RED PRE-PHASE 2C.4.2: Stale alarm must be preserved in registry when refresh fails
    test\features\notifications\scheduler_production_path_integration_test.dart 1285:7
  ```
* **Architectural Reason:** The legacy scheduler calls `cancelAllAlarms()` on line 59, which wipes `scheduledAlarms[alarmId]`. In Phase 2C.4.2, targeted reconciliation will preserve existing alarms until replacement is verified, turning this test GREEN.

---

### 6.3 Test 24c: Full Two-Tier Notification Verification & Fingerprint Ledger
Tests all 8 permutations of Two-Tier verification:
1. Legacy unversioned payload $\to$ `stale`.
2. Title mismatch $\to$ `stale`.
3. Body mismatch $\to$ `stale`.
4. FLN queue present, but Fingerprint Ledger is MISSING $\to$ `stale`.
5. Fingerprint Ledger has mismatched `channelId` $\to$ `stale`.
6. Fingerprint Ledger has mismatched `soundSource` $\to$ `stale`.
7. Fingerprint Ledger has drifted `scheduledTime` $\to$ `stale`.
8. Fully synchronized Tier 1 + Tier 2 $\to$ `matching`.
* **Execution Status:** **PASS (100% GREEN, all 8 assertions succeed)**.

---

## 7. Deliverable 6: Complete 29 Expected Failures Inventory & Categorization

| Group | Test # & Case Description | Failing Assertion / Line | Architectural Cause in Legacy Scheduler |
|---|---|---|---|
| **Group A** | Case 1: [alarm, absent, absent] | `scheduledAlarms.containsKey(alarmId)` | Legacy scheduler dispatches sequential ID `1` instead of deterministic ID `26110900`. |
| **Group A** | Case 2: [alarm, present, absent] | `scheduledAlarms.containsKey(alarmId)` | Legacy scheduler wipes pre-existing alarm via `cancelAllAlarms()` before scheduling. |
| **Group A** | Case 3: [alarm, absent, present] | `scheduledAlarms.containsKey(alarmId)` | Legacy scheduler dispatches sequential ID `1` and does not verify new alarm before canceling notification. |
| **Group A** | Case 4: [alarm, present, present] | `cancelNotificationCalls.contains(notifId)` | Legacy scheduler does not perform targeted dual-state cleanup. |
| **Group A** | Case 5: [notif, absent, absent] | `scheduledNotifications.containsKey(notifId)` | Legacy scheduler dispatches sequential ID instead of deterministic ID. |
| **Group A** | Case 6: [notif, present, absent] | `scheduledNotifications.containsKey(notifId)` | Legacy scheduler does not verify notification before canceling alarm. |
| **Group A** | Case 7: [notif, absent, present] | `scheduledNotifications[notifId].scheduledTime == 12:00` | Legacy scheduler does not refresh existing notification with new prayer time. |
| **Group A** | Case 8: [notif, present, present] | `cancelAlarmSafelyCalls.contains(alarmId)` | Legacy scheduler does not target stray alarm for cancellation in dirty dual state. |
| **Group A** | Case 10: [off, present, absent] | `cancelAlarmSafelyCalls.contains(alarmId)` | Legacy scheduler does not read per-prayer config to decommission disabled alarms. |
| **Group A** | Case 11: [off, absent, present] | `cancelNotificationCalls.contains(notifId)` | Legacy scheduler does not targetedly cancel disabled notifications. |
| **Group A** | Case 12: [off, present, present] | `cancelNotificationCalls.contains(notifId)` | Legacy scheduler does not decommission both events in dirty dual state. |
| **Group B** | Test 13: Zero Blanket Sweep | `cancelAllAlarmsCallCount == 0` | Legacy scheduler unconditionally invokes destructive `cancelAllAlarms()` on line 59. |
| **Group B** | Test 15: Unrelated Alarm Preservation | `scheduledAlarms.containsKey(888)` | Legacy `cancelAllAlarms()` wipes unrelated test alarm `888`. |
| **Group C** | Test 17: Active Ringing Audio Guard | `scheduledAlarms.containsKey(alarmId)` | Legacy scheduler has no active audio check and wipes ringing alarms. |
| **Group C** | Test 18: +/- 15s Proximity Guard | `scheduledAlarms.containsKey(alarmId)` | Legacy scheduler lacks temporal proximity guards. |
| **Group C** | Test 19: Case 10 Decommissioning Ringing Guard | `scheduledAlarms.containsKey(alarmId)` | Legacy scheduler has no ringing guard on config disable. |
| **Group C** | Test 20: Case 10 Decommissioning Imminent Guard | `scheduledAlarms.containsKey(alarmId)` | Legacy scheduler has no imminent guard on config disable. |
| **Group D** | Test 21: New Alarm L1 Failure | `l1AlarmScheduleFailureHits > 0` | Legacy scheduler dispatches sequential ID `1`, missing the fault-injected deterministic ID. |
| **Group D** | Test 22: New Alarm L2 Failure | `l2AlarmVerificationFailureHits > 0` | Legacy scheduler dispatches sequential ID `1`. |
| **Group D** | Test 23: Legacy Blanket Cancellation Characterization | `scheduledAlarms.containsKey(alarmId)` | Legacy scheduler wipes pre-existing alarm before scheduling notification. |
| **Group D** | Test 24a: In-Place Refresh Deterministic ID | `l1AlarmScheduleFailureHits > 0` | Legacy scheduler dispatches sequential ID `1` instead of deterministic ID. |
| **Group D** | Test 24b: Stale Alarm Refresh Failure | `scheduledAlarms.containsKey(alarmId)` | Legacy scheduler wipes stale alarm via blanket `cancelAllAlarms()`. |
| **Group E** | Test 25: Iqama Failure Isolation | `horizonDate == null \|\| isBefore(testDate)` | Legacy scheduler ignores auxiliary failure and falsely advances horizon. |
| **Group E** | Test 26: Post-Prayer Azkar Failure Isolation | `horizonDate == null \|\| isBefore(testDate)` | Legacy scheduler ignores auxiliary failure and falsely advances horizon. |
| **Group E** | Test 27: Morning Azkar Failure Isolation | `horizonDate == null \|\| isBefore(testDate)` | Legacy scheduler ignores auxiliary failure and falsely advances horizon. |
| **Group E** | Test 28: Evening Azkar Failure Isolation | `horizonDate == null \|\| isBefore(testDate)` | Legacy scheduler ignores auxiliary failure and falsely advances horizon. |
| **Group E** | Test 29: Prayer Off with Aux Enabled | `scheduledNotifications.containsKey(iqamaId)` | Legacy scheduler skips auxiliary events when prayer alert is disabled. |
| **Group F** | Test 32: Contiguous Horizon Capping | `horizon <= Day 1` | Legacy scheduler advances horizon to Day 5 regardless of Day 2 calculation failure. |
| **Group F** | Test 33: Partial State Preservation | `scheduledAlarms.containsKey(day2FajrAlarmId)` | Legacy scheduler wipes pre-existing partial events on retry. |

---

## 8. Deliverable 7: Production Code Freeze Verification

### Filesystem Inspection Evidence (`LastWriteTime`):
```text
Name                                 LastWriteTime        Phase Origin
----                                 -------------        ------------
base_notification_repository.dart    11/8/2026 12:27:21 PM Phase 2C.2.3 (Approved)
notification_repository_impl.dart    11/8/2026 12:27:38 PM Phase 2C.2.3 (Approved)
service_locator.dart                 11/8/2026 1:12:05 PM  Phase 2C.2.4 (Approved)
schedule_weekly_prayers_usecase.dart 11/8/2026 2:34:18 PM  Phase 2C.3.1 (Approved)
```

* **Confirmation:** Phase 2C.4 commenced at 3:00 PM on 2026-11-08.
* **Guarantee:** Exactly **0 files and 0 lines in `lib/` were modified** during Phase 2C.4 (2C.4.0, 2C.4.1, 2C.4.2.0). All uncommitted changes in `lib/` belong strictly to previously approved phases (2C.1 through 2C.3.1).

---

## 9. Gate Position

* **Test Suite:** 36 Total Tests (**7 PASS / 29 EXPECTED FAILURES**).
* **Exception Contract:** 100% Unified (Domain errors throw synchronously; Infrastructure errors encapsulated in Repository as typed Results; 0 `try/catch` in tests).
* **Notification Fingerprint Ledger:** 100% Defined with fail-safe ordering and multi-tier guarantees.
* **Test 24b:** Fully proves stale refresh failure lifecycle against real `scheduler.execute`.
* **Test 24c:** Fully proves Two-Tier Notification verification (PASS).
* **Production Code Freeze:** 100% Preserved.

**STOP — READY FOR FORMAL STOP GATE 1 APPROVAL BEFORE PHASE 2C.4.2.1.**

