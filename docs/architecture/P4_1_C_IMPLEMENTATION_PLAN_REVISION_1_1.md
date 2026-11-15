# P4.1-C — Independent Prayer Alarms UI & User Controls
## Definitive Architecture, UI/UX, Domain Integration & Verification Plan (Revision 1.1)

**Feature Branch:** `feature/p4.1-independent-alarms-adhan`  
**Document Version:** 1.1.0  
**Status:** PLAN REVISION 1.1 — READY FOR STOP GATE C.0 REVIEW  
**Implementation Authorization:** NOT AUTHORIZED  
**Commit / Merge / Release / Deploy:** NOT AUTHORIZED

---

## 1. Executive Product & Behavioral Contract

The goal of **Phase P4.1-C** is to empower users with full, independent control over each of the five daily prayers (`Fajr`, `Dhuhr`, `Asr`, `Maghrib`, `Isha`). Rather than treating notification/alarm muting as a volume attenuation hack, the system implements **mode-level operational separation** rooted in our dual-device proven scheduling engine.

### 1.1 The Tri-State Prayer Alert Contract

Each prayer operates in one of three definitive, isolated modes governed by `PrayerAlarmType`:

| Mode | Full-Screen Alarm (`package:alarm`) | Adhan Audio Output | Notification Banner (`FLN`) | Native Lifecycle Engine |
|:---:|:---:|:---:|:---:|:---:|
| **`alarm`** | **Active (Full-screen Intent)** | **Active (Configured Muezzin & Volume)** | Optional auxiliary | `package:alarm` + Native `AlarmService` |
| **`notification`** | **Disabled (0 Service / 0 Audio)** | **Disabled (0 Adhan Audio)** | **Active (Audible Alert Banner)** | `flutter_local_notifications` pure native |
| **`off`** | **Disabled** | **Disabled** | **Disabled** | None (Fully Decommissioned) |

### 1.2 Core Guarantees
1. **Purity of Notification Mode:** When a prayer is in `notification` mode, it is scheduled exclusively through `flutter_local_notifications` (deterministic ID formula `typeOffset: 1`). It **never** invokes `package:alarm`, never spins up Android `AlarmService`, never plays Adhan audio assets, and never launches `AdhanScreen`.
2. **Purity of Alarm Mode:** When a prayer is in `alarm` mode, it schedules a full-screen intent alarm via `package:alarm` (deterministic ID formula `typeOffset: 0`) with configured muezzin audio, volume level, and vibration.
3. **Complete Independence:** Changing the mode or audio of one prayer has zero impact on any other prayer.
4. **Subsystem Isolation:** Prayer alerts are completely decoupled from Iqama reminders and Azkar notifications.

---

## 2. Home Quick Toggle Contract (`Alarm ↔ Notification`)

The Quick Control on each Home Prayer Card provides a 1-tap toggle between the two active notification tiers:

```
[ Alarm (Full Adhan) ]   ◄───( Home Card Tap )───►   [ Notification (Banner Only) ]
```

### 2.1 State Transitions & Visual Matrix
- **🔔 Alarm Active:** 
  - Visual: `Icons.notifications_active_rounded` (or active bell icon) in vibrant accent color.
  - Accessibility Label: `"تبديل إلى وضع الإشعار البسيط لصلاة [اسم الصلاة]"`
  - Tap Action: Transitions prayer to `PrayerAlarmType.notification`.
- **🔕 Notification Active:** 
  - Visual: `Icons.notifications_none_rounded` (or silent bell icon) in subtle/secondary text color.
  - Accessibility Label: `"تفعيل الأذان الكامل لصلاة [اسم الصلاة]"`
  - Tap Action: Transitions prayer to `PrayerAlarmType.alarm`.
- **⛔ Off Mode:** 
  - Visual: `Icons.notifications_off_outlined` with slash, dimmed.
  - Accessibility Label: `"تنبيهات [اسم الصلاة] معطلة بالكامل"`
  - Tap Action: Non-toggleable on Home Card (tapping presents an informative SnackBar with a direct shortcut to open Settings).
- **⏳ Updating State:** 
  - Visual: Micro `CircularProgressIndicator` (stroke width 2, size 16) replacing the icon during async operation.
  - Interaction: Debounced/locked until operation finishes.

### 2.2 Active Ringing Lifecycle Execution
When the user taps the toggle while an alarm for that prayer is **actively ringing**:
```text
User Taps Quick Toggle (Alarm -> Notification)
  ├── Step 1: Check active ringing state via Alarm.isRinging(activeAlarmId)
  │     └── If TRUE: invoke await Alarm.stop(activeAlarmId) immediately
  │           (Terminates audio playback, kills FGS, dismisses AdhanScreen)
  ├── Step 2: Update persistent PrayerAlarmConfig to notification mode
  ├── Step 3: Trigger Two-Phase Reconciler to:
  │     ├── Decommission any future scheduled Alarm instances for this prayer
  │     └── Schedule FLN Notification instances for upcoming days
  └── Step 4: Emit updated UI state via PrayerAlarmSettingsCubit
```

### 2.3 Imminent Window Safety Semantics
- If the user toggles a prayer when its alarm is within the imminent guard window ($< 15$ seconds before trigger):
  1. The persistent configuration is immediately updated to `PrayerAlarmType.notification`.
  2. The imminent guard prevents unsafe race-condition deletion in `AlarmManagerService`.
  3. When the native alarm fires: the runtime `AdhanScreen` checks the updated persistent config. Seeing it marked as `notification`, it automatically suppresses audio/full-screen UI and posts a local notification instead.
  4. The UI reflects the persistent saved state immediately with no misleading claims.

---

## 3. Detailed Settings Hub Architecture

### 3.1 Settings Screen Entry Point
In `lib/features/settings/presentation/screens/settings_screen.dart`:
- Replace legacy `طريقة تنبيه الأذان` Dialog tile with a premier navigation row:
  - Title: **«إعدادات تنبيهات الصلاة»** (Prayer Alarm Settings)
  - Subtitle: Dynamic summary of configured prayers (e.g., `الفجر: أذان • الظهر..العشاء: إشعار`)
  - Icon: `Icons.alarm_on_rounded` with trailing chevron.
  - Navigation: `Navigator.push(context, MaterialPageRoute(builder: (_) => const PrayerAlarmSettingsScreen()))`.

### 3.2 Master Hub: `PrayerAlarmSettingsScreen`
Displays all 5 obligatory daily prayers (`Fajr`, `Dhuhr`, `Asr`, `Maghrib`, `Isha`) in tailored cards:
- **Card Elements:**
  - Prayer Name (Cairo Bold) & Islamic Icon.
  - Current Alert Mode Badge:
    - `منبه كامل` (Alarm) — Gold Badge
    - `إشعار بسيط` (Notification) — Cyan/Blue Badge
    - `معطل` (Off) — Grey Badge
  - Audio Profile Summary (Muezzin name & Volume percentage, visible if Alarm).
  - Vibration Summary (`اهتزاز مفعّل` / `معطل`).
  - Chevron leading to `PrayerDetailSettingsScreen`.

### 3.3 Prayer Detail Hub: `PrayerDetailSettingsScreen`
Controls all attributes for a single designated prayer:
- **Section A — Alert Mode Selector:**
  - Radio options for `Alarm` (منبه بكامل الشاشة مع الأذان), `Notification` (إشعار بسيط عند دخول الوقت), and `Off` (إيقاف التنبيه).
  - Clear Arabic explanatory copy under each mode.
- **Section B — Adhan Audio Configuration (Active only when Mode == Alarm):**
  - **Audio Source Tile:** Displays selected Muezzin name, opens `AdhanCatalogScreen`.
  - **Live Audio Preview:** Play/Stop button with animated waveform/progress indicator.
  - **Volume Slider:** Continuous slider (0% to 100%) with live numeric feedback.
- **Section C — Vibration Configuration:**
  - Switch: `تخصيص الاهتزاز لهذه الصلاة`.
  - When enabled: Toggle for Vibration on/off. When disabled: follows global setting.
  - Live Vibration Preview button.
- **Section D — Reset to Defaults:**
  - TextButton: `إعادة ضبط إعدادات هذه الصلاة فقط`.
  - Resets target prayer to factory defaults (Alarm mode, default sound, global vibration) without affecting any other prayer.

---

## 4. Audio Catalog & Local Import Architecture

### 4.1 Strongly Typed Audio Source Contract
```dart
sealed class AudioSourceConfig {
  final String id;
  final String displayName;

  const AudioSourceConfig({required this.id, required this.displayName});

  Map<String, dynamic> toJson();
  static AudioSourceConfig fromJson(Map<String, dynamic> json);
}

class BuiltInAudioSource extends AudioSourceConfig {
  final String assetPath;

  const BuiltInAudioSource({
    required super.id,
    required super.displayName,
    required this.assetPath,
  });
}

class CustomAudioSource extends AudioSourceConfig {
  final String localRelativePath;
  final int fileSizeBytes;
  final Duration duration;

  const CustomAudioSource({
    required super.id,
    required super.displayName,
    required this.localRelativePath,
    required this.fileSizeBytes,
    required this.duration,
  });
}
```

### 4.2 Built-in Catalog Registry
- `builtIn:default_fajr`: "أذان الفجر (الافتراضي)" -> `assets/sounds/fajr_azan.mp3`
- `builtIn:default_general`: "الأذان العام (الافتراضي)" -> `assets/sounds/adhan.mp3`

### 4.3 Custom Audio Ingestion Service (`CustomAudioStorageService`)
- **Picker:** Uses `file_picker` plugin with audio-only filter.
- **Sanitization & Validation:**
  - Allowed extensions: `.mp3`, `.m4a`, `.wav`.
  - Size constraint: $\le 15$ MB.
  - Header validation & playable duration probe via `audioplayers`.
- **Atomic Import:**
  - Copies file from temporary cache into:
    `getApplicationDocumentsDirectory()/adhan_sounds/<uuid>.mp3`
  - Stores canonical metadata in local storage ledger.
- **Resilient Fallback Policy:**
  - If a custom file is missing, deleted, or unplayable at trigger/schedule time, the engine automatically falls back to the canonical built-in sound (`builtIn:default_fajr` for Fajr, `builtIn:default_general` for others) and logs an observable warning.

### 4.4 Audio Preview Lifecycle
- Dedicated `AudioPreviewService` holding an isolated `AudioPlayer` instance.
- **Strict Teardown Rules:**
  - Audio preview stops immediately when:
    - User leaves the screen (`dispose()`).
    - App is paused or moved to background (`AppLifecycleState.paused`).
    - Audio focus is lost (interrupted by phone call or media).
    - User selects a different audio track or taps stop.
    - A scheduled alarm triggers.

---

## 5. Domain & Persistence Evolution

### 5.1 Updated `PrayerAlarmConfig` Entity
```dart
@immutable
class PrayerAlarmConfig {
  final PrayerId prayerId;
  final PrayerAlarmType alarmType; // alarm, notification, off
  final AudioSourceConfig audioSource;
  final double volume; // 0.05 to 1.0 (default 1.0)
  final bool? isVibrationEnabled; // null = use global default, true/false = explicit override

  const PrayerAlarmConfig({
    required this.prayerId,
    required this.alarmType,
    required this.audioSource,
    this.volume = 1.0,
    this.isVibrationEnabled,
  });
  
  PrayerAlarmConfig copyWith({...});
}
```

### 5.2 Non-Destructive Versioned Migration (v1 -> v2)
- Handled in `PrayerAlarmConfigLocalDataSourceImpl`:
  - `currentVersion` bumped to `2`.
  - If v1 configs exist in `prayer_alarm_configs_json`: read existing `prayerId` and `alarmType`. Preserve them exactly.
  - Seed `audioSource`: Fajr gets `builtIn:default_fajr`, others get `builtIn:default_general`.
  - Seed `volume`: reads existing `prefs.getDouble('adhan_volume') ?? 1.0`.
  - Seed `isVibrationEnabled`: `null` (inherits global `isAdhanVibrationEnabled`).
  - Migration is 100% idempotent and non-destructive.

---

## 6. Implementation Phases & Stop Gates Matrix

```
┌─────────────────────────────────────────────────────────────┐
│ Phase P4.1-C.0: Baseline Architecture Inspection            │◄── [CURRENT STOP GATE]
├─────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.1: Domain Models, AudioSource & Migration v2   │
├─────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.2: State Management (PrayerAlarmSettingsCubit) │
├─────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.3: Home Prayer Cards Quick Toggle Widget       │
├─────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.4: Prayer Alarm Settings Master Hub Screen     │
├─────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.5: Prayer Detail & Audio Catalog Screens       │
├─────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.6: Custom Audio Ingestion Service              │
├─────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.7: Scheduler & Reconciliation Wire-up          │
├─────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.8: Comprehensive Automated Testing Matrix      │
├─────────────────────────────────────────────────────────────┤
│ Phase P4.1-C.9: Dual-Device Physical Verification & Bundle │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. Verification Plan & Test Strategy

### 7.1 Automated Test Suites
1. **Domain Tests (`test/features/notifications/domain/`):**
   - Verify `PrayerAlarmConfig` instantiation, equality, copyWith with `AudioSourceConfig`.
   - Verify `AudioSourceConfig` serialization & deserialization for built-in and custom types.
   - Verify migration v1 -> v2 preserves existing `alarmType` selections.
2. **Cubit Tests (`test/features/notifications/presentation/`):**
   - Test toggle from `alarm` to `notification`: emits updating state, invokes `Alarm.stop()` if ringing, updates storage, triggers reconciliation.
   - Test toggle from `notification` to `alarm`: schedules alarm with configured audio & volume.
   - Test per-prayer state isolation: changing Asr does not emit state changes for Fajr.
   - Test Audio Preview lifecycle: disposal stops playback.
3. **Widget Tests (`test/features/home/presentation/widgets/`):**
   - Test `PrayerCard` displays bell icon when mode is `alarm`.
   - Test `PrayerCard` displays silent/subtle icon when mode is `notification`.
   - Test `PrayerCard` displays disabled slash icon when mode is `off`.
   - Test tap invokes toggle callback without navigating away.
   - Verify 48dp minimum touch target bounding box.
   - Test Sunrise card suppresses the toggle icon.
4. **Settings Widget Tests (`test/features/settings/presentation/`):**
   - Test `PrayerAlarmSettingsScreen` lists 5 prayers with correct mode badges.
   - Test `PrayerDetailSettingsScreen` mode selection updates cubit.
   - Test reset button resets target prayer only.
5. **Scheduler Integration Tests (`test/features/notifications/scheduler_integration_test.dart`):**
   - Verify that when a prayer is in `notification` mode, `verifyAlarm()` decommissions the opposing alarm and schedules FLN notification.
   - Verify that when a prayer is in `alarm` mode, `verifyNotification()` decommissions opposing notification and schedules Alarm.
   - Verify all 52 existing scheduler integration tests remain 100% green.

### 7.2 Physical Dual-Device Validation
- **Xiaomi Redmi Note 14 Pro+ 5G (Android 16 HyperOS):**
  - Verify Home card 1-tap toggle responsiveness.
  - Verify immediate silencing of active ringing alarm via Home toggle.
  - Verify smooth navigation and RTL typography in Settings.
- **Samsung Galaxy Tab A7 LTE (Android 12 One UI 4.1):**
  - Verify tablet grid layout and touch accessibility.
  - Verify FLN notification delivery when set to `notification` mode.
  - Verify zero lingering alarms/notifications after state changes.

---

## 8. Summary of Corrections from Review

| Review Item | Status in Revision 1.1 |
|---|:---:|
| **B1 (Instantaneous Mute)** | **Resolved:** Replaced with explicit `Alarm ↔ Notification` toggle. Active ringing alarms are immediately silenced via `Alarm.stop()`. |
| **B2 (Volume Contract)** | **Resolved:** Volume is an independent volume parameter (0.05 to 1.0) for Alarm mode, not a mute surrogate. |
| **B3 (Notification Mode)** | **Resolved:** Explicitly verified that `notification` mode is 100% pure FLN notification with zero `package:alarm` usage. |
| **R1 (Migration Contract)** | **Resolved:** Idempotent, non-destructive migration preserving existing user selections. |
| **R2 (Vibration Contract)** | **Resolved:** Tri-state `bool?` (`null` = global default, `true/false` = per-prayer override). |
| **R3 (Audio Source Identity)** | **Resolved:** Strongly typed `AudioSourceConfig` with unique string IDs and safe fallback policy. |
| **R4 (Touch Target)** | **Resolved:** 48dp minimum touch target with Arabic accessibility semantics. |

---

## 9. Stop Gate C.0 Checklist

- [x] Tri-state contract (`alarm`, `notification`, `off`) mathematically formalized.
- [x] Home Quick Toggle defined as `Alarm ↔ Notification` with active ringing dismissal.
- [x] Purity of Notification mode verified (zero `package:alarm` interaction).
- [x] Audio source identity, lifecycle, and fallback specified.
- [x] Migration and vibration resolution contracts finalized.
- [x] Risk register and automated/manual test plans updated.
- [ ] **Engineering Review & Formal Approval of Revision 1.1 (STOP GATE C.0)**.
- [ ] Production code diff remains strictly 0 lines.

