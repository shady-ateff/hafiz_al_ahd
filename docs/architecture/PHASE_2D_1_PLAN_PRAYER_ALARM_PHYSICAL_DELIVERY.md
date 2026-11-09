# Phase 2D.1 — Prayer Alarm Physical Delivery Plan
## Real-Device Delivery, Target Identity Persistence, Audio & Lifecycle Verification

- **Milestone:** P4.1-B.3 — Phase 2D.1
- **Branch:** `feature/p4.1-independent-alarms-adhan`
- **Previous Phase:** Phase 2D.0 — CLOSED & APPROVED
- **Status:** **PLAN — SUBMITTED FOR REVIEW & COMMENCEMENT**

---

## 1. Executive Summary & Objectives

Phase 2D.1 executes the physical delivery verification of **Prayer Alarms** (`package:alarm`) across both test devices:
- **Primary Device:** Xiaomi Redmi Note 14 Pro+ 5G (`dfa9f629`, Android 16 / API 36)
- **Secondary Device:** Samsung Galaxy Tab A7 LTE (`192.168.1.186:45067`, Android 12 / API 31)

### Core Verification Goals
1. **Target Alarm Identity Persistence (CRITICAL):**
   Conclusively prove that the specific test alarm (`pluginTestAlarmId = 999901`) with its exact scheduled timestamp (`origWhen` / `whenElapsed`) and bound `AlarmReceiver` PendingIntent:
   - Is registered in Android AlarmManager service scheduling state.
   - **Persists after app process termination (`SIGKILL_PROCESS_TERMINATION`)**.
   - Fired by Android OS at the scheduled time while the app process is dead.
2. **Real-Device Lifecycle Delivery:**
   - **Foreground:** App open on screen at trigger time.
   - **Background:** App backgrounded via `KEYCODE_HOME` at trigger time.
   - **Process Death:** App process killed via `SIGKILL` prior to trigger time; verified wake-up via native `AlarmReceiver`.
3. **Native Service, Audio & UI Execution:**
   - Prove native `AlarmService` starts as a foreground service.
   - Prove native audio player initializes and starts audio playback.
   - Prove full-screen intent or high-priority notification appears.
4. **Strict Isolation & Surgical Cleanup:**
   - Preflight ownership validation (abort on collision).
   - Only `pluginTestAlarmId = 999901` is scheduled and cancelled.
   - Zero blanket wipes (`cancelAllAlarms()` strictly prohibited).
   - Production code (`lib/`, `android/`) remains strictly untouched.

---

## 2. Strict Evidence Tier Separation

To avoid confounding plugin state with real OS delivery, evidence is strictly categorized into 4 tiers:

| Tier | Level | Concrete Evidence Source | What It Proves | What It Does NOT Prove |
|---|---|---|---|---|
| **Tier 1** | Plugin / Dart VM | `Alarm.ringing` stream callback | Dart VM received broadcast callback from native plugin | Audio is playing or screen is visible |
| **Tier 2** | Android OS Scheduling | `dumpsys alarm` (matching `origWhen` & `AlarmReceiver`) | Target alarm is scheduled in Android AlarmManager kernel queue | Audio won't be blocked by DND, audio focus, or vendor power manager |
| **Tier 3** | Native Android Execution | Logcat traces (`AlarmReceiver.onReceive`, `AlarmService.startForeground`, `MediaPlayer.start`) | Android woke up app, service started, audio playback requested | Hardware speaker physically emitted audible sound |
| **Tier 4** | Hardware Acoustic Output | Workstation microphone capture / manual hearing check | Sound was physically audible to human ear | N/A |

---

## 3. Test Scenarios Matrix

| Scenario ID | Scenario Name | Lifecycle State | Target Horizon | Key Verifications | Target Evidence Files |
|---|---|---|---|---|---|
| **2D.1.1** | Foreground Delivery | Foreground | `+15s` | `Alarm.ringing` callback, delivery delta $\le 1000$ms, surgical cleanup | `pilot_alarm_foreground_<dev>_<ts>.json` |
| **2D.1.2** | Background Delivery | Background (`KEYCODE_HOME`) | `+20s` | `AlarmReceiver` triggers in background, `AlarmService` foreground start, notification visible | `alarm_background_<dev>_<ts>.json` |
| **2D.1.3** | **Target Identity Persistence & Process-Death Delivery** *(Critical)* | Process Death (`SIGKILL`) | `+30s` | 1. Pre-kill `dumpsys alarm` target match<br>2. Post-kill `dumpsys alarm` target match<br>3. AlarmManager fires native `AlarmReceiver` to dead app<br>4. `AlarmService` spawns new process<br>5. Audio playback starts | `target_alarm_persistence_<dev>_<ts>.json`<br>`alarm_process_death_<dev>_<ts>.json` |
| **2D.1.4** | Dual Device Delta Comparison | All states | Multiple | Compare Xiaomi (Android 16) vs Samsung (Android 12) delivery latency and full-screen intent behavior | `dual_device_2d1_comparison.json` |

---

## 4. Scenario 2D.1.3 Detailed Step-by-Step Execution Protocol (The Critical Test)

This scenario answers the key reservation from Gate 2D.0: **proving that the specific target alarm persists and fires across process death.**

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. PREFLIGHT: Verify ID 999901 is absent from device                   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 2. SCHEDULE: Schedule Alarm ID 999901 for TargetTime (Now + 30s)       │
│    Record TargetEpochMs = TargetTime.millisecondsSinceEpoch            │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 3. TARGET IDENTITY PROOF (Pre-Kill):                                  │
│    dumpsys alarm | grep -Context "origWhen $TargetEpochMs"             │
│    Confirm: tag=*walarm*...AlarmReceiver, operation=PendingIntent      │
│    Status: TARGET_ALARM_REGISTERED                                     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 4. BACKGROUND & TERMINATE PROCESS:                                     │
│    adb shell input keyevent KEYCODE_HOME                               │
│    adb shell run-as com.shadyatef.hafiz_alahd /system/bin/kill <pid>   │
│    Confirm: pidof returns empty (Process Dead)                         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 5. TARGET IDENTITY PERSISTENCE PROOF (During Death):                  │
│    dumpsys alarm | grep -Context "origWhen $TargetEpochMs"             │
│    Confirm: Exact same AlarmRecord with TargetEpochMs is STILL PRESENT!│
│    Status: TARGET_ALARM_PERSISTENCE_PROVEN                             │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 6. NATIVE DELIVERY AT SCHEDULED TIME (Now + 30s):                      │
│    Observer monitors logcat:                                           │
│    - AlarmManager dispatches Intent to AlarmReceiver                   │
│    - AlarmReceiver starts AlarmService                                 │
│    - AlarmService starts foreground notification & audio playback     │
│    Status: OS_DELIVERY_SUCCESSFUL_FROM_PROCESS_DEATH                   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
┌───────────────────────────────────▼────────────────────────────────────┐
│ 7. SURGICAL CLEANUP & POST-VERIFICATION:                               │
│    Stop alarm via Alarm.stop(999901) or intent / notification action   │
│    Verify target alarm removed from dumpsys alarm                      │
│    Verify non-target alarms (sibling user prayers) strictly preserved  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Tooling & Observer Script Enhancements

To support Scenario 2D.1.3, [`scripts/device_observer.ps1`](file:///c:/Users/shady%20atef/Documents/projects/hafiz_al_ahd/scripts/device_observer.ps1) is extended with:

1. **`verify-target-alarm`:**
   - Parameters: `-DeviceId`, `-ScheduledEpochMs`.
   - Searches `dumpsys alarm` specifically for the alarm record containing `origWhen <ScheduledEpochMs>` and `AlarmReceiver`.
   - Emits structured JSON confirming target presence, `PendingIntent` hash, and `whenElapsed`.
2. **`monitor-alarm-lifecycle`:**
   - Streams logcat filtered for tags: `AlarmPlugin`, `AlarmService`, `AlarmReceiver`, `MediaPlayer`, `ActivityTaskManager`.
   - Captures native broadcast dispatch, foreground service startup, and audio playback events across process termination.

---

## 6. Exit Criteria for Phase 2D.1

| # | Criterion | Verification Target |
|---|---|---|
| 1 | **Target Identity Registration** | Target alarm `999901` identified in `dumpsys alarm` by its exact `origWhen` epoch timestamp on both devices. |
| 2 | **Target Identity Persistence** | Target alarm confirmed present in `dumpsys alarm` **after** `SIGKILL_PROCESS_TERMINATION` while app is dead. |
| 3 | **Foreground Delivery** | Alarm fires on time in foreground; delivery delta $\le 1000$ms on both devices. |
| 4 | **Background Delivery** | Alarm fires while app is in background; native `AlarmService` starts and posts notification. |
| 5 | **Process-Death Delivery** | Alarm fires while app is dead; Android AlarmManager wakes up process via `AlarmReceiver` and starts `AlarmService`. |
| 6 | **Audio Playback Verification** | Logcat confirms audio resource (`fajr_azan.mp3`) prepared and playback started natively. |
| 7 | **Surgical Cleanup** | Only ID `999901` is removed; all other device alarms remain completely intact. |
| 8 | **Zero Production Changes** | `lib/` and `android/` production source remain 100% untouched. |

---

**Next Action:** Proceed with implementation of the observer target identity verification actions and execute Scenario 2D.1.3 on the primary device.

