# P4.1-C — Independent Prayer Alarms UI & User Controls
## Definitive Architecture, UI/UX, Domain Integration & Runtime Safety Plan (Revision 1.2)

**Feature Branch:** `feature/p4.1-independent-alarms-adhan`  
**Document Version:** 1.2.0  
**Status:** PLAN REVISION 1.2 — READY FOR STOP GATE C.0 ENGINEERING REVIEW  
**Implementation Authorization:** NOT AUTHORIZED  
**Commit / Merge / Release / Deploy:** NOT AUTHORIZED

---

## 1. Executive Product & Behavioral Contract

**Phase P4.1-C** establishes independent control over each of the five daily prayers (`Fajr`, `Dhuhr`, `Asr`, `Maghrib`, `Isha`) without relying on volume attenuation workarounds. The system implements **mode-level operational separation** rooted in our dual-device proven scheduling engine.

### 1.1 The Tri-State Prayer Alert Contract

Each prayer operates in one of three definitive, isolated modes governed by `PrayerAlarmType`:

| Mode | Full-Screen Alarm (`package:alarm`) | Adhan Audio Output | Notification Banner (`FLN`) | Native Engine & Channel |
|:---:|:---:|:---:|:---:|:---:|
| **`alarm`** | **Active (Full-screen Intent)** | **Active (Muezzin Audio, Vol 0.1..1.0)** | Auxiliary / None | `package:alarm` + Native `AlarmService` |
| **`notification`** | **Disabled (0 Service / 0 Intent)** | **Disabled (0 Adhan Audio)** | **Active (Standard Chime & Banner)** | `flutter_local_notifications` (`prayer_channel_v10_default`) |
| **`off`** | **Disabled** | **Disabled** | **Disabled** | None (Fully Decommissioned) |

### 1.2 Core Architectural Invariants
1. **Purity of Notification Mode:** When in `notification` mode, scheduling is dispatched exclusively through `flutter_local_notifications` (deterministic ID formula `typeOffset: 1`). It **never** invokes `package:alarm`, never starts Android `AlarmService`, never plays Adhan audio assets, and never mounts `AdhanScreen`.
2. **Notification Mode Acoustic Semantics:** `notification` mode posts to Android channel `prayer_channel_v10_default` with `importance: 5` (`IMPORTANCE_HIGH`), producing the system's default notification chime and heads-up banner according to the user's Android Notification settings. It does **not** play Adhan audio files. If the user or OS mutes this notification channel in Android Settings, the banner displays silently. The application does not falsely claim audible delivery if the OS channel is muted.
3. **Purity of Alarm Mode:** When in `alarm` mode, it schedules a full-screen intent alarm via `package:alarm` (deterministic ID formula `typeOffset: 0`) with configured muezzin audio, volume level, and vibration.
4. **Complete Per-Prayer Isolation:** Modifying any prayer alert mode, muezzin, volume, or vibration has zero side-effects on any other prayer.
5. **Subsystem Independence:** Prayer alerts are completely decoupled from Iqama reminders and Azkar notifications.

---

## 2. Complete Transition State Machine & Imminent Safety Architecture

### 2.1 The Transition Matrix
Every user-initiated transition across all three modes behaves deterministically across active ringing, future alarms, and future notifications:

| Transition | Active Ringing State | Future Scheduled Alarm | Future Scheduled FLN | Operational Finality |
|---|---|---|---|---|
| **`Alarm → Notification`** | **Stop immediately (`Alarm.stop`)** | Cancel via `cancelAlarmSafely` | Schedule via FLN | Complete when Alarm absent & FLN present |
| **`Alarm → Off`** | **Stop immediately (`Alarm.stop`)** | Cancel via `cancelAlarmSafely` | None (Decommission if any) | Complete when both absent |
| **`Notification → Alarm`** | N/A (No alarm ringing) | Schedule via `scheduleAdhanAlarm` | Cancel via `cancelNotificationSafely` | Complete when Alarm present & FLN absent |
| **`Notification → Off`** | N/A | None | Cancel via `cancelNotificationSafely` | Complete when FLN absent |
| **`Off → Alarm`** | N/A | Schedule via `scheduleAdhanAlarm` | None | Complete when Alarm present |
| **`Off → Notification`** | N/A | None | Schedule via FLN | Complete when FLN present |

---

### 2.2 Formal State Machine & Failure Handling

A prayer's configuration state is not considered operationally complete merely because `alarmType` was persisted. The lifecycle is modeled as an observable finite state machine:

```
                  ┌────────────────────────────────────────┐
                  │                 ALARM                  │
                  └───────────────────┬────────────────────┘
                                      │ User Taps Toggle
                                      ▼
                        ┌───────────────────────────┐
                        │    TRANSITION_PENDING     │
                        └─────────────┬─────────────┘
                                      │
              ┌───────────────────────┴───────────────────────┐
              ▼                                               ▼
    [Active Ringing?]                                 [Imminent Window?]
     ├── YES: await Alarm.stop(id)                     ├── YES: Defer Alarm Cancellation
     └── NO: Proceed to Reconciliation                 │        Suppress Opposing FLN Today
                                                       │        Persist Config for Tomorrow
                                                       └── NO:  Execute cancelAlarmSafely()
                                                                Schedule FLN Notification
                                                                      │
                                      ┌───────────────────────────────┴───────────────────────────────┐
                                      ▼                                                               ▼
                        ┌───────────────────────────┐                                   ┌───────────────────────────┐
                        │       NOTIFICATION        │                                   │     TRANSITION_FAILED     │
                        │   (Operationally Done)    │                                   │ (Rollback / Alert User)   │
                        └───────────────────────────┘                                   └───────────────────────────┘
```

#### Detailed Transition Steps:
1. **Persist Intent First:** Write the desired target mode to persistent storage (`SharedPreferences`).
2. **Active Ringing Resolution:**
   - Query `await Alarm.isRinging(activeAlarmId)`.
   - If `true`: immediately execute `await Alarm.stop(activeAlarmId)` to kill native `AlarmService` and silence audio track.
3. **Temporal Proximity & Imminent Guard Handling (Addressing Review B1 & B2):**
   - **Case A: Normal Window ($> 15$ seconds before scheduled epoch):**
     - Execute `cancelAlarmSafely()`.
     - Query registry: confirm `postCheck == null`.
     - Schedule opposing FLN Notification via `schedulePrayerNotification()`.
     - Mark state: `notification` (Operationally Complete). Dual delivery is mathematically impossible.
   - **Case B: Imminent Guard Window ($< 15$ seconds before scheduled epoch):**
     - **Truth in Advertising:** We do NOT claim the upcoming alarm in 5 seconds is cancelled, nor do we falsely claim Dart can intercept native `AlarmService` during process death.
     - `cancelAlarmSafely()` returns `deferredImminent` to prevent Android `AlarmManager` dispatch race conditions.
     - **Dual Delivery Prevention:** The opposing FLN Notification for *today's* imminent prayer is **STRICTLY SUPPRESSED** (not scheduled).
     - **Future Consistency:** The new mode (`notification`) is persisted. All future days of the week are scheduled as FLN Notifications.
     - **UI State:** The Home Card displays a truthful transitional state: `Icons.hourglass_top_rounded` with tooltip/badge: `"قيد الانتقال (سيبدأ بعد الصلاة الحالية)"`.
     - Once today's imminent epoch passes $+60$s, the transitional state automatically resolves to `notification`.
4. **Failure Recovery:**
   - If FLN scheduling fails or cancellation throws an unrecoverable exception:
     - The state transitions to `transitionFailed`.
     - Persistent storage rolls back to the previous stable mode.
     - The UI emits a SnackBar: `"تعذر تغيير وضع التنبيه، يرجى المحاولة مرة أخرى"`.
   - If process death occurs during transition:
     - On app relaunch, `PrayerAlarmSettingsCubit` reads persistent config and runs a reconciliation check to reconcile any orphaned or half-transitioned alarms.

---

## 3. Home Quick Toggle Contract (`Alarm ↔ Notification`)

The Quick Control on each Home Prayer Card provides an accessible 1-tap toggle between the two active notification tiers:

```
[ Alarm (Full Adhan) ]   ◄───( 1-Tap Home Card )───►   [ Notification (System Chime) ]
```

### 3.1 Visual & Accessibility Specification
- **Touch Target:** Minimum **`48 x 48 dp`** bounding box (`IconButton` with `constraints: BoxConstraints.tightFor(width: 48, height: 48)`).
- **Icon Placement:** `Positioned(top: 6, right: 8)` in RTL (opposite to the floating `NextPrayerTimer` at `top: 6, left: 8`).
- **States:**
  - **🔔 Alarm Active:** `Icons.notifications_active_rounded` (Gold accent). Semantic label: `"صلاة [اسم]: وضع الأذان الكامل مفعّل. اضغط للتحويل إلى إشعار بسيط"`.
  - **🔕 Notification Active:** `Icons.notifications_none_rounded` (Secondary text color). Semantic label: `"صلاة [اسم]: وضع الإشعار البسيط مفعّل. اضغط للتحويل إلى الأذان الكامل"`.
  - **⛔ Off Mode:** `Icons.notifications_off_outlined` (Muted/Grey). Semantic label: `"صلاة [اسم]: التنبيهات معطلة بالكامل. اضغط لفتح الإعدادات"`. Tap displays a SnackBar with an action button navigating directly to Settings.
  - **⏳ Transition Pending:** Micro `CircularProgressIndicator` (size 16, stroke width 2). Semantic label: `"جاري تحديث وضع التنبيه..."`.
  - **🌅 Sunrise Handling:** Sunrise (`الشروق`, `prayerId: null`) completely suppresses the icon widget.

---

## 4. Settings Hub Architecture

### 4.1 Navigation Entry
In `lib/features/settings/presentation/screens/settings_screen.dart`:
- Replace legacy global `_showAdhanStyleDialog` tile with navigation row:
  - Title: **«إعدادات تنبيهات الصلاة»** (Prayer Alarm Settings)
  - Subtitle: Dynamic summary of configured prayers (e.g., `الفجر: أذان • الظهر..العشاء: إشعار`)
  - Icon: `Icons.alarm_on_rounded` with trailing chevron.
  - Route: `PrayerAlarmSettingsScreen`.

### 4.2 Master Hub: `PrayerAlarmSettingsScreen`
Lists all 5 obligatory daily prayers with:
- Prayer Arabic Name & Islamic Icon.
- Current Alert Mode Badge (`منبه كامل` / `إشعار بسيط` / `معطل`).
- Muezzin & Volume summary (if Alarm).
- Vibration summary (`اهتزاز مفعّل` / `معطل`).
- Chevron navigating to `PrayerDetailSettingsScreen`.

### 4.3 Detail Screen: `PrayerDetailSettingsScreen`
- **Section A — Mode Selector:** Radio list tiles for `Alarm`, `Notification`, and `Off`.
- **Section B — Adhan Audio (Visible only when Mode == Alarm):**
  - Muezzin Selector tile (opens `AdhanCatalogScreen`).
  - Live Audio Preview (Play/Stop button with strict lifecycle teardown).
  - Volume Slider: clamped between `0.1` and `1.0` (10% to 100%) with live percentage display. Value `0.0` is disallowed in Alarm mode; silent alerts belong to `Notification` mode.
- **Section C — Vibration Configuration:**
  - Switch: `تخصيص الاهتزاز لهذه الصلاة`.
  - If enabled: Toggle for Vibration on/off (`true` or `false`).
  - If disabled: inherits global setting (`null`).
  - Live Vibration Preview button (`Vibrator.vibrate()`).
- **Section D — Reset to Defaults:**
  - `TextButton`: Resets target prayer to factory defaults (`Alarm` mode, default sound, global vibration) without affecting any other prayer.

---

## 5. Audio Catalog, Identity & Fallback Architecture

### 5.1 Strongly Typed Audio Source Contract
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

### 5.2 Built-in Catalog Registry
- `builtIn:default_fajr`: "أذان الفجر (الافتراضي)" -> `assets/sounds/fajr_azan.mp3`
- `builtIn:default_general`: "الأذان العام (الافتراضي)" -> `assets/sounds/adhan.mp3`

### 5.3 Custom Audio Storage & Scheduling Fallback Contract (Addressing Review B6)
1. **Private Ingestion:** Picked files (`.mp3`, `.m4a`, `.wav`, $\le 15$ MB) are copied into:
   `getApplicationDocumentsDirectory()/adhan_sounds/<uuid>.mp3`.
2. **Deletion Protection:** Custom audio files actively assigned to any prayer cannot be deleted from the catalog. The UI disables the delete button with an explanatory tooltip: `"هذا الصوت مستخدم حالياً في صلاة [اسم الصلاة]"`.
3. **Schedule-Time Fallback:**
   - When `ScheduleWeeklyPrayersUseCase` prepares an alarm:
   - It checks `File(absolutePath).existsSync()`.
   - If the file exists: schedules with `absolutePath`.
   - If missing/inaccessible:
     - Automatically falls back to the canonical built-in asset (`default_fajr` for Fajr, `default_general` for others).
     - Persists the fallback in config metadata.
     - Logs an observable diagnostic warning: `⚠️ [Scheduler] Custom audio missing for $prayerId, safely falling back to built-in asset.`
4. **Trigger-Time Protection:**
   - Because weekly reconciliation runs automatically every 24 hours, any missing file is healed and rescheduled with built-in asset long before the alarm triggers.
   - If an unexpected native read failure occurs at trigger time, native Android `MediaPlayer` catches the exception and logs an event without crashing the system service.

### 5.4 Audio Preview Lifecycle Service
- Dedicated `AudioPreviewService` wrapping an isolated `AudioPlayer`.
- **Teardown Rules:** Playback stops immediately on:
  - Screen disposal (`dispose()`).
  - App moving to background (`AppLifecycleState.paused`).
  - Audio focus loss (incoming call or external media playback).
  - Tapping stop or switching tracks.
  - Native alarm triggering.

---

## 6. Domain Model & Migration Matrix

### 6.1 Updated `PrayerAlarmConfig` Entity
```dart
@immutable
class PrayerAlarmConfig {
  final PrayerId prayerId;
  final PrayerAlarmType alarmType; // alarm, notification, off
  final AudioSourceConfig audioSource;
  final double volume; // clamped: 0.1 to 1.0 (default 1.0)
  final bool? isVibrationEnabled; // null = inherit global, true/false = per-prayer override

  const PrayerAlarmConfig({
    required this.prayerId,
    required this.alarmType,
    required this.audioSource,
    this.volume = 1.0,
    this.isVibrationEnabled,
  });

  /// Allows explicit clearing of nullable vibration override back to null (inherit global).
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
      volume: (volume ?? this.volume).clamp(0.1, 1.0),
      isVibrationEnabled: clearVibrationOverride
          ? null
          : (isVibrationEnabled ?? this.isVibrationEnabled),
    );
  }
}
```

### 6.2 Formal Migration Matrix (Addressing Review B5)

| Legacy Storage State | Migration v2 Action | Resolved State for All 5 Prayers |
|---|---|---|
| **Existing v1 Config** (`prayer_alarm_configs_json`) | Read & preserve existing `alarmType` per prayer. Seed `audioSource` with default built-ins, `volume` with existing `adhan_volume`, and `isVibrationEnabled: null`. | **PRESERVED EXACTLY** (Zero user setting loss). |
| **No v1 Config + `adhanStyle == 'alarm'`** | Set `alarmType: PrayerAlarmType.alarm` for all 5 prayers. | All 5 prayers set to `Alarm`. |
| **No v1 Config + `adhanStyle == 'notification'`** | Set `alarmType: PrayerAlarmType.notification` for all 5 prayers. | All 5 prayers set to `Notification`. |
| **No v1 Config + `adhanStyle == 'none'`** | Set `alarmType: PrayerAlarmType.off` for all 5 prayers. | All 5 prayers set to `Off`. |
| **No Config + Unrecognized / Null Style** | Fallback to safe default (`PrayerAlarmType.alarm`). | All 5 prayers set to `Alarm`. |
| **Existing `isAdhanVibrationEnabled`** | Kept intact in `SharedPreferences`. | Inherited by all prayers where `isVibrationEnabled == null`. |

#### Migration Safety Rules:
- **Idempotency:** Checks `version >= 2` and verifies all keys exist before executing. If already migrated, returns `false` without touching data.
- **Zero In-Flight Interference:** Migration does **NOT** cancel alarms or execute scheduling directly. It updates configuration models only. Scheduling reconciliation runs in its own scheduled lifecycle.
- **Atomic Persistence:** Writes individual keys, writes atomic JSON payload, performs read-back verification, and only writes `prayer_alarm_config_version = 2` upon complete success.

---

## 7. Implementation Phases & Stop Gates Matrix

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase P4.1-C.0: Baseline Architecture Inspection & Revision 1.2 │◄── [CURRENT STOP GATE]
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.1: Domain Models, AudioSource & Migration v2       │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.2: State Management (PrayerAlarmSettingsCubit)     │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.3: Home Prayer Cards Quick Toggle (48dp Target)    │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.4: Prayer Alarm Settings Master Hub Screen         │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.5: Prayer Detail & Audio Catalog Screens           │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.6: Custom Audio Ingestion Service & Fallback       │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.7: Scheduler Transition State Machine Wire-up      │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.8: Comprehensive Automated Testing Matrix          │
├─────────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.9: Dual-Device Physical Verification & Bundle     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 8. Comprehensive Automated Testing Matrix (Addressing Review Section 5)

| Test Identifier | Category | Scenario / Invariant | Expected Outcome |
|---|---|---|---|
| `TEST-C-01` | Domain | `AudioSourceConfig` serialization & deserialization | Full JSON round-trip for built-in and custom types |
| `TEST-C-02` | Domain | Unknown AudioSource discriminator | Fallback to `builtIn:default_general` without throw |
| `TEST-C-03` | Domain | `PrayerAlarmConfig.copyWith` with `clearVibrationOverride` | Correctly clears `isVibrationEnabled` back to `null` |
| `TEST-C-04` | Domain | Volume clamping | Clamps inputs `< 0.1` to `0.1` and `> 1.0` to `1.0` |
| `TEST-C-05` | Migration | Idempotent Migration v1 -> v2 | Preserves existing per-prayer selections, writes v2 marker |
| `TEST-C-06` | Migration | Migration from legacy `adhanStyle` (no v1 JSON) | Maps `alarm`, `notification`, `none` accurately across all 5 prayers |
| `TEST-C-07` | Cubit | Home Toggle `Alarm → Notification` (Normal) | Calls `cancelAlarmSafely`, schedules FLN, emits `notification` |
| `TEST-C-08` | Cubit | Home Toggle `Alarm → Notification` (Active Ringing) | Calls `Alarm.stop(id)` immediately, decommissions future alarms |
| `TEST-C-09` | Cubit | Home Toggle `Alarm → Notification` (Imminent Window) | Defers cancellation, suppresses today's FLN, emits `transitionPending` |
| `TEST-C-10` | Cubit | Settings Transition `Alarm → Off` (Active Ringing) | Calls `Alarm.stop(id)`, decommissions all future alerts |
| `TEST-C-11` | Cubit | Per-Prayer State Isolation | Toggling Asr emits state update strictly for Asr (Fajr..Isha untouched) |
| `TEST-C-12` | Cubit | Audio Preview Lifecycle | Disposing cubit or pausing player halts audio immediately |
| `TEST-C-13` | Widget | `PrayerCard` Touch Target & Accessibility | Bounding box is $\ge 48\times 48$ dp, Arabic semantic label present |
| `TEST-C-14` | Widget | `PrayerCard` Sunrise suppression | Sunrise card contains zero toggle widgets |
| `TEST-C-15` | Widget | `PrayerCard` Off Mode interaction | Tapping displays informational SnackBar without activating alarm |
| `TEST-C-16` | Scheduler | Purity of Notification Mode | `verifyAlarm()` decommissions alarm, zero `Alarm.set()` calls |
| `TEST-C-17` | Scheduler | Purity of Alarm Mode | `verifyNotification()` decommissions FLN, `Alarm.set()` called |
| `TEST-C-18` | Scheduler | Custom audio missing at schedule time | Falls back to built-in asset, logs warning, schedules successfully |
| `TEST-C-19` | Scheduler | Sibling non-interference | Modifying Fajr mode does not affect Dhuhr..Isha in AlarmManager |
| `TEST-C-20` | Scheduler | Existing 52 Scheduler Integration Tests | 100% green pass rate maintained |

---

## 9. Dual-Device Physical Verification Protocol

Dual-device physical testing on **Xiaomi Redmi Note 14 Pro+ 5G** (Android 16 HyperOS) and **Samsung Galaxy Tab A7 LTE** (Android 12 One UI 4.1) will strictly separate:
1. `dumpsys alarm` registration state.
2. `dumpsys notification` active `NotificationRecord`.
3. Actual notification shade visibility via UI Automator.
4. `AudioTrack` native playback request.
5. Verification of zero `package:alarm` interaction during `Notification` mode delivery.

---

## 10. Stop Gate C.0 Revision 1.2 Sign-Off Request

- [x] Runtime suppression blocker resolved (B1 & B2): Imminent guard respects native engine; dual delivery prevented by suppressing opposing FLN during imminent window; truthful transitional state.
- [x] Notification mode acoustic semantics formalized (B3): FLN channel chime/banner only; zero Adhan audio; zero `package:alarm`.
- [x] Complete transition matrix covering all mode pairs and active ringing (B4).
- [x] Formal migration matrix for legacy global modes (B5).
- [x] Audio source identity, deletion protection, and fallback contract finalized (B6 & C1).
- [x] Volume range (0.1..1.0) and nullable vibration clearing defined (C2 & C3).
- [x] 48dp touch target and complete automated test matrix documented.
- [ ] **Engineering Review & Formal Approval of Revision 1.2 (STOP GATE C.0)**.
- [ ] Production code diff remains strictly 0 lines.

