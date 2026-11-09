# PHASE 2C.4.2.0 — Production Interface & Baseline Inspection Audit
## Architectural Inspection, Real Repository Capabilities & L1/L2 Contract Audit

**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** Phase 2C.4.2.0  
**Type:** Production Baseline & Interface Capability Audit  
**Status:** SUBMITTED FOR STOP GATE 1 REVIEW  
**Execution Timestamp:** 2026-11-08  

---

## 1. Executive Summary & Preflight Confirmation

### 1.1 Preflight Phase 2C.4.1 Closure
All mandatory preflight requirements have been satisfied:
1. **Test 23 Reclassified:** Reclassified as `Legacy Blanket Cancellation Behavior: Pre-existing alarm wiped before notification scheduling` in [`scheduler_production_path_integration_test.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/test/features/notifications/scheduler_production_path_integration_test.dart#L1071).
2. **L2 Claim Removed:** All L2 verification claims and artificial fault injection sets were removed from Test 23. Test 23 now proves purely that the legacy scheduler's `cancelAllAlarms()` wipes pre-existing alarms before scheduling.
3. **34-Test Matrix Execution:** Fully executed with **7 PASS / 27 EXPECTED RED** (honest TDD baseline).
4. **Core Regression Suite:** All **75 / 75 PASS (100% GREEN)** across 5 suites.
5. **Baseline Integration Suite:** **52 PASS / 6 EXPECTED RED** (identical to Phase 2C.0 baseline).
6. **Production Code Freeze:** **0 lines of production code in `lib/` modified**.

---

## 2. Production Codebase & Dependency Audit

| Component | File Path | Current Status & Capabilities |
|---|---|---|
| **Scheduler Use Case** | [`lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart) | Reads and validates configs (Phase 2C.2.3), but still uses sequential IDs (`currentId++`), global `adhanStyle`, and blanket `cancelAllAlarms()` at line 59. |
| **Notification Repository (Interface)** | [`lib/features/notifications/domain/repos/base_notification_repository.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/repos/base_notification_repository.dart) | Declares `schedulePrayerNotification`, `scheduleAdhanAlarm`, `cancelAlarmSafely`, `cancelNotification`, `cancelAllAlarms`, `cancelAllNotifications`, `getPendingNotificationsCount`. **Lacks L2 query methods.** |
| **Notification Repository (Impl)** | [`lib/features/notifications/data/repos/notification_repository_impl.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/data/repos/notification_repository_impl.dart) | Wraps `flutter_local_notifications: ^21.0.0` and `alarm: ^5.3.0`. Implements `cancelAlarmSafely()` with $\pm 15\text{s}$ guard and active audio protection. |
| **Deterministic ID Contract** | [`lib/features/notifications/domain/entities/calendar_alarm_id_contract.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/entities/calendar_alarm_id_contract.dart) | Mathematical formula producing unique 32-bit IDs (`24010100..99123149`) per date, prayer (0..4), and event type (0..5). Rejects UTC. |
| **Prayer Decision Entity** | [`lib/features/notifications/domain/entities/prayer_scheduling_decision.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/entities/prayer_scheduling_decision.dart) | Pure mapping enum: `PrayerAlertDecision.fromConfig(config)` mapping `alarm -> alarm`, `notification -> notification`, `off -> none`. |
| **Config Repository** | [`lib/features/notifications/domain/repos/prayer_alarm_config_repository.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/repos/prayer_alarm_config_repository.dart) | Provides validated `Map<PrayerId, PrayerAlarmConfig>` for all 5 prayers. |

---

## 3. Deep Forensic Investigation of the Six Audit Questions

### 3.1 Question 1: Which methods provide L1 scheduling success?
* **Alarms (`scheduleAdhanAlarm`):**
  * Invokes `await Alarm.set(alarmSettings: alarmSettings)`.
  * **L1 Definition:** The asynchronous platform channel call returns without throwing an uncaught exception (`PlatformException`, `StateError`, etc.).
  * *Implementation Note:* In `NotificationRepositoryImpl` (lines 258–264), an existing guard silently returns if `scheduledTime` is within 1 minute of `DateTime.now()` (except for test alarm ID 888).
* **Notifications (`schedulePrayerNotification`):**
  * On Android/iOS: Invokes `await flutterLocalNotificationsPlugin.zonedSchedule(...)` with `AndroidScheduleMode.exactAllowWhileIdle`.
  * On Desktop: Invokes `flutterLocalNotificationsPlugin.show(...)` via in-memory `Timer`.
  * **L1 Definition:** The asynchronous call completes normally without throwing.

### 3.2 Question 2: Which methods can verify L2 persistence?
* **Notifications (`flutter_local_notifications`):**
  * The plugin exposes `flutterLocalNotificationsPlugin.pendingNotificationRequests()`, which returns `Future<List<PendingNotificationRequest>>`. Each request exposes `int id`, `String? title`, `String? body`, `String? payload`.
  * **Current Repository Gap:** Currently, `BaseNotificationRepository` only exposes `Future<int> getPendingNotificationsCount();` (line 26). Callers cannot check whether a specific ID exists.
* **Alarms (`package:alarm`):**
  * The package exposes `Alarm.getAlarm(int id)`, returning `Future<AlarmSettings?>` (or `AlarmSettings?` synchronous lookup in package internal registry).
  * `Alarm.getAlarms()` returns `List<AlarmSettings>` of all currently active alarms in the package registry.
  * **Current Repository Gap:** `cancelAlarmSafely()` internally calls `Alarm.getAlarm(id)` (line 320), but `BaseNotificationRepository` does not expose an external query method for callers to verify an alarm's existence.

### 3.3 Question 3: Whether `package:alarm` exposes sufficient identity and state inspection?
* **Identity Inspection: YES.**
  * `Alarm.getAlarm(id)` verifies whether an alarm with `id` is registered in `package:alarm`'s internal storage and returns its complete `AlarmSettings` (`dateTime`, `assetAudioPath`, etc.).
* **Ringing / Active State Inspection: YES (Best Effort).**
  * `Alarm.isRinging(id)` returns `Future<bool>` querying the background audio player service.
* **Architectural Limitation & Inevitable Race Window:**
  * `package:alarm` manages alarms in user-space SharedPreferences and schedules native alarms via Android `AlarmManager`.
  * `Alarm.getAlarm(id)` inspects the package's registry, **not the Android OS kernel queue (`dumpsys alarm`)**.
  * A native alarm may fire at the OS level milliseconds before Dart registers `isRinging(id) == true`.
  * Therefore, state inspection alone is insufficient to prevent audio clipping; the **$\pm 15\text{s}$ temporal proximity guard** implemented in `cancelAlarmSafely()` is mathematically mandatory.

### 3.4 Question 4: Whether same-ID replacement is supported?
* **In `package:alarm`:**
  * Calling `Alarm.set()` with an existing `id` replaces the previous alarm in the package registry.
  * **CRITICAL FINDING: Same-ID replacement is NOT ATOMIC.**
    * If `Alarm.set()` encounters an I/O error or permission failure during update, the previous alarm may be partially corrupted or removed.
    * No rollback transaction exists between Dart and the Android `AlarmManager`.
  * Furthermore, in Hafiz Al-Ahd, prayer alarms and prayer notifications have **disjoint IDs**:
    * Alarm ID: `...0`
    * Notification ID: `...1`
    * A transition between Alarm and Notification (e.g. Case 3, Case 6) is **cross-ID**, not same-ID. Same-ID replacement applies solely to in-place parameter refreshes of the same alert type (Case 2 and Case 7).
* **In `flutter_local_notifications`:**
  * Calling `zonedSchedule()` with an existing `id` updates the `PendingIntent` (`FLAG_UPDATE_CURRENT`) and overwrites the SQLite row in FLN's internal database. It is handled by the plugin, but again lacks multi-subsystem transactional guarantees.

### 3.5 Question 5: Which cancellation methods are ID-specific?
* **Targeted ID-Specific Methods:**
  1. `cancelAlarmSafely(int id, ...)`:
     * Validates ID domain (`1..100` legacy, `24010100..99123149` modern).
     * Validates asset ownership (`adhan.mp3` / `fajr_azan.mp3`).
     * Enforces drift guard ($\le 60\text{s}$).
     * Enforces active audio protection (`isRinging`).
     * Enforces temporal proximity guard ($\pm 15\text{s}$).
     * Executes `Alarm.stop(id)`.
  2. `cancelNotification(int id)`:
     * Calls `flutterLocalNotificationsPlugin.cancel(id: id)`.
     * Safe and idempotent if `id` is not currently scheduled.
* **Blanket / Destructive Methods (MUST BE REMOVED from Weekly Scheduler):**
  1. `cancelAllAlarms()`: Destroys all alarms indiscriminately via `Alarm.stopAll()`. Wipes test alarm ID `888`.
  2. `cancelAllNotifications()`: Destroys all notifications indiscriminately via `flutterLocalNotificationsPlugin.cancelAll()`. Wipes foreground service sticky countdown ID `8888` and widget ID `999`.
  3. `cancelActivePrayerNotification()`: Wipes notifications in tray on channel `prayer_channel_v9`.

### 3.6 Question 6: Which operations are asynchronous and can partially fail?
* **All Platform Interop Calls are Asynchronous:**
  1. `prayerAlarmConfigRepository.getConfigs()` $\to$ Storage read failure.
  2. `getPrayerTimesUseCase.execute()` $\to$ Calculation failure for a specific date (e.g. Day 2 calculation throws).
  3. `scheduleAdhanAlarm()` $\to$ L1 exception or L2 persistence failure.
  4. `schedulePrayerNotification()` $\to$ L1 exception or L2 persistence failure (applies to prayer alert, Iqama, post-prayer azkar, morning azkar, evening azkar).
  5. `cancelAlarmSafely()` $\to$ Returns `false` when suppressed by temporal or audio guards.
  6. `pref.setString('scheduled_until_date', ...)` $\to$ SharedPreferences commit failure.
* **Failure Boundary & Horizon Integrity:**
  * Because operations can partially fail mid-day or mid-week without atomic rollback, the scheduler **must never assume all-or-nothing execution**.
  * If Day 2 encounters any failure, all successful events on Day 0, Day 1, and Day 2 **must remain registered in hardware/plugin registries under their deterministic IDs**.
  * The scheduling horizon `scheduled_until_date` must cap at the **last contiguous complete day** (Day 1).
  * Subsequent retries will converge idempotently without duplication.

---

## 4. Proposed Interface Extension (Smallest Necessary Change)

To allow the production scheduler ([`ScheduleWeeklyPrayersUseCase`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/usecases/schedule_weekly_prayers_usecase.dart)) to execute **Targeted Reconciliation** and **L2 Verification** without violating clean architecture:

### 4.1 Interface Additions to `BaseNotificationRepository`
We propose adding exactly **two pure query methods** to [`BaseNotificationRepository`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/lib/features/notifications/domain/repos/base_notification_repository.dart):

```dart
  /// Checks whether a notification with [id] is registered in the plugin pending queue (L2 verification).
  Future<bool> isNotificationPending(int id);

  /// Checks whether an alarm with [id] is registered in the alarm package registry (L2 verification).
  Future<bool> isAlarmScheduled(int id);
```

### 4.2 Implementation in `NotificationRepositoryImpl`
```dart
  @override
  Future<bool> isNotificationPending(int id) async {
    final pending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    return pending.any((req) => req.id == id);
  }

  @override
  Future<bool> isAlarmScheduled(int id) async {
    final alarm = await Alarm.getAlarm(id);
    return alarm != null;
  }
```

### 4.3 Why this is the Smallest Necessary Change:
1. **Zero Leaked Types:** Uses pure `bool` query signatures; domain does not import `AlarmSettings` or `PendingNotificationRequest`.
2. **Reuses Existing Plugin Capabilities:** Both `Alarm.getAlarm` and `pendingNotificationRequests` are already utilized in `NotificationRepositoryImpl`.
3. **Enables Pure L2 Verify-Before-Cancel:** The scheduler can query `await notificationRepository.isAlarmScheduled(alarmId)` and `await notificationRepository.isNotificationPending(notifId)` before deciding whether to cancel conflicting events.
4. **Zero Overhead:** ~5 lines of code per method in `NotificationRepositoryImpl` and `StatefulNotificationRepositoryFake`.

---

## 5. STOP GATE 1 — Submission & Verification

```text
================================================================================
Phase 2C.4.2.0 Deliverable: PHASE_2C_4_2_0_PRODUCTION_INTERFACE_AUDIT.md
Preflight Status:
  - Test 23 Reclassified to Legacy Blanket Cancellation Behavior: CONFIRMED
  - 34 Production-Path Tests: 7 PASS / 27 EXPECTED RED (HONEST BASELINE)
  - Core Regression Suite: 75 / 75 PASS (100% GREEN)
  - Baseline Integration Suite: 52 PASS / 6 EXPECTED RED (IDENTICAL TO 2C.0)
  - Production Code Freeze: 100% RESPECTED (0 production lines edited)
Interface Audit Findings:
  - 6 forensic questions answered with code line citations.
  - Minimal interface extension proposed: isNotificationPending(id) & isAlarmScheduled(id).
Gate Status: STRICT STOP GATE 1 ACTIVE. Awaiting user approval to proceed to Phase 2C.4.2.1.
================================================================================
```

