# P4.1-C — Independent Prayer Alarms UI & User Controls
## Definitive Architecture, UI/UX, Domain Integration & Runtime Safety Plan (Revision 1.3)

**Feature Branch:** `feature/p4.1-independent-alarms-adhan`  
**Document Version:** 1.3.0  
**Status:** PLAN REVISION 1.3 — READY FOR STOP GATE C.0 ENGINEERING REVIEW  
**Implementation Authorization:** NOT AUTHORIZED  
**Commit / Merge / Release / Deploy:** NOT AUTHORIZED

---

## 1. Executive Product & Behavioral Contract

**Phase P4.1-C** establishes independent control over each of the five daily prayers (`Fajr`, `Dhuhr`, `Asr`, `Maghrib`, `Isha`) through **mode-level operational separation** rather than volume attenuation workarounds.

### 1.1 The Tri-State Prayer Alert Contract

Each prayer operates in one of three definitive, isolated modes governed by `PrayerAlarmType`:

| Mode | Full-Screen Alarm (`package:alarm`) | Adhan Audio Output | Notification Banner (`FLN`) | Native Engine & Channel Profile |
|:---:|:---:|:---:|:---:|:---:|
| **`alarm`** | **Active (Full-screen Intent)** | **Active (Configured Muezzin, Vol 0.1..1.0)** | Auxiliary / None | `package:alarm` + Native `AlarmService` |
| **`notification`** | **Disabled (0 Service / 0 Intent)** | **Disabled (0 Adhan Audio)** | **Active (System Chime & Banner)** | `flutter_local_notifications` (`prayer_channel_v10_default`, `importance: 5`) |
| **`off`** | **Disabled** | **Disabled** | **Disabled** | None (Fully Decommissioned) |

### 1.2 Core Architectural Invariants
1. **Purity of Notification Mode:** When in `notification` mode, scheduling is dispatched exclusively through `flutter_local_notifications` (deterministic ID formula `typeOffset: 1`). It **never** invokes `package:alarm`, never starts Android `AlarmService`, never plays Adhan audio assets, and never mounts `AdhanScreen`.
2. **Notification Mode Acoustic Semantics:** `notification` mode posts to Android channel `prayer_channel_v10_default` with `importance: 5` (`IMPORTANCE_HIGH`), producing the system's default notification chime and heads-up banner according to the user's Android Notification settings. It does **not** play Adhan audio files. If the user or OS mutes this notification channel in Android Settings, the banner displays silently. The application does not falsely claim audible delivery if the OS channel is muted.
3. **Purity of Alarm Mode:** When in `alarm` mode, it schedules a full-screen intent alarm via `package:alarm` (deterministic ID formula `typeOffset: 0`) with configured muezzin audio, volume level, and vibration.
4. **Complete Per-Prayer Isolation:** Modifying any prayer alert mode, muezzin, volume, or vibration has zero side-effects on any other prayer.
5. **Subsystem Independence:** Prayer alerts are completely decoupled from Iqama reminders and Azkar notifications.

---

## 2. Transition Coordinator & Persistent Recovery Protocol (Addressing Review B1 & B3)

A fundamental finding of Engineering Review 1.2 is that `SharedPreferences` only stores **Desired Configuration**, which is insufficient to safely recover interrupted or deferred transitions across process death. Revision 1.3 introduces a dedicated, persistent **Transition Lifecycle Protocol**.

### 2.1 The Persistent Transition Record (`PrayerAlertTransitionRecord`)
Stored under key `prayer_alert_transition_${prayerId.key}` in `SharedPreferences`:

```dart
enum TransitionStatus {
  pending,
  waitingForImminentAlarm,
  reconciling,
  completed,
  failed,
}

class PrayerAlertTransitionRecord {
  final String operationId;           // Unique UUID tracking this transition
  final PrayerId prayerId;            // Target prayer
  final PrayerAlarmType sourceMode;   // Mode before transition
  final PrayerAlarmType targetMode;   // Desired mode
  final DateTime requestedAt;         // Timestamp of user action
  final DateTime? protectedAlarmEpoch;// Imminent alarm trigger epoch (if deferred)
  final TransitionStatus status;      // Current state of execution
  final String? failureReason;        // Diagnostic details if failed

  const PrayerAlertTransitionRecord({
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

### 2.2 Complete Transition Lifecycle State Machine

```
                   User Initiates Mode Transition
                                │
                                ▼
         ┌──────────────────────────────────────────────┐
         │ 1. Create Persistent Transition Record       │
         │    Status: PENDING                           │
         │    (Stored in SharedPreferences)             │
         └──────────────────────┬───────────────────────┘
                                │
               ┌────────────────┴────────────────┐
               ▼                                 ▼
      [Active Ringing?]                  [Imminent Window?]
       ├── YES: await Alarm.stop(id)      ├── YES: Status = WAITING_FOR_IMMINENT
       └── NO:  Proceed to Reconcile      │        Suppress today's opposing FLN
                                          │        Schedule FLN for Days 2..5
                                          │        (Await Epoch + 60s)
                                          │
                                          └── NO:  Status = RECONCILING
                                                   Reconcile 5-Day Horizon
                                                        │
                                ┌───────────────────────┴───────────────────────┐
                                ▼                                               ▼
                  ┌───────────────────────────┐                   ┌───────────────────────────┐
                  │ 2. RECONCILIATION SUCCESS │                   │ 3. RECONCILIATION FAILURE │
                  │    - Old Subsystem Clean  │                   │    - Record Status=FAILED │
                  │    - New Subsystem Set    │                   │    - No Blind Rollback    │
                  │    - Record Purged/Done   │                   │    - Keep Intent          │
                  │    - State: OPERATIONAL   │                   │    - Surface Retry UI     │
                  └───────────────────────────┘                   └───────────────────────────┘
```

#### Transition Execution Rules:
1. **Creation:** Before any destructive OS call, create `PrayerAlertTransitionRecord` with `status: pending`.
2. **Active Ringing Resolution:** If `Alarm.isRinging(activeAlarmId) == true`, call `await Alarm.stop(activeAlarmId)` immediately.
3. **Temporal Proximity Decision:**
   - **Case A — Normal Window ($> 15$s before scheduled epoch):**
     - Record status updated to `reconciling`.
     - Decommission opposing subsystem across the **active 5-day rolling horizon**.
     - Schedule new subsystem across the active 5-day rolling horizon.
     - On verification of all days: delete transition record; mark prayer as operationally completed.
   - **Case B — Imminent Guard Window ($< 15$s before scheduled epoch) (Addressing Review B1 & B2):**
     - `cancelAlarmSafely()` returns `deferredImminent`.
     - Record status updated to `waitingForImminentAlarm` with `protectedAlarmEpoch: alarmEpoch`.
     - **Dual Delivery Prevention:** Opposing FLN Notification for *today's* imminent prayer is **STRICTLY SUPPRESSED**.
     - Upcoming days (Days 2..5 in the rolling horizon) are scheduled immediately in the target mode.
     - **Transparent User Feedback (B2):**
       The UI displays an informative notice:
       `"تعذر إلغاء منبه الصلاة الحالية لقرب موعده (< 15 ثانية). سيعمل المنبه الحالي مرة أخيرة، ثم تتحول الصلاة إلى وضع الإشعار البسيط."`
     - **Resolution:** When `DateTime.now() > protectedAlarmEpoch + 60s`, the `TransitionCoordinator` triggers automated reconciliation, confirms the old alarm has fired and left the queue, and marks the record `completed`.
4. **Failure Handling (Addressing Review B3):**
   - **No Blind Config Rollback:** If an operation fails mid-flight (e.g. FLN scheduling fails after Alarm was cancelled), the system does **NOT** roll back `alarmType` in configuration, because claiming the alarm is active when it was cancelled is an untruthful state.
   - Instead, the transition record records `status: failed` with `failureReason`.
   - The UI displays `TransitionStatus.failed` with an explicit "إعادة المحاولة" (Retry) action button.
   - Retrying invokes the `TransitionCoordinator` idempotently to complete the remaining steps safely.

---

### 2.3 Process Death Recovery Protocol (`TransitionCoordinator`)
During app startup (in `service_locator` or `PrayerAlarmSettingsCubit` initialization):
1. `TransitionCoordinator.recoverIncompleteTransitions()` is executed.
2. Scans for existing `prayer_alert_transition_*` records:
   - **If `status == waitingForImminentAlarm`:**
     - If `DateTime.now() > protectedAlarmEpoch + 60s`: The imminent event has elapsed. Trigger reconciliation for the full 5-day horizon and delete the record.
     - If `DateTime.now() <= protectedAlarmEpoch + 60s`: The imminent event is still pending or executing. Leave record intact and schedule an in-memory timer for `(epoch + 60s) - now` to resolve it upon completion.
   - **If `status == pending` or `reconciling`:**
     - The process was killed mid-transition. Re-run reconciliation across the 5-day horizon for `targetMode` idempotently.
   - **If `status == failed`:**
     - Preserve record and surface retry option in UI.
   - **If `status == completed`:**
     - Delete stale record.

---

## 3. Complete Transition Matrix Across All Mode Pairs (Addressing Review B4)

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

## 4. Home Quick Toggle Contract (`Alarm ↔ Notification`)

The Quick Control on each Home Prayer Card provides an accessible 1-tap toggle between the two active notification tiers:

```
[ Alarm (Full Adhan) ]   ◄───( 1-Tap Home Card )───►   [ Notification (System Chime) ]
```

### 4.1 Visual & Accessibility Specification
- **Touch Target:** Minimum **`48 x 48 dp`** bounding box (`IconButton` with `constraints: BoxConstraints.tightFor(width: 48, height: 48)`).
- **Icon Placement:** `Positioned(top: 6, right: 8)` in RTL (opposite to the floating `NextPrayerTimer` at `top: 6, left: 8`).
- **States:**
  - **🔔 Alarm Active:** `Icons.notifications_active_rounded` (Gold accent). Semantic label: `"صلاة [اسم]: وضع الأذان الكامل مفعّل. اضغط للتحويل إلى إشعار بسيط"`.
  - **🔕 Notification Active:** `Icons.notifications_none_rounded` (Secondary text color). Semantic label: `"صلاة [اسم]: وضع الإشعار البسيط مفعّل. اضغط للتحويل إلى الأذان الكامل"`.
  - **⛔ Off Mode:** `Icons.notifications_off_outlined` (Muted/Grey). Semantic label: `"صلاة [اسم]: التنبيهات معطلة بالكامل. اضغط لفتح الإعدادات"`. Tap displays a SnackBar with an action button navigating directly to Settings.
  - **⏳ Transition Pending:** Micro `CircularProgressIndicator` (size 16, stroke width 2). Semantic label: `"جاري تحديث وضع التنبيه..."`.
  - **🌅 Sunrise Handling:** Sunrise (`الشروق`, `prayerId: null`) completely suppresses the icon widget.

---

## 5. Audio Architecture: Separation of Configured vs. Effective Scheduled Source (Addressing Review B5 & B6)

### 5.1 Non-Destructive Fallback Contract
Under no circumstances shall the scheduling engine overwrite or erase the user's saved audio preference when a file is temporarily missing. We explicitly separate:
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

If the file is later restored, the scheduler automatically returns to using the custom audio source upon next reconciliation.

---

### 5.2 Extension Preservation & File Ingestion (Addressing Review B5)
`CustomAudioStorageService` validates and preserves the original file extension:
- **Allowed Extensions:** `.mp3`, `.m4a`, `.wav`.
- **Target Storage Path:** `getApplicationDocumentsDirectory()/adhan_sounds/<uuid>.<original_ext>`.
- **Validation Pipeline:**
  1. Inspect file extension and MIME type.
  2. Verify file size $\le 15$ MB.
  3. Probe playable duration and audio readability via `audioplayers`.
  4. Perform atomic copy to app-private directory.
  5. Return `CustomAudioSource(id, displayName, localRelativePath, fileSizeBytes, durationMs)`.

---

### 5.3 Strongly Typed Audio Source Models & Validation (Addressing Review C1)
```dart
sealed class AudioSourceConfig {
  final String id;
  final String displayName;

  const AudioSourceConfig({required this.id, required this.displayName});

  Map<String, dynamic> toJson();

  static AudioSourceConfig fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'builtIn':
        return BuiltInAudioSource.fromJson(json);
      case 'custom':
        return CustomAudioSource.fromJson(json);
      default:
        // Safe fallback for corrupted or unknown discriminators
        return const BuiltInAudioSource(
          id: 'builtIn:default_general',
          displayName: 'الأذان العام (الافتراضي)',
          assetPath: 'assets/sounds/adhan.mp3',
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioSourceConfig && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class BuiltInAudioSource extends AudioSourceConfig {
  final String assetPath;

  const BuiltInAudioSource({
    required super.id,
    required super.displayName,
    required this.assetPath,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'builtIn',
        'id': id,
        'displayName': displayName,
        'assetPath': assetPath,
      };

  factory BuiltInAudioSource.fromJson(Map<String, dynamic> json) =>
      BuiltInAudioSource(
        id: json['id'] as String? ?? 'builtIn:default_general',
        displayName: json['displayName'] as String? ?? 'الأذان العام',
        assetPath: json['assetPath'] as String? ?? 'assets/sounds/adhan.mp3',
      );
}

class CustomAudioSource extends AudioSourceConfig {
  final String localRelativePath;
  final int fileSizeBytes;
  final int durationMs;

  const CustomAudioSource({
    required super.id,
    required super.displayName,
    required this.localRelativePath,
    required this.fileSizeBytes,
    required this.durationMs,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'custom',
        'id': id,
        'displayName': displayName,
        'localRelativePath': localRelativePath,
        'fileSizeBytes': fileSizeBytes,
        'durationMs': durationMs,
      };

  factory CustomAudioSource.fromJson(Map<String, dynamic> json) =>
      CustomAudioSource(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? 'ملف صوتي مخصص',
        localRelativePath: json['localRelativePath'] as String,
        fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
      );
}
```

---

## 6. Domain Model Corrections (Addressing Review B4 & C2 & C3)

### 6.1 Updated `PrayerAlarmConfig` Entity
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

  /// Code-level fix: num.clamp().toDouble() ensures valid double typing in Dart.
  /// clearVibrationOverride: true resets isVibrationEnabled back to null (inherit global).
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

`PrayerAlarmConfigLocalDataSourceImpl` handles migration v2 through strict, non-destructive recovery rules:

| Storage State | Concrete Condition | Recovery & Migration Behavior |
|---|---|---|
| **M1: Current Valid** | `version >= 2` & all 5 prayer keys valid in JSON | No-op. Return `false` immediately. User data preserved. |
| **M2: Incomplete v2** | `version == 2` & JSON missing 1 or more prayers | Repair without resetting. Preserve valid prayers; seed missing prayers with defaults. |
| **M3: Complete v1** | `version < 2` & valid v1 JSON exists | Migrate v1 to v2: preserve each prayer's `alarmType`; seed default audio sources, `volume`, and `vibration: null`. |
| **M4: Partial v1** | `version < 2` & partial v1 JSON exists | Preserve valid v1 entries; seed missing prayers from legacy global `adhanStyle`. |
| **M5: Legacy Global** | `version < 2` & no JSON & legacy `adhanStyle` exists | Convert legacy `alarm`, `notification`, `none` to all 5 prayers. |
| **M6: Corrupted / Null** | `version < 2` & no valid keys | Seed all 5 prayers with safe factory defaults (`PrayerAlarmType.alarm`). |
| **M7: Process Death** | Killed before `version = 2` written | On next run, re-executes idempotently. No duplicate keys created. |

---

## 8. Notification Channel Baseline & Operational Reality (Addressing Review B8)

From the C.0 baseline inspection of `lib/features/notifications/data/repos/notification_repository_impl.dart`:
- **Current Channel ID:** `'prayer_channel_v10_default'`
- **Channel Name:** `'إشعارات الصلاة'`
- **Importance:** `Importance.max` (`IMPORTANCE_HIGH` = 5)
- **Sound:** Default Android Notification Sound (chime)
- **Vibration:** Enabled
- **Operational Reality Contract:**
  1. Once Android creates this channel on the device (Android 8.0+), the user has sovereign authority in Android Settings to change sound, vibration, or mute the channel.
  2. The application will **NOT** change the channel ID to an artificial version (e.g. `v11`) merely to override the user's choice.
  3. Scheduling an FLN notification successfully confirms **OS Registration**. It does not guarantee audible playback if the user has muted the channel in Android Settings.

---

## 9. Re-Ordered Implementation Phases & Stop Gates (Addressing Review Section 8)

The implementation sequence is structured so that data models, persistent recovery, and transition coordination are completed and tested **before** UI widgets:

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase P4.1-C.0: Baseline Architecture Inspection & Revision 1.3 │◄── [CURRENT STOP GATE]
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.1: Domain Models, AudioSource & Migration v2       │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.2: Transition Coordinator & Persistent Recovery    │
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
│ Phase P4.1-C.8: Comprehensive Automated Testing Matrix (34 TCs) │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.9: Dual-Device Physical Verification & Bundle     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10. Comprehensive 34-Case Automated Testing Matrix (Addressing Review Section 7)

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

---

## 11. Dual-Device Physical Verification Protocol

Dual-device physical testing on **Xiaomi Redmi Note 14 Pro+ 5G** (Android 16 HyperOS) and **Samsung Galaxy Tab A7 LTE** (Android 12 One UI 4.1) will strictly separate:
1. `dumpsys alarm` registration state.
2. `dumpsys notification` active `NotificationRecord`.
3. Actual notification shade visibility via UI Automator.
4. `AudioTrack` native playback request.
5. Verification of zero `package:alarm` interaction during `Notification` mode delivery.

---

## 12. Stop Gate C.0 Revision 1.3 Sign-Off Request

- [x] Persistent Transition Record (`PrayerAlertTransitionRecord`) & recovery protocol defined (B1).
- [x] Truthful Imminent UX copy and reconciliation gate specified (B2).
- [x] Operational recovery established (no blind config rollbacks) (B3).
- [x] Code-level `copyWith` double casting & constructor validation fixed (B4).
- [x] Custom audio original extension preservation (`.mp3`, `.m4a`, `.wav`) implemented (B5).
- [x] User configured audio source preserved during effective fallback (B6).
- [x] 7-case Migration Recovery Matrix documented (B7).
- [x] Notification Channel baseline inspected and documented (B8).
- [x] 5-day rolling horizon semantics defined for all transitions (B9).
- [x] Implementation phases re-ordered to prioritize Transition Coordinator (Section 9).
- [x] Full 34-case automated testing matrix defined (Section 10).
- [ ] **Engineering Review & Formal Approval of Revision 1.3 (STOP GATE C.0)**.
- [ ] Production code diff remains strictly 0 lines.

