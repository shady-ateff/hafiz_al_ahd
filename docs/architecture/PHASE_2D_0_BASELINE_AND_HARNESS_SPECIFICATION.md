# Phase 2D.0 — Baseline & Test Harness Specification (Revision 3)
## Frozen Baseline, Dual Device Profiles, Isolated Harness & Native Evidence Boundaries

- **Milestone:** P4.1-B.3 — Phase 2D.0
- **Branch:** `feature/p4.1-independent-alarms-adhan`
- **Baseline Git Commit:** `9b016573cac649c421f6414eeba29e720e9d30ef` (Phase 2C.4.2.4 Final)
- **Status:** **REVISED SPECIFICATION & HARNESS IMPLEMENTATION — READY FOR GATE 2D.0 AUDIT**

---

## 1. Frozen Baseline Environment

| Parameter | Recorded Value | Verification Source |
|---|---|---|
| **Git Commit Hash** | `9b016573cac649c421f6414eeba29e720e9d30ef` | `git rev-parse HEAD` |
| **Git Working Tree** | Clean (`nothing to commit, working tree clean`) | `git status` |
| **Flutter SDK** | `3.44.2 • channel stable` (rev `c9a6c48423`, 2026-06-10) | `flutter --version` |
| **Dart SDK** | `3.12.2` | `flutter --version` |
| **DevTools** | `2.57.0` | `flutter --version` |
| **Flutter Engine** | `04efd7c093d4e9281d5526ebcad6ecc60ba8badf` | `flutter --version` |
| **`alarm` Plugin** | `5.12.0` | `pubspec.lock` |
| **`flutter_local_notifications`** | `21.0.0` | `pubspec.lock` |
| **`crypto` Package** | `3.0.7` | `pubspec.lock` |
| **Android Application ID** | `com.shadyatef.hafiz_alahd` | `android/app/build.gradle.kts` |

---

## 2. Dual Physical Device Matrix & Comparative Analysis

Both devices are physically connected, individually profiled, and verified via ADB:

| Parameter | Primary Device: Xiaomi Redmi Note 14 Pro+ 5G | Secondary Device: Samsung Galaxy Tab A7 LTE | Operational Difference Analysis |
|---|---|---|---|
| **ADB Identity** | `dfa9f629` (USB) / `192.168.1.183:41503` | `192.168.1.186:45067` (Wi-Fi) | Primary via high-speed USB; secondary over local Wi-Fi |
| **Model & Code** | `25098RA98G` (`kunzite`) | `SM-T505N` (`gta4l`) | Modern 2025/2026 phone vs legacy 2020 tablet |
| **Manufacturer** | Xiaomi (HyperOS) | Samsung (One UI) | Aggressive OEM background managers on both vendors |
| **Android / API** | **Android 16 / API 36** | **Android 12 / API 31** | **Major API delta (4 Android generations apart)** |
| **Build ID** | `BP2A.250605.031.A3` | `SP1A.210812.016.T505NDXS7CXG1` | Vendor-certified production builds |
| **Timezone** | `Africa/Cairo` (`EET`, UTC+2) | `Africa/Cairo` (`EET`, UTC+2) | Synchronized local time |
| **Power Supply** | **USB powered (52%)** | **Battery powered (57%)** | Power-connected vs battery discharging |
| **Deviceidle Whitelist** | Whitelisted (`user,com.shadyatef.hafiz_alahd,10492`) | Whitelisted (`user,com.shadyatef.hafiz_alahd,10404`) | Whitelisted in baseline; tested without in 2D.4 |
| **Standby Bucket** | `5` (`STANDBY_BUCKET_EXEMPTED`) | `5` (`STANDBY_BUCKET_EXEMPTED`) | Exempted in baseline; tested in restricted buckets in 2D.4 |
| **Full Screen Intent** | `allow` (AppOp verified on Android 16) | N/A (Granted at install time on API 31) | Android 14+ introduced explicit runtime AppOp gate |
| **Process Kill Tool** | `run-as com.shadyatef.hafiz_alahd /system/bin/kill` | `run-as com.shadyatef.hafiz_alahd /system/bin/kill` | Both require `run-as` because shell user lacks signal perms |

> [!IMPORTANT]
> **Controlled Baseline Definition:** The active battery whitelist and exempted standby buckets represent the *Controlled Baseline Configuration*. These conditions are NOT treated as identical. In Phase 2D.4, each power variable (un-whitelisted, restricted bucket, screen off, on battery) will be tested independently and compared against this baseline.

---

## 3. Diagnostic Harness Architecture

To guarantee strict isolation and survive app process termination, the harness is split into three decoupled components:

```
┌─────────────────────────────────────────────────────────────┐
│                 HOST MACHINE (PowerShell / ADB)             │
│  External Device Observer: scripts/device_observer.ps1      │
│  - Dumpsys Alarm / Notification capture                     │
│  - Continuous Logcat streaming & filter                     │
│  - Process lifecycle control (background, kill, force)      │
│  - JSON Evidence Record emitter                             │
└──────────────────────────────┬──────────────────────────────┘
                               │ ADB Bridge
┌──────────────────────────────▼──────────────────────────────┐
│                 ANDROID PHYSICAL DEVICE                     │
│  In-App Controller: integration_test/                       │
│  physical_verification_controller_test.dart                 │
│  - Real plugin calls (Alarm.init, FLN, Repository)          │
│  - Option B: Plugin-Level Dedicated Test IDs (999901/999902)│
│  - Preflight Ownership & Collision Checks                   │
│  - Targeted surgical cancellation (NO blanket wipes)        │
│  - In-app evidence emitter [PHASE_2D_APP_EVIDENCE]          │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 Component 1: In-App Controller (`integration_test/`)
- Located in [`integration_test/physical_verification_controller_test.dart`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/integration_test/physical_verification_controller_test.dart).
- Runs directly on the device as an instrumented test.
- Zero production code contamination: zero debug UI, zero modifications to `lib/`.

### 3.2 Component 2: External Host-Side Device Observer (`scripts/device_observer.ps1`)
- Located in [`scripts/device_observer.ps1`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/scripts/device_observer.ps1).
- Runs as an independent process on the development workstation.
- **Survives Flutter process death:** Monitors device state via ADB even after the Flutter VM is terminated.
- **Empirically Verified Process Lifecycle Operations:**
  1. **Background:** `adb shell input keyevent KEYCODE_HOME`.
  2. **Process Death (Memory Reclaim Simulation):**
     - Direct `adb shell kill <pid>` fails on both devices (`Operation not permitted` because shell/2000 cannot signal app UID).
     - **Verified working command:** `run-as com.shadyatef.hafiz_alahd /system/bin/kill <pid>` (with fallback to `/system/bin/kill -s 9 <pid>`).
     - **Observer Verification Contract:**
       - Records PID before termination.
       - Executes command and captures exact exit code (`0`).
       - Proves PID disappearance via `pidof com.shadyatef.hafiz_alahd` (returns empty, exit code `1`).
       - Proves non-force-stop behavior by verifying that `dumpsys alarm | grep com.shadyatef.hafiz_alahd` **retains all active RTC_WAKEUP alarms**!
       - Writes evidence to `test_evidence/process_death_<device>_<timestamp>.json`.
  3. **Force Stop:** `adb shell am force-stop com.shadyatef.hafiz_alahd` (explicitly used to test Android's force-stop policy where AlarmManager clears alarms).

### 3.3 Component 3: Test Event Isolation Contract (Option B Adopted)
To address the temporal mismatch between calendar-derived IDs and short-horizon testing, **Option B (Plugin-Level Dedicated Test IDs)** is adopted:

1. **Dedicated Non-Calendar Test IDs:**
   - Test Alarm ID: `pluginTestAlarmId = 999901`
   - Test Notification ID: `pluginTestNotifId = 999902`
   - These are 6-digit IDs, clearly outside the production 8-digit calendar contract range (`YYMMDDPT`, e.g., `26110900`).
   - Explicit scope: Tests Level 1 physical delivery on Android OS. Does **NOT** test `CalendarAlarmIdContract` or weekly scheduler reconciliation. (The production scheduling path is tested independently in `scheduler_production_path_integration_test.dart`).
2. **Preflight Ownership & Collision Check:**
   - Before any scheduling, the harness queries `Alarm.getAlarms()` and `fln.pendingNotificationRequests()`.
   - If either test ID is already present, the harness **ABORTS immediately with a StateError**, rejecting execution to prevent unauthorized modification.
3. **Harness Ownership Tracking:**
   - Scheduled IDs are recorded in an active harness ownership set (`ownedAlarmIds`, `ownedNotifIds`).
4. **Targeted Surgical Cleanup Only:**
   - Cleanup routines only cancel IDs explicitly owned by the current scenario run.
   - Sibling and production prayer alarms are strictly preserved.
5. **Strict Prohibition of Blanket Cancellation:**
   - `cancelAllAlarms()` and `cancelAllNotifications()` are strictly forbidden in all harness code.

---

## 4. Native Evidence Boundaries & Classification

| Evidence Source | Verification Level | What It Proves | What It Does NOT Prove |
|---|---|---|---|
| **`Alarm.getAlarm(id)`** | L1: Plugin State | Alarm settings are stored in SQLite / plugin memory | Android OS will deliver or trigger the alarm |
| **`fln.pendingNotificationRequests()`** | L1: Plugin State | Notification is recorded in FLN's internal registry | Android AlarmManager scheduled the PendingIntent |
| **`Alarm.ringing` Stream** | L1: Dart VM State | Native service sent broadcast callback to active Dart VM | User saw screen, heard audio, or that delivery works when app is dead |
| **`dumpsys alarm`** | L2: OS AlarmManager | Android kernel queue registered the exact RTC trigger time (`RTC_WAKEUP`) with bound `PendingIntentRecord` | Audio won't be suppressed by audio focus, DND, or OEM power manager |
| **`dumpsys notification`** | L2: OS NotificationManager | Distinguishes 3 states:<br>1. **Active Posted:** Present in `Active Notifications`<br>2. **Delivered & Dismissed:** Recorded in history / logcat<br>3. **Never Delivered:** Completely absent from active & history | Audio/vibration played correctly.<br>*(Note: Absence from active list does NOT prove non-delivery if dismissed/cancelled).* |
| **Logcat (`AlarmReceiver`, `AlarmService`, `FLTNotification`)** | L2/L3: Native Transitions | Exact timestamp of broadcast receipt, foreground service start, audio playback start | Complete user experience without hardware speaker validation |
| **Workstation Audio Capture (Optional L3)** | L3: Physical Hardware | Audio was physically rendered by device speaker | N/A |

---

## 5. Plugin API Compatibility (`alarm 5.12.0`)

Verified against `pubspec.lock` (version `5.12.0`):

- **Initialization:** `await Alarm.init();` must precede all calls.
- **Stream Subscription:** `Alarm.ringing` returns `ValueStream<AlarmSet>`.
  - Type: Subscribes as `Alarm.ringing.listen((AlarmSet alarmSet) { ... });`.
  - Content: `alarmSet.alarms` provides `List<AlarmSettings>`.
- **Cancellation:** `await subscription.cancel();`.
- **Retrieval:** `await Alarm.getAlarm(id);` returns `AlarmSettings?`.
- **Cold Start Behavior:** When app process is killed, `AlarmService` runs natively in Android without Dart VM. When user opens app from notification, `Alarm.init()` restores in-memory state, and `Alarm.isRinging(id)` can query active ringing alarms.

---

## 6. Standardized Evidence Logger Schema

Every scenario writes a consolidated JSON evidence record:

```json
{
  "scenario_run_id": "2D.0_PILOT_ALARM_001",
  "scenario_id": "2D.0.Pilot.AlarmShortHorizon",
  "commit_hash": "9b016573cac649c421f6414eeba29e720e9d30ef",
  "app_version": "1.0.0+1",
  "device_id": "Xiaomi_25098RA98G",
  "device_build_fingerprint": "Redmi/kunzite_global/kunzite:16/BP2A.250605.031.A3/OS3.0.304.0.WPQMIXM:user/release-keys",
  "app_process_state": "foreground",
  "battery_optimization_state": "whitelisted",
  "standby_bucket": "5_EXEMPTED",
  "notification_permission_state": "granted",
  "full_screen_intent_permission_state": "allow",
  "test_id_strategy": "Option_B_Plugin_Level_Dedicated",
  "preflight_ownership_checked": true,
  "event_id": 999901,
  "event_type": "alarm",
  "schedule_requested_at_utc": "2026-11-09T09:40:00.000Z",
  "expected_delivery_at_utc": "2026-11-09T09:40:15.000Z",
  "actual_delivery_at_utc": "2026-11-09T09:40:15.240Z",
  "delivery_delta_ms": 240,
  "plugin_verification_status": "matching",
  "audio_asset": "assets/sounds/fajr_azan.mp3",
  "audio_started": true,
  "vibration_started": true,
  "evidence_source": "adb_observer_logcat_and_dumpsys",
  "evidence_confidence": "high",
  "observed_result": "Alarm triggered on time, audio started, dismissed cleanly",
  "failure_classification": "none"
}
```

---

## 7. Exit Criteria for Phase 2D.0

| # | Requirement | Status | Verification Evidence |
|---|---|---|---|
| 1 | **Git Baseline** | Verified | Commit `9b016573cac649c421f6414eeba29e720e9d30ef` |
| 2 | **Git Scope Hygiene** | Verified | Only `integration_test/`, `scripts/`, `docs/`, `test_evidence/` modified; `lib/` untouched |
| 3 | **Dual Device Hardware Profiles** | Verified | Xiaomi (`dfa9f629`, API 36) & Samsung (`192.168.1.186:45067`, API 31) JSON profiles preserved |
| 4 | **Decoupled Observer Architecture** | Verified | `scripts/device_observer.ps1` operational and verified on both devices |
| 5 | **Empirical Process Death Verification** | Verified | Executed on both devices with PID termination, exit code 0, and AlarmManager alarm persistence proven |
| 6 | **Plugin API Compatibility** | Verified | `alarm 5.12.0` `Alarm.ringing` (`ValueStream<AlarmSet>`) and FLN verified |
| 7 | **Option B Test ID Isolation & Preflight** | Verified | Dedicated IDs `999901`/`999902`, preflight check, zero collision, surgical cancel |
| 8 | **Native Evidence Boundaries** | Documented | Explicit differentiation between FLN/Alarm plugin state and Android OS native dumpsys |
| 9 | **Static Analysis** | Verified | `flutter analyze integration_test/` 0 issues found |
| 10 | **Production Isolation** | Verified | Zero changes to `lib/` or production Android code |
