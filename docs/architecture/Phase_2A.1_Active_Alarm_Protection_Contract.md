# P4.1-B.3 Phase 2A.1 — Active Alarm Protection Contract
**Project:** Hafiz Al-Ahd (حافظ العهد)  
**Branch:** `feature/p4.1-independent-alarms-adhan`  
**Phase:** P4.1-B.3 — Phase 2A.1  
**Document ID:** Deliverable C (`Phase_2A.1_Active_Alarm_Protection_Contract.md`)  
**Status:** Frozen Contract — Architectural Specification  

---

## 1. Objective & Downgraded Classification (C1)

### Official Architectural Designation:
> **`Best-effort Active Alarm Protection — Not Atomic Guarantee`**

### Classification Clarifications:
- This mechanism provides robust, defense-in-depth protection across typical runtime conditions.
- It **does NOT** provide a hardware-level atomic guarantee across asynchronous IPC boundaries.
- Under strict architectural guidelines, this mechanism is **never** characterized as *guaranteed*, *atomic*, *race-free*, or *100% safe*.
- The boundary between Dart and Android Native `AlarmManager`/`MediaPlayer` relies on asynchronous platform channels. Therefore, true transactional two-phase commits across processes are impossible without custom native locking.

---

## 2. Mathematical Definition of the Temporal Guard Window (C2)

The Temporal Guard provides a proximity buffer to prevent cancellation races in the critical window surrounding alarm trigger time:

$$\text{TemporalGuardWindow}(T_{\text{scheduled}}) = [T_{\text{scheduled}} - 15\,\text{seconds}, \; T_{\text{scheduled}} + 15\,\text{seconds}]$$

### Implementation Formula:
```dart
bool isInTemporalGuard(DateTime scheduledTime, [DateTime? referenceTime]) {
  final now = referenceTime ?? DateTime.now();
  final difference = (now.difference(scheduledTime)).inSeconds.abs();
  return difference <= 15;
}
```

### Operational Rules for Temporal Guard:
1. **Target of Guard:** Applies exclusively to **destructive cancellation operations** (`Alarm.stop(id)`).
2. **Rescheduling Exemption:** In-place same-ID updates (`Alarm.set()`) do not call `stop()` and are permitted within the window because `Alarm.set()` on Android updates the `PendingIntent` without terminating an active foreground service audio player.
3. **Config Change to `off` Inside Window:** If the user toggles a prayer to `off` while it is within the $\pm 15$-second window, **cancellation is suppressed**. The alarm is permitted to fire rather than risking an IPC race condition that cuts audio mid-start.
4. **Time Already Passed ($T_{\text{scheduled}} < \text{now} - 15\text{s}$):**
   - If `!await Alarm.isRinging(id)`: The alarm has concluded and is considered an expired past event. Safe to clean up.
   - If `await Alarm.isRinging(id)`: The Adhan audio (duration ~2–3 minutes) is actively ringing. Cancellation is **strictly blocked** until playback finishes.

---

## 3. Analysis of Six Runtime Race Scenarios (C3)

### Scenario 1: Alarm is Already Ringing Before the Check
- **State:** User opens the app while the Adhan is playing. The scheduler executes.
- **Trigger:** Scheduler evaluates prayer with `alarmId`.
- **Expected Behavior:** Scheduler queries `await Alarm.isRinging(alarmId)`. Since it returns `true`, the scheduler skips any cancellation call.
- **Platform Limitation:** None; standard platform channel query succeeds.
- **Recovery Behavior:** Ringing audio continues uninterrupted. The scheduler reconciles next days.
- **Phase 2B Test:** `Test G.1: Active ringing Adhan is preserved during full weekly reschedule`.

### Scenario 2: Alarm Starts Ringing Between `isRinging()` and `stop()` (TOCTOU Race)
- **State:** The check `await Alarm.isRinging(id)` returns `false`. In the microseconds before `Alarm.stop(id)` executes, the OS triggers the alarm.
- **Expected Behavior:** Mitigation provided by the **Temporal Guard**. Because the alarm is within $\pm 15$ seconds of trigger time, the cancellation was already blocked prior to querying `isRinging()`.
- **Platform Limitation:** If time calculation drifts $>15$s, a microscopic window exists where `stop()` could cancel a nascent alarm.
- **Recovery Behavior:** Fallback is graceful; user sees notification on screen.
- **Phase 2B Test:** `Test G.2: Alarm within ±15s guard is never cancelled even if isRinging returns false`.

### Scenario 3: Alarm is Within the Temporal Guard Window
- **State:** The scheduled time is 04:30:00. Rescheduling triggers at 04:29:50 ($\Delta t = 10\text{s}$).
- **Expected Behavior:** Scheduler detects proximity $\le 15\text{s}$ and suppresses `Alarm.stop(id)`.
- **Platform Limitation:** Platform channel call is completely avoided.
- **Recovery Behavior:** Alarm fires as scheduled.
- **Phase 2B Test:** `Test G.3: Proximity check rejects cancellation at boundary T-14s and T+14s`.

### Scenario 4: Alarm Stops Ringing During Reconciliation Loop
- **State:** Alarm was ringing during Day 0 evaluation. By the time the loop reaches cleanup, playback completes naturally.
- **Expected Behavior:** Once `isRinging(id)` turns `false` and time is $>15$s past trigger, obsolete alarms are eligible for cleanup.
- **Platform Limitation:** Dependent on Android MediaPlayer callback delivery to Dart.
- **Recovery Behavior:** Natural progression; no orphaned state.
- **Phase 2B Test:** `Test G.4: Completed playback transitions safely to eligible cleanup state`.

### Scenario 5: Unrelated Alarm is Ringing (e.g. Test Alarm #888)
- **State:** Test alarm `#888` is sounding when prayer scheduler triggers.
- **Expected Behavior:** Because scheduler strictly uses **Targeted Cancellation** on deterministic IDs (`26,000,000+`), it never references ID `888`.
- **Platform Limitation:** None. Complete ID isolation.
- **Recovery Behavior:** Test alarm #888 continues unaffected.
- **Phase 2B Test:** `Test G.5: Test alarm #888 and reserved IDs are never targeted or stopped`.

### Scenario 6: Same-ID Refresh Occurs While Previous Alarm is Ringing
- **State:** Dhuhr alarm is ringing today. Scheduler runs and schedules Dhuhr for upcoming days with distinct deterministic calendar IDs.
- **Expected Behavior:** Upcoming Dhuhr has ID `(Tomorrow)`, not today's ID. If today's Dhuhr is refreshed with identical ID, `Alarm.set()` updates the pending intent without killing the active MediaPlayer foreground service.
- **Platform Limitation:** Android OS behavior with `FLAG_UPDATE_CURRENT`.
- **Recovery Behavior:** Audio continues smoothly.
- **Phase 2B Test:** `Test G.6: Same-ID Alarm.set during active playback does not interrupt MediaPlayer`.

