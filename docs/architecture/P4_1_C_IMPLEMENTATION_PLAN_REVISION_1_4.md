# P4.1-C — Independent Prayer Alarms UI & User Controls
## Definitive Architecture, UI/UX, Domain Integration & Runtime Safety Plan (Revision 1.4)

**Feature Branch:** `feature/p4.1-independent-alarms-adhan`  
**Document Version:** 1.4.0  
**Status:** PLAN REVISION 1.4 — READY FOR STOP GATE C.0 ENGINEERING REVIEW  
**Implementation Authorization:** NOT AUTHORIZED  
**Commit / Merge / Release / Deploy:** NOT AUTHORIZED

---

## 1. Executive Product & Behavioral Contract

**Phase P4.1-C** establishes independent control over each of the five daily prayers (`Fajr`, `Dhuhr`, `Asr`, `Maghrib`, `Isha`) through **mode-level operational separation** rooted in our dual-device proven scheduling engine.

### 1.1 The Tri-State Prayer Alert Contract

Each prayer operates in one of three definitive, isolated modes governed by `PrayerAlarmType`:

| Mode | Full-Screen Alarm (`package:alarm`) | Adhan Audio Output | Notification Banner (`FLN`) | Native Engine & Channel Profile |
|:---:|:---:|:---:|:---:|:---:|
| **`alarm`** | **Active (Full-screen Intent)** | **Active (Configured Muezzin, Vol 0.1..1.0)** | Auxiliary / None | `package:alarm` + Native `AlarmService` |
| **`notification`** | **Disabled for this prayer** | **Disabled (0 Adhan Audio)** | **Active (System Chime & Banner)** | `flutter_local_notifications` (`prayer_channel_v10_default`, `importance: 5`) |
| **`off`** | **Disabled for this prayer** | **Disabled** | **Disabled** | None (Fully Decommissioned) |

### 1.2 Core Architectural Invariants
1. **Purity of Notification Mode:** No Prayer Alarm instance is scheduled or delivered for this prayer while in `notification` mode. Scheduling is dispatched exclusively through `flutter_local_notifications` (deterministic ID formula `typeOffset: 1`). It **never** invokes `package:alarm` for this prayer, never starts Android `AlarmService` for this prayer, never plays Adhan audio assets, and never mounts `AdhanScreen`.
2. **Notification Mode Acoustic Semantics:** `notification` mode posts to Android channel `prayer_channel_v10_default` with `importance: 5` (`IMPORTANCE_HIGH`), producing the system's default notification chime and heads-up banner according to the user's Android Notification settings. It does **not** play Adhan audio files. If the user or OS mutes this notification channel in Android Settings, the banner displays silently. The application does not falsely claim audible delivery if the OS channel is muted.
3. **Purity of Alarm Mode:** When in `alarm` mode, it schedules a full-screen intent alarm via `package:alarm` (deterministic ID formula `typeOffset: 0`) with configured muezzin audio, volume level, and vibration.
4. **Complete Per-Prayer Isolation:** Modifying any prayer alert mode, muezzin, volume, or vibration has zero side-effects on any other prayer.
5. **Subsystem Independence:** Prayer alerts are completely decoupled from Iqama reminders and Azkar notifications.

---

## 2. Transition Coordinator & Persistent Recovery Protocol (Addressing Review B1, B2, B3 & B4)

### 2.1 Canonical Temporal Guard Alignment: `[-15s, +60s]` (Addressing Review B1)
In strict alignment with the P4.1-B.3 safety contract:
1. **Protected Temporal Interval:**
   $$\text{Protected Window} = [\text{scheduledEpoch} - 15\,\text{seconds},\, \text{scheduledEpoch} + 60\,\text{seconds}]$$
2. **Deterministic Trigger:** The `TransitionCoordinator` does **not** compute divergent timing logic. The definitive signal of whether an alarm is deferred is the actual cancellation result from the repository:
   $$\text{isDeferred} \iff \text{cancelAlarmSafely}() == \text{EventCancellationStatus.deferredImminent}$$
   Whether the transition is requested 10 seconds before the epoch or 20 seconds after the epoch within the protected window, `deferredImminent` routes the operation into the safe waiting state.

---

### 2.2 Desired State vs. Transition Record Source of Truth (Addressing Review B2)
To eliminate atomicity gaps between `PrayerAlarmConfig` and `PrayerAlertTransitionRecord`, the system establishes a strict **Source of Truth Hierarchy**:

| Condition | Source of Truth for Desired Mode | Operational UI State |
|---|---|---|
| **No Active Transition Record** | `PrayerAlarmConfig.alarmType` | `Operational` (Stable) |
| **Active Transition (`pending / reconciling / waitingForImminentAlarm`)** | `PrayerAlertTransitionRecord.targetMode` | `TransitionPending` |
| **Failed Transition (`failed`)** | `PrayerAlertTransitionRecord.targetMode` | `TransitionFailed` (Retryable) |
| **Transition Completed** | `PrayerAlarmConfig.alarmType` (Synced & record purged) | `Operational` (Stable) |

```dart
enum TransitionStatus {
  pending,
  waitingForImminentAlarm,
  reconciling,
  completed,
  failed,
}

class PrayerAlertTransitionRecord {
  final int schemaVersion;           // Current schema version (1)
  final int revision;                // Monotonically increasing per-prayer revision counter
  final String operationId;          // Unique UUID tracking this transition instance
  final PrayerId prayerId;           // Target prayer
  final PrayerAlarmType sourceMode;  // Mode before transition
  final PrayerAlarmType targetMode;  // Desired target mode
  final DateTime requestedAt;        // Timestamp of user action
  final DateTime? protectedAlarmEpoch;// Exact scheduled epoch of protected alarm (if deferred)
  final TransitionStatus status;     // Execution state
  final String? failureReason;       // Diagnostic error if failed

  const PrayerAlertTransitionRecord({
    this.schemaVersion = 1,
    required this.revision,
    required this.operationId,
    required this.prayerId,
    required this.sourceMode,
    required this.targetMode,
    required this.requestedAt,
    this.protectedAlarmEpoch,
    required this.status,
    this.failureReason,
  });

  Map<String, dynamic> toJson();
  static PrayerAlertTransitionRecord? fromJson(Map<String, dynamic>? json);
}
```

---

### 2.3 Per-Prayer Mutex, Serialization & Concurrency (Addressing Review B4)
To prevent race conditions from rapid user taps or conflicting asynchronous operations:
1. **Per-Prayer Async Lock:** All mutations for a given `PrayerId` are serialized through an in-memory mutex (`Map<PrayerId, Future<void>> _locks`). An operation for `fajr` cannot execute concurrently with another operation for `fajr`.
2. **Monotonic Revision & Stale Operation Rejection:**
   Every transition increments `revision`. Any callback or asynchronous continuation verifies `record.revision == currentRevision && record.operationId == currentOperationId`. If superseded, the stale execution terminates immediately without modifying storage.
3. **Rapid Tapping UI Policy:**
   When an operation is in progress, the Home Card button displays the micro `CircularProgressIndicator` and ignores taps for 1.5 seconds. If the user changes their mind after completion, a new serialized transition begins with an incremented revision.

---

### 2.4 Post-Protected Interval Verification (Addressing Review B3)
The system does **not** assume an alarm fired simply because time elapsed. After the protected interval (`now > protectedAlarmEpoch + 60s`):
```text
Step 1: Execute cancelAlarmSafely() to verify and clean lingering state.
Step 2: Confirm plugin registry absence (postCheck == null).
Step 3: Reconcile target subsystem across active horizon.
Step 4: Mark transition completed ONLY after postconditions pass.
(The engine NEVER claims or records that the alarm 'fired' without independent evidence.)
```

---

### 2.5 Process Death Recovery Protocol
During app startup (`TransitionCoordinator.recoverIncompleteTransitions()`):
1. Scans `prayer_alert_transition_*` records:
   - **`waitingForImminentAlarm`:**
     - If `now > protectedAlarmEpoch + 60s`: Runs post-protected cleanup, schedules target mode, purges record.
     - If `now <= protectedAlarmEpoch + 60s`: Leaves record intact, arms a recovery timer.
   - **`pending` or `reconciling`:**
     - Re-executes reconciliation for `targetMode` idempotently across the active 5-day horizon.
   - **`failed`:**
     - Preserves record and surfaces retry button in UI.
   - **`completed`:**
     - Purges stale record.

---

## 3. Complete Transition Matrix Across All Mode Pairs

Every user-initiated transition across all three modes behaves deterministically across active ringing, future alarms, and future notifications across the 5-day rolling horizon:

| Transition | Active Ringing State | 5-Day Horizon Scheduled Alarm | 5-Day Horizon Scheduled FLN | Operational Finality Verification |
|---|---|---|---|---|
| **`Alarm → Notification`** | **Stop immediately (`Alarm.stop`)** | Cancel via `cancelAlarmSafely` | Schedule via FLN | Verified Alarm absent & FLN present on all 5 days |
| **`Alarm → Off`** | **Stop immediately (`Alarm.stop`)** | Cancel via `cancelAlarmSafely` | None (Decommission if any) | Verified both absent on all 5 days |
| **`Notification → Alarm`** | N/A (No alarm ringing) | Schedule via `scheduleAdhanAlarm` | Cancel via `cancelNotificationSafely` | Verified Alarm present & FLN absent on all 5 days |
| **`Notification → Off`** | N/A | None | Cancel via `cancelNotificationSafely` | Verified FLN absent on all 5 days |
| **`Off → Alarm`** | N/A | Schedule via `scheduleAdhanAlarm` | None | Verified Alarm present on all 5 days |
| **`Off → Notification`** | N/A | None | Schedule via FLN | Verified FLN present on all 5 days |

---

## 4. Home Quick Toggle UX & Imminent Messaging (Addressing Review B2)

The Quick Control on each Home Prayer Card provides an accessible 1-tap toggle between `Alarm ↔ Notification`:

### 4.1 Visual & Accessibility Specification
- **Touch Target:** Minimum **`48 x 48 dp`** bounding box (`IconButton` with `constraints: BoxConstraints.tightFor(width: 48, height: 48)`).
- **Icon Placement:** `Positioned(top: 6, right: 8)` in RTL (opposite to the floating `NextPrayerTimer` at `top: 6, left: 8`).
- **States:**
  - **🔔 Alarm Active:** `Icons.notifications_active_rounded` (Gold accent). Semantic label: `"صلاة [اسم]: وضع الأذان الكامل مفعّل. اضغط للتحويل إلى إشعار بسيط"`.
  - **🔕 Notification Active:** `Icons.notifications_none_rounded` (Secondary text color). Semantic label: `"صلاة [اسم]: وضع الإشعار البسيط مفعّل. اضغط للتحويل إلى الأذان الكامل"`.
  - **⛔ Off Mode:** `Icons.notifications_off_outlined` (Muted/Grey). Semantic label: `"صلاة [اسم]: التنبيهات معطلة بالكامل. اضغط لفتح الإعدادات"`. Tap displays a SnackBar with an action button navigating directly to Settings.
  - **⏳ Transition Pending (Normal):** Micro `CircularProgressIndicator` (size 16, stroke width 2). Semantic label: `"جاري تحديث وضع التنبيه..."`.
  - **⚠️ Transition Pending (Imminent Window):** `Icons.hourglass_top_rounded` with Banner / SnackBar copy:
    > **«تعذر إلغاء منبه الصلاة الحالية لقرب موعده (< 15 ثانية). سيعمل المنبه الحالي مرة أخيرة، ثم تتحول الصلاة إلى وضع الإشعار البسيط.»**
  - **🌅 Sunrise Handling:** Sunrise (`الشروق`, `prayerId: null`) completely suppresses the icon widget.

---

## 5. Audio Architecture: Fallback, Validation & Native Compatibility (Addressing Review B5 & B6)

### 5.1 Non-Destructive Fallback Contract
The system strictly separates configured preference from effective scheduling:
1. **`configuredAudioSource`:** The user's persisted preference stored in `PrayerAlarmConfig`.
2. **`effectiveScheduledAudioSource`:** The resolved audio source passed to `scheduleAdhanAlarm()`.

```
[ User Configured Audio Source ] (e.g. custom:uuid-123)
                 │
                 ▼
       [ File exists on disk? ]
         ├── YES ──► Effective Source = custom:uuid-123
         └── NO  ──► Effective Source = builtIn:default_general
                     Reason = AudioFallbackReason.fileMissing
                     (Persisted Config remains custom:uuid-123!)
                     (UI displays informative warning badge)
```

### 5.2 Extension Preservation & Path Traversal Guard (Addressing Review B5 & B6)
`CustomAudioStorageService` validates extensions and guards against directory traversal:
- **Allowed Extensions:** `.mp3`, `.m4a`, `.wav`.
- **Target Storage Path:** `getApplicationDocumentsDirectory()/adhan_sounds/<uuid>.<original_ext>`.
- **Path Traversal Guard:**
  ```dart
  final storageDir = Directory('${appDocDir.path}/adhan_sounds');
  final resolvedPath = path.normalize(path.join(storageDir.path, localRelativePath));
  if (!resolvedPath.startsWith(storageDir.path)) {
    throw SecurityException('Invalid path: Directory traversal attempt detected.');
  }
  ```
- **Native Alarm Compatibility:** Format support (`.mp3`, `.m4a`, `.wav`) must be verified through the actual native `AlarmService` playback path on both devices during Phase C.9. Any format failing native verification is removed from the production allowed list.

### 5.3 AudioSource Deserialization Robustness (Addressing Review B6)
```dart
sealed class AudioSourceConfig {
  final String id;
  final String displayName;

  const AudioSourceConfig({required this.id, required this.displayName});

  Map<String, dynamic> toJson();

  static AudioSourceConfig fromJson(Map<String, dynamic> json) {
    try {
      final type = json['type'] as String?;
      switch (type) {
        case 'builtIn':
          return BuiltInAudioSource.fromJson(json);
        case 'custom':
          return CustomAudioSource.fromJson(json);
        default:
          return _defaultBuiltInFallback();
      }
    } catch (e) {
      // Handles known discriminators with malformed fields without throwing
      return _defaultBuiltInFallback();
    }
  }

  static BuiltInAudioSource _defaultBuiltInFallback() => const BuiltInAudioSource(
        id: 'builtIn:default_general',
        displayName: 'الأذان العام (الافتراضي)',
        assetPath: 'assets/sounds/adhan.mp3',
      );
}
```

---

## 6. Domain Model Corrections (Addressing Review B4 & C2 & C3)

```dart
@immutable
class PrayerAlarmConfig {
  final PrayerId prayerId;
  final PrayerAlarmType alarmType; // alarm, notification, off
  final AudioSourceConfig audioSource;
  final double volume; // 0.1 to 1.0 (clamped, default 1.0)
  final bool? isVibrationEnabled; // null = inherit global, true/false = per-prayer override

  PrayerAlarmConfig({
    required this.prayerId,
    required this.alarmType,
    required this.audioSource,
    double volume = 1.0,
    this.isVibrationEnabled,
  }) : volume = volume.clamp(0.1, 1.0).toDouble();

  PrayerAlarmConfig copyWith({
    PrayerId? prayerId,
    PrayerAlarmType? alarmType,
    AudioSourceConfig? audioSource,
    double? volume,
    bool? isVibrationEnabled,
    bool clearVibrationOverride = false,
  }) {
    return PrayerAlarmConfig(
      prayerId: prayerId ?? this.prayerId,
      alarmType: alarmType ?? this.alarmType,
      audioSource: audioSource ?? this.audioSource,
      volume: (volume ?? this.volume).clamp(0.1, 1.0).toDouble(),
      isVibrationEnabled: clearVibrationOverride
          ? null
          : (isVibrationEnabled ?? this.isVibrationEnabled),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrayerAlarmConfig &&
          prayerId == other.prayerId &&
          alarmType == other.alarmType &&
          audioSource == other.audioSource &&
          volume == other.volume &&
          isVibrationEnabled == other.isVibrationEnabled;

  @override
  int get hashCode => Object.hash(
        prayerId,
        alarmType,
        audioSource,
        volume,
        isVibrationEnabled,
      );
}
```

---

## 7. Migration Recovery Matrix (Addressing Review B7)

`PrayerAlarmConfigLocalDataSourceImpl` handles migration v2 through comprehensive recovery rules:

| Storage State | Concrete Condition | Recovery & Migration Behavior |
|---|---|---|
| **M1: Current Valid** | `version == 2` & all 5 prayer keys valid in JSON | No-op. Return `false`. User data preserved. |
| **M2: Future Schema** | `version > 2` | **Preserve data. Do NOT downgrade or overwrite. Report unsupported future schema.** |
| **M3: Incomplete v2** | `version == 2` & JSON missing $\ge 1$ prayers | Validate and repair without resetting. Preserve valid prayers; seed missing prayers with defaults. |
| **M4: Complete v1** | `version < 2` & valid v1 JSON exists | Migrate v1 to v2: preserve each prayer's `alarmType`; seed default audio sources, `volume`, and `vibration: null`. |
| **M5: Partial v1** | `version < 2` & partial v1 JSON exists | Preserve valid v1 entries; seed missing prayers from legacy global `adhanStyle`. |
| **M6: Legacy Global** | `version < 2` & no JSON & legacy `adhanStyle` exists | Convert legacy `alarm`, `notification`, `none` across all 5 prayers. |
| **M7: Corrupted / Invalid JSON** | `version < 2` & unparseable JSON | Log diagnostic; read fallback individual keys `prayer_alarm_type_*`. If absent, seed factory defaults. |
| **M8: Crash Recovery** | Killed before `version = 2` written | Idempotently retry migration on next run without duplicating keys. |

---

## 8. Five-Day Rolling Horizon Extension (Addressing Review B8)

1. **Horizon Scope:** All mode transitions re-schedule target prayer instances across the full active **5-day rolling horizon**.
2. **Post-Imminent Extension:** When today's imminent event elapses, the automated daily reconciliation cycle (or startup recovery) extends the schedule to cover the full 5 future days from `now`, guaranteeing unbroken rolling coverage.

---

## 9. Re-Ordered Implementation Phases & Testing Protocol (Addressing Review Section 8)

Phase C.2 implements the `TransitionCoordinator` using **testable scheduling adapters** to verify all lifecycle, recovery, concurrency, and serialization invariants *before* UI integration:

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase P4.1-C.0: Baseline Architecture Inspection & Revision 1.4 │◄── [CURRENT STOP GATE]
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.1: Domain Models, AudioSource & Migration v2       │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.2: Transition Coordinator (Adapter-Tested)         │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.3: State Management (PrayerAlarmSettingsCubit)     │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.4: Home Prayer Cards Quick Toggle (48dp Target)    │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.5: Settings Master & Detail Screens                │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.6: Audio Catalog, Import & Fallback Service        │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.7: Scheduler Integration & Horizon Reconciliation  │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.8: Comprehensive Automated Testing Matrix (46 TCs) │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.9: Dual-Device Physical Verification & Bundle     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10. Comprehensive 46-Case Automated Testing Matrix (Addressing Review Section 7)

| Test Identifier | Category | Scenario / Invariant | Expected Outcome |
|---|---|---|---|
| `TEST-C-01` | Domain | `AudioSourceConfig` serialization & deserialization | Full JSON round-trip for built-in and custom types |
| `TEST-C-02` | Domain | Unknown AudioSource discriminator | Fallback to `builtIn:default_general` without throw |
| `TEST-C-03` | Domain | `PrayerAlarmConfig.copyWith` with `clearVibrationOverride` | Correctly clears `isVibrationEnabled` back to `null` |
| `TEST-C-04` | Domain | Volume clamping and `double` typing | Clamps inputs `< 0.1` to `0.1` and `> 1.0` to `1.0`, returns `double` |
| `TEST-C-05` | Migration | Idempotent Migration v1 -> v2 | Preserves existing per-prayer selections, writes v2 marker |
| `TEST-C-06` | Migration | Migration from legacy `adhanStyle` (no v1 JSON) | Maps `alarm`, `notification`, `none` accurately across all 5 prayers |
| `TEST-C-07` | Transition | Home Toggle `Alarm → Notification` (Normal) | Calls `cancelAlarmSafely`, schedules FLN, deletes transition record |
| `TEST-C-08` | Transition | Home Toggle `Alarm → Notification` (Active Ringing) | Calls `Alarm.stop(id)` immediately, decommissions future alarms |
| `TEST-C-09` | Transition | Home Toggle `Alarm → Notification` (Imminent Window) | Defers cancellation, suppresses today's FLN, schedules Days 2..5 |
| `TEST-C-10` | Transition | Settings Transition `Alarm → Off` (Active Ringing) | Calls `Alarm.stop(id)`, decommissions all future alerts |
| `TEST-C-11` | Transition | Notification → Off | Target FLN removed only, no alarm scheduled |
| `TEST-C-12` | Transition | Notification → Alarm | FLN removed and Alarm scheduled across 5-day horizon |
| `TEST-C-13` | Transition | Off → Notification | FLN scheduled across 5-day horizon |
| `TEST-C-14` | Transition | Off → Alarm | Alarm scheduled across 5-day horizon |
| `TEST-C-15` | Transition | Alarm cancellation failure | Transition record status marked `failed`, no false complete state |
| `TEST-C-16` | Transition | FLN scheduling failure | Transition record status marked `failed`, no false complete state |
| `TEST-C-17` | Transition | Process death during transition | `recoverIncompleteTransitions()` resumes and completes safely |
| `TEST-C-18` | Transition | Repeated reconciliation | Idempotent; zero duplicate alarms or notifications |
| `TEST-C-19` | Transition | Imminent transition after process death | Target prayer handled according to recorded transition |
| `TEST-C-20` | Cubit | Per-Prayer State Isolation | Toggling Asr emits state update strictly for Asr (Fajr..Isha untouched) |
| `TEST-C-21` | Cubit | Audio Preview Lifecycle | Disposing cubit or pausing player halts audio immediately |
| `TEST-C-22` | Cubit | Audio Preview Non-Interference | Audio preview does not interfere with AlarmService playback |
| `TEST-C-23` | Widget | `PrayerCard` Touch Target & Accessibility | Bounding box is $\ge 48\times 48$ dp, Arabic semantic label present |
| `TEST-C-24` | Widget | `PrayerCard` Sunrise suppression | Sunrise card contains zero toggle widgets |
| `TEST-C-25` | Widget | `PrayerCard` Off Mode interaction | Tapping displays informational SnackBar without activating alarm |
| `TEST-C-26` | Scheduler | Purity of Notification Mode | `verifyAlarm()` decommissions alarm, zero `Alarm.set()` calls |
| `TEST-C-27` | Scheduler | Purity of Alarm Mode | `verifyNotification()` decommissions FLN, `Alarm.set()` called |
| `TEST-C-28` | Scheduler | Custom audio with `.m4a` and `.wav` | Preserves extension, valid local path generated |
| `TEST-C-29` | Scheduler | Custom audio missing at schedule time | Effective fallback to built-in asset, configured source preserved |
| `TEST-C-30` | Scheduler | Sibling non-interference | Modifying Fajr mode does not affect Dhuhr..Isha in AlarmManager |
| `TEST-C-31` | Scheduler | Iqama/Azkar coexistence | Modifying prayer mode does not affect Iqama or Azkar alarms |
| `TEST-C-32` | Scheduler | Migration partial payload recovery | Preserves valid entries, repairs missing without resetting |
| `TEST-C-33` | Channel | Channel muted in Android Settings | Registration succeeds, no false audible claim emitted |
| `TEST-C-34` | Scheduler | Existing 52 Scheduler Integration Tests | 100% green pass rate maintained |
| `TEST-C-35` | Transition | Cancellation returns deferred inside `+20s` | Enters waiting state matching `[-15s, +60s]` contract |
| `TEST-C-36` | Transition | Process death before Config update | Recovers desired target from Transition Record |
| `TEST-C-37` | Transition | Process death after Config update | Idempotent recovery |
| `TEST-C-38` | Transition | Concurrent opposite transitions | Serialized via per-prayer mutex; no duplicate scheduling |
| `TEST-C-39` | Transition | Stale operation updates | Rejected by operation ID / revision validation |
| `TEST-C-40` | Transition | Protected epoch elapsed without confirmed delivery | Retries cleanup, verifies absence; does not claim fired |
| `TEST-C-41` | Transition | Device reboot during imminent transition | Startup recovery and horizon restoration |
| `TEST-C-42` | Audio | Malformed CustomAudioSource JSON | Recovers safely with default built-in asset |
| `TEST-C-43` | Audio | Custom audio path traversal attempt | Rejects path containing `..` or escaping directory |
| `TEST-C-44` | Audio | Native `.m4a` / `.wav` playback | Verified through actual AlarmService path on dual devices |
| `TEST-C-45` | Migration | Future schema version (`version > 2`) | Preserves data, no destructive downgrade |
| `TEST-C-46` | Scheduler | Imminent horizon extension | Restores full 5-day rolling horizon after protected day |

---

## 11. Dual-Device Physical Verification Protocol

Dual-device physical testing on **Xiaomi Redmi Note 14 Pro+ 5G** (Android 16 HyperOS) and **Samsung Galaxy Tab A7 LTE** (Android 12 One UI 4.1) will strictly separate:
1. `dumpsys alarm` registration state.
2. `dumpsys notification` active `NotificationRecord`.
3. Actual notification shade visibility via UI Automator.
4. `AudioTrack` native playback request.
5. Verification of zero `package:alarm` interaction during `Notification` mode delivery.

---

## 12. Stop Gate C.0 Revision 1.4 Sign-Off Request

- [x] Imminent guard aligned with canonical `[-15s, +60s]` contract (B1).
- [x] Desired mode vs. Transition Record source of truth hierarchy formalized (B2).
- [x] Truthful post-protected interval verification without assuming delivery (B3).
- [x] Per-prayer async mutex, operation ID, and revision validation specified (B4).
- [x] Native audio compatibility gating and path traversal protection enforced (B5 & B6).
- [x] Migration recovery matrix handles future versions (`version > 2`) without downgrade (B7).
- [x] 5-day rolling horizon extension and recovery documented (B8).
- [x] Phase C.2 prioritized with adapter-tested coordinator (Section 9).
- [x] 46-case automated testing matrix covering all concurrency, recovery, and safety cases (Section 10).
- [ ] **Engineering Review & Formal Approval of Revision 1.4 (STOP GATE C.0)**.
- [ ] Production code diff remains strictly 0 lines.

